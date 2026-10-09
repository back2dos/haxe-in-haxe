import hxc.Native;

// hxc target (backend/): Reflect over runtime type information (hxc.Native).
class Reflect {
	public static function hasField(o:Dynamic, field:String):Bool
		return Native.hasField(o, field);

	public static function field(o:Dynamic, field:String):Dynamic
		return Native.getField(o, field);

	public static function setField(o:Dynamic, field:String, value:Dynamic):Void
		Native.setField(o, field, value);

	public static function getProperty(o:Dynamic, field:String):Dynamic {
		var getter = Native.getField(o, "get_" + field);
		return getter != null && isFunction(getter) ? Native.callMethod(getter, []) : Native.getField(o, field);
	}

	public static function setProperty(o:Dynamic, field:String, value:Dynamic):Void {
		var setter = Native.getField(o, "set_" + field);
		if (setter != null && isFunction(setter)) Native.callMethod(setter, [value]) else Native.setField(o, field, value);
	}

	public static function callMethod(o:Dynamic, func:haxe.Constraints.Function, args:Array<Dynamic>):Dynamic
		return Native.callMethod(func, args);

	public static function fields(o:Dynamic):Array<String>
		return Native.fields(o);

	public static function isFunction(f:Dynamic):Bool
		return Native.typeKind(f) == 5;

	public static function compare<T>(a:T, b:T):Int
		return Native.compare(a, b);

	public static function compareMethods(f1:Dynamic, f2:Dynamic):Bool
		return Native.compareMethods(f1, f2);

	public static function isObject(v:Dynamic):Bool {
		var k = Native.typeKind(v);
		return k == 4 || k == 6 || k == 8 || k == 9 || k == 10;
	}

	public static function isEnumValue(v:Dynamic):Bool
		return Native.typeKind(v) == 7;

	public static function deleteField(o:Dynamic, field:String):Bool
		return Native.deleteField(o, field);

	public static function copy<T>(o:Null<T>):Null<T>
		return o == null ? null : Native.copyObject(o);

	@:overload(function(f:Array<Dynamic>->Void):Dynamic {})
	public static function makeVarArgs<T>(f:Array<Dynamic>->T):Dynamic
		throw "Reflect.makeVarArgs is not supported on hxc";
}
