// The raw-address check: the address of a heap object must not be live across a GC point.
// expect: RawAcross.hx:8: RawAcross.main: a raw heap address (Mem.addr) in p is live across the allocation of an array
import hxmc.unsafe.*;

class RawAcross {
	static var keep:Array<Int>;

	static function main() {
		var b = haxe.io.Bytes.alloc(16);
		var p = Mem.addr(b).add(8);
		keep = [1, 2, 3];
		Mem.setI32(p, 0, 5);
	}
}
