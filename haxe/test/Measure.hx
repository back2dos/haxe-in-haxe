import Harness.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Peak memory (the peak resident set of the process tree, as getrusage's
// RUSAGE_CHILDREN reports it through /usr/bin/time), wall and CPU time of:
//   self-compile   the port's self-compile to HXB: ours (PORT_BIN) and the reference
//   native build   the port built by the tool, cold (no cached objects)
//   stage0         the stage0 module under node building the native tool
//   npm wasm       @hxmc/wasm's compiler (bin/npm/native/wasm32-wasi/haxe.wasm) under node
//                  building the native compiler, as hxmc-rebuild does without a native one
//   bin/hxmc/hxmc -cp haxe/test -cp hxmc/test --run Measure [--only a,b,...] [--port <exe>]
//       [--reference <exe>] [--summary <file>]
// A table on stdout and in the job summary. Fails when ours regresses beyond
// generous limits: the self-compile's peak above the reference's, the native
// build above 3 GB; the WebAssembly builds warn above 4 GB (wasm32's whole
// memory). Linux and macOS (/usr/bin/time); elsewhere the peak is not measured.
class Measure {
	static final NATIVE_BUDGET_MB = 3072;
	static final WASM_WARN_MB = 4096;

	static var rows:Array<MeasureRow> = [];

	static function main() {
		var a = parseArgs(Sys.args(), ["--only", "--port", "--reference", "--summary"]);
		var only = a.has("--only") ? a.get("--only").split(",") : ["self-compile", "native-build", "stage0", "npm-wasm"];
		var port = FileSystem.fullPath(a.get("--port", Sys.getEnv("HAXE_IN_HAXE_PORT") ?? "bin/port/haxe"));
		var reference = a.get("--reference", Sys.getEnv("HAXE_REFERENCE") ?? "bin/reference/haxe");
		var host = (Sys.systemName() == "Mac" ? "macos-" : "linux-") + (exec(["uname", "-m"]).out.trim().startsWith("x86") ? "x86_64" : "arm64");
		var failures = [], warnings = [];
		mkdirs("bin/test/measure");
		var self = ["-cp", "haxe/src", "-main", "haxe.Main", "-D", "disable-parallelism", "--interp", "--no-output", "--hxb"];
		if (only.contains("self-compile")) {
			var ref = measure("self-compile", "reference", [FileSystem.fullPath(reference)].concat(self).concat(["bin/test/measure/ref.hxb"]));
			var ours = measure("self-compile", "ours", [port].concat(self).concat(["bin/test/measure/ours.hxb"]));
			if (ref.ok && ours.ok) {
				var c = compareHxb("bin/test/measure/ref.hxb", "bin/test/measure/ours.hxb");
				if (c != null) failures.push("self-compile: the archives differ: " + c);
				if (ours.peakMb > 0 && ref.peakMb > 0 && ours.peakMb > ref.peakMb)
					failures.push('self-compile: peak ${ours.peakMb} MB above the reference\'s ${ref.peakMb} MB');
			}
		}
		var tool = FileSystem.fullPath("bin/hxmc/hxmc");
		var toolArgs = ["-cp", "haxe/src", "-cp", "hxmc/src", "-main", "hxmc.Main", "-D", "disable-parallelism", "-D", "hih_no_generators", "-cp", "bin/hxmc/std", "--custom-target", "hxmc"];
		if (only.contains("native-build")) {
			rmrf("bin/test/measure/port.hxmc");
			var r = measure("native build (the port, cold)", "ours", [tool, "bin/test/measure/port", "-cp", "haxe/src", "-main", "haxe.Main", "-D", "disable-parallelism",
				"-cp", "bin/hxmc/std", "--custom-target", "hxmc"]);
			if (r.peakMb > NATIVE_BUDGET_MB) failures.push('native build: peak ${r.peakMb} MB above $NATIVE_BUDGET_MB MB');
			rmrf("bin/test/measure/port.hxmc");
		}
		var node = ["node", "--stack-size=65500", FileSystem.fullPath("hxmc/bootstrap/wasi.mjs")];
		if (only.contains("stage0") && FileSystem.exists("hxmc/bootstrap/stage0.wasm.br")) {
			rmrf("bin/test/measure/hxmc1.hxmc");
			var r = measure("stage0 builds the tool (node)", "ours", node.concat([FileSystem.fullPath("hxmc/bootstrap/stage0.wasm.br"), "bin/test/measure/hxmc1"]).concat(toolArgs));
			if (r.peakMb > WASM_WARN_MB) warnings.push('stage0: peak ${r.peakMb} MB above $WASM_WARN_MB MB');
			rmrf("bin/test/measure/hxmc1.hxmc");
		}
		if (only.contains("npm-wasm") && FileSystem.exists("bin/npm/native/wasm32-wasi/haxe.wasm")) {
			rmrf("bin/test/measure/native.hxmc");
			var r = measure("npm wasm builds the compiler (node)", "ours", node.concat([FileSystem.fullPath("bin/npm/native/wasm32-wasi/haxe.wasm"), "-cp", "haxe/src", "-cp", "hxmc/src",
				"-main", "hxmc.HaxeMain", "-D", "disable-parallelism", "-cp", "bin/hxmc/std", "--custom-target", "hxmc=bin/test/measure/native"]), ["HXMC_HOST" => host]);
			if (r.peakMb > WASM_WARN_MB) warnings.push('npm wasm: peak ${r.peakMb} MB above $WASM_WARN_MB MB');
			rmrf("bin/test/measure/native.hxmc");
		}
		for (r in rows) if (!r.ok) failures.push(r.what + " (" + r.who + ") failed: " + r.detail);
		var t = new StringBuf();
		t.add("| build | compiler | peak RSS | wall | CPU |\n| --- | --- | ---: | ---: | ---: |\n");
		for (r in rows) t.add('| ${r.what} | ${r.who} | ${r.peakMb > 0 ? r.peakMb + " MB" : "-"} | ${fixed(r.wall)} s | ${r.cpu > 0 ? fixed(r.cpu) + " s" : "-"} |\n');
		Sys.print(t.toString());
		for (w in warnings) Sys.println("warning: " + w);
		for (f in failures) Sys.println("FAIL: " + f);
		summary(a.get("--summary"), "### Memory and time\n\n" + t.toString() + [for (w in warnings) "\nwarning: " + w].join("") + [for (f in failures) "\n**FAIL**: " + f].join("") + "\n\n");
		Sys.exit(failures.length > 0 ? 1 : 0);
	}

	static function measure(what:String, who:String, cmd:Array<String>, ?env:Map<String, Null<String>>):MeasureRow {
		var log = FileSystem.fullPath("bin/test/measure") + "/" + rows.length + ".log";
		var mac = Sys.systemName() == "Mac";
		var time = FileSystem.exists("/usr/bin/time") ? (mac ? ["/usr/bin/time", "-l"] : ["/usr/bin/time", "-f", "MEASURE %M %e %U %S"]) : [];
		var r = exec(time.concat(cmd), {env: env, log: log});
		var text = readText(log);
		var row:MeasureRow = {what: what, who: who, ok: r.code == 0, peakMb: 0, wall: r.seconds, cpu: 0, detail: r.code == 0 ? "" : tail(text, 400)};
		if (mac) {
			var rss = ~/([0-9]+)\s+maximum resident set size/;
			if (rss.match(text)) row.peakMb = Math.round(Std.parseFloat(rss.matched(1)) / 1048576);
			var t = ~/([0-9.]+) real\s+([0-9.]+) user\s+([0-9.]+) sys/;
			if (t.match(text)) row.cpu = Std.parseFloat(t.matched(2)) + Std.parseFloat(t.matched(3));
		} else {
			var m = ~/MEASURE ([0-9]+) ([0-9.]+) ([0-9.]+) ([0-9.]+)/;
			if (m.match(text)) {
				row.peakMb = Math.round(Std.parseFloat(m.matched(1)) / 1024);
				row.cpu = Std.parseFloat(m.matched(3)) + Std.parseFloat(m.matched(4));
			}
		}
		rows.push(row);
		Sys.println('${what} (${who}): ${row.ok ? "ok" : "FAILED"}, ${row.peakMb} MB, ${fixed(row.wall)} s wall, ${fixed(row.cpu)} s CPU');
		return row;
	}
}

typedef MeasureRow = {what:String, who:String, ok:Bool, peakMb:Int, wall:Float, cpu:Float, detail:String}
