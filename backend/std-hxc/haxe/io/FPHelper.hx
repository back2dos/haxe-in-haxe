package haxe.io;

// hxc target (backend/): float bit patterns in the runtime (rt_std.c).
extern class FPHelper {
	static function i32ToFloat(i:Int):Float;
	static function floatToI32(f:Float):Int;
	static function i64ToDouble(low:Int, high:Int):Float;
	static inline function doubleToI64(v:Float):haxe.Int64
		return haxe.Int64.make(doubleHigh(v), doubleLow(v));
	static function doubleLow(v:Float):Int;
	static function doubleHigh(v:Float):Int;
}
