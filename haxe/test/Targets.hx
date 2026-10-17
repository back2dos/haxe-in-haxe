import Harness.*;
import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Compile time and output of the target generators, for the website's target
// table (site/data/targets.json): the reference and the port compile the
// same projects to every target; the outputs must be identical.
//   bin/hxmc/hxmc -cp haxe/test --run Targets [-n RUNS] [-p formatter,self]
//       [-t js,lua,...] [--port <exe>] [--reference <exe>] [--json <file>] [--merge]
// Projects:
//   formatter  haxe-formatter with its libraries (bin/haxebench), the
//              HaxeBenchmarks formatter_noio case
//   self       the port's own source (haxe/src, haxe.Main)
// Each run is a fresh process with -D disable-parallelism, both compilers in
// the same directory (bin/bench-targets/cwd: some outputs embed it). CPU is
// user + system time and the peak RSS that of /usr/bin/time; CPU and wall are
// the best of RUNS, the peak the largest. The outputs of the last runs are
// compared: files and directories byte for byte, JARs and HXB archives member
// by member; hl/c's digest names that depend on the reference's machine code
// are renamed on both sides first (HlcNames). --merge replaces only the
// measured project/target rows of an existing --json file.
class Targets {
	static final WORK = "bin/bench-targets";
	static final FMT_CPS = ["formatter/src", "tokentree/src", "haxeparser/src", "hxparse/src", "json2object/src", "hxargs", "hxjsonast/src"];
	static final TARGETS:Array<{name:String, args:Array<String>, output:String}> = [
		{name: "hxb", args: ["--interp", "--no-output", "--hxb", "out/out.zip"], output: "zip:out/out.zip"},
		{name: "js", args: ["--js", "out/main.js"], output: "file:out/main.js"},
		{name: "lua", args: ["--lua", "out/main.lua"], output: "file:out/main.lua"},
		{name: "python", args: ["--python", "out/main.py"], output: "file:out/main.py"},
		{name: "php", args: ["--php", "out/php"], output: "dir:out/php"},
		{name: "neko", args: ["--neko", "out/main.n"], output: "file:out/main.n"},
		{name: "hl", args: ["--hl", "out/main.hl"], output: "file:out/main.hl"},
		{name: "hlc", args: ["--hl", "out/hlc/main.c", "-D", "no-compilation"], output: "dir:out/hlc"},
		{name: "cpp", args: ["--cpp", "out/cpp", "-D", "no-compilation"], output: "dir:out/cpp"},
		{name: "jvm", args: ["--jvm", "out/main.jar"], output: "zip:out/main.jar"},
		{name: "swf", args: ["--swf", "out/main.swf"], output: "file:out/main.swf"},
	];

	static function project(name:String, target:String):Array<String> {
		return switch name {
			case "self":
				["-cp", root + "/haxe/src", "-main", "haxe.Main"];
			case "formatter":
				var libs = root + "/bin/haxebench/libs";
				var a = ["-cp", root + "/bin/haxebench/runner/cases/formatter_noio", "-main", "BMFormatterNoIOCode"];
				for (d in FMT_CPS) a = a.concat(["-cp", '$libs/$d']);
				for (d in FMT_CPS) a = a.concat(["-D", d.split("/")[0]]);
				if (target == "js") a = a.concat(["-lib", "hxnodejs"]);
				a;
			case _: fail("unknown project " + name);
		}
	}

	static var root:String;

