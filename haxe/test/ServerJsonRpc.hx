import Harness.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The `server/*` JSON-RPC methods through a running compilation server:
//   <haxe> -cp haxe/test --run ServerJsonRpc [--keep] [--summary <file>]
// Starts the reference and the port as compilation servers (one after the
// other, on the project haxe/test/server-jsonrpc), compiles it through
// --connect, then sends both the same display JSON-RPC requests: initialize,
// server/readClassPaths, contexts, modules, module, type, typeContexts, files,
// moduleCreated, invalidate, configure, memory, memory/context, memory/module
// and typer/compiledTypes, with a recompilation in between so that modules
// come back from the server's cache; in both cache modes (HXB, typed modules
// in memory). Compared per request: exit code, stdout and the response, once
// the `timestamp` is replaced and, in server/memory*, every size, cache total
// and `leaks` (measured on each runtime's heap) is blanked and the size-sorted
// lists are sorted by content.
class ServerJsonRpc {
	static final MEMORY = ["server/memory", "server/memory/context", "server/memory/module"];
	static final SIZES = ["size", "totalCache", "contextCache", "haxelibCache", "directoryCache", "nativeLibCache", "moduleExtra"];
	static var project:String;

	static function session(cmd:Array<String>, extra:Array<String>, tag:String):Array<String> {
		var base = ["--cwd", project, "-cp", "src", "-main", "Main", "--interp", "--no-output", "-D", "disable-parallelism"].concat(extra);
		var srv = Server.startServer("server", cmd, '${Server.gen}/server-$tag.log');
		var log = [];
		function compile(label:String) {
			var r = Server.client(cmd, srv.port, base, root, null, 300);
			log.push(entry(label, r.code, r.out, r.err, false));
		}
		function rpc(method:String, params:String):Dynamic {
			var req = '{"jsonrpc":"2.0","id":1,"method":${haxe.Json.stringify(method)},"params":$params}';
			var r = Server.client(cmd, srv.port, base.concat(["--display", req]), root, null, 300);
			log.push(entry(method + " " + params, r.code, r.out, r.err, MEMORY.contains(method)));
			return try haxe.Json.parse(r.err) catch (_:Dynamic) null;
		}
		function str(s:String) return haxe.Json.stringify(s);
		compile("compile 1");
		rpc("initialize", '{"supportsResolve":true}');
		rpc("server/readClassPaths", "{}");
		var contexts:Array<Dynamic> = try rpc("server/contexts", "{}").result.result catch (_:Dynamic) null;
		var signs:Array<String> = contexts == null ? [] : [for (c in contexts) c.signature];
		for (sign in signs) {
			var s = '"signature":${str(sign)}';
			rpc("server/modules", '{$s}');
			rpc("server/files", '{$s}');
			for (path in ["pack.Other", "Main", "Build", "StdTypes", "haxe.ds.StringMap", "NoSuchModule"]) rpc("server/module", '{$s,"path":${str(path)}}');
			for (mt in [["pack.Other", "E"], ["pack.Other", "Abs"], ["pack.Other", "T"], ["pack.Other", "Other"], ["pack.Other", "Nope"], ["Main", "Main"], ["Nope", "Nope"]])
				rpc("server/type", '{$s,"modulePath":${str(mt[0])},"typeName":${str(mt[1])}}');
			rpc("server/memory/context", '{$s}');
			rpc("server/memory/module", '{$s,"path":"pack.Other"}');
		}
		rpc("server/typeContexts", '{"modulePath":"pack.Other","typeName":"E"}');
		rpc("server/typeContexts", '{"modulePath":"Main","typeName":"Main"}');
		rpc("server/memory", "{}");
		rpc("server/configure", '{"print":{"addedDirectory":true,"stats":false},"noModuleChecks":false}');
		rpc("server/configure", '{"print":{"noSuchSetting":true}}');
		var other = str(project + "/src/pack/Other.hx");
		rpc("server/moduleCreated", '{"file":$other}');
		rpc("server/invalidate", '{"file":$other}');
		for (sign in signs) {
			rpc("server/module", '{"signature":${str(sign)},"path":"pack.Other"}');
			rpc("server/module", '{"signature":${str(sign)},"path":"Main"}');
		}
		compile("compile 2");
		for (sign in signs) {
			var s = '"signature":${str(sign)}';
			rpc("server/modules", '{$s}');
			rpc("server/module", '{$s,"path":"pack.Other"}');
			rpc("server/module", '{$s,"path":"Main"}');
			rpc("server/type", '{$s,"modulePath":"pack.Other","typeName":"Other"}');
		}
		rpc("server/memory", "{}");
		rpc("typer/compiledTypes", "{}");
		rpc("server/noSuchMethod", "{}");
		Server.stopServer(srv);
		return log;
	}

