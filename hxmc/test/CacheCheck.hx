import Harness.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The store of the module cache (hxmc/src/hxmc/ModuleCache.hx, CacheDir.hx)
// in a cache of its own (bin/hxmc-t/cache): a tool directory per build of
// the tool, written and then read, two builds of the tool side by side, the
// trim of a tool directory and of an index unused for a month while the
// recent ones stay, of a blob no index names,
// and a cache that cannot be written (a build without it). Unix (touch -d
// backdates files).
//   bin/hxmc/hxmc -cp hxmc/test -cp haxe/test --run CacheCheck
class CacheCheck {
	static var dir:String;
	static var failures = 0;

	static function check(what:String, ok:Bool) {
		Sys.println((ok ? "ok    " : "FAIL  ") + what);
		if (!ok) failures++;
	}

	// a build of the hello program by tool with the class path std, the cache in
	// cache; whether it built and runs
	static function build(tool:String, std:String, cache:String):Bool {
		var r = exec([tool, dir + "/hello/m", "-cp", dir + "/hello", "-main", "Main", "-cp", std, "--custom-target", "hxmc"], {
			env: [
				"HXMC_CACHE" => cache,
				"HXMC_MODULE_CACHE" => null,
				"HXMC_STATS" => null,
				"HXMC_RT_DIR" => FileSystem.fullPath("bin/hxmc/rt")
			],
			merge: true
		});
		if (r.code != 0) {
			Sys.println(tail(r.out, 600));
			return false;
		}
		return exec([dir + "/hello/m"]).out == "hi\n";
	}

	// <cache>/modules/<tool>/ directories
	static function tools(cache:String):Array<String> {
		var t = cache + "/modules";
		if (!FileSystem.exists(t)) return [];
		var r = [for (n in FileSystem.readDirectory(t)) if (FileSystem.isDirectory(t + "/" + n)) t + "/" + n];
		r.sort(compare);
		return r;
	}

	static function packs(d:String):Array<String>
		return [for (n in FileSystem.readDirectory(d)) if (n.endsWith(".idx")) d + "/" + n];

	static function backdate(path:String, ago:String)
		exec(["touch", "-d", ago, path]);

	static function main() {
		dir = FileSystem.fullPath("bin") + "/hxmc-t/cache";
		rmrf(dir);
		mkdirs(dir + "/hello");
		File.saveContent(dir + "/hello/Main.hx", 'class Main { static function main() Sys.println("hi"); }\n');
		copyTree("bin/hxmc/std", dir + "/std");
		mkdirs(dir + "/b");
		File.copy("bin/hxmc/hxmc", dir + "/b/hxmc");
		exec(["chmod", "+x", dir + "/b/hxmc"]);
		var a = FileSystem.fullPath("bin/hxmc/hxmc"), b = dir + "/b/hxmc", std = dir + "/std", cache = dir + "/cache";

		// the first build writes the store
		check("first build", build(a, std, cache));
		var ta = tools(cache);
		check("one tool directory, an index, its last use", ta.length == 1 && packs(ta[0]).length > 0 && FileSystem.exists(ta[0] + "/used"));
		if (ta.length != 1) Sys.exit(1);
		check("the trim stamp", FileSystem.exists(cache + "/modules/trim.txt"));

		// a warm build leaves the packs as they were
		var pack = packs(ta[0])[0];
		backdate(pack, "2 days ago");
		var old = mtime(pack);
		check("second build", build(a, std, cache));
		check("warm: the index is not written again", mtime(pack) == old);
		check("no temporary files left", [for (n in FileSystem.readDirectory(ta[0])) if (n.contains(".tmp")) n].length == 0);

		// another build of the tool: its own directory beside
		check("build by another tool", build(b, std, cache));
		var both = tools(cache);
		check("two tool directories, an index in each", both.length == 2 && packs(both[0]).length > 0 && packs(both[1]).length > 0);
		var tb = both.filter(d -> d != ta[0])[0];

		// unused for a month, the trim removes it (the trim of the day is done:
		// a stamp of long ago lets it run)
		backdate(tb + "/used", "30 days ago");
		backdate(ta[0] + "/used", "3 days ago");
		check("a build within the day does not trim", build(a, std, cache) && tools(cache).length == 2);
		// (a pack of the running tool unused for a month: another project's)
		var stale = ta[0] + "/0000000000000000-old.idx";
		File.saveContent(stale, "stale");
		backdate(stale, "30 days ago");
		// (a blob no index names, written days ago)
		mkdirs(ta[0] + "/b/00");
		var orphan = ta[0] + "/b/00/00000000000000000000000000000000";
		File.saveContent(orphan, "orphan");
		backdate(orphan, "3 days ago");
		var blobs = [for (d in FileSystem.readDirectory(ta[0] + "/b")) for (f in FileSystem.readDirectory(ta[0] + "/b/" + d)) f].length;
		File.saveContent(cache + "/modules/trim.txt", "0");
		check("a build after a day trims", build(a, std, cache));
		check("a blob no index names is gone, the others stay", !FileSystem.exists(orphan)
			&& [for (d in FileSystem.readDirectory(ta[0] + "/b")) for (f in FileSystem.readDirectory(ta[0] + "/b/" + d)) f].length == blobs - 1);
		check("an index unused for a month is gone, the build's stays", !FileSystem.exists(stale) && packs(ta[0]).length > 0);
		check("the unused tool directory is gone, the recent one stays", tools(cache).join(",") == ta[0] && packs(ta[0]).length > 0);
		check("its last use refreshed", Date.now().getTime() - mtime(ta[0] + "/used") < 600000);
		check("the trim stamp renewed", Std.parseFloat(File.getContent(cache + "/modules/trim.txt")) > 1e9);
		check("the other tool writes its store again", build(b, std, cache) && tools(cache).length == 2);

		// a cache that cannot be written: the build types everything
		File.saveContent(dir + "/file", "");
		check("an unwritable cache: the build goes on without it", build(a, std, dir + "/file/cache"));
		check("an empty HOME and no HXMC_CACHE: the same", {
			var r = exec([a, dir + "/hello/m", "-cp", dir + "/hello", "-main", "Main", "-cp", std, "--custom-target", "hxmc"], {
				env: [
					"HXMC_CACHE" => null,
					"HXMC_MODULE_CACHE" => null,
					"HXMC_STATS" => null,
					"HOME" => dir + "/file",
					"XDG_CACHE_HOME" => null,
					"HXMC_RT_DIR" => FileSystem.fullPath("bin/hxmc/rt")
				],
				merge: true
			});
			r.code == 0 && r.out.trim() == "" && exec([dir + "/hello/m"]).out == "hi\n";
		});

		Sys.println(failures == 0 ? "module cache store: all checks passed" : 'module cache store: $failures failed');
		if (failures == 0) rmrf(dir);
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
