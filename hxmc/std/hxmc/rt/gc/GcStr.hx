package hxmc.rt.gc;

// -D hxmc.wasm-gc: the runtime's string functions (UTF-16 arrays, W), the
// same results as hxmc.rt.Str's
@:keep @:hxmc.wasmgc
class GcStr {
	// s[pos...pos+n] as a new string
	public static function sub(s:String, pos:Int, n:Int):String {
		var r = W.strNew(n);
		W.strCopy(r, 0, s, pos, n);
		return r;
	}

	@:hxmc.host("hx_str_concat") static function concat(a:String, b:String):String {
		if (a == null) a = "null";
		if (b == null) b = "null";
		var la = W.strLen(a), lb = W.strLen(b);
		if (la == 0) return b;
		if (lb == 0) return a;
		var r = W.strNew(la + lb);
		W.strCopy(r, 0, a, 0, la);
		W.strCopy(r, la, b, 0, lb);
		return r;
	}

	@:hxmc.host("hx_str_or_null") @:hxmc.noGc static function orNull(s:String):String
		return W.isNull(s) ? "null" : s;

	@:hxmc.host("hx_str_eq") @:hxmc.noGc static function eq(a:String, b:String):Bool {
		if (W.isNull(a) || W.isNull(b)) return W.isNull(a) && W.isNull(b);
		var n = W.strLen(a);
		if (n != W.strLen(b)) return false;
		for (i in 0...n)
			if (W.strGet(a, i) != W.strGet(b, i)) return false;
		return true;
	}

	@:hxmc.host("hx_str_cmp") @:hxmc.noGc public static function cmp(a:String, b:String):Int {
		if (W.isNull(a)) return W.isNull(b) ? 0 : -1;
		if (W.isNull(b)) return 1;
		var na = W.strLen(a), nb = W.strLen(b);
		var n = na < nb ? na : nb;
		for (i in 0...n) {
			var x = W.strGet(a, i), y = W.strGet(b, i);
			if (x != y) return x < y ? -1 : 1;
		}
		return na < nb ? -1 : na > nb ? 1 : 0;
	}

	// FNV-1a over the units (as hxmc.rt.Str: switch on strings compares these)
	@:hxmc.host("hx_str_hash") @:hxmc.noGc static function hash(s:String):Int {
		var x = 0x811C9DC5;
		for (i in 0...W.strLen(s))
			x = (x ^ W.strGet(s, i)) * 16777619;
		return x == 0 ? 1 : x;
	}

	// StringMap's (the same as hx_str_hash: maps iterate in the native order)
	public static function strHash(s:String):Int
		return W.isNull(s) ? 0 : hash(s);

	@:hxmc.host("hx_str_of_int") static function ofInt(v:Int):String {
		if (v == 0) return "0";
		// (digits from the end; the most negative Int has no positive counterpart)
		var neg = v < 0, n = 0, x = v;
		while (x != 0) {
			n++;
			x = Std.int(x / 10);
		}
		var r = W.strNew(neg ? n + 1 : n), i = neg ? n + 1 : n;
		x = v;
		while (x != 0) {
			var d = x % 10;
			W.strSet(r, --i, 48 + (d < 0 ? -d : d));
			x = Std.int(x / 10);
		}
		if (neg) W.strSet(r, 0, 45);
		return r;
	}

	@:hxmc.host("hx_str_of_i64") static function ofI64(v:hxmc.I64):String {
		// (digits of the negative value: no overflow at the minimum)
		var neg = v < 0;
		var m = neg ? v : -v;
		var n = 1;
		var t = m;
		while (t <= -10) {
			t = t / 10;
			n++;
		}
		if (neg) n++;
		var r = W.strNew(n), k = n;
		do {
			var q = m / 10;
			W.strSet(r, --k, 48 + (q * 10 - m).toInt());
			m = q;
		} while (m < 0);
		if (neg) W.strSet(r, 0, 45);
		return r;
	}

