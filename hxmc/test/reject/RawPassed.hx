// The raw-address check: a heap address passed to a C call in a safe region (the object may move meanwhile).
// expect: RawPassed.main: a raw heap address (Mem.addr) is passed to a call of the C function t_strlen
import hxmc.unsafe.*;

extern class C {
	@:hxmc.c("t_strlen") static function strlen(s:Ptr<UInt8>):UInt64;
}

class RawPassed {
	static function main() {
		var b = haxe.io.Bytes.ofString("abc\x00");
		trace(C.strlen(Mem.addr(b).add(8)).toInt());
	}
}
