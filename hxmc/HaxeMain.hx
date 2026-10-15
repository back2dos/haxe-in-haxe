package hxmc;

import haxe.io.Path;

// `haxe` with hxmc built in (the npm package): the port's command line, where
// `--custom-target hxmc=<out>` compiles the program to an executable for the
// host (-D hxmc.target=<target> names another). In the package:
//   hxmc/bootstrap/haxe[.exe]        this binary (in place of the launcher), or
//                                    haxe.wasm, its WebAssembly build, run by it
//   haxe/upstream/std                the std (HAXE_STD_PATH unless set)
//   hxmc/bootstrap/std/hxmc/Init.hx  `--custom-target hxmc` calls hxmc.Init.init():
//                                    it adds hxmc/bootstrap/hxmc-std, hxmc's std
//   hxmc/bootstrap/rt/<target>       the runtime objects (rt.o, ssl.o, uv.o)
// Elsewhere (the launcher runs it from its cache) HAXE_STD_PATH and
// HXMC_RT_DIR name them. The WebAssembly build learns the host from HXMC_HOST.
class HaxeMain {
	static function main() {
		Sys.exit(run(Sys.args()));
	}

	public static function run(args:Array<String>):Int {
		var failed = null;
		// (through links to the binary, as npm's node_modules/.bin/haxe)
		var exe = try sys.FileSystem.fullPath(Sys.programPath()) catch (_:Dynamic) Sys.programPath();
		var boot = Path.directory(exe);
		if (sys.FileSystem.exists(boot + "/launcher.mjs")) {
			var pkg = Path.directory(Path.directory(boot));
			if (Sys.getEnv("HXMC_RT_DIR") == null)
				Options.rtDirOverride = boot + "/rt/";
			// the port looks for the std next to the binary as upstream does
			// (<bin>/lib/haxe/std, ...): this layout's through HAXE_STD_PATH
			if (Sys.getEnv("HAXE_STD_PATH") == null)
				Sys.putEnv("HAXE_STD_PATH", pkg + "/haxe/upstream/std" + (Sys.systemName() == "Windows" ? ";" : ":") + boot + "/std");
		}
		var host = hostTarget();
		// (the port calls the hook with --no-output too: e.g. writing HXB only)
		var noOutput = args.contains("--no-output");
		compiler.Compiler.generateHook = function(com) {
			if (noOutput) return;
			switch com.platform {
				case CustomTarget("hxmc"):
				case _: return;
			}
			try {
				if (!core.Define.rawDefined(com.defines, "hxmc.target")) {
					if (host == null) throw "hxmc: the host is unknown (HXMC_HOST): name the target with -D hxmc.target=<target>";
					core.Define.rawDefineValue(com.defines, "hxmc.target", host);
				}
				@:privateAccess Main.generate(com, com.file);
			} catch (e:Dynamic) {
				failed = Std.string(e);
			}
		}
		var code = haxe.Main.run(args);
		if (failed != null) {
			Sys.stderr().writeString("hxmc: " + failed + "\n");
			return 1;
		}
		return code;
	}

	// the target this binary runs on
	static function hostTarget():Null<String> {
		var env = Sys.getEnv("HXMC_HOST");
		if (env != null) return env;
		var t = haxe.macro.Compiler.getDefine("hxmc.target");
		return t == null || t == "1" ? "linux-x86_64" : t == "wasm32-wasi" ? null : t;
	}
}
