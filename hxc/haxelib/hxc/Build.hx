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

	// single: one file <out>.c instead of the chunks of <out>_hxc/
	public static function toC(archive:String, out:String, main:String, defines:Array<String>, stdPath:Array<String>, single = false):Int {
		Sys.putEnv("HXC_SINGLE", single ? "1" : "0");
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
		var rtFiles = [for (f in ["rt", "rt_dyn", "rt_std", "rt_str", "rt_sys", "rt_net", "rt_ssl", "rt_uv", "rt_thread", "rt_census", "rt_win", "rt_sys_win", "rt_net_win"]) rt + f + ".c"];
		// chunked output (<out>_hxc/files.txt) unless hxc.com wrote one file (-D hxc.single)
		var chunks = out + "_hxc/";
		var single = o.single == true;
		var files = single ? [out + ".c"].concat(rtFiles) : rtFiles;
		// slots are read as int32/double/pointer through casts: no strict aliasing
		var flags = (o.debug ? ["-O0", "-g"] : ["-O2"]).concat(["-w", "-fno-strict-aliasing", "-I", rt]);
		var libs = ["-lm"];
		var compiler = o.isStatic ? cosmocc() : (o.cc != null ? o.cc : findCc());
		var isCosmo = o.isStatic || StringTools.endsWith(compiler.split(" ")[0], "cosmocc");
		if ((o.ssl || o.uv) && isCosmo) {
			// cosmocc can't link the system's libraries: the package carries mbedtls and
			// libuv built with cosmocc (fat static libraries, hxc/tools/deps.sh cosmo).
			// `-L<dir>` in one argument: cosmocc maps it to <dir>/.aarch64 for the aarch64 half
			var deps = lib + "cosmo/";
			if (!FileSystem.exists(deps + "lib/libuv.a")) throw 'hxc: $deps is missing: this hxc package has no mbedtls/libuv for -D hxc.static';
			flags = flags.concat(["-I", deps + "include"]);
			libs.push("-L" + deps + "lib");
		}
		if (o.ssl) libs = libs.concat(["-lmbedtls", "-lmbedx509", "-lmbedcrypto"]) else flags.push("-DHXC_NO_SSL");
		if (o.uv) libs.push("-luv") else flags.push("-DHXC_NO_UV");
		var parts = compiler.split(" ");
		var code;
		if (single) {
			if (verbose) Sys.println("hxc: " + parts.concat(flags).concat(files).concat(libs).concat(["-o", out]).join(" "));
			code = Sys.command(parts[0], parts.slice(1).concat(flags).concat(files).concat(libs).concat(["-o", out]));
		} else {
			// release builds fold the ids into the code (ids.h); debug builds keep them
			// as const globals, so an edit recompiles only the chunks it changes
			var objs = compileChunks(parts, o.debug ? flags : flags.concat(["-DHXC_CONST_IDS"]), chunks, rtFiles, rt, o.jobs);
			if (objs == null) return 1;
			if (verbose) Sys.println("hxc: " + parts.concat(flags).concat(["<" + objs.length + " objects>"]).concat(libs).concat(["-o", out]).join(" "));
			code = Sys.command(parts[0], parts.slice(1).concat(flags).concat(objs).concat(libs).concat(["-o", out]));
		}
		// cosmocc's per-architecture binaries and symbols, next to the fat binary
		if (code == 0 && o.isStatic && !o.debug)
			for (f in [out + ".aarch64.elf", out + ".com.dbg"]) if (FileSystem.exists(f)) FileSystem.deleteFile(f);
		return code;
	}

	// Compiles the chunks <dir>files.txt lists and the runtime, `jobs` at a time
	// (default: the number of cores), into <dir>obj-<hash of the command>/,
	// reusing objects newer than their source and the headers. Returns the
	// objects, or null when a compilation failed.
	static function compileChunks(cc:Array<String>, flags:Array<String>, dir:String, rtFiles:Array<String>, rt:String, jobs:Null<Int>):Null<Array<String>> {
		var objDir = dir + "obj-" + haxe.crypto.Md5.encode(cc.concat(flags).join(" ")).substr(0, 12) + "/";
		if (!FileSystem.exists(objDir)) FileSystem.createDirectory(objDir);
		var mtime = (f:String) -> FileSystem.exists(f) ? FileSystem.stat(f).mtime.getTime() : -1.0;
		var genHeaders = Math.max(mtime(dir + "hxc.h"), Math.max(mtime(rt + "rt.h"), mtime(rt + "rt_gc.h")));
		if (flags.contains("-DHXC_CONST_IDS")) genHeaders = Math.max(genHeaders, mtime(dir + "ids.h"));
		var rtHeaders = Math.max(mtime(rt + "rt.h"), mtime(rt + "rt_gc.h"));
		var objs = [], todo = [];
		var sources = [for (f in sys.io.File.getContent(dir + "files.txt").split("\n")) if (f.trim() != "") {src: dir + f.trim(), headers: genHeaders}];
		for (f in rtFiles)
			sources.push({src: f, headers: rtHeaders});
		for (s in sources) {
			var o = objDir + haxe.io.Path.withoutDirectory(haxe.io.Path.withoutExtension(s.src)) + ".o";
			objs.push(o);
			var t = mtime(o);
			if (t < 0 || t < mtime(s.src) || t < s.headers) todo.push({src: s.src, obj: o});
		}
		if (jobs == null || jobs < 1) jobs = cores();
		if (verbose) Sys.println('hxc: compiling ${todo.length} of ${objs.length} files, $jobs at a time');
		var failed = false;
		var command = (t:{src:String, obj:String}) -> cc.concat(flags).concat(["-c", t.src, "-o", t.obj]);
		if (Sys.systemName() == "Windows" || jobs == 1) {
			for (t in todo)
				if (!failed && Sys.command(cc[0], command(t).slice(1)) != 0) failed = true;
		} else {
			// at most `jobs` processes; output merged into stdout (`2>&1`), read when the oldest finishes
			var running:Array<{p:Process, obj:String}> = [];
			function wait() {
				var r = running.shift();
				var output = r.p.stdout.readAll().toString();
				var code = r.p.exitCode();
				r.p.close();
				if (output != "") Sys.print(output);
				if (code != 0) {
					failed = true;
					if (FileSystem.exists(r.obj)) FileSystem.deleteFile(r.obj);
				}
			}
			for (t in todo) {
				if (failed) break;
				if (running.length >= jobs) wait();
				running.push({p: new Process("sh", ["-c", 'exec "$$@" 2>&1', "sh"].concat(command(t))), obj: t.obj});
			}
			while (running.length > 0)
				wait();
		}
		return failed ? null : objs;
	}

	static function cores():Int {
		var env = Sys.getEnv("HXC_JOBS");
		var n = env == null ? null : Std.parseInt(env);
		if (n != null && n > 0) return n;
		try {
			var p = new Process("sh", ["-c", "nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu"]);
			n = Std.parseInt(p.stdout.readAll().toString().trim());
			p.close();
		} catch (_:Dynamic) {}
		return n != null && n > 0 ? n : 4;
	}

	static function findCc():String {
		// clang first: 4-10% less CPU than gcc on the self-compile (site/bench/README.md, 2026-10-09 clang)
		for (c in ["clang", "cc", "gcc", "tcc"])
			if (exists(c)) return c;
		Sys.println("hxc: no C compiler found (clang, cc, gcc or tcc); using cosmocc");
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
	var ?single:Bool; // toC wrote one file
	var ?jobs:Int; // parallel C compilations (default: $HXC_JOBS, else the number of cores)
}
