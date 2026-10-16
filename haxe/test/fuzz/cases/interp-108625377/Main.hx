// seed 108625377, diff:interp, reduced. Not a port bug: a math library's
// rounding. sin(-2.5) lies almost halfway between two doubles (0.497 and
// 0.503 ulps from them); glibc (the reference's Eval) returns -0.598472144103956549,
// musl (hxmc's LibM, the port's Eval) -0.598472144103956438, an ulp apart. Times
// 100 that is 2 ulps: -59.847214410395658 against -59.8472144103956438 (both
// Eval's "%.18g"; the reference's 18th digit is 0, dropped). Runner.sameOutput
// accepts printed floats up to MAX_ULPS apart.

import H;

abstract A3(Int) from Int to Int {
	public inline function new(i:Int)
		this = i;

	public var twice(get, never):Int;

	function get_twice():Int
		return this * 2;
}

class Main {
	public static function main():Void {
		H.out("start");
		H.out("o115 " + Std.string(((new A3(50)).twice * Math.sin((-2.5)))));
	}
}
