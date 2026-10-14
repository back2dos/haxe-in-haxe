package hxmc;

// Atomic cells (hxmc/std/hxmc/rt/Atomics.hx) behind haxe.atomic,
// sequentially consistent. An Int cell is a raw object, an object cell a
// one-slot reference array (stores go through the GC write barrier).
extern class NativeAtomic {
	static function intNew(v:Int):Dynamic;
	static function intLoad(a:Dynamic):Int;
	static function intStore(a:Dynamic, v:Int):Int; // returns v
	static function intExchange(a:Dynamic, v:Int):Int; // the operations below return the previous value
	static function intCompareExchange(a:Dynamic, expected:Int, replacement:Int):Int;
	static function intAdd(a:Dynamic, v:Int):Int;
	static function intSub(a:Dynamic, v:Int):Int;
	static function intAnd(a:Dynamic, v:Int):Int;
	static function intOr(a:Dynamic, v:Int):Int;
	static function intXor(a:Dynamic, v:Int):Int;
	static function objNew(v:Dynamic):Dynamic;
	static function objLoad(a:Dynamic):Dynamic;
	static function objStore(a:Dynamic, v:Dynamic):Dynamic; // returns v
	static function objExchange(a:Dynamic, v:Dynamic):Dynamic;
	static function objCompareExchange(a:Dynamic, expected:Dynamic, replacement:Dynamic):Dynamic; // by reference
}