	static function entry(label:String, code:String, out:String, resp:String, memory:Bool):String {
		var r = resp;
		if (memory) try r = canonical(strip(haxe.Json.parse(resp))) catch (_:Dynamic) {}
		r = ~/"timestamp":[0-9.eE+-]+/g.replace(r, '"timestamp":0');
		return '$label\nexit $code\n--- stdout\n$out\n--- response\n$r';
	}

	static function strip(j:Dynamic):Dynamic {
		if (Std.isOfType(j, Array)) {
			var l:Array<Dynamic> = [for (x in (j : Array<Dynamic>)) strip(x)];
			if (Lambda.foreach(l, x -> Reflect.isObject(x) && !Std.isOfType(x, String) && !Std.isOfType(x, Array) && (Reflect.hasField(x, "path") || Reflect.hasField(x, "name"))))
				l.sort((a, b) -> compare(canonical(a), canonical(b)));
			return l;
		}
		if (Reflect.isObject(j) && !Std.isOfType(j, String)) {
			var o = {};
			for (k in Reflect.fields(j)) Reflect.setField(o, k, SIZES.contains(k) ? 0 : k == "leaks" ? "<leaks>" : strip(Reflect.field(j, k)));
			return o;
		}
		return j;
	}

	// JSON with sorted keys
	static function canonical(j:Dynamic):String {
		if (j == null) return "null";
		if (Std.isOfType(j, String)) return haxe.Json.stringify(j);
		if (Std.isOfType(j, Array)) return "[" + [for (x in (j : Array<Dynamic>)) canonical(x)].join(",") + "]";
		if (Reflect.isObject(j)) {
			var keys = Reflect.fields(j);
			keys.sort(compare);
			return "{" + [for (k in keys) haxe.Json.stringify(k) + ":" + canonical(Reflect.field(j, k))].join(",") + "}";
		}
		return haxe.Json.stringify(j);
	}

	static function main() {
		var a = parseArgs(Sys.args(), ["--summary"]);
		var ref = [FileSystem.fullPath(Sys.getEnv("HAXE_REFERENCE") ?? "bin/reference/haxe")];
		var port = shellSplit(Sys.getEnv("HAXE_IN_HAXE_PORT") ?? "bin/port/haxe");
		if (FileSystem.exists(port[0])) port[0] = FileSystem.fullPath(port[0]);
		Sys.putEnv("HAXE_STD_PATH", root + "/haxe/upstream/std");
		project = root + "/haxe/test/server-jsonrpc";
		mkdirs("bin/test/server-jsonrpc");
		Server.gen = FileSystem.fullPath("bin/test/server-jsonrpc");
		var ok = true, lines = [];
		for (mode in [{name: "hxb-cache", extra: []}, {name: "disable-hxb-cache", extra: ["-D", "disable-hxb-cache"]}]) {
			var r = session(ref, mode.extra, "reference"), p = session(port, mode.extra, "port");
			if (a.has("--keep")) {
				File.saveContent('${Server.gen}/${mode.name}.reference.txt', r.join("\n\n"));
				File.saveContent('${Server.gen}/${mode.name}.port.txt', p.join("\n\n"));
			}
			var same = 0;
			for (i in 0...(r.length < p.length ? r.length : p.length)) {
				var label = r[i].split("\n")[0];
				if (r[i] == p[i]) {
					same++;
					Sys.println('ok   ${mode.name} ${Std.string(i + 1).lpad(" ", 3)} $label');
				} else
					Sys.println('FAIL ${mode.name} ${Std.string(i + 1).lpad(" ", 3)} $label\n  reference: ${r[i].substr(0, 600).replace("\n", " ")}\n  port:      ${p[i].substr(0, 600).replace("\n", " ")}');
			}
			if (r.length != p.length) Sys.println('FAIL ${mode.name} request count: reference ${r.length}, port ${p.length}');
			var line = '${mode.name}: $same/${r.length > p.length ? r.length : p.length} requests identical';
			Sys.println(line);
			lines.push(line);
			ok = ok && same == r.length && r.length == p.length;
		}
		summary(a.get("--summary"), "### server JSON-RPC\n\n" + lines.join("\n\n") + "\n\n");
		Sys.exit(ok ? 0 : 1);
	}
}
