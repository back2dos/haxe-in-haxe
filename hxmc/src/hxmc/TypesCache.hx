package hxmc;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

// The runtime's typed modules, cached (README.md, "Runtime in Haxe"): the
// modules of hxmc's own package of the std (the runtime, hxmc.unsafe, the
// natives: about 15k lines a program would otherwise type every time) are
// typed once per tool and configuration by a separate run of the tool
// (`--types-cache`), which writes them as an HXB archive; a build then loads
// them from it as a library (--hxb-lib) instead of typing them. They are the
// same typed modules either way (HXB round-trips them), so the executable is
// the same.
//
// The cache is the user's (HXMC_CACHE, else $XDG_CACHE_HOME/hxmc or
// ~/.cache/hxmc, macOS ~/Library/Caches/hxmc, Windows
// %LOCALAPPDATA%\hxmc\cache), shared by every build of the tool:
// <cache>/types/<tool>/ holds one build's entries, <config>.zip the archive
// and <config>.deps what it was typed from: every module file the run typed
// (each must still be the file the build would read, unchanged: size and
// date) and the defines the conditions of those files test (each must have
// the build's value). The .deps is written last and deleted first: an entry
// without it is not there; anything missing, unreadable or different is a
// miss, never an error, and a cache that cannot be written is not used.
// <tool>/used is the last build that used it (refreshed at most every
// USED_REFRESH); at most every TRIM_INTERVAL (<cache>/types/trim.txt) a
// build removes the tool directories unused for MAX_UNUSED, and the least
// recently used ones while the whole exceeds MAX_SIZE (best effort: errors
// are ignored, a failed removal is retried next time). HXMC_TYPES_CACHE=0
// turns the cache off. Builds with init macros (--macro), HXB libraries of
// their own, HXB output or display requests, and the compilation server,
// type everything as usual.
class TypesCache {
	// the module that imports every module of the package
	static inline var ALL = "hxmc.rt.Modules";

	// seconds between two refreshes of a tool directory's last use
	static inline var USED_REFRESH = 3600.0;
	// seconds between two trims of the cache
	static inline var TRIM_INTERVAL = 86400.0;
	// seconds without use after which a tool directory goes
	static inline var MAX_UNUSED = 14 * 86400.0;
	// bytes the tool directories may take together (beyond it the least
	// recently used go, except those used within two USED_REFRESH: they may
	// be in use)
	static inline var MAX_SIZE = 1024.0 * 1024 * 1024;

	public static function install()
		compiler.Compiler.beforeTypingHook = hook;

	// <cache>/types/ (null: no place for it)
	static function typesDir():Null<String> {
		inline function env(n:String):Null<String> {
			var v = Sys.getEnv(n);
			return v == null || v == "" ? null : v;
		}
		var d = env("HXMC_CACHE");
		if (d == null) {
			var home = env("HOME");
			d = switch Sys.systemName() {
				case "Windows":
					var l = env("LOCALAPPDATA");
					if (l == null && env("USERPROFILE") != null) l = env("USERPROFILE") + "/AppData/Local";
					l == null ? null : l + "/hxmc/cache";
				case "Mac": home == null ? null : home + "/Library/Caches/hxmc";
				case _:
					var x = env("XDG_CACHE_HOME");
					x != null && Path.isAbsolute(x) ? x + "/hxmc" : home == null ? null : home + "/.cache/hxmc";
			}
		}
		return d == null ? null : Path.addTrailingSlash(d) + "types/";
	}

	static function now():Float
		return Date.now().getTime() / 1000;

	static function mtime(p:String):Float
		return try FileSystem.stat(p).mtime.getTime() / 1000 catch (_:Dynamic) 0.0;

	static function stamp(p:String):String {
		var s = try FileSystem.stat(p) catch (_:Dynamic) null;
		return s == null ? "?" : s.size + "@" + s.mtime.getTime();
	}

	// (the binary, however it was named)
	static function toolStamp():String {
		var p = try FileSystem.fullPath(Sys.programPath()) catch (_:Dynamic) Sys.programPath();
		return Fingerprint.hash("hxmc-types|" + p + "|" + stamp(p)).substr(0, 16);
	}

	// the defines that select a configuration (they are passed to the run
	// that types the modules)
	static var CONFIG = ["hxmc.target", "hxmc.census"];

	static function define(com:context.Common.CommonContext, name:String):Null<String> {
		var u = StringTools.replace(name, "-", "_");
		if (core.Define.rawDefined(com.defines, u)) return core.Define.rawDefinedValue(com.defines, u);
		if (core.Define.rawDefined(com.defines, name)) return core.Define.rawDefinedValue(com.defines, name);
		return null;
	}

