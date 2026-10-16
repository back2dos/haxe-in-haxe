package hxmc.macro;

#if hxmc.jit
import core.Globals.Pos;
import macros.eval.EvalValue.Value;
import macros.eval.EvalEncode;
import macros.eval.EvalHash;
import hxmc.unsafe.Mem;
import hxmc.rt.Gc;
import hxmc.macro.Loader.Bundle;

// Unsupported at the boundary: the engine falls back to Eval.
class Unsupported extends haxe.Exception {}

// Native objects of a bundle to and from Eval values at the boundary of
// native macros, so MacroApi stays the one implementation of the macro API:
// arguments and results of macro calls, and of the API calls macro code
// makes (GuestApi: `hxmc_macro_api`). Native objects are read and made with
// the runtime's reflection, which knows the bundle's types (Loader).
// Strings, numbers, booleans, arrays, anonymous structures and enum values
// are converted; other values (positions, types, ...) pass through as the
// Eval values themselves, opaque to macro code. Enum values carry the
// positions Eval gives them: the declaration of a constructor without
// arguments, the construction for the others (recorded by the guest code:
// `hxmc_macro_enum_pos`).
@:access(hxmc.rt.Gc)
class Bridge {
	public static var bundle:Null<Bundle> = null;
	// the macro context's enums (the declaration positions of their constructors)
	public static var enumLookup:Null<String->Null<core.TType.TEnum>> = null;
	static var enumPos = new haxe.ds.ObjectMap<Dynamic, Null<Pos>>();
	public static var apiCalls = 0;

	public static function reset() {
		enumPos = new haxe.ds.ObjectMap();
		slotPos = new haxe.ds.ObjectMap();
	}

	// ---- the exports macro code calls

	@:hxmc.export("hxmc_macro_api") static function api(name:String, args:Array<Dynamic>):Dynamic {
		apiCalls++;
		var f = macros.eval.EvalContext.GlobalState.macroLib.get(name);
		if (f == null) throw new Unsupported("macro API " + name);
		var vl = [for (a in args) toValue(a)];
		return ofValue(macros.eval.EvalMisc.callValue(f, vl));
	}

	@:hxmc.export("hxmc_macro_pos") static function mkPos(file:String, min:Int, max:Int):Dynamic
		return EvalEncode.encodePos({pfile: file, pmin: min, pmax: max});

	@:hxmc.export("hxmc_macro_enum_pos") static function enumAt(v:Dynamic, file:String, min:Int, max:Int):Dynamic {
		enumPos.set(v, {pfile: file, pmin: min, pmax: max});
		return v;
	}

	// ---- native to Eval

	static function isValue(v:Dynamic):Bool
		return switch Type.typeof(v) {
			case TEnum(e): e == Value;
			case _: false;
		}

	// the positions of the shared values of constructors without arguments, by place (container, slot)
	static var slotPos = new haxe.ds.ObjectMap<Dynamic, Map<String, Null<Pos>>>();

	static function placed(c:Dynamic, k:String):{found:Bool, p:Null<Pos>} {
		var m = c == null ? null : slotPos.get(c);
		return m != null && m.exists(k) ? {found: true, p: m.get(k)} : {found: false, p: null};
	}

	static function place(c:Dynamic, pend:Array<{k:String, p:Null<Pos>}>) {
		if (pend.length == 0) return;
		var m = slotPos.get(c);
		if (m == null) slotPos.set(c, m = new Map());
		for (x in pend)
			m.set(x.k, x.p);
	}

