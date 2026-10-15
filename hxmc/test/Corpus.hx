import Harness.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The hxmc test corpus (README.md, "Testing"): every program compiled by
// hxmc, run, and its output compared with its golden file.
//   bin/hxmc/hxmc -cp hxmc/test -cp haxe/test --run Corpus [-j N] [-v] [--target T] [--stage DIR] [--bless] [case ...]
// The cases are the programs of hxmc/test/cases (<Name>.hx with class <Name>)
// and the fuzzer programs frozen in hxmc/test/fuzz-1000.zip (extracted to
// bin/hxmc-fuzz, cases fuzz-<seed>). Each case's HXB archive is written once
// by the tool as the compiler (`-cp bin/hxmc/std --custom-target hxmc`;
// cached, rewritten when a source is newer); the tool compiles it and the
// output ("exit <code>" and stdout) must equal hxmc/test/expected/<case>.txt.
// The golden files are frozen: a new case gets one with --bless (written from
// hxmc's own output, to be checked by hand). --target cross-builds for another
// target (linux-arm64 runs under qemu-aarch64-static, windows-x86_64 under
// wine64, wasm32-wasi under node or, with HXMC_WASM_RUNNER=wasmtime,
// wasmtime); --stage only builds and copies each executable with its golden
// file to DIR/<case>/ (Check runs them on the target's machine).
class Corpus {
	static final OUT = "bin/hxmc-t";
	static final STD = "bin/hxmc/std";
	static final CASES = "hxmc/test/cases";
	static final EXPECTED = "hxmc/test/expected";
	static final FUZZ_ZIP = "hxmc/test/fuzz-1000.zip";
	static final FUZZ = "bin/hxmc-fuzz";
	// the cases a WebAssembly module cannot run
	static final WASM_EXCLUDED = ["ThreadNatives" => "no threads on wasm32-wasi", "NetNatives" => "no sockets on wasm32-wasi"];

	static var tool:String;
	static var target:Null<String>;
	static var stage:Null<String>;
	static var bless = false;

	static function main() {
		var a = parseArgs(Sys.args(), ["-j", "--target", "--stage"]);
		tool = FileSystem.fullPath(Sys.getEnv("HXMC_TOOL") ?? "bin/hxmc/hxmc");
		target = a.get("--target");
		stage = a.get("--stage");
		bless = a.has("--bless");
		var verbose = a.has("-v");
		if (!FileSystem.exists(STD + "/.stamp")) fail("Corpus: bin/hxmc/std is missing (make std)");
		var cases = caseList(a.rest);
		var t0 = now();
		var bad = 0, excluded = 0;
		parallel(cases, a.int("-j", cpus()), runCase, (c, r) -> {
			var good = r.status == "ok" || r.status == "blessed" || r.status == "excluded";
			Sys.println(pad(r.name, 24) + " " + pad(r.status, 12) + " " + (good || !verbose ? r.detail : ""));
			if (r.status == "excluded") excluded++ else if (r.status != "ok" && r.status != "blessed") {
				bad++;
				if (verbose) Sys.println("    " + r.detail.replace("\n", "\n    "));
			}
		});
		Sys.println('${cases.length - bad - excluded}/${cases.length - excluded} ok' + (excluded > 0 ? ' ($excluded excluded)' : '') + ', ${fixed(now() - t0)}s');
		Sys.exit(bad > 0 ? 1 : 0);
	}

	static function fuzzPrograms():Array<String> {
		var stamp = FUZZ + "/.stamp";
		if (!FileSystem.exists(stamp) || mtime(stamp) < mtime(FUZZ_ZIP)) {
			rmrf(FUZZ);
			mkdirs(FUZZ);
			var z = readZip(FUZZ_ZIP);
			for (n in z.names) {
				if (n.endsWith("/")) continue;
				var p = FUZZ + "/" + (n.startsWith("./") ? n.substr(2) : n);
				mkdirs(haxe.io.Path.directory(p));
				File.saveBytes(p, z.data[n]);
			}
			File.saveContent(stamp, "");
		}
		var r = [for (d in FileSystem.readDirectory(FUZZ)) if (FileSystem.exists(FUZZ + "/" + d + "/Main.hx")) d];
		r.sort(compare);
		return r;
	}

	static function caseList(names:Array<String>):Array<Case> {
		var cases:Array<Case> = [];
		var files = [for (f in FileSystem.readDirectory(CASES)) if (f.endsWith(".hx")) f.substr(0, f.length - 3)];
		files.sort(compare);
		for (f in files) cases.push({name: f, cps: [CASES], main: f});
		for (d in fuzzPrograms()) cases.push({name: "fuzz-" + d, cps: [FUZZ + "/" + d], main: "Main"});
		if (names.length == 0) return cases;
		var known = [for (c in cases) c.name => c];
		var bad = [for (n in names) if (!known.exists(n)) n];
		if (bad.length > 0) fail("Corpus: unknown case(s): " + bad.join(", "));
		return [for (n in names) known[n]];
	}

