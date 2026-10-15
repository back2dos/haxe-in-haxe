// A jump table indexed by an Int whose register's upper half is not zero:
// the remainder of a negative number made positive (an addition x86-64 does
// with lea, 64-bit), as test/fuzz's Rng.int does (it crashed the fuzzer).
class Rng {
	var s:Int;

	public function new(seed:Int)
		s = seed;

	public function next():Int {
		var x = s;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		s = x;
		return x;
	}

	public function int(n:Int):Int {
		var r = next() % n;
		return r < 0 ? r + n : r;
	}
}

class SwitchIndex {
	static function pick(r:Rng, k:Int):String {
		return switch r.int(7) {
			case 0: "a" + k;
			case 1: "b";
			case 2: "c" + k;
			case 3: "d";
			case 4: "e" + k;
			case 5: "f";
			default: "g";
		}
	}

	static function main() {
		var r = new Rng(1059514019);
		var counts = new Map<String, Int>();
		var out = new StringBuf();
		for (i in 0...200) {
			var s = pick(r, i).charAt(0);
			counts.set(s, (counts.exists(s) ? counts.get(s) : 0) + 1);
			if (i < 20) out.add(s);
		}
		Sys.println(out.toString());
		var keys = [for (k in counts.keys()) k];
		keys.sort(Reflect.compare);
		Sys.println([for (k in keys) k + "=" + counts.get(k)].join(" "));
	}
}
