import Harness.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Runs the executables staged by `Corpus --stage <dir>` on the machine of
// their target (CI's test jobs) and compares each output with its golden file:
//   <haxe> -cp hxmc/test -cp haxe/test --run Check <dir> [--summary <file>] [--runner <command>] [--timeout <s>]
// WebAssembly modules (m.wasm) run under --runner (node with
// hxmc/bootstrap/wasi.mjs, or wasmtime). Exits non-zero when a case differs.
class Check {
	static function main() {
		var a = parseArgs(Sys.args(), ["--summary", "--runner", "--timeout"]);
		if (a.rest.length != 1) fail("usage: Check <dir> [--summary <file>] [--runner <command>]");
		var dir = a.rest[0];
		var runner = shellSplit(a.get("--runner", ""));
		var timeout = a.int("--timeout", 300);
		var cases = [for (d in FileSystem.readDirectory(dir)) if (FileSystem.exists('$dir/$d/expected.txt')) d];
		cases.sort(compare);
		var bad = [];
		var t0 = now();
		for (c in cases) {
			var d = '$dir/$c';
			var exe = FileSystem.exists('$d/m.exe') ? '$d/m.exe' : FileSystem.exists('$d/m.wasm') ? '$d/m.wasm' : '$d/m';
			if (!windows) exec(["chmod", "+x", exe]);
			var r = exec(runner.concat([FileSystem.fullPath(exe)]), {cwd: d, timeout: timeout, env: ["RT_MINOR_KB" => Sys.getEnv("RT_MINOR_KB") ?? "64"]});
			var got = r.timedOut ? "timeout\n" : 'exit ${r.code}\n' + r.out;
			var exp = File.getContent('$d/expected.txt');
			var ok = got == exp;
			Sys.println(pad(c, 24) + " " + pad(ok ? "ok" : "DIFFERS", 8) + " " + fixed(r.seconds) + "s");
			if (!ok) {
				File.saveContent('$d/got.txt', got + r.err);
				var diff = lineDiff(exp, got, 30);
				bad.push({name: c, diff: diff, err: tail(r.err, 1500)});
				Sys.println("    " + diff.join("\n    "));
				if (r.err != "") Sys.println("    stderr: " + tail(r.err, 1500).replace("\n", "\n    "));
			}
		}
		Sys.println('${cases.length - bad.length}/${cases.length} ok, ${fixed(now() - t0)}s');
		var s = new StringBuf();
		s.add('### ${haxe.io.Path.withoutDirectory(haxe.io.Path.removeTrailingSlashes(dir))}: ${cases.length - bad.length}/${cases.length} ok\n\n');
		for (b in bad.slice(0, 20)) s.add('<details><summary>${b.name}</summary>\n\n```\n${b.diff.join("\n")}\n${b.err}\n```\n</details>\n\n');
		summary(a.get("--summary"), s.toString());
		Sys.exit(bad.length > 0 || cases.length == 0 ? 1 : 0);
	}
}
