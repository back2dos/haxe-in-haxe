package hxmc;

// Runtime intrinsics for the std implementations (rt_dyn.c). Type and Reflect
// are Haxe code over these.
extern class Native {
	// hash of a string's contents, cached in the string
	static function strHash(s:String):Int;
	// stable identity hash of an object (kept in its header across GC moves)
	static function objHash(o:Dynamic):Int;
	// physical equality
	static function refEq(a:Dynamic, b:Dynamic):Bool;
	// a boxed haxe.Int64 (rt_dyn.c)
	static function isInt64(v:Dynamic):Bool;
	// 0 null, 1 Int, 2 Float, 3 Bool, 4 anonymous object, 5 function, 6 class
	// instance, 7 enum value, 8 String, 9 Array, 10 class or enum value (Class<T>), 11 other
	static function typeKind(v:Dynamic):Int;
	static function getClass(v:Dynamic):Dynamic;
	static function getEnum(v:Dynamic):Dynamic;
	static function superClass(c:Dynamic):Dynamic;
	static function typeName(t:Dynamic):String;
	static function resolveType(name:String):Dynamic;
	static function createEmpty(c:Dynamic):Dynamic;
	static function enumCtorNames(e:Dynamic):Array<String>;
	static function enumCreate(e:Dynamic, index:Int, params:Null<Array<Dynamic>>):Dynamic;
	static function enumIndex(v:Dynamic):Int;
	static function enumParams(v:Dynamic):Array<Dynamic>;
	static function enumCtorName(v:Dynamic):String;
	static function enumEq(a:Dynamic, b:Dynamic):Bool;
	static function instanceFields(c:Dynamic):Array<String>;
	static function fields(o:Dynamic):Array<String>;
	static function hasField(o:Dynamic, f:String):Bool;
	static function getField(o:Dynamic, f:String):Dynamic;
	static function setField(o:Dynamic, f:String, v:Dynamic):Void;
	static function deleteField(o:Dynamic, f:String):Bool;
	static function callMethod(f:Dynamic, args:Array<Dynamic>):Dynamic;
	static function compareMethods(a:Dynamic, b:Dynamic):Bool;
	static function copyObject(o:Dynamic):Dynamic;
	static function compare(a:Dynamic, b:Dynamic):Int;
}
