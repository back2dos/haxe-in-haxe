package hxc;

// `haxelib run hxc ...`: shorthand for `haxe -lib hxc ...` (see Boot), adding
// `--custom-target hxc=bin/main` when no hxc output is given.
//
//   haxelib run hxc build.hxml
//   haxelib run hxc -cp src -main Main
//   haxelib run hxc setup-cosmocc        download cosmocc now (for -D hxc.static)
using StringTools;

class Run {
	static function main() {
		Build.lib = haxe.io.Path.addTrailingSlash(Sys.getCwd()); // haxelib runs us from the library directory
		var args = Sys.args();
		if (Sys.getEnv("HAXELIB_RUN") == "1" && args.length > 0) Sys.setCwd(args.pop()); // and appends the caller's directory
		if (args[0] == "setup-cosmocc") {
			Sys.println(Build.cosmocc());
			return;
		}
		if (args.length == 0 || args[0] == "--help" || args[0] == "help") {
			Sys.println("hxc: Haxe to C, then to a native binary.\n");
			Sys.println("  haxe -lib hxc -main Main --custom-target hxc=bin/main");
			Sys.println("  haxelib run hxc build.hxml          (haxe -lib hxc build.hxml)");
			Sys.println("  haxelib run hxc setup-cosmocc       download cosmocc now\n");
			Sys.println("  -D hxc.cc=<command>  -D hxc.static  -D hxc.debug  -D hxc.c-only  -D hxc.single  -D hxc.jobs=<n>  -D hxc.ssl  -D hxc.uv  -D hxc.keep-hxb");
			return;
		}
		if (!hasOutput(args)) args = args.concat(["--custom-target", "hxc=bin/main"]);
		Sys.exit(Sys.command("haxe", ["-lib", "hxc"].concat(args)));
	}

	static function hasOutput(args:Array<String>):Bool {
		for (i in 0...args.length) {
			var a = args[i];
			if ((a == "--custom-target" || a == "-custom") && i + 1 < args.length && args[i + 1].startsWith("hxc")) return true;
			if (a.endsWith(".hxml") && sys.FileSystem.exists(a)) {
				var words = [];
				for (line in sys.io.File.getContent(a).split("\n")) {
					line = line.trim();
					if (line == "" || line.startsWith("#")) continue;
					for (w in line.split(" ")) if (w != "") words.push(w);
				}
				if (hasOutput(words)) return true;
			}
		}
		return false;
	}
}
