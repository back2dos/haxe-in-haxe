package hxmc.rt.gc;

// -D hxmc.wasm-gc: the WasmGC instructions the runtime is written with (each
// call is replaced by them: hxmc.wasmgc.FuncGen.host). A String is an array of
// UTF-16 units.
extern class W {
	static function strLen(s:String):Int;
	static function strGet(s:String, i:Int):Int;
	static function strNew(n:Int):String;
	static function strSet(s:String, i:Int, c:Int):Void;
	static function strCopy(dst:String, di:Int, src:String, si:Int, n:Int):Void;
	// the host's output (hxmc/bootstrap/wasmgc.mjs): fd 1 or 2
	static function write(fd:Int, s:String):Void;
	// seconds since some point, as precisely as the host gives (performance.now)
	static function now():Float;
	// 0 null, 1 Int, 2 Float, 3 Bool, 4 String, 5 class instance, 6 enum,
	// 7 array, 8 function, 9 Int64, 10 anonymous structure, 11 other
	static function kind(v:Dynamic):Int;
	static function unboxInt(v:Dynamic):Int;
	static function unboxFloat(v:Dynamic):Float;
	static function unboxBool(v:Dynamic):Bool;
	static function isNull(v:Dynamic):Bool;
	// the host's shortest form of a Float (JavaScript's, as hxmc.rt.FloatText formats)
	static function fmt(v:Float):String;
	static function parseFloat(s:String):Float;
	// Math.sin... (op: 0 sin, 1 cos, 2 tan, 3 asin, 4 acos, 5 atan, 6 atan2, 7 exp, 8 log, 9 pow) on the host's Math
	static function math(op:Int, x:Float, y:Float):Float;
	static function random():Float;
	static function trap():Void;
}