	static function main() {
		var a = parseArgs(Sys.args(), ["-n", "-p", "-t", "--port", "--reference", "--json"]);
		root = FileSystem.fullPath(".");
		var runs = Std.parseInt(a.get("-n", "3"));
		var projects = a.get("-p", "formatter,self").split(",");
		var targets = a.get("-t", [for (t in TARGETS) t.name].join(",")).split(",");
		var port = FileSystem.fullPath(a.get("--port", Sys.getEnv("HAXE_IN_HAXE_PORT") ?? "bin/port/haxe"));
		var reference = FileSystem.fullPath(a.get("--reference", Sys.getEnv("HAXE_REFERENCE") ?? "bin/reference/haxe"));
		var json = a.get("--json");
		var std = root + "/haxe/upstream/std";
		Sys.putEnv("HAXE_STD_PATH", std);
		Sys.putEnv("HAXE_IN_HAXE_STD_PATH", std);
		mkdirs(WORK);
		var results:Array<Dynamic> = [];
		var merge = a.has("--merge");
		for (p in projects) for (tn in targets) {
			var t = [for (t in TARGETS) if (t.name == tn) t][0];
			if (t == null) fail("unknown target " + tn);
			var args = project(p, tn).concat(t.args).concat(["-D", "disable-parallelism"]);
			var ref = bench(reference, args, t.output, runs);
			if (ref.row.status != "ok") {
				Sys.println('${pad(p, 10)} ${pad(tn, 7)} reference fails: ${tail(ref.row.status, 120)}');
				results.push({project: p, target: tn, reference: ref.row, port: null, identical: null});
			} else {
				var ours = bench(port, args, t.output, runs);
				var line = '${pad(p, 10)} ${pad(tn, 7)} ';
				var same = false;
				if (ours.row.status == "ok") {
					var d = compare(ref.out, ours.out);
					same = d == null;
					line += 'ref ${fixed(ref.row.cpu, 2)}s ${Math.round(ref.row.rss_mb)} MB  port ${fixed(ours.row.cpu, 2)}s ${Math.round(ours.row.rss_mb)} MB  '
						+ '${fixed(ours.row.cpu / ref.row.cpu, 2)}x  ' + (same ? "identical" : "DIFFERENT (" + d + ")");
				} else {
					line += 'port fails: ${tail(ours.row.status, 120)}';
				}
				Sys.println(line);
				results.push({project: p, target: tn, reference: ref.row, port: ours.row, identical: same});
			}
			if (json != null) write(json, results, merge, runs, port, reference);
		}
		if (json != null) write(json, results, merge, runs, port, reference);
	}

	static function bench(compiler:String, args:Array<String>, output:String, runs:Int):{row:Dynamic, out:Null<Map<String, Bytes>>} {
		var cwd = FileSystem.fullPath(WORK) + "/cwd";
		var log = FileSystem.fullPath(WORK) + "/log.txt";
		var best:Dynamic = null;
		for (_ in 0...runs) {
			rmrf(cwd);
			mkdirs(cwd + "/out");
			var time = FileSystem.exists("/usr/bin/time") ? ["/usr/bin/time", "-f", "MEASURE %M %U %S"] : [];
			var r = exec(time.concat([compiler]).concat(args), {cwd: cwd, log: log});
			var text = readText(log);
			if (r.code != 0) {
				var lines = [for (l in text.split("\n")) if (l.trim() != "" && !l.startsWith("MEASURE ")) l.trim()];
				return {row: {status: 'exit ${r.code}: ' + lines.slice(lines.length > 3 ? lines.length - 3 : 0).join(" | ")}, out: null};
			}
			var cpu = 0.0, rss = 0.0;
			var m = ~/MEASURE ([0-9]+) ([0-9.]+) ([0-9.]+)/;
			if (m.match(text)) {
				rss = Std.parseFloat(m.matched(1)) / 1024;
				cpu = Std.parseFloat(m.matched(2)) + Std.parseFloat(m.matched(3));
			}
			if (best == null) best = {cpu: cpu, wall: r.seconds, rss_mb: rss} else {
				best.cpu = Math.min(best.cpu, cpu);
				best.wall = Math.min(best.wall, r.seconds);
				best.rss_mb = Math.max(best.rss_mb, rss);
			}
		}
		var out = snapshot(output, cwd);
		best.status = "ok";
		best.members = out == null ? 0 : [for (k in out.keys()) k].length;
		var bytes = 0;
		if (out != null) for (v in out) bytes += v.length;
		best.bytes = bytes;
		return {row: best, out: out};
	}

	// the output as member => bytes
	static function snapshot(output:String, cwd:String):Null<Map<String, Bytes>> {
		var i = output.indexOf(":");
		var kind = output.substr(0, i), p = cwd + "/" + output.substr(i + 1);
		if (!FileSystem.exists(p)) return null;
		return switch kind {
			case "file": ["" => File.getBytes(p)];
			case "dir": [for (f in walk(p)) f => File.getBytes('$p/$f')];
			case _:
				var z = readZip(p);
				[for (n in z.names) if (!n.endsWith("/")) n => z.data[n]];
		}
	}

	static function compare(a:Null<Map<String, Bytes>>, b:Null<Map<String, Bytes>>):Null<String> {
		if (a == null || b == null) return a == b ? null : "no output on one side";
		if (HlcNames.isHlc([for (k in a.keys()) k])) {
			var n = HlcNames.normalize(a, b);
			a = n.a;
			b = n.b;
		}
		var names = [for (k in a.keys()) k];
		for (k in b.keys()) if (!a.exists(k)) names.push(k);
		names.sort(Harness.compare);
		var bad = [for (n in names) if (!a.exists(n) || !b.exists(n) || a[n].compare(b[n]) != 0) n];
		return bad.length == 0 ? null : '${bad.length} of ${names.length} differ: ${bad.slice(0, 3).join(", ")}';
	}