	static function hook(com:context.Common.CommonContext, actx:compiler.ParsedArg.ArgContext) {
		if (Sys.getEnv("HXMC_TYPES_CACHE") == "0" || Sys.systemName() == "Wasi" || Driver.resident) return;
		switch com.platform {
			case CustomTarget("hxmc"):
			case _: return;
		}
		if (actx.hxbLibs.length > 0 || actx.configMacros.length > 0 || actx.hxbOut != null || actx.displayArg != null) return;
		// the class path of hxmc's std: the first with the runtime
		var std = null;
		for (cp in com.classPaths.asStringList())
			if (cp != "" && FileSystem.exists(Path.addTrailingSlash(cp) + "hxmc/rt/Runtime.hx")) {
				std = FileSystem.absolutePath(Path.addTrailingSlash(cp));
				break;
			}
		if (std == null) return;
		var config = [for (n in CONFIG) {var v = define(com, n); v == null ? null : n + "=" + v;}].filter(x -> x != null);
		var types = typesDir();
		if (types == null) return;
		var dir = types + toolStamp() + "/";
		var base = dir + Fingerprint.hash(std + "|" + Sys.getEnv("HAXE_STD_PATH") + "|" + config.join("|")).substr(0, 16);
		if (!valid(com, base)) {
			// (writing `used` also tells whether the cache can be written)
			if (!touch(dir + "used")) return;
			if (!build(std, config, base)) return;
			if (!valid(com, base)) return;
		} else if (now() - mtime(dir + "used") > USED_REFRESH)
			touch(dir + "used");
		trim(types, dir);
		actx.hxbLibs.unshift(compiler.ParsedArg.ParsedArgTools.createNativeLib(base + ".zip", false, HxbLib));
	}

