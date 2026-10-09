// `haxelib run hxc ...`: compiles a Haxe program to C with the bundled hxc
// compiler (bin/hxc.com, the haxe-in-haxe port with the C backend), then to a
// native binary with a C compiler. Runs on the user's own Haxe (--interp).
//
//   haxelib run hxc build.hxml
//   haxelib run hxc -cp src -main Main --custom-target hxc=bin/main
//
// Options (removed before the compiler sees the arguments):
//   --hxc-cc <command>   C compiler (default: $HXC_CC, else cc, gcc, clang, tcc)
//   --hxc-static         fully static, portable binary with cosmocc (downloaded once)
//   --hxc-debug          -O0 -g instead of -O2
//   --hxc-c-only         stop after writing the C file
//   --hxc-ssl, --hxc-uv  link the system's mbedtls / libuv (sys.ssl, eval.luv);
//                        without them those natives throw when called
//   setup-cosmocc        just download cosmocc
import haxe.io.Path;
import sys.FileSystem;
import sys.io.Process;

using StringTools;

class Run {
	static var lib:String;

	static function main() {
		lib = Path.addTrailingSlash(Sys.getCwd()); // haxelib runs us from the library directory
		var args = Sys.args();
		if (Sys.getEnv("HAXELIB_RUN") == "1" && args.length > 0) Sys.setCwd(args.pop()); // and appends the caller's directory
		if (args[0] == "setup-cosmocc") {
			Sys.println(cosmocc());
			return;
		}
		if (args.length == 0 || args[0] == "--help" || args[0] == "help") {
			usage();
			return;
		}
		var cc = Sys.getEnv("HXC_CC"), static_ = false, debug = false, cOnly = false, ssl = false, uv = false;
		var rest = [];
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			switch a {
				case "--hxc-cc": cc = args[i++];
				case "--hxc-static": static_ = true;
				case "--hxc-debug": debug = true;
				case "--hxc-c-only": cOnly = true;
				case "--hxc-ssl": ssl = true;
				case "--hxc-uv": uv = true;
				case _: rest.push(a);
			}
		}
		var out = outputOf(rest);
		if (out == null) {
			out = "bin/main";
			rest = rest.concat(["--custom-target", "hxc=" + out]);
		}
		var dir = Path.directory(out);
		if (dir != "" && !FileSystem.exists(dir)) FileSystem.createDirectory(dir);
		// 1. Haxe -> C
		var code = run(compilerCommand(), [out, "-cp", lib + "hxstd"].concat(rest));
		if (code != 0) Sys.exit(code);
		if (cOnly) return;
		// 2. C -> binary
		var rt = lib + "rt/";
		var files = [out + ".c"].concat([for (f in ["rt", "rt_dyn", "rt_std", "rt_str", "rt_sys", "rt_net", "rt_ssl", "rt_uv"]) rt + f + ".c"]);
		// slots are read as int32/double/pointer through casts: no strict aliasing
		var flags = (debug ? ["-O0", "-g"] : ["-O2"]).concat(["-w", "-fno-strict-aliasing", "-I", rt]);
		var libs = ["-lm"];
		if (ssl) libs = libs.concat(["-lmbedtls", "-lmbedx509", "-lmbedcrypto"]) else flags.push("-DHXC_NO_SSL");
		if (uv) libs.push("-luv") else flags.push("-DHXC_NO_UV");
		var compiler = static_ ? Path.join([cosmocc(), "bin", "cosmocc"]) : (cc != null ? cc : findCc());
		var parts = compiler.split(" ");
		code = run(parts[0], parts.slice(1).concat(flags).concat(files).concat(libs).concat(["-o", out]));
		if (code != 0) Sys.exit(code);
		// cosmocc's per-architecture binaries and symbols, next to the fat binary
		if (static_ && !debug) for (f in [out + ".aarch64.elf", out + ".com.dbg"]) if (FileSystem.exists(f)) FileSystem.deleteFile(f);
		Sys.println(out);
	}

	static function usage() {
		Sys.println("hxc: Haxe to C, then to a native binary.\n");
		Sys.println("  haxelib run hxc build.hxml");
		Sys.println("  haxelib run hxc -cp src -main Main --custom-target hxc=bin/main\n");
		Sys.println("  --hxc-cc <command>  C compiler (default: $HXC_CC, else cc, gcc, clang, tcc)");
		Sys.println("  --hxc-static        static, portable binary with cosmocc (downloaded once)");
		Sys.println("  --hxc-debug         -O0 -g");
		Sys.println("  --hxc-c-only        stop after writing the C file");
		Sys.println("  --hxc-ssl, --hxc-uv link the system's mbedtls / libuv");
		Sys.println("  setup-cosmocc       download cosmocc now");
	}

	// the path given with --custom-target hxc=<path> (in the arguments or in an .hxml file)
	static function outputOf(args:Array<String>):Null<String> {
		for (i in 0...args.length) {
			var a = args[i];
			if ((a == "--custom-target" || a == "-custom") && i + 1 < args.length && args[i + 1].startsWith("hxc=")) return args[i + 1].substr(4);
			if (a.endsWith(".hxml") && FileSystem.exists(a)) {
				var words = [];
				for (line in sys.io.File.getContent(a).split("\n")) {
					line = line.trim();
					if (line == "" || line.startsWith("#")) continue;
					for (w in line.split(" ")) if (w != "") words.push(w);
				}
				var o = outputOf(words);
				if (o != null) return o;
			}
		}
		return null;
	}

	static function compilerCommand():String {
		var com = lib + "bin/hxc.com";
		if (Sys.systemName() == "Windows") return com;
		// an APE file starts as a shell script: `sh` runs it without binfmt_misc
		Sys.putEnv("HXC_APE", com);
		return "sh";
	}

	static function run(cmd:String, args:Array<String>):Int {
		if (cmd == "sh") args = [Sys.getEnv("HXC_APE")].concat(args);
		return Sys.command(cmd, args);
	}

	static function findCc():String {
		for (c in ["cc", "gcc", "clang", "tcc"])
			if (exists(c)) return c;
		Sys.println("hxc: no C compiler found (cc, gcc, clang or tcc); using cosmocc");
		return Path.join([cosmocc(), "bin", "cosmocc"]);
	}

	static function exists(cmd:String):Bool {
		try {
			var p = new Process(Sys.systemName() == "Windows" ? "where" : "which", [cmd]);
			var ok = p.exitCode() == 0;
			p.close();
			return ok;
		} catch (_:Dynamic) {
			return false;
		}
	}

	// cosmocc, downloaded and unpacked once into ~/.hxc/cosmocc
	static function cosmocc():String {
		var home = Sys.getEnv(Sys.systemName() == "Windows" ? "USERPROFILE" : "HOME");
		var dir = Path.join([home, ".hxc", "cosmocc"]);
		if (FileSystem.exists(Path.join([dir, "bin", "cosmocc"]))) return dir;
		FileSystem.createDirectory(dir);
		var zip = Path.join([home, ".hxc", "cosmocc.zip"]);
		var url = Sys.getEnv("HXC_COSMOCC_URL");
		if (url == null) url = "https://cosmo.zip/pub/cosmocc/cosmocc.zip";
		Sys.println('hxc: downloading cosmocc (~420 MB) from $url');
		if ((exists("curl") ? Sys.command("curl", ["-fL", "-o", zip, url]) : Sys.command("wget", ["-O", zip, url])) != 0) {
			Sys.println("hxc: download failed");
			Sys.exit(1);
		}
		if (Sys.command("unzip", ["-q", "-o", zip, "-d", dir]) != 0) {
			Sys.println("hxc: unzip failed");
			Sys.exit(1);
		}
		FileSystem.deleteFile(zip);
		return dir;
	}
}
