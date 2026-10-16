// Math's functions on deterministic inputs (random bit patterns, typical
// ranges, edge cases): a checksum of the result bits per function (NaNs
// counted as one pattern: their sign and payload follow the processor),
// and a few results printed. The golden file is musl's (main's Linux
// x86-64 build, which linked musl's C library); every target computes the
// same (hxmc/std/hxmc/rt/LibM.hx).
import haxe.io.FPHelper;

class MathLib {
	static var seed = 12345;

	static function next():Int {
		seed = seed * 1103515245 + 12345;
		var a = seed >>> 8;
		seed = seed * 1103515245 + 12345;
		return (a << 8) ^ (seed >>> 12);
	}

	// a double of random bits
	static function bitsDouble():Float
		return FPHelper.i64ToDouble(next(), next());

	// uniform in [lo, hi)
	static function unif(lo:Float, hi:Float):Float
		return lo + (hi - lo) * ((next() >>> 1) / 2147483648.0);

	static var EDGES:Array<Float> = [0.0, -0.0, Math.POSITIVE_INFINITY, Math.NEGATIVE_INFINITY, Math.NaN, 1, -1, 0.5, -0.5, 2, -2,
		3.141592653589793, -3.141592653589793, 1.5707963267948966, 0.7853981633974483, 1e-300, 5e-324, -5e-324, 2.2250738585072014e-308,
		1e300, 1.7976931348623157e308, -1.7976931348623157e308, 709.782712893384, 709.7827128933841, -745.1332191019411, -745.1332191019412,
		0.1, 1e22, 4503599627370496.0, 4503599627370495.5, -4503599627370495.5, 0.49999999999999994, -0.49999999999999994, 2.5, -2.5, 1e-8,
		1e15, 1e16, 6.283185307179586, 1e10, -1e10, 0.9999999999999999, 1.0000000000000002, 10, 100, -100, 1024, -1075];

	static var h1 = 0;
	static var h2 = 0;

	static function add(r:Float) {
		var lo = FPHelper.doubleLow(r), hi = FPHelper.doubleHigh(r);
		if (r != r) {
			lo = 0;
			hi = 0x7ff80000;
		}
		h1 = h1 * 31 + lo;
		h2 = h2 * 37 + hi;
	}

	static function unary(name:String, f:Float->Float, lo:Float, hi:Float, lo2:Float, hi2:Float) {
		h1 = h2 = 0;
		for (x in EDGES)
			add(f(x));
		for (i in 0...20000) {
			var x = switch i % 3 {
				case 0: bitsDouble();
				case 1: unif(lo, hi);
				case _: unif(lo2, hi2);
			}
			add(f(x));
		}
		Sys.println(name + " " + StringTools.hex(h1, 8) + StringTools.hex(h2, 8) + " " + f(0.3) + " " + f(-1.7) + " " + f(123.456));
	}

	static function binary(name:String, f:(Float, Float) -> Float, lo:Float, hi:Float, ylo:Float, yhi:Float) {
		h1 = h2 = 0;
		for (x in EDGES)
			for (y in EDGES)
				add(f(x, y));
		for (i in 0...20000) {
			var x = 0.0, y = 0.0;
			switch i % 3 {
				case 0:
					x = bitsDouble();
					y = bitsDouble();
				case 1:
					x = unif(lo, hi);
					y = unif(ylo, yhi);
				case _:
					x = unif(-10, 0);
					y = (next() >>> 1) % 41 - 20;
			}
			add(f(x, y));
		}
		Sys.println(name + " " + StringTools.hex(h1, 8) + StringTools.hex(h2, 8) + " " + f(0.3, 2.5) + " " + f(-1.7, 3) + " " + f(123.456, -0.75));
	}

	static function main() {
		unary("sin", Math.sin, -7, 7, -1e6, 1e6);
		unary("cos", Math.cos, -7, 7, -1e6, 1e6);
		unary("tan", Math.tan, -7, 7, -1e6, 1e6);
		unary("asin", Math.asin, -1, 1, -1.1, 1.1);
		unary("acos", Math.acos, -1, 1, -1.1, 1.1);
		unary("atan", Math.atan, -10, 10, -1e8, 1e8);
		unary("exp", Math.exp, -745.2, 709.8, -2, 2);
		unary("log", Math.log, 0, 10, 0, 1e300);
		unary("sqrt", Math.sqrt, 0, 100, 0, 1e300);
		unary("ffloor", Math.ffloor, -1e3, 1e3, -1e16, 1e16);
		unary("fceil", Math.fceil, -1e3, 1e3, -1e16, 1e16);
		unary("fround", Math.fround, -1e3, 1e3, -1e16, 1e16);
		binary("atan2", Math.atan2, -10, 10, -10, 10);
		binary("pow", Math.pow, 0, 4, -1100, 1100);
		binary("fmod", (x, y) -> x % y, -1e6, 1e6, -10, 10);
		// Int results
		var s = 0;
		for (i in 0...20000) {
			var x = unif(-1e6, 1e6);
			s = s * 31 + Math.floor(x) + 7 * Math.ceil(x) + 13 * Math.round(x);
		}
		Sys.println("floor/ceil/round " + StringTools.hex(s, 8) + " " + Math.floor(-0.5) + " " + Math.ceil(-0.5) + " " + Math.round(-0.5) + " "
			+ Math.round(2.5) + " " + Math.round(-2.5));
	}
}
