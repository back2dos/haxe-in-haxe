import haxe.io.Bytes;

// The hl/c output's digest names, normalized for comparing the port with the
// reference. hl2c names function, virtual and context types `t$fun_`, `t$vrt_`
// and `t$ctx_` followed by the first 7 hex digits of the MD5 of the type's
// description marshalled with closures (32 digits when the 7 are taken), and
// writes a context's header as `hl/ctx/<the digits but the first two>.h`. When
// the description reaches an object or virtual prototype, it holds a PMap's
// comparison closure, which the reference marshals as a code pointer of its
// own machine code; the port writes a fixed placeholder there
// (haxe/src/generators/Hl2c.hx, OcamlExtern), so these names differ by design.
//
// `normalize` takes both outputs (path => bytes) and renames, on each side,
// the digest names that occur on that side only, to `t$fun_@<n>` (`@L<n>` for
// a 32-digit one), numbered in order of first appearance (`hl/types.c` first,
// then the files by path, the context headers last), and the context headers
// named after them (paths and `#include`s). Names that occur on both sides stay
// as they are, and every other byte must still match: the renamed outputs are
// identical only when the two sides use their names in the same places.
class HlcNames {
	static final CTX = "hl/ctx/";

	// whether an output (its paths) is hl/c's
	public static function isHlc(paths:Iterable<String>):Bool {
		for (p in paths) if (isTypes(p)) return true;
		return false;
	}

	static function isTypes(p:String):Bool return p == "hl/types.c" || StringTools.endsWith(p, "/hl/types.c");

	public static function normalize(a:Map<String, Bytes>, b:Map<String, Bytes>):{a:Map<String, Bytes>, b:Map<String, Bytes>, renamed:Int} {
		var ta = texts(a), tb = texts(b);
		var na = names(ta), nb = names(tb);
		var setA = new Map<String, Bool>(), setB = new Map<String, Bool>();
		for (n in na) setA.set(n, true);
		for (n in nb) setB.set(n, true);
		var onlyA = [for (n in na) if (!setB.exists(n)) n], onlyB = [for (n in nb) if (!setA.exists(n)) n];
		return {a: rename(a, ta, onlyA), b: rename(b, tb, onlyB), renamed: onlyA.length > onlyB.length ? onlyA.length : onlyB.length};
	}

	// the files as text (hl/c writes ASCII), in the order names are numbered in
	static function texts(m:Map<String, Bytes>):Array<{path:String, text:String}> {
		function rank(p:String):Int return isTypes(p) ? 0 : p.indexOf(CTX) >= 0 ? 2 : 1;
		var paths = [for (k in m.keys()) k];
		paths.sort((x, y) -> {
			var c = rank(x) - rank(y);
			c != 0 ? c : x < y ? -1 : x > y ? 1 : 0;
		});
		return [for (p in paths) {path: p, text: m.get(p).toString()}];
	}

	static inline function isHex(c:Int):Bool return (c >= "0".code && c <= "9".code) || (c >= "a".code && c <= "f".code);

	static function hexRun(s:String, i:Int):Int {
		var n = 0;
		while (i + n < s.length && isHex(StringTools.fastCodeAt(s, i + n))) n++;
		return n;
	}

	// the length of the digest name at i, which starts with `t$` (0 if none)
	static function nameAt(s:String, i:Int):Int {
		var k = s.substr(i, 6);
		if (k != "t$fun_" && k != "t$vrt_" && k != "t$ctx_") return 0;
		var n = hexRun(s, i + 6);
		return n >= 32 ? 6 + 32 : n >= 7 ? 6 + 7 : 0;
	}

	// the digest names of an output, in order of first appearance
	static function names(files:Array<{path:String, text:String}>):Array<String> {
		var seen = new Map<String, Bool>(), out = [];
		for (f in files) {
			var s = f.text;
			var i = s.indexOf("t$");
			while (i >= 0) {
				var n = nameAt(s, i);
				if (n > 0) {
					var name = s.substr(i, n);
					if (!seen.exists(name)) {
						seen.set(name, true);
						out.push(name);
					}
				}
				i = s.indexOf("t$", i + (n > 0 ? n : 2));
			}
		}
		return out;
	}

	static function rename(m:Map<String, Bytes>, files:Array<{path:String, text:String}>, renamed:Array<String>):Map<String, Bytes> {
		if (renamed.length == 0) return m;
		var to = new Map<String, String>(), ctx = new Map<String, String>();
		for (i in 0...renamed.length) {
			var s = renamed[i];
			var digits = s.substr(6);
			var c = (digits.length == 32 ? "@L" : "@") + i;
			to.set(s, s.substr(0, 6) + c);
			if (StringTools.startsWith(s, "t$ctx_")) ctx.set(digits.substr(2), c);
		}
		function apply(s:String):String {
			var parts = [];
			var i = s.indexOf("t$");
			while (i >= 0) {
				var n = nameAt(s, i);
				if (n > 0) {
					var r = to.get(s.substr(i, n));
					if (r != null) parts.push({at: i, len: n, by: r});
				}
				i = s.indexOf("t$", i + (n > 0 ? n : 2));
			}
			var j = s.indexOf(CTX);
			while (j >= 0) {
				var r = hexRun(s, j + CTX.length);
				var c = r > 0 && s.substr(j + CTX.length + r, 2) == ".h" ? ctx.get(s.substr(j + CTX.length, r)) : null;
				if (c != null) parts.push({at: j + CTX.length, len: r, by: c});
				j = s.indexOf(CTX, j + CTX.length);
			}
			if (parts.length == 0) return s;
			parts.sort((x, y) -> x.at - y.at);
			var out = new StringBuf(), last = 0;
			for (p in parts) {
				out.addSub(s, last, p.at - last);
				out.add(p.by);
				last = p.at + p.len;
			}
			out.addSub(s, last, s.length - last);
			return out.toString();
		}
		var res = new Map<String, Bytes>();
		for (f in files) {
			var t = apply(f.text);
			res.set(apply(f.path), t == f.text ? m.get(f.path) : Bytes.ofString(t));
		}
		return res;
	}
}
