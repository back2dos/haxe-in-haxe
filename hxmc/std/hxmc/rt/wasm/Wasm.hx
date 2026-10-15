package hxmc.rt.wasm;

import hxmc.I64;
import hxmc.unsafe.Ptr;

// What the linker writes as WebAssembly instructions (wasm.LinkWasm's builtins).
@:hxmc.c @:hxmc.fast extern class Wasm {
	static function wasm_memory_size():Int; // pages
	static function wasm_memory_grow(pages:Int):Int; // the old size, -1: refused
	static function memcpy(dst:Ptr, src:Ptr, n:I64):Ptr;
	static function memset(dst:Ptr, c:Int, n:I64):Ptr;
	static function memmove(dst:Ptr, src:Ptr, n:I64):Ptr;
	static function floor(x:Float):Float;
	static function trunc(x:Float):Float;
}
