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
	static function objHash(o:Dynamic):Int;
	static function unboxInt(v:Dynamic):Int;
	static function unboxFloat(v:Dynamic):Float;
	static function unboxBool(v:Dynamic):Bool;
	static function unboxI64(v:Dynamic):hxmc.I64;
	static function isNull(v:Dynamic):Bool;
	// the same reference (or both null)
	static function same(a:Dynamic, b:Dynamic):Bool;
	// the host's shortest form of a Float (JavaScript's, as hxmc.rt.FloatText formats)
	static function fmt(v:Float):String;
	static function parseFloat(s:String):Float;
	// Math.sin... (op: 0 sin, 1 cos, 2 tan, 3 asin, 4 acos, 5 atan, 6 atan2, 7 exp, 8 log, 9 pow) on the host's Math
	static function math(op:Int, x:Float, y:Float):Float;
	static function random():Float;
	static function trap():Void;
	// arrays of any element kind: 0 Int, 1 Float, 2 Int64, 3 references, 4 Bool (-1: not an array)
	static function arrLen(a:Dynamic):Int;
	static function arrKind(a:Dynamic):Int;
	// a[i] boxed (null out of range)
	static function arrGet(a:Dynamic, i:Int):Dynamic;
	// a[i] = v, unboxed (the array grows as Haxe's do)
	static function arrSet(a:Dynamic, i:Int, v:Dynamic):Void;
	static function arrNew(kind:Int, n:Int):Dynamic;
	// the length set (grown with zeros, or cut)
	static function arrSetLen(a:Dynamic, n:Int):Void;
	// dst[di...di+n] = src[si...si+n] (one kind, dst long enough)
	static function arrBlit(dst:Dynamic, di:Int, src:Dynamic, si:Int, n:Int):Void;
	// haxe.io.Bytes: an array of bytes
	static function bytesNew(n:Int):Dynamic;
	static function bytesLen(b:Dynamic):Int;
	static function bytesGet(b:Dynamic, i:Int):Int;
	static function bytesSet(b:Dynamic, i:Int, v:Int):Void;
	static function bytesCopy(dst:Dynamic, di:Int, src:Dynamic, si:Int, n:Int):Void;
	static function bytesFill(b:Dynamic, pos:Int, v:Int, n:Int):Void;
	static function bytesGetI32(b:Dynamic, pos:Int):Int;
	static function bytesSetI32(b:Dynamic, pos:Int, v:Int):Void;
	// reflection (hxmc.wasmgc.Meta): the class of an object, the names of its
	// fields (class or anonymous structure: their order is objGet's), a field by index
	static function classOf(o:Dynamic):Dynamic;
	static function fieldNames(o:Dynamic):Dynamic;
	static function objGet(o:Dynamic, i:Int):Dynamic;
	static function objSet(o:Dynamic, i:Int, v:Dynamic):Void;
	static function createEmpty(cl:Dynamic):Dynamic;
	static function enumOf(v:Dynamic):Dynamic;
	static function enumIndex(v:Dynamic):Int;
	static function enumNames(e:Dynamic):Dynamic;
	static function enumParams(v:Dynamic):Array<Dynamic>;
	// Type.enumEq (hxmc.wasmgc.Meta.enumEq)
	static function enumEq(a:Dynamic, b:Dynamic):Bool;
	static function enumCreate(e:Dynamic, index:Int, params:Array<Dynamic>):Dynamic;
	// the classes' types then the enums' (null past the end)
	static function typeAt(i:Int):Dynamic;
	// a type value's kind (0 class, 1 enum, 2 builtin), id, name
	static function typeKind(t:Dynamic):Int;
	static function typeId(t:Dynamic):Int;
	static function typeName(t:Dynamic):String;
	static function isType(v:Dynamic):Bool;
	// the fields added to an anonymous structure (a GcFields)
	static function anonOverflow(o:Dynamic):Dynamic;
	static function setAnonOverflow(o:Dynamic, v:Dynamic):Void;
	static function dynCall(f:Dynamic, args:Array<Dynamic>):Dynamic;
	// the host's system functions (hxmc/bootstrap/wasmgc.mjs: GcSys's op codes)
	static function sysStr(op:Int, a:String, b:String):String;
	static function sysNum(op:Int, a:String, b:String, n:Float):Float;
	// a file's bytes (null when it cannot be read), written (appended)
	static function readFile(path:String):Dynamic;
	static function writeFile(path:String, b:Dynamic, append:Bool):Bool;
	// GcDate's calendar (op codes there)
	static function dateNum(op:Int, t:Float, y:Int, m:Int, d:Int, h:Int, mi:Int, s:Int):Float;
	static function f32Bits(v:Float):Int;
	static function bitsF32(v:Int):Float;
}