	// The file as Python's `json.dump(..., indent=1)` wrote it (the format it has
	// had): with --merge, the measured rows and the meta replace theirs in the
	// existing text and every other row stays as it is.
	static function write(path:String, results:Array<Dynamic>, merge:Bool, runs:Int, port:String, reference:String) {
		var cpu = null;
		if (FileSystem.exists("/proc/cpuinfo")) for (l in File.getContent("/proc/cpuinfo").split("\n")) if (l.startsWith("model name")) {
			cpu = l.substr(l.indexOf(":") + 1).trim();
			break;
		}
		var version = exec([reference, "--version"]).out.trim().split("\n")[0];
		var meta:Array<{k:String, v:Dynamic}> = [
			{k: "date", v: DateTools.format(Date.now(), "%Y-%m-%dT%H:%M:%S")},
			{k: "commit", v: exec(["git", "-C", root, "rev-parse", "--short", "HEAD"]).out.trim()},
			{k: "cpu", v: cpu},
			{k: "cores", v: cpus()},
			{k: "runs", v: runs},
			{k: "port", v: port.startsWith(root + "/") ? port.substr(root.length + 1) : port},
			{k: "reference", v: version.split("+")[0]},
			{k: "platform", v: [for (o in ["-s", "-r", "-m"]) exec(["uname", o]).out.trim()].join("-")}
		];
		var metaText = obj(meta, 1);
		var rows = [for (r in results) rowText(r)];
		var text = merge && FileSystem.exists(path) ? File.getContent(path) : null;
		if (text == null) {
			text = '{\n "meta": $metaText,\n "results": [\n' + [for (r in rows) "  " + r].join(",\n") + "\n ]\n}";
		} else {
			var m = text.indexOf('"meta": {'), e = text.indexOf("\n }", m);
			if (m < 0 || e < 0) fail(path + ": no meta");
			text = text.substr(0, m) + '"meta": ' + metaText + text.substr(e + 3);
			for (i in 0...results.length) {
				var r = results[i];
				var head = '\n  {\n   "project": ${haxe.Json.stringify(r.project)},\n   "target": ${haxe.Json.stringify(r.target)},';
				var s = text.indexOf(head);
				if (s >= 0) {
					var end = text.indexOf("\n  }", s + head.length);
					text = text.substr(0, s + 3) + rows[i] + text.substr(end + 4);
				} else {
					var end = text.lastIndexOf("\n ]");
					text = text.substr(0, end) + ",\n  " + rows[i] + text.substr(end);
				}
			}
		}
		File.saveContent(path, text);
	}

	static function rowText(r:Dynamic):String {
		function side(s:Dynamic):Dynamic {
			if (s == null) return null;
			if (s.status != "ok") return new Raw(obj([{k: "status", v: s.status}], 3));
			return new Raw(obj([
				{k: "cpu", v: s.cpu}, {k: "wall", v: s.wall}, {k: "rss_mb", v: s.rss_mb}, {k: "status", v: s.status},
				{k: "members", v: s.members}, {k: "bytes", v: s.bytes}
			], 3));
		}
		return obj([
			{k: "project", v: r.project}, {k: "target", v: r.target}, {k: "reference", v: side(r.reference)}, {k: "port", v: side(r.port)},
			{k: "identical", v: r.identical}
		], 2);
	}

	static function obj(fields:Array<{k:String, v:Dynamic}>, level:Int):String {
		var ind = "".lpad(" ", level + 1);
		return "{\n" + [for (f in fields) ind + haxe.Json.stringify(f.k) + ": " + value(f.v)].join(",\n") + "\n" + "".lpad(" ", level) + "}";
	}

	static function value(v:Dynamic):String {
		if (Std.isOfType(v, Raw)) return (v : Raw).text;
		// a measured time or size: 6 decimals (the parsed rows keep their text)
		if (Std.isOfType(v, Float) && !Std.isOfType(v, Int)) {
			var f:Float = v;
			var n = Std.string(Math.round(Math.abs(f) * 1e6)).lpad("0", 7);
			var s = n.substr(0, n.length - 6) + "." + n.substr(n.length - 6);
			while (s.endsWith("0") && !s.endsWith(".0")) s = s.substr(0, s.length - 1);
			return (f < 0 ? "-" : "") + s;
		}
		return haxe.Json.stringify(v);
	}
}

private class Raw {
	public final text:String;

	public function new(text:String) this.text = text;
}
