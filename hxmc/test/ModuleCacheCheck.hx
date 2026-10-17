import Harness.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The gate of the persistent module cache (hxmc/src/hxmc/ModuleCache.hx,
// docs/plans/compiler.md, "Cached modules"): every build with the cache writes the same
// output, byte for byte, as the same build without it, through a cold run
// (an empty cache), a warm run, a run after a file's date changes (the same
// content), after an edit of one module, after an edit of a std override,
// after a new file shadows a module, and back. For the hxmc target (the tool,
// and `haxe` with hxmc built in for the hello world) and JS (`haxe`), on a
// hello world, a program of several modules (interfaces, a @:generic class,
// inline functions across modules, enums, abstracts, static
// initialization), one with macros (a build macro, an expression macro
// reading a file through Context with its dependency registered) and one
// whose typed program keeps a Null<Unknown> (a monomorph's modifier, which
// HXB does not keep). The warm runs must restore every module (none typed
// again). Copies of the std (hxmc's and upstream's) are edited, never the
// repository's. In bin/hxmc-t/module-cache (removed when every check passes):
//   bin/hxmc/hxmc -cp hxmc/test -cp haxe/test --run ModuleCacheCheck [--port] [--haxe <haxe>]
// --port adds the port itself (haxe/src: a large program) for the hxmc target;
// --haxe names `haxe` with hxmc built in (default: bin/npm/native/<host>/haxe).
class ModuleCacheCheck {
	static var dir:String;
	static var tool:String;
	// `haxe` with hxmc built in (HaxeMain: the npm package's compiler)
	static var haxeBin:String;
	static var failures = 0;
	static var builds = 0;

	static function check(what:String, ok:Bool) {
		Sys.println((ok ? "ok    " : "FAIL  ") + what);
		if (!ok) failures++;
	}

	static function write(path:String, s:String) {
		var d = haxe.io.Path.directory(path);
		if (d != "" && !FileSystem.exists(d)) mkdirs(d);
		File.saveContent(path, s);
	}

	// a program: its directory, files, the build arguments per target
	static function programs():Array<{name:String, files:Map<String, String>, args:Array<String>, edit:String, run:String}> {
		var hello = [
			"src/Main.hx" => 'class Main {\n\tstatic function main() {\n\t\ttrace("hello " + [1, 2, 3].map(x -> x * 2));\n\t\ttrace(StringTools.lpad("x", ".", 4));\n\t}\n}\n'
		];
		var multi = [
			"src/Main.hx" => [
				"import shapes.*;",
				"import util.Util;",
				"import util.Box;",
				"class Main {",
				"\tstatic function main() {",
				"\t\tvar shapes:Array<Shape> = [new Circle(1.5), new Square(2)];",
				"\t\tfor (s in shapes) trace(s.name() + \" \" + Util.round(s.area()));",
				"\t\tvar b = new Box<Int>(Util.twice(21));",
				"\t\ttrace(b.get() + \" \" + Util.label + \" \" + (Color.Red : Int));",
				"\t\tvar m:util.Meters = 3.5;",
				"\t\ttrace(m.toFeet());",
				"\t\tswitch Color.Green { case Green: trace(\"green\"); case _: }",
				"\t}",
				"}"
			].join("\n") + "\n",
			"src/shapes/Shape.hx" => "package shapes;\ninterface Shape {\n\tfunction area():Float;\n\tfunction name():String;\n}\n",
			"src/shapes/Circle.hx" => "package shapes;\nclass Circle implements Shape {\n\tvar r:Float;\n\tpublic function new(r) this.r = r;\n\tpublic function area() return Math.PI * r * r;\n\tpublic function name() return \"circle\";\n}\n",
			"src/shapes/Square.hx" => "package shapes;\nclass Square implements Shape {\n\tvar s:Float;\n\tpublic function new(s) this.s = s;\n\tpublic function area() return s * s;\n\tpublic function name() return \"square\";\n}\n",
			"src/Color.hx" => "enum abstract Color(Int) to Int {\n\tvar Red = 1;\n\tvar Green = 2;\n}\n",
			"src/util/Util.hx" => "package util;\nclass Util {\n\tpublic static var label = \"v\" + 1;\n\tpublic static inline function twice(x:Int) return x * 2;\n\tpublic static function round(f:Float) return Math.round(f * 100) / 100;\n}\n",
			"src/util/Box.hx" => "package util;\n@:generic class Box<T> {\n\tvar v:T;\n\tpublic function new(v:T) this.v = v;\n\tpublic function get():T return v;\n}\n",
			"src/util/Meters.hx" => "package util;\nabstract Meters(Float) from Float {\n\tpublic inline function toFeet():Float return this * 3.28084;\n}\n"
		];
		var macros = [
			"src/Main.hx" => [
				"@:build(Builder.build())",
				"class Main {",
				"\tstatic function main() {",
				"\t\ttrace(Builder.data());",
				"\t\ttrace(greeting());",
				"\t\ttrace(Other.twice(4));",
				"\t}",
				"}"
			].join("\n") + "\n",
			"src/Other.hx" => "class Other {\n\tpublic static function twice(x:Int) return x * 2;\n}\n",
			"src/Builder.hx" => [
				"import haxe.macro.Context;",
				"import haxe.macro.Expr;",
				"class Builder {",
				"\tpublic static macro function data():Expr {",
				"\t\tvar path = Context.resolvePath(\"data.txt\");",
				"\t\tContext.registerModuleDependency(Context.getLocalModule(), path);",
				"\t\treturn macro $v{sys.io.File.getContent(path)};",
				"\t}",
				"\tpublic static macro function build():Array<Field> {",
				"\t\tvar fields = Context.getBuildFields();",
				"\t\tvar n = fields.length;",
				"\t\tfields.push({name: \"greeting\", access: [AStatic, APublic], kind: FFun({args: [], ret: null, expr: macro return \"built \" + $v{n}}), pos: Context.currentPos()});",
				"\t\treturn fields;",
				"\t}",
				"}"
			].join("\n") + "\n",
			"src/data.txt" => "data one"
		];
		// (a monomorph Null<Unknown> left in the typed program: HXB does not
		// keep its modifier, the cache does)
		var lossy = [
			"src/Main.hx" => "class Main {\n\tstatic function main() {\n\t\tLossy.run();\n\t\ttrace(Other.x);\n\t}\n}\n",
			"src/Other.hx" => "class Other {\n\tpublic static var x = 3;\n}\n",
			"src/Lossy.hx" => "class Lossy {\n\tstatic function time<A, R>(f:A->R, arg:A):R return f(arg);\n\tpublic static function run() trace(time(function(_) return 1, null));\n}\n"
		];
		return [
			{name: "lossy", files: lossy, args: ["-cp", "src", "-main", "Main"], edit: "src/Other.hx", run: "lossy"},
			{name: "hello", files: hello, args: ["-cp", "src", "-main", "Main"], edit: "src/Main.hx", run: "hello"},
			{name: "multi", files: multi, args: ["-cp", "src", "-cp", "src2", "-main", "Main"], edit: "src/util/Util.hx", run: "multi"},
			{name: "macros", files: macros, args: ["-cp", "src", "-main", "Main"], edit: "src/data.txt", run: "macros"}
		];
	}

	static function env(cache:Bool):Map<String, Null<String>>
		return [
			"HXMC_CACHE" => dir + "/cache",
			"HXMC_MODULE_CACHE" => cache ? "1" : "0",
			"HXMC_MODULE_CACHE_LOG" => null,
			"HXMC_STATS" => "1",
			"HXMC_TYPES_CACHE" => null,
			"HXMC_RT_DIR" => FileSystem.fullPath("bin/hxmc/rt"),
			"HAXE_STD_PATH" => dir + "/upstream-std"
		];

	// a build: its output's bytes (null: failed), the modules it read from
	// the store and encoded
	static function build(target:String, pdir:String, args:Array<String>, cache:Bool):{out:Null<haxe.io.Bytes>, read:Int, encoded:Int, log:String} {
		builds++;
		var out = pdir + "/out." + target;
		for (f in [out, out + ".hxmc"])
			rmrf(f);
		var cmd = switch target {
			case "js": [haxeBin, "--js", out].concat(args);
			case "haxe-hxmc": [haxeBin].concat(args).concat(["-cp", dir + "/std", "--custom-target", "hxmc=" + out]);
			case _: [tool, out].concat(args).concat(["-cp", dir + "/std", "--custom-target", "hxmc"]);
		}
		var r = exec(cmd, {cwd: pdir, env: env(cache), merge: true});
		var read = 0, encoded = -1;
		var re = ~/module cache: (\d+) modules in \d+ packs read/;
		if (re.match(r.out)) read = Std.parseInt(re.matched(1));
		var re2 = ~/module cache: \d+ checked \(\d+ ms\), (\d+) modules encoded/;
		if (re2.match(r.out)) encoded = Std.parseInt(re2.matched(1));
		if (r.code != 0 || !FileSystem.exists(out)) {
			Sys.println(tail(r.out, 2000));
			return {out: null, read: read, encoded: encoded, log: r.out};
		}
		return {out: File.getBytes(out), read: read, encoded: encoded, log: r.out};
	}

	static function same(a:Null<haxe.io.Bytes>, b:Null<haxe.io.Bytes>):Bool
		return a != null && b != null && a.compare(b) == 0;

	// the build with the cache against the build without it
	static function gate(what:String, target:String, pdir:String, args:Array<String>, ?expectEncoded:Int):{read:Int, encoded:Int} {
		var ref = build(target, pdir, args, false);
		var got = build(target, pdir, args, true);
		var ok = same(ref.out, got.out);
		var extra = ' (${got.read} read, ${got.encoded} encoded)';
		if (expectEncoded != null && got.encoded != expectEncoded) {
			ok = false;
			extra += ' expected $expectEncoded encoded';
		}
		check('$target: $what: the same output$extra', ok);
		return {read: got.read, encoded: got.encoded};
	}

	static function edit(path:String, f:String->String)
		File.saveContent(path, f(File.getContent(path)));

	static function main() {
		var withPort = Sys.args().contains("--port");
		dir = FileSystem.fullPath("bin") + "/hxmc-t/module-cache";
		tool = FileSystem.fullPath("bin/hxmc/hxmc");
		var a = parseArgs(Sys.args(), ["--haxe"]);
		haxeBin = a.opts.exists("--haxe") ? FileSystem.fullPath(a.opts.get("--haxe")) : null;
		if (haxeBin == null)
			for (h in ["bin/npm/native/linux-x86_64/haxe", "bin/npm/native/linux-arm64/haxe", "bin/npm/native/macos-arm64/haxe", "bin/npm/native/macos-x86_64/haxe"])
				if (FileSystem.exists(h)) {
					haxeBin = FileSystem.fullPath(h);
					break;
				}
		if (haxeBin == null) fail("no haxe with hxmc built in (make bin/npm/native/<host>/haxe, or --haxe <path>)");
		rmrf(dir);
		mkdirs(dir);
		copyTree("bin/hxmc/std", dir + "/std");
		copyTree("haxe/upstream/std", dir + "/upstream-std");
		for (target in ["hxmc", "js", "haxe-hxmc"]) {
			for (p in programs()) {
				// (through haxe for hxmc: the hello program)
				if (target == "haxe-hxmc" && p.name != "hello") continue;
				var pdir = dir + "/" + target + "-" + p.name;
				for (f => s in p.files)
					write(pdir + "/" + f, s);
				mkdirs(pdir + "/src2");
				var name = p.name;
				// cold: an empty cache, written
				rmrf(dir + "/cache");
				var cold = gate('$name cold', target, pdir, p.args);
				check('$target: $name cold: nothing read', cold.read == 0 && cold.encoded > 0);
				// warm: every module restored
				var warm = gate('$name warm', target, pdir, p.args, 0);
				var again = 0;
				check('$target: $name warm: read from the store', warm.read > 0);
				// a new date, the same content
				var t = pdir + "/" + p.edit;
				exec(["touch", "-d", "1 hour ago", t]);
				gate('$name, a file with a new date', target, pdir, p.args, again);
				// one module edited
				var orig = File.getContent(t);
				File.saveContent(t, switch name {
					case "hello": orig.replace("hello ", "hello again ");
					case "multi": orig.replace("\"v\" + 1", "\"v\" + 2");
					case "lossy": orig.replace("3", "4");
					case _: "data two";
				});
				var e = gate('$name, ${p.edit} edited', target, pdir, p.args);
				check('$target: $name, ${p.edit} edited: some modules restored', name == "hello" || e.encoded < cold.encoded);
				gate('$name, ${p.edit} edited, warm', target, pdir, p.args, again);
				// back to the original (an older entry's content again)
				File.saveContent(t, orig);
				gate('$name, ${p.edit} back', target, pdir, p.args);
				if (name == "multi") {
					// a new file shadows a module (src2, given last, comes first)
					write(pdir + "/src2/util/Util.hx", File.getContent(pdir + "/src/util/Util.hx").replace("\"v\" + 1", "\"shadow\""));
					gate('multi, util.Util shadowed', target, pdir, p.args);
					rmrf(pdir + "/src2/util");
					gate('multi, the shadowing file removed', target, pdir, p.args);
				}
				if (name == "hello") {
					// a std override edited (hxmc's std for hxmc, upstream's for JS)
					var std = target == "js" ? dir + "/upstream-std/StringTools.hx" : dir + "/std/StringTools.hx";
					var s = File.getContent(std);
					File.saveContent(std, s.replace("public static function lpad(s:String, c:String, l:Int):String {",
						"public static function lpad(s:String, c:String, l:Int):String {\n\t\tif (l == 4) l = 5;"));
					check('$target: hello, the std edit applies', File.getContent(std) != s);
					gate('hello, std StringTools edited', target, pdir, p.args);
					gate('hello, std StringTools edited, warm', target, pdir, p.args, again);
					File.saveContent(std, s);
					gate('hello, std StringTools back', target, pdir, p.args);
				}
			}
		}
		// the cache off by HXMC_MODULE_CACHE=0 although the define asks for it
		{
			var pdir = dir + "/hxmc-hello";
			var r = exec([tool, pdir + "/out.off", "-cp", "src", "-main", "Main", "-D", "hxmc.module-cache", "-cp", dir + "/std", "--custom-target", "hxmc"],
				{cwd: pdir, env: env(false), merge: true});
			check("HXMC_MODULE_CACHE=0 wins over -D hxmc.module-cache", r.code == 0 && r.out.indexOf("module cache") < 0);
			var r = exec([tool, pdir + "/out.def", "-cp", "src", "-main", "Main", "-D", "hxmc.module-cache", "-cp", dir + "/std", "--custom-target", "hxmc"],
				{cwd: pdir, env: [for (k => v in env(false)) k => k == "HXMC_MODULE_CACHE" ? null : v], merge: true});
			check("-D hxmc.module-cache turns it on", r.code == 0 && r.out.indexOf("modules in") >= 0);
			// a display request: no cache, an answer
			var r = exec([tool, "-cp", "src", "--display", "src/Main.hx@0@diagnostics"], {cwd: pdir, env: env(true), merge: true});
			check("a display request does not use it", r.out.indexOf("modules in") < 0);
		}
		if (withPort) {
			var pdir = FileSystem.fullPath(".");
			var args = ["-cp", "haxe/src", "-main", "haxe.Main", "-D", "disable-parallelism"];
			rmrf(dir + "/cache");
			function port(cache:Bool) {
				var out = dir + "/port";
				rmrf(out);
				rmrf(out + ".hxmc");
				builds++;
				var r = exec([tool, out].concat(args).concat(["-cp", dir + "/std", "--custom-target", "hxmc"]),
					{cwd: pdir, env: [for (k => v in env(cache)) k => k == "HAXE_STD_PATH" ? FileSystem.fullPath("haxe/upstream/std") : v], merge: true});
				if (r.code != 0) Sys.println(tail(r.out, 2000));
				return r.code == 0 ? File.getBytes(out) : null;
			}
			var ref = port(false);
			check("the port: cold", same(ref, port(true)));
			check("the port: warm", same(ref, port(true)));
		}
		Sys.println('module cache: $builds builds, ' + (failures == 0 ? "all checks passed" : '$failures failed'));
		if (failures == 0) rmrf(dir);
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