	static function runCase(c:Case):Result {
		var d = OUT + "/" + c.name;
		mkdirs(d);
		var wasm = target != null && target.startsWith("wasm");
		if (wasm && WASM_EXCLUDED.exists(c.name)) return {name: c.name, status: "excluded", detail: WASM_EXCLUDED[c.name]};
		var hxb = d + "/" + (wasm ? 'prog-$target.hxb.zip' : "prog.hxb.zip");
		var t0 = now();
		// (WebAssembly: the program is typed for it, with its runtime)
		if (!FileSystem.exists(hxb) || mtime(hxb) < Math.max(newest(c.cps), mtime(STD + "/.stamp"))) {
			var cmd = [tool];
			// (absolute class paths: positions name the files relative to them)
			for (cp in c.cps) cmd = cmd.concat(["-cp", FileSystem.fullPath(cp)]);
			cmd = cmd.concat(["-cp", FileSystem.fullPath(STD), "-main", c.main, "--custom-target", 'hxmc=$d/x', "--hxb", hxb, "-D", "disable-parallelism", "--no-output"]);
			if (wasm) cmd = cmd.concat(["-D", "hxmc.target=" + target]);
			var r = exec(cmd);
			if (r.code != 0) return {name: c.name, status: "hxb-fail", detail: tail(r.out + r.err, 1500)};
		}
		var expected = EXPECTED + "/" + c.name + ".txt";
		if (!FileSystem.exists(expected) && !bless)
			return {name: c.name, status: "no-golden", detail: '$expected is missing (--bless writes it from hxmc\'s output)'};
		var exe = d + "/" + (target != null ? "m-" + target : "m");
		if (target != null && target.startsWith("windows")) exe += ".exe";
		if (wasm) exe += ".wasm";
		var cmd = [tool, exe, "--hxb-lib", hxb, "-main", c.main, "--custom-target", "hxmc", "-D", "disable-parallelism"];
		if (target != null) cmd = cmd.concat(["-D", "hxmc.target=" + target]);
		var r = exec(cmd, {env: ["HXMC_STATS" => "1"]});
		File.saveContent(d + "/hxmc.log", r.out + r.err);
		if (r.code != 0) return {name: c.name, status: "hxmc-fail", detail: tail(r.out + r.err, 2000)};
		var re = ~/hxmc: ([0-9]+) functions/;
		var nf = re.match(r.out) ? re.matched(1) + " functions" : "";
		if (stage != null) {
			// cross builds: the executable and the expected output, run elsewhere (Check)
			var sd = stage + "/" + c.name;
			mkdirs(sd);
			File.copy(exe, sd + "/m" + (exe.endsWith(".exe") ? ".exe" : exe.endsWith(".wasm") ? ".wasm" : ""));
			File.copy(expected, sd + "/expected.txt");
			return {name: c.name, status: "ok", detail: "staged " + nf};
		}
		var runner = switch target {
			case "linux-arm64": ["qemu-aarch64-static"];
			case "windows-x86_64": ["/usr/lib/wine/wine64"];
			case _ if (wasm): wasmRunner();
			case _: [];
		}
		// a small nursery: frequent collections, so a missing or stale root shows
		var r = exec(runner.concat([FileSystem.fullPath(exe)]), {cwd: d, timeout: 120, env: ["RT_MINOR_KB" => Sys.getEnv("RT_MINOR_KB") ?? "64", "WINEDEBUG" => "-all"]});
		if (r.timedOut) return {name: c.name, status: "timeout", detail: ""};
		var got = 'exit ${r.code}\n' + r.out;
		if (bless && !FileSystem.exists(expected)) {
			File.saveContent(expected, got);
			return {name: c.name, status: "blessed", detail: 'wrote $expected (check it)'};
		}
		if (got != File.getContent(expected)) {
			File.saveContent(d + "/got.txt", got + r.err);
			return {name: c.name, status: "differs", detail: 'diff $expected $d/got.txt\n' + tail(r.err, 800)};
		}
		return {name: c.name, status: "ok", detail: '${fixed(now() - t0)}s $nf'};
	}

	// wasm32-wasi: node (hxmc/bootstrap/wasi.mjs) or, with HXMC_WASM_RUNNER=wasmtime, wasmtime
	public static function wasmRunner():Array<String> {
		if (Sys.getEnv("HXMC_WASM_RUNNER") == "wasmtime") return ["wasmtime", "run", "-W", "exceptions=y", "--dir", ".", "--dir", "/", "--env", "RT_MINOR_KB"];
		return ["node", "--no-warnings", FileSystem.fullPath("hxmc/bootstrap/wasi.mjs")];
	}

	public static function tail(s:String, n:Int):String return s.length <= n ? s : s.substr(s.length - n);
}

typedef Case = {name:String, cps:Array<String>, main:String}
typedef Result = {name:String, status:String, detail:String}
