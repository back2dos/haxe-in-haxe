import Harness.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Display (IDE services) conformance of the port:
//   <haxe> -cp haxe/test --run Display [-j N] [--extended] [--list] [--summary <file>] [name-substring ...]
// The corpus is upstream's tests/display/src/cases/*.hx, removed upstream in
// 3d317d905 (#13015): extracted from the submodule's history (its parent,
// fetched when the checkout is shallow) into bin/test/display-corpus, or the
// tests/display directory named by HAXE_DISPLAY_CORPUS. Every documented test
// method holds a snippet with `{-N-}` markers; the method body names the
// requests it issues (fields/toplevel -> display/completion,
// type/doc/metadataDoc -> display/hover, position(s) -> display/definition,
// usage -> display/references, signature -> display/signatureHelp,
// diagnostics() -> display/diagnostics, documentSymbols() ->
// display/documentSymbols). Markers are extracted as Marker.hx does and the
// snippet written to bin/test/display/<Case>/<method>/<CaseFile>.hx (cwd that
// directory, `-cp src-misc`, `-D message.reporting=classic`, `--no-output`).
// Each request is a batch `--display <json-rpc>` invocation of the reference
// and of the port; exit code, stdout and stderr must be equal once the
// "timestamp" of JSON-RPC responses is replaced. A non-literal marker expands
// over every marker; initialize, display/metadata and display/defines are sent
// once. --extended also queries every marker with every position method and
// every snippet with every file method.
class Display {
	static final CORPUS_COMMIT = "4d9a9fd7367d650da673c7ef6e699798ec900645"; // 3d317d905^: the last with tests/display
	static final GENERATED = "bin/test/display";
	static final TIMEOUT = 600;
	static final METHODS = [
		"fields" => "display/completion", "toplevel" => "display/completion", "type" => "display/hover", "doc" => "display/hover",
		"metadataDoc" => "display/hover", "position" => "display/definition", "positions" => "display/definition",
		"usage" => "display/references", "signature" => "display/signatureHelp"
	];
	static final EXTENDED_MARKER = ["display/completion", "display/hover", "display/definition", "display/typeDefinition", "display/implementation",
		"display/references", "display/signatureHelp"];
	static final EXTENDED_FILE = ["display/diagnostics", "display/documentSymbols", "display/statistics", "display/package"];

	static function corpusRoot():String {
		var env = Sys.getEnv("HAXE_DISPLAY_CORPUS");
		if (env != null) return env;
		var out = "bin/test/display-corpus";
		if (!FileSystem.exists(out + "/tests/display/src/cases")) {
			mkdirs(out);
			var tar = FileSystem.fullPath(out) + "/corpus.tar";
			var r = exec(["git", "-C", "haxe/upstream", "archive", "-o", tar, CORPUS_COMMIT, "tests/display"], {merge: true});
			if (r.code != 0) {
				exec(["git", "-C", "haxe/upstream", "fetch", "-q", "--depth", "1", "origin", CORPUS_COMMIT], {merge: true});
				r = exec(["git", "-C", "haxe/upstream", "archive", "-o", tar, CORPUS_COMMIT, "tests/display"], {merge: true});
				if (r.code != 0) fail("Display: cannot extract tests/display at " + CORPUS_COMMIT + ": " + r.out);
			}
			exec(["tar", "-x", "-f", tar, "-C", out]);
		}
		return out + "/tests/display";
	}

	static function extractMarkers(doc:String):{source:String, markers:Map<Int, Int>} {
		var markers = new Map<Int, Int>();
		var re = ~/\{-([0-9]+)-\}/;
		var out = new StringBuf();
		var rest = doc;
		while (re.match(rest)) {
			var p = re.matchedPos();
			out.add(rest.substr(0, p.pos));
			markers[Std.parseInt(re.matched(1))] = out.length;
			rest = rest.substr(p.pos + p.len);
		}
		out.add(rest);
		return {source: out.toString(), markers: markers};
	}

	static function bodyOf(text:String, start:Int):String {
		var i = text.indexOf("{", start);
		var depth = 0;
		for (j in i...text.length) {
			var c = text.charAt(j);
			if (c == "{") depth++ else if (c == "}") {
				depth--;
				if (depth == 0) return text.substring(i, j + 1);
			}
		}
		return text.substr(i);
	}

	static function sortedKeys(m:Map<Int, Int>):Array<Int> {
		var k = [for (x in m.keys()) x];
		k.sort((a, b) -> a - b);
		return k;
	}

