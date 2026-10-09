import hxc.Native;

enum ValueType {
	TNull;
	TInt;
	TInt64;
	TFloat;
	TBool;
	TObject;
	TFunction;
	TClass(c:Class<Dynamic>);
	TEnum(e:Enum<Dynamic>);
	TUnknown;
}

// hxc target (backend/): Type over runtime type information (hxc.Native).
class Type {
	public static function getClass<T>(o:T):Null<Class<T>>
		return Native.getClass(o);

	public static function getEnum(o:EnumValue):Null<Enum<Dynamic>>
		return Native.getEnum(o);

	public static function getSuperClass(c:Class<Dynamic>):Null<Class<Dynamic>>
		return Native.superClass(c);

	public static function getClassName(c:Class<Dynamic>):String
		return Native.typeName(c);

	public static function getEnumName(e:Enum<Dynamic>):String
		return Native.typeName(e);

	public static function resolveClass(name:String):Null<Class<Dynamic>> {
		var t = Native.resolveType(name);
		return t != null && Native.enumCtorNames(t) == null ? t : null;
	}

	public static function resolveEnum(name:String):Null<Enum<Dynamic>> {
		var t = Native.resolveType(name);
		return t != null && Native.enumCtorNames(t) != null ? t : null;
	}

	public static function createInstance<T>(cl:Class<T>, args:Array<Dynamic>):T
		throw "Type.createInstance is not supported on hxc";

	public static function createEmptyInstance<T>(cl:Class<T>):T
		return Native.createEmpty(cl);

	public static function createEnum<T>(e:Enum<T>, constr:String, ?params:Array<Dynamic>):T {
		var names = Native.enumCtorNames(e);
		var i = names.indexOf(constr);
		if (i < 0) throw "No such constructor " + constr;
		return Native.enumCreate(e, i, params);
	}

	public static function createEnumIndex<T>(e:Enum<T>, index:Int, ?params:Array<Dynamic>):T
		return Native.enumCreate(e, index, params);

	public static function getInstanceFields(c:Class<Dynamic>):Array<String>
		return Native.instanceFields(c);

	public static function getClassFields(c:Class<Dynamic>):Array<String>
		return [];

	public static function getEnumConstructs(e:Enum<Dynamic>):Array<String>
		return Native.enumCtorNames(e).copy();

	public static function typeof(v:Dynamic):ValueType {
		return switch Native.typeKind(v) {
			case 0: TNull;
			case 1: TInt;
			case 2: TFloat;
			case 3: TBool;
			case 4 | 10: TObject;
			case 5: TFunction;
			case 6: TClass(Native.getClass(v));
			case 7: TEnum(Native.getEnum(v));
			case 8: TClass(String);
			case 9: TClass(Array);
			case _: TUnknown;
		}
	}

	public static function enumEq<T:EnumValue>(a:T, b:T):Bool
		return Native.enumEq(a, b);

	public static function enumConstructor(e:EnumValue):String
		return Native.enumCtorName(e);

	public static function enumParameters(e:EnumValue):Array<Dynamic>
		return Native.enumParams(e);

	public static function enumIndex(e:EnumValue):Int
		return Native.enumIndex(e);

	public static function allEnums<T>(e:Enum<T>):Array<T> {
		var r = [];
		var names = Native.enumCtorNames(e);
		for (i in 0...names.length) {
			var v:Dynamic = try Native.enumCreate(e, i, null) catch (_:Dynamic) null;
			if (v != null && Native.enumParams(v).length == 0) r.push(v);
		}
		return r;
	}
}
