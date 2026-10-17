package hxmc;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

// The user's cache directory and its upkeep (the module cache's store,
// ModuleCache.hx): HXMC_CACHE, else $XDG_CACHE_HOME/hxmc or ~/.cache/hxmc,
// macOS ~/Library/Caches/hxmc, Windows %LOCALAPPDATA%\hxmc\cache. A
// directory of it (<cache>/modules/) holds one subdirectory per tool build
// (toolStamp); <tool>/used is the last build that used it, <tool>/<f>.used
// the last that used <f> (refreshed at most every USED_REFRESH); at most
// every TRIM_INTERVAL (<dir>/trim.txt) a build removes the tool directories
// and the running tool's files unused for MAX_UNUSED, and the least
// recently used ones while the whole exceeds MAX_SIZE (best effort: errors are
// ignored, a failed removal is retried next time). Files are written beside
// and renamed into place (replace), with a nonce in the temporary name.
class CacheDir {
	// seconds between two refreshes of a tool directory's last use
	public static inline var USED_REFRESH = 3600.0;
	// seconds between two trims of the cache
	static inline var TRIM_INTERVAL = 86400.0;
	// seconds without use after which a tool directory goes
	static inline var MAX_UNUSED = 14 * 86400.0;
	// bytes the tool directories may take together (beyond it the least
	// recently used go, except those used within two USED_REFRESH: they may
	// be in use)
	static inline var MAX_SIZE = 1024.0 * 1024 * 1024;

	// the user's cache directory, with a trailing slash (null: no place for it)
	public static function root():Null<String> {
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
		return d == null ? null : Path.addTrailingSlash(d);
	}

	public static function now():Float
		return Date.now().getTime() / 1000;

	public static function mtime(p:String):Float
		return try FileSystem.stat(p).mtime.getTime() / 1000 catch (_:Dynamic) 0.0;

	static function stamp(p:String):String {
		var s = try FileSystem.stat(p) catch (_:Dynamic) null;
		return s == null ? "?" : s.size + "@" + s.mtime.getTime();
	}

	// this build of the tool (the binary, however it was named)
	public static function toolStamp():String {
		var p = try FileSystem.fullPath(Sys.programPath()) catch (_:Dynamic) Sys.programPath();
		return Fingerprint.hash("hxmc-tool|" + p + "|" + stamp(p)).substr(0, 16);
	}

	// a define's value (null: not defined), by its name with - or _
	public static function define(com:context.Common.CommonContext, name:String):Null<String> {
		var u = StringTools.replace(name, "-", "_");
		if (core.Define.rawDefined(com.defines, u)) return core.Define.rawDefinedValue(com.defines, u);
		if (core.Define.rawDefined(com.defines, name)) return core.Define.rawDefinedValue(com.defines, name);
		return null;
	}

