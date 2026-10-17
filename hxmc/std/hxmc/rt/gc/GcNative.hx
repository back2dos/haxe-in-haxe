package hxmc.rt.gc;

// -D hxmc.wasm-gc: reflection (hxmc.Native: Type, Reflect, the maps), as
// hxmc.rt.Dyn's, over the tables and functions of hxmc.wasmgc.Meta (W)
@:keep @:hxmc.wasmgc
class GcNative {
	public static function refEq(a:Dynamic, b:Dynamic):Bool
		return W.same(a, b);

	// 0 null, 1 Int, 2 Float, 3 Bool, 4 anonymous object, 5 function, 6 class
	// instance, 7 enum value, 8 String, 9 Array, 10 a type object, 11 other
	public static function typeKind(v:Dynamic):Int
		return switch W.kind(v) {
			case 0: 0;
			case 1: 1;
			case 2: 2;
			case 3: 3;
			case 4: 8;
			case 5: 6;
			case 6: 7;
			case 7: 9;
			case 8: 5;
			case 10: 4;
			case 12: 10;
			case _: 11;
		}

	public static function isInt64(v:Dynamic):Bool
		return W.kind(v) == 9;

	public static function getClass(v:Dynamic):Dynamic
		return switch W.kind(v) {
			case 4: String;
			case 7: Array;
			case 5: W.classOf(v);
			case _: null;
		}

	public static function getEnum(v:Dynamic):Dynamic
		return W.kind(v) == 6 ? W.enumOf(v) : null;

	public static function superClass(c:Dynamic):Dynamic
		throw "Type.getSuperClass: not supported by -D hxmc.wasm-gc yet";

	public static function typeName(t:Dynamic):String
		return W.typeName(t);

	public static function resolveType(n:String):Dynamic {
		var i = 0;
		while (true) {
			var t = W.typeAt(i++);
			if (t == null) break;
			if (W.typeName(t) == n) return t;
		}
		return n == "String" ? String : null;
	}

	public static function createEmpty(c:Dynamic):Dynamic
		return W.createEmpty(c);

	public static function enumCtorNames(e:Dynamic):Array<String> {
		if (!W.isType(e) || W.typeKind(e) != 1) return null;
		return (W.enumNames(e) : Array<String>).copy();
	}

	public static function enumCreate(e:Dynamic, index:Int, params:Array<Dynamic>):Dynamic {
		var names:Array<String> = W.enumNames(e);
		if (index < 0 || index >= names.length) throw "Invalid enum constructor";
		return W.enumCreate(e, index, params == null ? [] : params);
	}

	public static function enumIndex(v:Dynamic):Int
		return W.enumIndex(v);

	public static function enumCtorName(v:Dynamic):String
		return (W.enumNames(W.enumOf(v)) : Array<String>)[W.enumIndex(v)];

	public static function enumParams(v:Dynamic):Array<Dynamic>
		return W.enumParams(v);

	public static function enumEq(a:Dynamic, b:Dynamic):Bool {
		if (W.same(a, b)) return true;
		if (a == null || b == null) return false;
		if (!W.same(W.enumOf(a), W.enumOf(b)) || W.enumIndex(a) != W.enumIndex(b)) return false;
		var pa = enumParams(a), pb = enumParams(b);
		for (i in 0...pa.length) {
			var x = pa[i], y = pb[i];
			if (W.kind(x) == 6 && W.kind(y) == 6) {
				if (!enumEq(x, y)) return false;
			} else if (!GcDyn.eq(x, y)) return false;
		}
		return true;
	}

	// ---- fields (a class instance's or an anonymous structure's, then those added: GcFields)

	static function extra(o:Dynamic, make:Bool):Null<GcFields> {
		if (W.kind(o) != 10) return null;
		var x:GcFields = W.anonOverflow(o);
		if (x == null && make) {
			x = new GcFields();
			W.setAnonOverflow(o, x);
		}
		return x;
	}

	public static function getField(o:Dynamic, name:String):Dynamic {
		var names:Array<String> = W.fieldNames(o);
		if (names != null) {
			var i = names.indexOf(name);
			if (i >= 0) return W.objGet(o, i);
		}
		var x = extra(o, false);
		return x == null ? null : x.get(name);
	}

	public static function setField(o:Dynamic, name:String, v:Dynamic):Void {
		var names:Array<String> = W.fieldNames(o);
		if (names != null) {
			var i = names.indexOf(name);
			if (i >= 0) {
				W.objSet(o, i, v);
				return;
			}
		}
		var x = extra(o, true);
		if (x != null) x.set(name, v);
	}

	public static function hasField(o:Dynamic, name:String):Bool {
		var names:Array<String> = W.fieldNames(o);
		if (names != null && names.indexOf(name) >= 0) return true;
		var x = extra(o, false);
		return x != null && x.names.indexOf(name) >= 0;
	}

	public static function fields(o:Dynamic):Array<String> {
		var names:Array<String> = W.fieldNames(o);
		var r = names == null ? [] : names.copy();
		var x = extra(o, false);
		if (x != null)
			for (n in x.names)
				r.push(n);
		return r;
	}

	public static function deleteField(o:Dynamic, name:String):Bool {
		var x = extra(o, false);
		if (x == null) return false;
		var i = x.names.indexOf(name);
		if (i < 0) return false;
		x.names.splice(i, 1);
		x.values.splice(i, 1);
		return true;
	}

	public static function instanceFields(c:Dynamic):Array<String>
		throw "Type.getInstanceFields: not supported by -D hxmc.wasm-gc yet";

	public static function callMethod(f:Dynamic, args:Array<Dynamic>):Dynamic
		return W.dynCall(f, args);

	public static function copyObject(o:Dynamic):Dynamic
		throw "Reflect.copy: not supported by -D hxmc.wasm-gc yet";

	public static function compareMethods(a:Dynamic, b:Dynamic):Bool
		return W.same(a, b);

	public static function compare(a:Dynamic, b:Dynamic):Int
		return @:privateAccess GcDyn.cmp(a, b);

	// (WasmGC objects have no address to hash: one bucket, ObjectMap then compares
	// by reference; correct, linear in the map's size)
	public static function objHash(o:Dynamic):Int
		return 0;

	// ---- Dynamic access (o.name on a Dynamic)

	@:hxmc.host("hx_dyn_get") static function dynGet(o:Dynamic, name:String):Dynamic
		return getField(o, name);

	@:hxmc.host("hx_dyn_set") static function dynSet(o:Dynamic, name:String, v:Dynamic):Void
		setField(o, name, v);

	@:hxmc.host("hx_dyn_call_field") static function dynCallField(o:Dynamic, name:String, args:Array<Dynamic>):Dynamic
		return W.dynCall(getField(o, name), args);

	// ---- structural access the generated code does not know the layout of (hxmc.wasmgc.FuncGen)

	@:hxmc.export("gc_anon_get") static function anonGet(o:Dynamic, name:String):Dynamic
		return getField(o, name);

	@:hxmc.export("gc_anon_set") static function anonSet(o:Dynamic, name:String, v:Dynamic):Void
		setField(o, name, v);
}

// the fields added to an anonymous structure (Reflect.setField of a name its layout lacks)
@:keep @:hxmc.wasmgc
class GcFields {
	public final names:Array<String> = [];
	public final values:Array<Dynamic> = [];

	public function new() {}

	public function get(name:String):Dynamic {
		var i = names.indexOf(name);
		return i < 0 ? null : values[i];
	}

	public function set(name:String, v:Dynamic) {
		var i = names.indexOf(name);
		if (i < 0) {
			names.push(name);
			values.push(v);
		} else values[i] = v;
	}
}