	static function parseCaseFile(path:String, extended:Bool):Array<DisplayTest> {
		var text = File.getContent(path);
		var tests = [];
		var pos = 0;
		var decl = ~/[ \t\r\n]*((?:@[:A-Za-z0-9_]+(?:\([^)]*\))?[ \t\r\n]*)*)(?:(?:public|private|static|override)[ \t\r\n]+)*function[ \t\r\n]+([A-Za-z0-9_]+)/;
		var callRe = new EReg("\\b(" + [for (k in METHODS.keys()) k].join("|") + ")\\(pos\\(([^)]*)\\)", "g");
		var stem = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path));
		while (true) {
			var start = text.indexOf("/**", pos);
			if (start < 0) break;
			var end = text.indexOf("**/", start + 3);
			if (end < 0) break;
			var doc = text.substring(start + 3, end);
			pos = end + 3;
			if (!decl.matchSub(text, pos) || decl.matchedPos().pos != pos) continue;
			var meta = decl.matched(1), name = decl.matched(2);
			var declEnd = decl.matchedPos().pos + decl.matchedPos().len;
			if (meta.contains("@:funcCode")) doc = "class Main { static function main() { " + doc + "}}";
			doc = doc.replace("**\\/", "**/");
			var filename = haxe.io.Path.withoutDirectory(path);
			var fm = ~/@:filename\([ \t\r\n]*"([^"]*)"[ \t\r\n]*\)/;
			if (fm.match(meta)) filename = fm.matched(1);
			var body = bodyOf(text, declEnd);
			var ex = extractMarkers(doc);
			var requests:Array<{rpc:String, marker:Null<Int>}> = [];
			var b = body;
			while (callRe.match(b)) {
				var method = callRe.matched(1), arg = callRe.matched(2).trim();
				var ids = ~/^[0-9]+$/.match(arg) ? [Std.parseInt(arg)] : sortedKeys(ex.markers);
				for (i in ids) if (ex.markers.exists(i)) requests.push({rpc: METHODS[method], marker: i});
				b = callRe.matchedRight();
			}
			if (~/\bdiagnostics\(\)/.match(body)) requests.push({rpc: "display/diagnostics", marker: null});
			// the legacy `0@module-symbols` form is gone; the JSON-RPC equivalent is used
			if (~/\bdocumentSymbols\(\)/.match(body)) requests.push({rpc: "display/documentSymbols", marker: null});
			if (extended) {
				for (i in sortedKeys(ex.markers)) for (rpc in EXTENDED_MARKER) requests.push({rpc: rpc, marker: i});
				for (rpc in EXTENDED_FILE) requests.push({rpc: rpc, marker: null});
			}
			var seen = new Map<String, Bool>(), unique = [];
			for (r in requests) {
				var key = r.rpc + "@" + r.marker;
				if (!seen.exists(key)) {
					seen[key] = true;
					unique.push(r);
				}
			}
			tests.push({caseName: stem, name: name, filename: filename, source: ex.source, markers: ex.markers, requests: unique});
		}
		return tests;
	}

	static function requestJson(rpc:String, filename:String, offset:Null<Int>):String {
		var params = '"file":' + haxe.Json.stringify(filename);
		if (offset != null) params += ',"offset":$offset';
		if (rpc == "display/completion" || rpc == "display/signatureHelp") params += ',"wasAutoTriggered":false';
		return '{"method":${haxe.Json.stringify(rpc)},"id":1,"params":{$params}}';
	}

	static function normalize(s:String):String return ~/"timestamp":-?[0-9.eE+-]+/g.replace(s, '"timestamp":0');

	static function main() {
		var a = parseArgs(Sys.args(), ["-j", "--summary"]);
		var corpus = FileSystem.fullPath(corpusRoot());
		var reference = FileSystem.fullPath(Sys.getEnv("HAXE_REFERENCE") ?? "bin/reference/haxe");
		var port = shellSplit(Sys.getEnv("HAXE_IN_HAXE_PORT") ?? "bin/port/haxe");
		if (FileSystem.exists(port[0])) port[0] = FileSystem.fullPath(port[0]);
		Sys.putEnv("HAXE_STD_PATH", root + "/haxe/upstream/std");
		var filters = a.rest;
		mkdirs(GENERATED);
		var jobs:Array<DisplayJob> = [];
		var files = [for (f in FileSystem.readDirectory(corpus + "/src/cases")) if (f.endsWith(".hx") && f != "import.hx") f];
		files.sort(compare);
		for (f in files)
			for (t in parseCaseFile(corpus + "/src/cases/" + f, a.has("--extended"))) {
				var label = t.caseName + "." + t.name;
				if (filters.length > 0 && !Lambda.exists(filters, x -> label.contains(x))) continue;
				var d = FileSystem.fullPath(GENERATED) + "/" + t.caseName + "/" + t.name;
				for (r in t.requests)
					jobs.push({label: label, dir: d, test: t, rpc: r.rpc, marker: r.marker,
						json: requestJson(r.rpc, t.filename, r.marker == null ? null : t.markers[r.marker])});
			}
		// requests that do not depend on a file
		var globals:DisplayTest = {caseName: "_global", name: "test", filename: "Main.hx", source: "class Main {}\n", markers: [], requests: []};
		for (g in [["initialize", "{}"], ["display/metadata", '{"compiler":true,"user":true}'], ["display/defines", '{"compiler":true,"user":true}']]) {
			var label = "_global." + g[0];
			if (filters.length > 0 && !Lambda.exists(filters, x -> label.contains(x))) continue;
			jobs.push({label: label, dir: FileSystem.fullPath(GENERATED) + "/_global", test: globals, rpc: g[0], marker: null,
				json: '{"method":"${g[0]}","id":1,"params":${g[1]}}'});
		}
		if (a.has("--list")) {
			for (j in jobs) Sys.println('${j.label} ${j.rpc} ${j.marker}');
			Sys.println(jobs.length + " requests");
			return;
		}
		var written = new Map<String, Bool>();
		for (j in jobs) {
			if (written.exists(j.dir)) continue;
			written[j.dir] = true;
			var target = j.dir + "/" + j.test.filename;
			mkdirs(haxe.io.Path.directory(target));
			File.saveContent(target, j.test.source);
		}
		var common = ["-cp", corpus + "/src-misc", "-D", "message.reporting=classic", "--no-output", "--display"];
		var counts = ["match" => 0, "mismatch" => 0, "timeout" => 0];
		var failures = [];
		var t0 = now();
		parallel(jobs, a.int("-j", cpus()), j -> {
			var ref = exec([reference].concat(common).concat([j.json]), {cwd: j.dir, timeout: TIMEOUT});
			var got = exec(port.concat(common).concat([j.json]), {cwd: j.dir, timeout: TIMEOUT});
			{ref: ref, got: got};
		}, (j, r) -> {
			var tag = '${j.label} ${j.rpc} ' + (j.marker == null ? "" : '{-${j.marker}-}');
			var refText = 'exit ${r.ref.code}\n--- stdout\n${normalize(r.ref.out)}\n--- stderr\n${normalize(r.ref.err)}\n';
			var gotText = 'exit ${r.got.code}\n--- stdout\n${normalize(r.got.out)}\n--- stderr\n${normalize(r.got.err)}\n';
			var status = r.got.timedOut ? "timeout" : refText == gotText ? "match" : "mismatch";
			counts[status]++;
			if (status != "match") {
				failures.push(tag);
				var name = j.rpc.replace("/", "_") + "." + (j.marker == null ? "file" : Std.string(j.marker)) + ".txt";
				File.saveContent(j.dir + "/request." + name, j.json + "\n");
				File.saveContent(j.dir + "/ref." + name, refText);
				File.saveContent(j.dir + "/port." + name, gotText);
			}
			Sys.println(pad(status.toUpperCase(), 8) + ' $tag (ref ${fixed(r.ref.seconds)}s, port ${fixed(r.got.seconds)}s)');
		});
		var total = counts["match"] + counts["mismatch"] + counts["timeout"];
		var line = '$total requests: ${counts["match"]} match, ${counts["mismatch"]} mismatch, ${counts["timeout"]} timeout (${Math.round(now() - t0)}s)';
		Sys.println("\n" + line);
		if (failures.length > 0) File.saveContent(GENERATED + "/failures.txt", failures.join("\n") + "\n");
		summary(a.get("--summary"), '### display\n\n$line\n\n' + [for (f in failures.slice(0, 30)) '- $f\n'].join("") + "\n");
		Sys.exit(failures.length > 0 ? 1 : 0);
	}
}

typedef DisplayTest = {caseName:String, name:String, filename:String, source:String, markers:Map<Int, Int>, requests:Array<{rpc:String, marker:Null<Int>}>}
typedef DisplayJob = {label:String, dir:String, test:DisplayTest, rpc:String, marker:Null<Int>, json:String}