	public static function toValue(v:Dynamic, ?c:Dynamic, ?k:String):Value {
		if (v == null) return VNull;
		switch Type.typeof(v) {
			case TNull: return VNull;
			case TInt: return VInt32(v);
			case TFloat: return VFloat(v);
			case TBool: return v ? VTrue : VFalse;
			case TClass(cl) if (cl == String): return EvalEncode.encodeString(v);
			case TClass(cl) if (cl == Array):
				var n:Int = v.length;
				return EvalEncode.encodeArray([for (i in 0...n) toValue(v[i], v, "i" + i)]);
			case TEnum(e) if (e == Value):
				return (v : Value);
			case TEnum(e):
				var name = Type.getEnumName(e);
				var idx = Type.enumIndex(v);
				var params = Type.enumParameters(v);
				var p:Null<Pos> = null;
				if (params.length == 0) {
					var at = placed(c, k);
					p = at.found ? at.p : declPos(name, idx);
				} else if (enumPos.exists(v)) {
					p = enumPos.get(v);
				} else throw new Unsupported("enum value without a position: " + name + "." + Type.enumConstructor(v));
				return EvalEncode.encodeEnumValue(EvalHash.hash(name), idx, [for (i in 0...params.length) toValue(params[i], v, "a" + i)], p);
			case TObject:
				var fs = Reflect.fields(v);
				return EvalEncode.encodeObjS([for (f in fs) {name: f, value: toValue(Reflect.field(v, f), v, "f" + f)}]);
			case t:
				throw new Unsupported("native value " + Std.string(t));
		}
	}

	static function declPos(name:String, idx:Int):Null<Pos> {
		var en = enumLookup == null ? null : enumLookup(name);
		if (en == null) return null;
		for (ef in en.eConstrs)
			if (ef.efIndex == idx) return ef.efPos;
		return null;
	}

	// ---- Eval to native

	// pend: where the caller records the position of a shared constructor value it gets for slot k
	public static function ofValue(v:Value, ?pend:Array<{k:String, p:Null<Pos>}>, ?k:String):Dynamic {
		return switch v {
			case VNull: null;
			case VTrue: true;
			case VFalse: false;
			case VInt32(i): i;
			case VFloat(f): f;
			case VString(s): s.sstring;
			case VArray(a):
				var r:Array<Dynamic> = [];
				var mine = [];
				for (i in 0...a.alength)
					r.push(ofValue(a.avalues[i], mine, "i" + i));
				place(r, mine);
				r;
			case VEnumValue(ev):
				var name = EvalHash.revHash(ev.epath);
				var to = bundle.typeObjs.get(name);
				if (to == null) throw new Unsupported("enum " + name + " not in the native code");
				var e:Enum<Dynamic> = Mem.obj(to);
				if (ev.eargs.length == 0) {
					var t = Mem.getI32(to, 0);
					var ct = Mem.getI32At(Mem.getPtr(Mem.sym("rt_types").add(t * 112), 88), 0, ev.eindex);
					var g = bundle.singletons.get(ct);
					if (g == null) throw new Unsupported("no shared value of " + name + "#" + ev.eindex);
					if (pend != null) pend.push({k: k, p: ev.enpos});
					Mem.getRef(Gc.globals, 8 * g);
				} else {
					var mine = [];
					var args = [for (i in 0...ev.eargs.length) ofValue(ev.eargs[i], mine, "a" + i)];
					var o:Dynamic = Type.createEnumIndex(e, ev.eindex, args);
					place(o, mine);
					enumPos.set(o, ev.enpos);
					o;
				}
			case VObject(o):
				var fs = macros.eval.EvalContext.objectFields(o);
				var names = [for (f in fs) EvalHash.revHash(f.name)];
				var r = newAnon(names);
				var mine = [];
				for (i in 0...fs.length)
					Reflect.setField(r, names[i], ofValue(fs[i].value, mine, "f" + names[i]));
				place(r, mine);
				r;
			// (forced: Eval forces it when macro code reads it)
			case VLazy(l): ofValue(l.force(), pend, k);
			case _: v; // opaque: a position, a type, ...
		}
	}

	// an object of the bundle's anonymous structure with the most of these fields (the others overflow)
	static function newAnon(names:Array<String>):Dynamic {
		var best = -1, bestN = -1;
		for (s in bundle.shapes) {
			var ok = true;
			for (f in s.fields)
				if (names.indexOf(f) < 0) {
					ok = false;
					break;
				}
			if (ok && s.fields.length > bestN) {
				best = s.tindex;
				bestN = s.fields.length;
			}
		}
		if (best < 0) throw new Unsupported("no anonymous structure for {" + names.join(", ") + "}");
		var n = Mem.getI32(Mem.sym("rt_types").add(best * 112), 16);
		return Mem.alloc(n > 0 ? n : 1, best, 0);
	}
}
#end
