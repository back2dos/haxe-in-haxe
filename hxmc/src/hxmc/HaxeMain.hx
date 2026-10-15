package hxmc;

// `haxe` with hxmc built in (packages/haxe): the port's command line, where
// `--custom-target hxmc=<out>` compiles the program to an executable.
// The installation is laid out as
//   <prefix>/bin/haxe[.exe]           this binary (or haxe.wasm, its WebAssembly build)
//   <prefix>/lib/haxe/std             the std (HAXE_STD_PATH unless set), with hxmc/Init.hx
//   <prefix>/lib/haxe/hxmc-std        hxmc's std (bin/hxmc/std), added by hxmc.Init
//   <prefix>/lib/haxe/rt/<target>     the runtime objects (rt.o, ssl.o, uv.o)
// The executable is for the host unless -D hxmc.target names another target;
// the WebAssembly build learns the host from HXMC_HOST.
class HaxeMain {
	static function main() {
		var failed = null;
		// (through links to the binary, as npm's node_modules/.bin/haxe)
		var exe = try sys.FileSystem.fullPath(Sys.programPath()) catch (_:Dynamic) Sys.programPath();
		var lib = haxe.io.Path.directory(haxe.io.Path.directory(exe)) + "/lib/haxe/";
		if (Sys.getEnv("HXMC_RT_DIR") != null)
			Options.rtDirOverride = haxe.io.Path.addTrailingSlash(Sys.getEnv("HXMC_RT_DIR"));
		else if (sys.FileSystem.exists(lib + "rt"))
			Options.rtDirOverride = lib + "rt/";
		// the port looks for the std next to the binary as upstream does
		// (<bin>/lib/haxe/std, ...): this layout's std through HAXE_STD_PATH
		if (Sys.getEnv("HAXE_STD_PATH") == null && sys.FileSystem.exists(lib + "std"))
			Sys.putEnv("HAXE_STD_PATH", sys.FileSystem.fullPath(lib + "std"));
		var host = hostTarget();
		compiler.Compiler.generateHook = function(com) {
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
		var code = haxe.Main.run(Sys.args());
		if (failed != null) {
			Sys.stderr().writeString("hxmc: " + failed + "\n");
			Sys.exit(1);
		}
		Sys.exit(code);
	}

	// the target this binary runs on
	static function hostTarget():Null<String> {
		var env = Sys.getEnv("HXMC_HOST");
		if (env != null) return env;
		var t = haxe.macro.Compiler.getDefine("hxmc.target");
		return t == null || t == "1" ? "linux-x86_64" : t == "wasm32-wasi" ? null : t;
	}
}
