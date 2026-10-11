package core;

import core.ds.NotFound;

class StringError {
	/* Source: http://en.wikibooks.org/wiki/Algorithm_implementation/Strings/Levenshtein_distance#OCaml */
	// port: the distance of upstream's matrix, computed with two rows, over the UTF-8 bytes
	// (OCaml strings are byte strings).
	public static function levenshtein(a:String, b:String):Int {
		var x = haxe.io.Bytes.ofString(a), y = haxe.io.Bytes.ofString(b);
		return switch [x.length, y.length] {
			case [0, n]: n;
			case [m, 0]: m;
			case [m, n]:
				var t = new haxe.ds.Vector<Int>(n + 1),
					s = new haxe.ds.Vector<Int>(n + 1);
				for (j in 0...n + 1) t[j] = j;
				for (i in 1...m + 1) {
					s[0] = i;
					var xi = x.get(i - 1);
					for (j in 1...n + 1) {
						var cost = xi == y.get(j - 1) ? 0 : 1;
						s[j] = minimum(t[j] + 1, s[j - 1] + 1, t[j - 1] + cost);
					}
					var r = t;
					t = s;
					s = r;
				}
				t[n];
		}
	}

	static inline function minimum(x:Int, y:Int, z:Int):Int {
		inline function m_(a:Int, b:Int) return if (a < b) a else b;
		return m_(m_(x, y), z);
	}

	public static function filterSimilar(f:String->Int->Bool, cl:Array<{s:String, i:Int}>):Array<String> {
		var r = [];
		for (c in cl) {
			if (!f(c.s, c.i)) break;
			r.push(c.s);
		}
		return r;
	}

	// port: OCaml's String.length counts bytes
	static function byteLength(s:String):Int return haxe.io.Bytes.ofString(s).length;

	public static function getSimilar(s:String, sl:Array<String>):Array<String> {
		if (sl.length == 0) return [];
		var cl = sl.map(function(s2) return {s: s2, i: levenshtein(s, s2)});
		// port: List.sort is stable
		haxe.ds.ArraySort.sort(cl, function(c1, c2) return Reflect.compare(c1.i, c2.i));
		var cl = filterSimilar(function(s2, i) {
			var a = byteLength(s), b = byteLength(s2);
			return i <= Std.int((a < b ? a : b) / 3);
		}, cl);
		return cl;
	}

	public static function stringErrorRaise(s:String, sl:Array<String>, msg:String):String {
		if (sl.length == 0) return msg;
		var cl = getSimilar(s, sl);
		return switch cl {
			case []: throw NotFound.raise();
			case [s]: '$msg (Suggestion: $s)';
			case sl: '$msg (Suggestions: ${sl.join(", ")})';
		}
	}

	public static function stringError(s:String, sl:Array<String>, msg:String):String {
		return try stringErrorRaise(s, sl, msg) catch (_:NotFound) msg;
	}
}
