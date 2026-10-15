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
// <cache>/<tool>-<config>.zip is the archive and .deps what it was typed
// from: every module file the run typed (each must still be the file the
// build would read, unchanged: size and date) and the defines the conditions
// of those files test (each must have the build's value). The cache is
// <tool dir>cache/ (HXMC_CACHE); HXMC_TYPES_CACHE=0 turns it off. Builds
// with init macros (--macro), HXB libraries of their own, HXB output or
// display requests, and the compilation server, type everything as usual.
class TypesCache {
	// the module that imports every module of the package
	static inline var ALL = "hxmc.rt.Modules";

	public static function install()
		compiler.Compiler.beforeTypingHook = hook;

	static function cacheDir():String {
		var d = Sys.getEnv("HXMC_CACHE");
		return d != null && d != "" ? Path.addTrailingSlash(d) : Options.toolDir() + "cache/";
	}

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
		var dir = cacheDir();
		var base = dir + toolStamp() + "-" + Fingerprint.hash(std + "|" + Sys.getEnv("HAXE_STD_PATH") + "|" + config.join("|")).substr(0, 16);
		if (!valid(com, base)) {
			if (!build(std, config, base)) return;
			if (!valid(com, base)) return;
		}
		actx.hxbLibs.unshift(compiler.ParsedArg.ParsedArgTools.createNativeLib(base + ".zip", false, HxbLib));
	}

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
		// (a name for its temporary files: builds may write the same archive at
		// the same time, and rand() is the same sequence in every process)
		var nonce = Fingerprint.hash(Sys.args().join("\x00") + "|" + Sys.time() + "|" + haxe.Timer.stamp()).substr(0, 16);
		var args = ["--types-cache", base, nonce, "-cp", std, "--custom-target", "hxmc", ALL];
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

	// `hxmc --types-cache <base> <nonce> <haxe arguments>`: the run that types the
	// modules (written beside, then renamed into place: builds running at the
	// same time see either no archive or a whole one)
	public static function write(args:Array<String>):Int {
		var base = args.shift();
		var nonce = args.shift();
		var dir = Path.directory(base);
		try {
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
		} catch (_:Dynamic) {
			return 1;
		}
		var tmp = base + "." + nonce + ".tmp";
		var conf = tmp + ".json";
		File.saveContent(conf, haxe.Json.stringify({
			archivePath: tmp + ".zip",
			targetConfig: {exclude: ["**"], include: ["hxmc"], generateDocumentation: false},
			macroConfig: {generate: false}
		}));
		var deps = null;
		compiler.Compiler.generateHook = com -> deps = depsOf(com);
		var code = try haxe.Main.run(args.concat(["--no-output", "--hxb", conf])) catch (_:Dynamic) 1;
		try FileSystem.deleteFile(conf) catch (_:Dynamic) {}
		if (code != 0 || deps == null || !FileSystem.exists(tmp + ".zip")) {
			try FileSystem.deleteFile(tmp + ".zip") catch (_:Dynamic) {}
			return 1;
		}
		// (.deps first: an archive is only used with its own; where a rename
		// does not replace a file, as on Windows, the first archive stays)
		try {
			File.saveContent(tmp + ".deps", deps);
			FileSystem.rename(tmp + ".deps", base + ".deps");
			FileSystem.rename(tmp + ".zip", base + ".zip");
		} catch (_:Dynamic) {
			for (f in [tmp + ".deps", tmp + ".zip"])
				try FileSystem.deleteFile(f) catch (_:Dynamic) {}
		}
		// the archives of other builds of the tool go once a day old (a build
		// of one may still be reading its archive)
		var mine = Path.withoutDirectory(base).substr(0, 16);
		var old = Date.now().getTime() - 86400000.0;
		for (f in FileSystem.readDirectory(dir))
			if (!StringTools.startsWith(f, mine) && (StringTools.endsWith(f, ".zip") || StringTools.endsWith(f, ".deps") || StringTools.endsWith(f, ".tmp")))
				try {
					if (FileSystem.stat(dir + "/" + f).mtime.getTime() < old) FileSystem.deleteFile(dir + "/" + f);
				} catch (_:Dynamic) {}
		return 0;
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
