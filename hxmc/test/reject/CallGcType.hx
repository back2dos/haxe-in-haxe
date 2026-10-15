// A call in a safe region cannot pass a GC reference (the collector may move it meanwhile).
// expect: C function takes_string: parameter s has no C type a call can pass (a GC reference, which only a @:hxmc.fast call may take
extern class C {
	@:hxmc.c static function takes_string(s:String):Int;
}

class CallGcType {
	static function main()
		trace(C.takes_string("x"));
}
