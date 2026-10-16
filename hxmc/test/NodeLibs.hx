import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// -lib from node_modules (hxmc/src/hxmc/NodeLibs.hx) with the npm package's
// compiler (`make test-node-libs`; CI: after `make npm`, and in the npm job
// with the installed package's native compiler, run without node):
//   <haxe> -cp hxmc/test --run NodeLibs [--haxe <compiler>] [--dir <scratch>]
// (default: bin/npm/native/<this machine>/haxe[.exe], bin/test/node-libs).
// A project with node_modules/@hxmc/demo ("haxe": class path, an hxml,
// dependencies), its dependency demo-dep (which depends on @hxmc/demo again)
// and left-pad (no "haxe" field); cases: -lib, -L with the package's name,
// --library name:version, nested hxml files, a subdirectory (node_modules of
// a parent), a version that does not match and an unknown name (haxelib's),
// lix's haxe_libraries/<name>.hxml first (haxelib's). haxelib is a fake on
// PATH printing <scratch>/haxelib/<name>/ as the class path (Unix; on
// Windows the cases expect haxelib's failure instead).
class NodeLibs {
	static final windows = Sys.systemName() == "Windows";
	static var haxe:String;
	static var failures = 0;

	static final FILES = [
		"proj/node_modules/@hxmc/demo/package.json" => '{"name": "@hxmc/demo", "version": "1.2.3", "haxe": {"name": "hxmc.demo", "classPath": "src", "hxml": "extra.hxml"}, "dependencies": {"demo-dep": "*", "left-pad": "*"}, "peerDependencies": {"@hxmc/cli": "*"}}',
		"proj/node_modules/@hxmc/demo/extra.hxml" => "# the extra hxml\n-D demo_extra=7\n",
		"proj/node_modules/@hxmc/demo/src/hxmc/demo/Demo.hx" => "package hxmc.demo;\nclass Demo {\n\tpublic static function hello() return 'demo and ' + demo.dep.Dep.name();\n}\n",
		"proj/node_modules/demo-dep/package.json" => '{"name": "demo-dep", "version": "0.1.0", "haxe": {"name": "demo.dep", "classPath": "lib"}, "dependencies": {"@hxmc/demo": "*"}}',
		"proj/node_modules/demo-dep/lib/demo/dep/Dep.hx" => "package demo.dep;\nclass Dep {\n\tpublic static function name() return 'dep';\n}\n",
		"proj/node_modules/left-pad/package.json" => '{"name": "left-pad", "version": "1.0.0"}',
		"proj/src/Main.hx" => "class Main {\n\tstatic function main() {\n\t\tSys.println(hxmc.demo.Demo.hello());\n\t\tSys.println(haxe.macro.Compiler.getDefine('hxmc.demo') + ' ' + haxe.macro.Compiler.getDefine('demo.dep') + ' ' + haxe.macro.Compiler.getDefine('demo_extra'));\n\t}\n}\n",
		"proj/src/Other.hx" => "class Other {\n\tstatic function main() Sys.println(other.Lib.name());\n}\n",
		"proj/build.hxml" => "-cp src\nlibs.hxml\n-main Main\n--interp\n",
		"proj/libs.hxml" => "# nested\n-lib hxmc.demo\n",
		"proj/sub/.keep" => "",
		"lixproj/node_modules/@hxmc/demo/package.json" => '{"name": "@hxmc/demo", "version": "1.2.3", "haxe": {"name": "hxmc.demo", "classPath": "src"}}',
		"lixproj/haxe_libraries/hxmc.demo.hxml" => "# lix's: haxelib (lix's shim) reads it\n",
		"lixproj/src/Main.hx" => "class Main {\n\tstatic function main() Sys.println(hxmc.demo.Demo.hello());\n}\n",
		"haxelib/hxmc.demo/hxmc/demo/Demo.hx" => "package hxmc.demo;\nclass Demo {\n\tpublic static function hello() return 'haxelib demo';\n}\n",
		"haxelib/hxmc.demo-9.9.9/hxmc/demo/Demo.hx" => "package hxmc.demo;\nclass Demo {\n\tpublic static function hello() return 'haxelib demo 9.9.9';\n}\n",
		"haxelib/other/other/Lib.hx" => "package other;\nclass Lib {\n\tpublic static function name() return 'haxelib other';\n}\n",
	];