	@:hxmc.host("hx_str_of_float") static function ofFloat(v:Float):String {
		// (integral values as Ints: no host call)
		if (v == Std.int(v) && (v != 0 || 1 / v > 0)) return ofInt(Std.int(v));
		return W.fmt(v);
	}

	@:hxmc.host("hx_str_of_bool") @:hxmc.noGc static function ofBool(b:Bool):String
		return b ? "true" : "false";

	@:hxmc.host("String_charAt") static function charAt(s:String, i:Int):String
		return i < 0 || i >= W.strLen(s) ? "" : sub(s, i, 1);

	@:hxmc.host("String_charCodeAt") static function charCodeAt(s:String, i:Int):Null<Int>
		return i < 0 || i >= W.strLen(s) ? null : W.strGet(s, i);

	@:hxmc.host("String_fromCharCode") static function fromCharCode(code:Int):String {
		if (code < 0x10000) {
			var r = W.strNew(1);
			W.strSet(r, 0, code);
			return r;
		}
		var r = W.strNew(2), c = code - 0x10000;
		W.strSet(r, 0, 0xD800 | (c >> 10));
		W.strSet(r, 1, 0xDC00 | (c & 0x3FF));
		return r;
	}

	@:hxmc.host("String_indexOf") @:hxmc.noGc static function indexOf(s:String, needle:String, start:Null<Int>):Int {
		var n = W.strLen(s), m = W.strLen(needle);
		var i = start == null ? 0 : start;
		if (i < 0) {
			i += n;
			if (i < 0) i = 0;
		}
		while (i + m <= n) {
			var k = 0;
			while (k < m && W.strGet(s, i + k) == W.strGet(needle, k))
				k++;
			if (k == m) return i;
			i++;
		}
		return m == 0 && i <= n ? n : -1;
	}

	@:hxmc.host("String_lastIndexOf") @:hxmc.noGc static function lastIndexOf(s:String, needle:String, start:Null<Int>):Int {
		var n = W.strLen(s), m = W.strLen(needle);
		var i = start == null ? n - m : start;
		if (i > n - m) i = n - m;
		while (i >= 0) {
			var k = 0;
			while (k < m && W.strGet(s, i + k) == W.strGet(needle, k))
				k++;
			if (k == m) return i;
			i--;
		}
		return -1;
	}

	@:hxmc.host("String_substr") static function substr(s:String, pos:Int, lenp:Null<Int>):String {
		var n = W.strLen(s);
		var len = lenp == null ? n : lenp;
		if (pos < 0) {
			pos += n;
			if (pos < 0) pos = 0;
		} else if (pos > n) return "";
		if (len < 0) {
			len += n - pos;
			if (len < 0) return "";
		}
		if (pos + len > n) len = n - pos;
		return len <= 0 ? "" : sub(s, pos, len);
	}

	@:hxmc.host("String_substring") static function substring(s:String, start:Int, endp:Null<Int>):String {
		var n = W.strLen(s);
		var end = endp == null ? n : endp;
		if (start < 0) start = 0;
		if (end < 0) end = 0;
		if (start > n) start = n;
		if (end > n) end = n;
		if (start > end) {
			var t = start;
			start = end;
			end = t;
		}
		return sub(s, start, end - start);
	}

	@:hxmc.host("String_toLowerCase") static function toLowerCase(s:String):String {
		var n = W.strLen(s), r = W.strNew(n);
		for (i in 0...n) {
			var c = W.strGet(s, i);
			W.strSet(r, i, c >= 65 && c <= 90 ? c + 32 : c);
		}
		return r;
	}

	@:hxmc.host("String_toUpperCase") static function toUpperCase(s:String):String {
		var n = W.strLen(s), r = W.strNew(n);
		for (i in 0...n) {
			var c = W.strGet(s, i);
			W.strSet(r, i, c >= 97 && c <= 122 ? c - 32 : c);
		}
		return r;
	}

	@:hxmc.host("String_toString") @:hxmc.noGc static function toString(s:String):String
		return s;

