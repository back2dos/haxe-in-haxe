package hxmc.unsafe;

// The layout of a @:hxmc.struct class (C's rules for the target: each field
// at the next multiple of its alignment, the size a multiple of the largest
// alignment), as constants the compiler substitutes (FnLower). The argument
// is the class itself: Struct.sizeOf(SDL_Rect).
extern class Struct {
	static function sizeOf(c:Class<Dynamic>):Int;
	static function alignOf(c:Class<Dynamic>):Int;
	// the offset of the field named by the string literal
	static function offsetOf(c:Class<Dynamic>, field:String):Int;
}
