package hxc;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.Process;

using StringTools;

// The steps after typing, run by the user's Haxe (macro context or haxelib run):
// the bundled compiler lowers the HXB archive to C, then a C compiler builds it.
class Build {
	public static var lib(get, default):String;
	public static var verbose = false;

	// the library root: hxstd/hxc/Build.hx -> ../../
	static function get_lib():String {
		if (lib == null) {
			var here = haxe.macro.Context.resolvePath("hxc/Build.hx");
			lib = Path.addTrailingSlash(Path.normalize(Path.join([Path.directory(FileSystem.absolutePath(here)), "..", ".."])));
		}
		return lib;
	}

	public static function toC(archive:String, out:String, main:String, defines:Array<String>, stdPath:Array<String>):Int {
		// The modules come from the archive. The std path must still be the one
		// the program was typed with: DCE (rerun on the loaded modules) keeps the
		// whole of every class whose file is outside the std path
		Sys.putEnv("HAXE_STD_PATH", stdPath.join(Sys.systemName() == "Windows" ? ";" : ":"));
		var args = [out, "--hxb-lib", archive, "-main", main, "--custom-target", "hxc", "-D", "disable-parallelism"];
		for (d in defines) args = args.concat(["-D", d]);
		var com = lib + "bin/hxc.com";
		if (verbose) Sys.println("hxc: " + [com].concat(args).join(" "));
		if (Sys.systemName() == "Windows") return Sys.command(com, args);
		// an APE file starts as a shell script: `sh` runs it without binfmt_misc.
		// Loading modules from HXB recurses deeply on large programs: raise the stack limit
		return Sys.command("sh", ["-c", 'ulimit -s unlimited 2>/dev/null || ulimit -s $$(ulimit -H -s) 2>/dev/null; exec sh "$$0" "$$@"', com].concat(args));
	}

	public static function toBinary(out:String, o:Options):Int {
		var rt = lib + "rt/";
		var files = [out + ".c"].concat([for (f in ["rt", "rt_dyn", "rt_std", "rt_str", "rt_sys", "rt_net", "rt_ssl", "rt_uv"]) rt + f + ".c"]);
		// slots are read as int32/double/pointer through casts: no strict aliasing
		var flags = (o.debug ? ["-O0", "-g"] : ["-O2"]).concat(["-w", "-fno-strict-aliasing", "-I", rt]);
		var libs = ["-lm"];
		if (o.ssl) libs = libs.concat(["-lmbedtls", "-lmbedx509", "-lmbedcrypto"]) else flags.push("-DHXC_NO_SSL");
		if (o.uv) libs.push("-luv") else flags.push("-DHXC_NO_UV");
		var compiler = o.isStatic ? cosmocc() : (o.cc != null ? o.cc : findCc());
		var parts = compiler.split(" ");
		if (verbose) Sys.println("hxc: " + parts.concat(flags).concat(files).concat(libs).concat(["-o", out]).join(" "));
		var code = Sys.command(parts[0], parts.slice(1).concat(flags).concat(files).concat(libs).concat(["-o", out]));
		// cosmocc's per-architecture binaries and symbols, next to the fat binary
		if (code == 0 && o.isStatic && !o.debug)
			for (f in [out + ".aarch64.elf", out + ".com.dbg"]) if (FileSystem.exists(f)) FileSystem.deleteFile(f);
		return code;
	}

	static function findCc():String {
		for (c in ["cc", "gcc", "clang", "tcc"])
			if (exists(c)) return c;
		Sys.println("hxc: no C compiler found (cc, gcc, clang or tcc); using cosmocc");
		return cosmocc();
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
	public static function cosmocc():String {
		var home = Sys.getEnv(Sys.systemName() == "Windows" ? "USERPROFILE" : "HOME");
		var dir = Path.join([home, ".hxc", "cosmocc"]);
		var bin = Path.join([dir, "bin", "cosmocc"]);
		if (FileSystem.exists(bin)) return bin;
		FileSystem.createDirectory(dir);
		var zip = Path.join([home, ".hxc", "cosmocc.zip"]);
		var url = Sys.getEnv("HXC_COSMOCC_URL");
		if (url == null) url = "https://cosmo.zip/pub/cosmocc/cosmocc.zip";
		Sys.println('hxc: downloading cosmocc (~420 MB unpacked) from $url');
		if ((exists("curl") ? Sys.command("curl", ["-fL", "-o", zip, url]) : Sys.command("wget", ["-O", zip, url])) != 0)
			throw "hxc: cosmocc download failed";
		if (Sys.command("unzip", ["-q", "-o", zip, "-d", dir]) != 0) throw "hxc: unzip failed";
		FileSystem.deleteFile(zip);
		return bin;
	}
}

typedef Options = {
	var cc:Null<String>;
	var isStatic:Bool;
	var debug:Bool;
	var ssl:Bool;
	var uv:Bool;
}
