package fuzz;

/**
	Deterministic 32-bit PRNG (xorshift32 seeded through a splitmix-style mixer).
	Only 32-bit Int operations, so a seed produces the same program on every
	host the fuzzer is built for (hxc, Eval, HashLink, JS).
**/
class Rng {
	var s:Int;

	public function new(seed:Int) {
		s = mix(seed);
		if (s == 0)
			s = 0x2545F491;
	}

	public static function mix(x:Int):Int {
		x = (x ^ (x >>> 16)) * 0x45d9f3b;
		x = (x ^ (x >>> 16)) * 0x45d9f3b;
		return x ^ (x >>> 16);
	}

	public function next():Int {
		var x = s;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		s = x;
		return x;
	}

	/** 0 <= result < n (n > 0). **/
	public function int(n:Int):Int {
		var r = next() % n;
		return r < 0 ? r + n : r;
	}

	/** lo <= result <= hi. **/
	public function range(lo:Int, hi:Int):Int
		return lo + int(hi - lo + 1);

	public function chance(percent:Int):Bool
		return int(100) < percent;

	public function pick<T>(a:Array<T>):T
		return a[int(a.length)];

	/** Picks an index by weight; weights <= 0 are never chosen. Returns -1 if all are <= 0. **/
	public function weighted(w:Array<Int>):Int {
		var total = 0;
		for (x in w)
			if (x > 0)
				total += x;
		if (total == 0)
			return -1;
		var r = int(total);
		for (i in 0...w.length) {
			if (w[i] <= 0)
				continue;
			if (r < w[i])
				return i;
			r -= w[i];
		}
		return -1;
	}

	public function shuffle<T>(a:Array<T>):Void {
		var i = a.length;
		while (i > 1) {
			var j = int(i);
			i--;
			var t = a[i];
			a[i] = a[j];
			a[j] = t;
		}
	}
}