	public static function touch(p:String):Bool {
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
	public static function replace(tmp:String, p:String):Bool {
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

	// removes the tool directories of dir, and the entries of the running
	// tool's (mine: <name>, its last use in <name>.used), unused for
	// MAX_UNUSED, then the least recently used ones beyond MAX_SIZE, at most
	// once every TRIM_INTERVAL (two builds trimming at once remove the same
	// ones)
	public static function trim(dir:String, mine:String, ?sweep:String->Void) {
		var t = now();
		var last = try Std.parseFloat(File.getContent(dir + "trim.txt")) catch (_:Dynamic) Math.NaN;
		if (last <= t && t - last < TRIM_INTERVAL) return;
		var tmp = dir + "trim." + nonce() + ".tmp";
		if (!touch(tmp) || !replace(tmp, dir + "trim.txt")) return;
		var entries:Array<{files:Array<String>, dir:Null<String>, used:Float, size:Float}> = [];
		var total = 0.0;
		inline function size(f:String):Float
			return try FileSystem.stat(f).size catch (_:Dynamic) 0;
		for (n in try FileSystem.readDirectory(dir) catch (_:Dynamic) []) {
			var d = dir + n + "/";
			if (!FileSystem.isDirectory(d)) continue;
			var names = try FileSystem.readDirectory(d) catch (_:Dynamic) [];
			if (d == mine) {
				for (f in names) {
					// (the blobs and objects: in the total, removed by sweep)
					if (FileSystem.isDirectory(d + f)) {
						for (g in try FileSystem.readDirectory(d + f) catch (_:Dynamic) [])
							if (FileSystem.isDirectory(d + f + "/" + g)) {
								for (h in try FileSystem.readDirectory(d + f + "/" + g) catch (_:Dynamic) [])
									total += size(d + f + "/" + g + "/" + h);
							} else
								total += size(d + f + "/" + g);
						continue;
					}
					var sz = size(d + f);
					total += sz;
					// (the leftovers of runs that did not finish)
					if (f.indexOf(".tmp") >= 0) {
						if (t - mtime(d + f) > TRIM_INTERVAL) try FileSystem.deleteFile(d + f) catch (_:Dynamic) {}
					} else if (f != "used" && !StringTools.endsWith(f, ".used")) {
						var u = d + f + ".used";
						var hasUsed = FileSystem.exists(u);
						entries.push({
							files: hasUsed ? [d + f, u] : [d + f],
							dir: null,
							used: Math.max(mtime(d + f), hasUsed ? mtime(u) : 0),
							size: sz
						});
					}
				}
				continue;
			}
			var files = [];
			function walk(p:String)
				for (f in try FileSystem.readDirectory(p) catch (_:Dynamic) [])
					if (FileSystem.isDirectory(p + f)) walk(p + f + "/") else files.push(p + f);
			walk(d);
			var sz = 0.0;
			for (f in files)
				sz += size(f);
			total += sz;
			// (`used` last: a removal that fails keeps its date)
			files.sort((a, b) -> (a == d + "used" ? 1 : 0) - (b == d + "used" ? 1 : 0));
			entries.push({
				files: files,
				dir: d,
				used: FileSystem.exists(d + "used") ? mtime(d + "used") : mtime(d),
				size: sz
			});
		}
		entries.sort((a, b) -> a.used < b.used ? -1 : a.used > b.used ? 1 : 0);
		for (e in entries)
			if (t - e.used > MAX_UNUSED || (total > MAX_SIZE && t - e.used > 2 * USED_REFRESH)) {
				total -= e.size;
				for (f in e.files)
					try FileSystem.deleteFile(f) catch (_:Dynamic) {}
				if (e.dir != null) rmdirs(e.dir);
			}
		// (what the entries of mine that remain no longer name)
		if (sweep != null) try sweep(mine) catch (_:Dynamic) {}
	}

	// the empty directories of a tree removed, then the tree's root
	static function rmdirs(d:String) {
		for (f in try FileSystem.readDirectory(d) catch (_:Dynamic) [])
			if (FileSystem.isDirectory(d + f)) rmdirs(d + f + "/");
		try FileSystem.deleteDirectory(d) catch (_:Dynamic) {}
	}

	// the last use of a file of the cache (its <file>.used), refreshed at
	// most every USED_REFRESH
	public static function used(file:String) {
		var u = file + ".used";
		if (now() - Math.max(mtime(file), mtime(u)) > USED_REFRESH) touch(u);
	}

	// a name for temporary files (builds may write the same file at the same
	// time, and rand() is the same sequence in every process)
	// a 64-bit hash of bytes (two 32-bit lanes, four bytes a step), as 16
	// hex digits: the store's content hashes (files, blobs), much cheaper
	// than MD5 in the tool's code
	public static function hashBytes(b:haxe.io.Bytes):String {
		var h1 = 0x811c9dc5, h2 = 0x2545f491;
		var n = b.length, i = 0;
		while (i + 4 <= n) {
			var w = b.getInt32(i);
			h1 = (h1 ^ w) * 0x01000193;
			h1 ^= h1 >>> 15;
			h2 = (h2 ^ w) * 0x5bd1e995;
			h2 ^= h2 >>> 13;
			i += 4;
		}
		while (i < n) {
			var c = b.get(i++);
			h1 = (h1 ^ c) * 0x01000193;
			h2 = (h2 ^ c) * 0x5bd1e995;
		}
		h1 ^= n;
		h1 = (h1 ^ (h1 >>> 16)) * 0x85ebca6b;
		h2 = (h2 ^ (h2 >>> 13)) * 0xc2b2ae35;
		h1 ^= h1 >>> 16;
		h2 ^= h2 >>> 16;
		return StringTools.hex(h1 ^ (h2 >>> 7), 8) + StringTools.hex(h2 ^ (h1 >>> 11), 8);
	}

	public static function nonce():String
		return Fingerprint.hash(Sys.args().join("\x00") + "|" + Sys.time() + "|" + haxe.Timer.stamp() + "|" + Sys.programPath()).substr(0, 16);
}
