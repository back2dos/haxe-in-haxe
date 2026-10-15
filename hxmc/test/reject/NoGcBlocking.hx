// A C call in a safe region is a GC point: only @:hxmc.fast calls are allowed in no-GC code.
// expect: NoGcBlocking.leaf is declared @:hxmc.noGc but reaches a GC point: it calls the C function blocking_strlen in a safe region
import hxmc.unsafe.*;

extern class C {
	@:hxmc.c("blocking_strlen") static function strlen(s:CString):UInt64;
}

class NoGcBlocking {
	@:hxmc.noGc static function leaf(s:CString):Int
		return C.strlen(s).toInt();

	static function main()
		Arena.scoped(a -> trace(leaf(a.cstring("abc"))));
}