	static function touch(p:String):Bool {
		try {
			var d = Path.directory(p);
			if (!FileSystem.exists(d)) FileSystem.createDirectory(d);
			File.saveContent(p, Std.string(now()));
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	// tmp renamed to p, replacing it (where a rename does not replace a file,
	// as on Windows, p is deleted first)
	static function replace(tmp:String, p:String):Bool {
		try {
			FileSystem.rename(tmp, p);
			return true;
		} catch (_:Dynamic) {}
		try {
			FileSystem.deleteFile(p);
			FileSystem.rename(tmp, p);
			return true;
		} catch (_:Dynamic) {
			try FileSystem.deleteFile(tmp) catch (_:Dynamic) {}
			return false;
		}
	}

	// removes the tool directories unused for MAX_UNUSED, then the least
	// recently used ones beyond MAX_SIZE, at most once every TRIM_INTERVAL
	// (two builds trimming at once remove the same ones); the
	// running tool's (mine) stays
	static function trim(types:String, mine:String) {
		var t = now();
		var last = try Std.parseFloat(File.getContent(types + "trim.txt")) catch (_:Dynamic) Math.NaN;
		if (last <= t && t - last < TRIM_INTERVAL) return;
		var tmp = types + "trim." + nonce() + ".tmp";
		if (!touch(tmp) || !replace(tmp, types + "trim.txt")) return;
		var dirs = [];
		var total = 0.0;
		for (n in try FileSystem.readDirectory(types) catch (_:Dynamic) []) {
			var d = types + n + "/";
			if (!FileSystem.isDirectory(d)) continue;
			var size = 0.0;
			for (f in try FileSystem.readDirectory(d) catch (_:Dynamic) []) {
				size += try FileSystem.stat(d + f).size catch (_:Dynamic) 0;
				// (and the leftovers of runs that did not finish)
				if (d == mine && f.indexOf(".tmp") >= 0 && t - mtime(d + f) > TRIM_INTERVAL)
					try FileSystem.deleteFile(d + f) catch (_:Dynamic) {}
			}
			total += size;
			if (d != mine) dirs.push({dir: d, used: FileSystem.exists(d + "used") ? mtime(d + "used") : mtime(d), size: size});
		}
		dirs.sort((a, b) -> a.used < b.used ? -1 : a.used > b.used ? 1 : 0);
		for (e in dirs)
			if (t - e.used > MAX_UNUSED || (total > MAX_SIZE && t - e.used > 2 * USED_REFRESH)) {
				total -= e.size;
				// (the .deps first: what remains is no entry; `used` last: a
				// removal that fails keeps its date)
				var files = try FileSystem.readDirectory(e.dir) catch (_:Dynamic) [];
				files.sort((a, b) -> (StringTools.endsWith(a, ".deps") ? 0 : a == "used" ? 2 : 1) - (StringTools.endsWith(b, ".deps") ? 0 : b == "used" ? 2 : 1));
				for (f in files)
					try FileSystem.deleteFile(e.dir + f) catch (_:Dynamic) {}
				try FileSystem.deleteDirectory(e.dir) catch (_:Dynamic) {}
			}
	}

	// a name for temporary files (builds may write the same file at the same
	// time, and rand() is the same sequence in every process)
	static function nonce():String
		return Fingerprint.hash(Sys.args().join("\x00") + "|" + Sys.time() + "|" + haxe.Timer.stamp() + "|" + Sys.programPath()).substr(0, 16);

	// whether the archive can stand in for typing its modules in this build
	static function valid(com:context.Common.CommonContext, base:String):Bool {
		if (!FileSystem.exists(base + ".zip")) return false;
		var lines = try File.getContent(base + ".deps").split("\n") catch (_:Dynamic) return false;
		if (lines[0] != "hxmc-types 1") return false;
		for (k in 1...lines.length) {
			var f = lines[k].split("\t");
			switch f[0] {
				case "D": // a define, its value (none: absent)
					var v = define(com, f[1]);
					if ((v == null ? "" : "=" + v) != (f.length > 2 ? f[2] : "")) return false;
				case "F": // a module's file as the build finds it, its stamp
					var r = com.classPaths.findFileNoRaise(f[1]);
					if (r == null || FileSystem.absolutePath(r.resolvedFile.file) != f[2] || stamp(f[2]) != f[3]) return false;
				case "":
				case _:
					return false;
			}
		}
		return true;
	}

	// types the package's modules into the archive (another run of the tool)
	static function build(std:String, config:Array<String>, base:String):Bool {
		var args = ["--types-cache", base, nonce(), "-cp", std, "--custom-target", "hxmc", ALL];
		for (c in config)
			args = args.concat(["-D", c]);
		try {
			var p = new sys.io.Process(Sys.programPath(), args);
			p.stdout.readAll();
			p.stderr.readAll();
			return p.exitCode() == 0;
		} catch (_:Dynamic) {
			return false;
		}
	}

	// `hxmc --types-cache <base> <nonce> <haxe arguments>`: the run that types
	// the modules (written beside, then renamed into place: the old .deps
	// deleted, the .zip replaced, the .deps last; builds running at the same
	// time see either no entry or a whole one)
	public static function write(args:Array<String>):Int {
		var base = args.shift();
		var nonce = args.shift();
		var tmp = base + "." + nonce + ".tmp";
		var conf = tmp + ".json";
		try {
			var dir = Path.directory(base);
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			File.saveContent(conf, haxe.Json.stringify({
				archivePath: tmp + ".zip",
				targetConfig: {exclude: ["**"], include: ["hxmc"], generateDocumentation: false},
				macroConfig: {generate: false}
			}));
		} catch (_:Dynamic) {
			return 1;
		}
		var deps = null;
		compiler.Compiler.generateHook = com -> deps = depsOf(com);
		var code = try haxe.Main.run(args.concat(["--no-output", "--hxb", conf])) catch (_:Dynamic) 1;
		try FileSystem.deleteFile(conf) catch (_:Dynamic) {}
		var ok = code == 0 && deps != null && FileSystem.exists(tmp + ".zip");
		if (ok)
			try {
				File.saveContent(tmp + ".deps", deps);
				if (FileSystem.exists(base + ".deps")) FileSystem.deleteFile(base + ".deps");
				ok = replace(tmp + ".zip", base + ".zip") && replace(tmp + ".deps", base + ".deps");
			} catch (_:Dynamic) {
				ok = false;
			}
		for (f in [tmp + ".deps", tmp + ".zip"])
			if (FileSystem.exists(f)) try FileSystem.deleteFile(f) catch (_:Dynamic) {}
		return ok ? 0 : 1;
	}

	// the names the conditions of a source test (#if and #elseif; a name, or
	// a parenthesized expression whose string literals are values)
	static function conditions(src:String, names:Map<String, Bool>) {
		var i = 0;
		while ((i = src.indexOf("#", i)) >= 0) {
			i++;
			if (src.substr(i, 2) == "if") i += 2 else if (src.substr(i, 6) == "elseif") i += 6 else continue;
			while (i < src.length && (src.charAt(i) == " " || src.charAt(i) == "\t" || src.charAt(i) == "!")) i++;
			var start = i;
			if (src.charAt(i) == "(") {
				var depth = 0;
				while (i < src.length) {
					var c = src.charAt(i++);
					if (c == "(") depth++ else if (c == ")" && --depth == 0) break;
				}
			} else
				while (i < src.length && ~/[A-Za-z0-9_.-]/.match(src.charAt(i))) i++;
			var cond = ~/"[^"]*"/g.replace(src.substring(start, i), "");
			var re = ~/[A-Za-z_][A-Za-z0-9_.-]*/;
			while (re.match(cond)) {
				names.set(re.matched(0), true);
				cond = re.matchedRight();
			}
		}
	}

	// the module files the run typed, and the defines their conditions test
	static function depsOf(com:context.Common.CommonContext):String {
		var out = new StringBuf();
		out.add("hxmc-types 1\n");
		var names = new Map<String, Bool>();
		var files = [];
		for (m in com.modules) {
			var file = m.mExtra.mFile.path;
			if (!FileSystem.exists(file)) continue;
			var rel = m.mPath.pack.concat([m.mPath.name]).join("/") + ".hx";
			files.push('F\t$rel\t${FileSystem.absolutePath(file)}\t${stamp(file)}');
			conditions(File.getContent(file), names);
		}
		files.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var ns = [for (n in names.keys()) n];
		ns.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		for (n in ns) {
			var v = define(com, n);
			out.add('D\t$n\t${v == null ? "" : "=" + v}\n');
		}
		for (f in files)
			out.add(f + "\n");
		return out.toString();
	}
}