	static function main() {
		var args = Sys.args();
		function opt(name:String, def:String) {
			var i = args.indexOf(name);
			return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
		}
		var host = (switch Sys.systemName() {
			case "Windows": "windows";
			case "Mac": "macos";
			case _: "linux";
		}) + "-" + (Sys.getEnv("PROCESSOR_ARCHITECTURE") == "ARM64" || ~/arm64|aarch64/i.match(uname()) ? "arm64" : "x86_64");
		haxe = FileSystem.fullPath(opt("--haxe", 'bin/npm/native/$host/haxe' + (windows ? ".exe" : "")));
		var dir = opt("--dir", "bin/test/node-libs");
		// (the repository's std, unless the compiler finds its own)
		if (Sys.getEnv("HAXE_STD_PATH") == null && FileSystem.exists("haxe/upstream/std"))
			Sys.putEnv("HAXE_STD_PATH", FileSystem.fullPath("haxe/upstream/std"));
		rmrf(dir);
		for (name => text in FILES) {
			FileSystem.createDirectory(Path.directory('$dir/$name'));
			File.saveContent('$dir/$name', text);
		}
		dir = FileSystem.fullPath(dir);
		if (!windows) {
			// haxelib path <libs> (after --cwd <dir> or --global)
			var fake = '$dir/bin/haxelib';
			FileSystem.createDirectory('$dir/bin');
			// (name:version: <scratch>/haxelib/name-version/)
			File.saveContent(fake, '#!/bin/sh\nwhile [ "$$1" != path ]; do shift; done; shift\nfor l in "$$@"; do\n  d=$$(echo "$$l" | tr : -)\n  if [ ! -d "$dir/haxelib/$$d" ]; then echo "library $$l is not installed" >&2; exit 1; fi\n  echo "$dir/haxelib/$$d/"; echo "-D $${l%%:*}=9.9.9"\ndone\n');
			Sys.command("chmod", ["+x", fake]);
			Sys.putEnv("PATH", '$dir/bin:' + Sys.getEnv("PATH"));
		}
		var demo = ["demo and dep", "1.2.3 0.1.0 7"];
		var proj = '$dir/proj';
		check("-lib", proj, ["-cp", "src", "-lib", "hxmc.demo", "-main", "Main", "--interp"], demo);
		check("-L with the package's name", proj, ["-cp", "src", "-L", "@hxmc/demo", "-main", "Main", "--interp"], demo);
		check("--library name:version", proj, ["-cp", "src", "--library", "hxmc.demo:1.2.3", "-main", "Main", "--interp"], demo);
		check("nested hxml", proj, ["build.hxml"], demo);
		check("a parent's node_modules", '$proj/sub', ["-cp", "../src", "-lib", "hxmc.demo", "-main", "Main", "--interp"], demo);
		check("another version: haxelib", proj, ["-cp", "src", "-lib", "hxmc.demo:9.9.9", "-main", "Main", "--interp"], ["haxelib demo 9.9.9", "9.9.9 null null"], true);
		check("an unknown name: haxelib", proj, ["-cp", "src", "-lib", "other", "-main", "Other", "--interp"], ["haxelib other"], true);
		check("node_modules and haxelib together", proj, ["-cp", "src", "-lib", "other", "-lib", "hxmc.demo", "-main", "Main", "--interp"], demo, true);
		check("lix's haxe_libraries first: haxelib", '$dir/lixproj', ["-cp", "src", "-lib", "hxmc.demo", "-main", "Main", "--interp"], ["haxelib demo"], true);
		Sys.println(failures == 0 ? "NodeLibs: all passed" : 'NodeLibs: $failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}

	// expect: the program's output lines; a case that calls haxelib expects
	// haxelib's failure on Windows (no fake there)
	static function check(name:String, cwd:String, args:Array<String>, expect:Array<String>, haxelib = false) {
		var p = new sys.io.Process(haxe, ["--cwd", cwd].concat(args));
		var out = p.stdout.readAll().toString().replace("\r", "");
		var err = p.stderr.readAll().toString().replace("\r", "");
		var code = p.exitCode();
		p.close();
		var ok = if (windows && haxelib) code != 0 && err.contains("haxelib") else code == 0 && out.trim().split("\n").join("|") == expect.join("|");
		Sys.println((ok ? "ok   " : "FAIL ") + name);
		if (!ok) {
			failures++;
			Sys.println('  haxe ${args.join(" ")} (in $cwd): exit $code\n  expected: ${expect.join("|")}\n  stdout: ${out.trim()}\n  stderr: ${err.trim()}');
		}
	}

	static function uname():String {
		if (windows) return "";
		try {
			var p = new sys.io.Process("uname", ["-m"]);
			var s = p.stdout.readAll().toString();
			p.close();
			return s;
		} catch (_:Dynamic) return "";
	}

	static function rmrf(path:String) {
		if (!FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path)) {
			for (e in FileSystem.readDirectory(path)) rmrf('$path/$e');
			FileSystem.deleteDirectory(path);
		} else FileSystem.deleteFile(path);
	}
}
