package core.ds;

import haxe.Int64;

/**
	C printf float conversions as used by OCaml's `Printf.sprintf "%.<p>g"`
	(glibc: exact decimal expansion, round-half-even on exact ties).
**/
class OcamlPrintf {
	/** Exact decimal digits of a finite, nonzero |f|: value = digits * 10^exp10. **/
	static function exactDecimal(f:Float):{digits:String, exp10:Int} {
		var bits = haxe.io.FPHelper.doubleToI64(f);
		var high = Int64.getHigh(bits), low = Int64.getLow(bits);
		var e = (high >>> 20) & 0x7FF;
		var mantHigh = high & 0xFFFFF;
		var exp2:Int;
		if (e == 0) {
			exp2 = -1074;
		} else {
			mantHigh |= 0x100000;
			exp2 = e - 1075;
		}
		// little-endian base 10000 limbs
		var big:Array<Int> = [0];
		function mulAdd(k:Int, add:Int):Void {
			var carry = add;
			for (i in 0...big.length) {
				var x = big[i] * k + carry;
				big[i] = x % 10000;
				carry = Std.int(x / 10000);
			}
			while (carry > 0) {
				big.push(carry % 10000);
				carry = Std.int(carry / 10000);
			}
		}
		mulAdd(1, mantHigh);
		mulAdd(65536, low >>> 16);
		mulAdd(65536, low & 0xFFFF);
		var exp10 = 0;
		if (exp2 >= 0) {
			var n = exp2;
			while (n >= 16) {
				mulAdd(65536, 0);
				n -= 16;
			}
			if (n > 0) mulAdd(1 << n, 0);
		} else {
			// m * 2^-k = m * 5^k / 10^k
			var n = -exp2;
			exp10 = exp2;
			while (n >= 6) {
				mulAdd(15625, 0);
				n -= 6;
			}
			var p = 1;
			for (_ in 0...n) p *= 5;
			if (p > 1) mulAdd(p, 0);
		}
		var buf = new StringBuf();
		var i = big.length - 1;
		while (i > 0 && big[i] == 0) i--;
		buf.add(Std.string(big[i]));
		while (--i >= 0) {
			var s = Std.string(big[i]);
			for (_ in s.length...4) buf.add("0");
			buf.add(s);
		}
		return {digits: buf.toString(), exp10: exp10};
	}

	/** `Printf.sprintf "%.<precision>g" f` **/
	public static function formatG(precision:Int, f:Float):String {
		if (Math.isNaN(f)) return "nan";
		if (!Math.isFinite(f)) return f < 0 ? "-inf" : "inf";
		var p = precision == 0 ? 1 : precision;
		var negative = f < 0 || (f == 0 && 1 / f < 0);
		var sign = negative ? "-" : "";
		if (f == 0) return sign + "0";
		var d = exactDecimal(Math.abs(f));
		var digits = d.digits;
		// decimal exponent of the first digit
		var x = digits.length - 1 + d.exp10;
		var sig:Array<Int> = [];
		for (i in 0...p) sig.push(i < digits.length ? StringTools.fastCodeAt(digits, i) - 48 : 0);
		if (digits.length > p) {
			var first = StringTools.fastCodeAt(digits, p) - 48;
			var roundUp = if (first > 5) true else if (first < 5) false else {
				var rest = false;
				for (i in p + 1...digits.length) if (StringTools.fastCodeAt(digits, i) != 48) {
					rest = true;
					break;
				}
				rest || (sig[p - 1] & 1) == 1;
			}
			if (roundUp) {
				var i = p - 1;
				while (i >= 0) {
					if (sig[i] == 9) {
						sig[i] = 0;
						i--;
					} else {
						sig[i]++;
						break;
					}
				}
				if (i < 0) {
					sig.unshift(1);
					sig.pop();
					x++;
				}
			}
		}
		var buf = new StringBuf();
		buf.add(sign);
		if (x < -4 || x >= p) {
			// exponential, trailing zeros removed
			var last = p - 1;
			while (last > 0 && sig[last] == 0) last--;
			buf.add(sig[0]);
			if (last > 0) {
				buf.add(".");
				for (i in 1...last + 1) buf.add(sig[i]);
			}
			buf.add(x < 0 ? "e-" : "e+");
			var ax = x < 0 ? -x : x;
			if (ax < 10) buf.add("0");
			buf.add(ax);
		} else {
			// fixed with p - 1 - x decimals, trailing zeros removed
			var intPart = new StringBuf();
			var frac:Array<Int> = [];
			if (x < 0) {
				intPart.add("0");
				for (_ in 0...(-x - 1)) frac.push(0);
				for (v in sig) frac.push(v);
			} else {
				for (i in 0...x + 1) intPart.add(sig[i]);
				for (i in x + 1...p) frac.push(sig[i]);
			}
			while (frac.length > 0 && frac[frac.length - 1] == 0) frac.pop();
			buf.add(intPart.toString());
			if (frac.length > 0) {
				buf.add(".");
				for (v in frac) buf.add(v);
			}
		}
		return buf.toString();
	}
}
