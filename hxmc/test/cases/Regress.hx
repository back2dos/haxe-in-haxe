// Regressions found compiling haxe-formatter with hxc (site/bench/README.md, 2026-10-09;
// from hxc's tests)
// prints "ok" six times.
class Regress {
	static function main() {
		// -dce full removed haxe.Exception.caught/thrown, which only the backend calls
		// (the lowering crashed on the missing field)
		try {
			throw new haxe.Exception("ok");
		} catch (e:haxe.Exception) {
			Sys.println(e.message);
		}
		try {
			throw "ok";
		} catch (e:haxe.Exception) {
			Sys.println(e.message);
		}
		// StringTools.isEof was `false` (the std fallback for unknown targets) while
		// fastCodeAt returns 0 past the end, so EOF loops (hxjsonast's Parser) never ended
		var s = "ab", i = 0, n = 0;
		while (!StringTools.isEof(StringTools.fastCodeAt(s, i++)))
			n++;
		Sys.println(n == 2 ? "ok" : "isEof: " + n);
		Sys.println(StringTools.isEof(StringTools.fastCodeAt("", 0)) ? "ok" : "isEof past the end");
		// String.split read the delimiter's length after allocating its result
		// array: a minor collection there moved a young delimiter, and the length
		// came from the forwarding address (crashed or split wrongly, depending
		// on where the heap was mapped)
		var bad = 0;
		for (i in 0...1000000) {
			var delim = (",;" + i).substr(0, 2); // a young ",;"
			var shift = haxe.io.Bytes.alloc(i % 61); // varies where the nursery fills up
			if ("a,;b,;c".split(delim).length != 3 + shift.length * 0) bad++;
		}
		Sys.println(bad == 0 ? "ok" : "split: " + bad);
		// a call through an interface left out an Int and a Float argument with
		// default values: they came as 0 (the interface's method has no body
		// to take them from; the implementation's apply, as on other targets)
		var e:Defaults = new WithDefaults();
		var got = e.go(1.0, null, 2) + " " + e.go(1.0);
		Sys.println(got == "-1 -1 -1 -1" ? "ok" : "interface defaults: " + got);
	}
}

interface Defaults {
	function go(a:Float, ?s:Array<Int>, n:Int = 0, base:Int = -1, cut:Float = -1):String;
}

class WithDefaults implements Defaults {
	public function new() {}

	public function go(a:Float, ?s:Array<Int>, n:Int = 0, base:Int = -1, cut:Float = -1):String
		return base + " " + cut;
}