	@:hxmc.host("String_split") static function split(s:String, delim:String):Array<String> {
		var out:Array<String> = [];
		var n = W.strLen(s), m = W.strLen(delim);
		if (m == 0) {
			for (i in 0...n)
				out.push(sub(s, i, 1));
			return out;
		}
		var from = 0;
		while (true) {
			var at = indexOf(s, delim, from);
			if (at < 0) break;
			out.push(sub(s, from, at - from));
			from = at + m;
		}
		out.push(sub(s, from, n - from));
		return out;
	}

	@:hxmc.host("Std_parseInt") static function parseInt(s:String):Null<Int> {
		if (W.isNull(s)) return null;
		var n = W.strLen(s), i = 0;
		while (i < n && isSpace(W.strGet(s, i)))
			i++;
		var neg = false;
		if (i < n && (W.strGet(s, i) == 45 || W.strGet(s, i) == 43)) {
			neg = W.strGet(s, i) == 45;
			i++;
		}
		if (i + 1 < n && W.strGet(s, i) == 48 && (W.strGet(s, i + 1) | 32) == 120) {
			i += 2;
			var v = 0, any = false;
			while (i < n) {
				var c = W.strGet(s, i) | 32, d = c >= 48 && c <= 57 ? c - 48 : c >= 97 && c <= 102 ? c - 87 : -1;
				if (d < 0) break;
				v = v * 16 + d;
				any = true;
				i++;
			}
			return any ? (neg ? -v : v) : null;
		}
		var v = 0, any = false;
		while (i < n) {
			var c = W.strGet(s, i);
			if (c < 48 || c > 57) break;
			v = v * 10 + (c - 48);
			any = true;
			i++;
		}
		return any ? (neg ? -v : v) : null;
	}

	@:hxmc.host("Std_parseFloat") static function parseFloat(s:String):Float
		return W.isNull(s) ? Math.NaN : W.parseFloat(s);

	@:hxmc.host("Std_random") @:hxmc.noGc static function random(max:Int):Int
		return max <= 0 ? 0 : Std.int(W.random() * max);

	static function isSpace(c:Int):Bool
		return c == 32 || (c >= 9 && c <= 13);

	@:hxmc.host("Std_string") public static function dynString(v:Dynamic):String
		return switch W.kind(v) {
			case 0: "null";
			case 1: ofInt(W.unboxInt(v));
			case 2: ofFloat(W.unboxFloat(v));
			case 3: W.unboxBool(v) ? "true" : "false";
			case 4: (v : String);
			case 7: @:privateAccess GcArr.toString(v);
			case 8: "<function>";
			case 9: ofI64(W.unboxI64(v));
			case _: "[object]";
		}

	@:hxmc.host("hx_std_string") static function stdString(v:Dynamic):String
		return dynString(v);

	// ---- StringBuf: a GcBuf

	@:hxmc.host("StringBuf_new") static function sbNew():Dynamic
		return new GcBuf();

	@:hxmc.host("StringBuf_add") static function sbAdd(b:Dynamic, x:Dynamic):Void
		(b : GcBuf).add(dynString(x));

	@:hxmc.host("StringBuf_addSub") static function sbAddSub(b:Dynamic, s:String, pos:Int, lenp:Null<Int>):Void
		(b : GcBuf).add(substr(s, pos, lenp));

	@:hxmc.host("StringBuf_addChar") static function sbAddChar(b:Dynamic, c:Int):Void
		(b : GcBuf).addChar(c);

	@:hxmc.host("StringBuf_clear") @:hxmc.noGc static function sbClear(b:Dynamic):Void
		(b : GcBuf).len = 0;

	@:hxmc.host("StringBuf_get_length") @:hxmc.noGc static function sbGetLength(b:Dynamic):Int
		return (b : GcBuf).len;

	@:hxmc.host("StringBuf_toString") static function sbToString(b:Dynamic):String {
		var g:GcBuf = b;
		return sub(g.chars, 0, g.len);
	}
}
