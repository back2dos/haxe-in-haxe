import Harness.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The cache of the runtime's typed modules (hxmc/src/hxmc/TypesCache.hx) in a
// cache of its own (bin/hxmc-t/cache): a hit, a miss after a change of a
// runtime module, two builds of the tool side by side, the trim of a tool
// directory unused for a month while the recent one stays, and a cache that
// cannot be written (a build without it). Unix (touch -d backdates files).
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
		var r = exec([tool, dir + "/hello/m", "-cp", dir + "/hello", "-main", "Main", "-cp", std, "--custom-target", "hxmc"],
			{env: ["HXMC_CACHE" => cache, "HXMC_TYPES_CACHE" => null, "HXMC_RT_DIR" => FileSystem.fullPath("bin/hxmc/rt")], merge: true});
		if (r.code != 0) {
			Sys.println(tail(r.out, 600));
			return false;
		}
		return exec([dir + "/hello/m"]).out == "hi\n";
	}

	// <cache>/types/<tool>/ directories
	static function tools(cache:String):Array<String> {
		var t = cache + "/types";
		if (!FileSystem.exists(t)) return [];
		var r = [for (n in FileSystem.readDirectory(t)) if (FileSystem.isDirectory(t + "/" + n)) t + "/" + n];
		r.sort(compare);
		return r;
	}

	static function zips(d:String):Array<String>
		return [for (n in FileSystem.readDirectory(d)) if (n.endsWith(".zip")) d + "/" + n];

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

		// a miss writes the entry
		check("first build", build(a, std, cache));
		var ta = tools(cache);
		check("one tool directory, one entry, its last use", ta.length == 1 && zips(ta[0]).length == 1 && FileSystem.exists(ta[0] + "/used"));
		if (ta.length != 1) Sys.exit(1);
		var zip = zips(ta[0])[0], deps = zip.substr(0, zip.length - 4) + ".deps";
		check("the trim stamp", FileSystem.exists(cache + "/types/trim.txt"));

		// a hit leaves it as it was
		backdate(zip, "2 days ago");
		var old = mtime(zip), oldDeps = File.getContent(deps);
		check("second build", build(a, std, cache));
		check("hit: the archive is not written again", mtime(zip) == old);

		// a runtime module changes: a miss, the entry is written again
		File.saveContent(std + "/hxmc/rt/Runtime.hx", File.getContent(std + "/hxmc/rt/Runtime.hx") + "\n// changed\n");
		check("build after a change", build(a, std, cache));
		check("miss: the archive and its .deps are written again", mtime(zip) > old && File.getContent(deps) != oldDeps);
		check("then a hit", {
			backdate(zip, "2 days ago");
			var m = mtime(zip);
			build(a, std, cache) && mtime(zip) == m;
		});
		check("no temporary files left", [for (n in FileSystem.readDirectory(ta[0])) if (n.contains(".tmp")) n].length == 0);

		// another build of the tool: its own directory beside
		check("build by another tool", build(b, std, cache));
		var both = tools(cache);
		check("two tool directories, an entry each", both.length == 2 && zips(both[0]).length == 1 && zips(both[1]).length == 1);
		var tb = both.filter(d -> d != ta[0])[0];
		check("the first tool's entry still hits", {
			backdate(zip, "2 days ago");
			var m = mtime(zip);
			build(a, std, cache) && mtime(zip) == m;
		});

		// unused for a month, the trim removes it (the trim of the day is done:
		// a stamp of long ago lets it run)
		backdate(tb + "/used", "30 days ago");
		backdate(ta[0] + "/used", "3 days ago");
		check("a build within the day does not trim", build(a, std, cache) && tools(cache).length == 2);
		File.saveContent(cache + "/types/trim.txt", "0");
		check("a build after a day trims", build(a, std, cache));
		check("the unused tool directory is gone, the recent one stays", tools(cache).join(",") == ta[0] && zips(ta[0]).length == 1);
		check("its last use refreshed", Date.now().getTime() - mtime(ta[0] + "/used") < 600000);
		check("the trim stamp renewed", Std.parseFloat(File.getContent(cache + "/types/trim.txt")) > 1e9);
		check("the other tool rebuilds its entry", build(b, std, cache) && tools(cache).length == 2);

		// a cache that cannot be written: the build types everything
		File.saveContent(dir + "/file", "");
		check("an unwritable cache: the build goes on without it", build(a, std, dir + "/file/cache"));
		check("an empty HOME and no HXMC_CACHE: the same", {
			var r = exec([a, dir + "/hello/m", "-cp", dir + "/hello", "-main", "Main", "-cp", std, "--custom-target", "hxmc"],
				{env: ["HXMC_CACHE" => null, "HOME" => dir + "/file", "XDG_CACHE_HOME" => null, "HXMC_RT_DIR" => FileSystem.fullPath("bin/hxmc/rt")], merge: true});
			r.code == 0 && r.out.trim() == "" && exec([dir + "/hello/m"]).out == "hi\n";
		});

		Sys.println(failures == 0 ? "types cache: all checks passed" : 'types cache: $failures failed');
		if (failures == 0) rmrf(dir);
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
