// Exception-heavy microbenchmark for the experimental backends: the compiler
// uses exceptions for control flow (parser backtracking, lookups).
class Miss {
	public var depth:Int;

	public function new(d:Int)
		depth = d;
}

class Exc {
	static function find(n:Int, depth:Int):Int {
		if (depth == 0) {
			if (n % 3 == 0) throw new Miss(n);
			return n;
		}
		return find(n, depth - 1) + 1;
	}

	static function main() {
		var hits = 0;
		var misses = 0;
		for (i in 0...2000000) {
			try {
				hits = (hits + find(i, i & 7)) & 0xFFFFFF;
			} catch (m:Miss) {
				misses++;
			}
		}
		Out.int(hits);
		Out.int(misses);
	}
}

class Out {
	public static function int(v:Int):Void {
		#if cross
		Host.printInt(v);
		#elseif sys
		Sys.println(v);
		#else
		js.Syntax.code("console.log({0})", v);
		#end
	}
}

extern class Host {
	static function printInt(v:Int):Void;
}
