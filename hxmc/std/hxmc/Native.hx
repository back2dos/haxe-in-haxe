package hxmc;

import hxmc.rt.Dyn;
import hxmc.rt.Str;

// Reflection for the std implementations (Type and Reflect are Haxe code
// over these), implemented in hxmc.rt.Dyn with the dynamic access
// (strHash: hxmc.rt.Str).
class Native {
	// hash of a string's contents, cached in the string
	public static inline function strHash(s:String):Int
		return Str.strHash(s);

	// stable identity hash of an object (kept in its header across GC moves)
	public static inline function objHash(o:Dynamic):Int
		return Dyn.objHash(o);

	// physical equality
	public static inline function refEq(a:Dynamic, b:Dynamic):Bool
		return Dyn.refEq(a, b);

	// a boxed haxe.Int64 (rt_dyn.c)
	public static inline function isInt64(v:Dynamic):Bool
		return Dyn.isInt64(v);

	// 0 null, 1 Int, 2 Float, 3 Bool, 4 anonymous object, 5 function, 6 class
	// instance, 7 enum value, 8 String, 9 Array, 10 class or enum value (Class<T>), 11 other
	public static inline function typeKind(v:Dynamic):Int
		return Dyn.typeKind(v);

	public static inline function getClass(v:Dynamic):Dynamic
		return Dyn.getClass(v);

	public static inline function getEnum(v:Dynamic):Dynamic
		return Dyn.getEnum(v);

	public static inline function superClass(c:Dynamic):Dynamic
		return Dyn.superClass(c);

	public static inline function typeName(t:Dynamic):String
		return Dyn.typeName(t);

	public static inline function resolveType(name:String):Dynamic
		return Dyn.resolveType(name);

	public static inline function createEmpty(c:Dynamic):Dynamic
		return Dyn.createEmpty(c);

	public static inline function enumCtorNames(e:Dynamic):Array<String>
		return Dyn.enumCtorNames(e);

	public static inline function enumCreate(e:Dynamic, index:Int, params:Null<Array<Dynamic>>):Dynamic
		return Dyn.enumCreate(e, index, params);

	public static inline function enumIndex(v:Dynamic):Int
		return Dyn.enumIndex(v);

	public static inline function enumParams(v:Dynamic):Array<Dynamic>
		return Dyn.enumParams(v);

	public static inline function enumCtorName(v:Dynamic):String
		return Dyn.enumCtorName(v);

	public static inline function enumEq(a:Dynamic, b:Dynamic):Bool
		return Dyn.enumEq(a, b);

	public static inline function instanceFields(c:Dynamic):Array<String>
		return Dyn.instanceFields(c);

	public static inline function fields(o:Dynamic):Array<String>
		return Dyn.fields(o);

	public static inline function hasField(o:Dynamic, f:String):Bool
		return Dyn.hasField(o, f);

	public static inline function getField(o:Dynamic, f:String):Dynamic
		return Dyn.getField(o, f);

	public static inline function setField(o:Dynamic, f:String, v:Dynamic):Void
		Dyn.setField(o, f, v);

	public static inline function deleteField(o:Dynamic, f:String):Bool
		return Dyn.deleteField(o, f);

	public static inline function callMethod(f:Dynamic, args:Array<Dynamic>):Dynamic
		return Dyn.callMethod(f, args);

	public static inline function compareMethods(a:Dynamic, b:Dynamic):Bool
		return Dyn.compareMethods(a, b);

	public static inline function copyObject(o:Dynamic):Dynamic
		return Dyn.copyObject(o);

	public static inline function compare(a:Dynamic, b:Dynamic):Int
		return Dyn.compare(a, b);
}
