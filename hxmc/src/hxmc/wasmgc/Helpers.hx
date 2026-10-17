package hxmc.wasmgc;

import hxmc.Buf;
import hxmc.ir.Ir;
import hxmc.wasm.Enc;

// Small functions the generated code calls (written here in wasm, once per
// module, when first asked for): Haxe's array accesses (reads out of range
// give the default, writes past the end grow the array), Dynamic's unboxing,
// fmod, interface tests and the kind of a Dynamic value (hxmc.rt.gc.W.kind).
class Helpers {
	static function valByte(k:String):Int
		return switch k {
			case "i" | "b": Enc.I32;
			case "f": Enc.F64;
			case "l": Enc.I64;
			case _: 0x6D;
		}

	static function get(b:Buf, i:Int) {
		b.u8(0x20);
		Enc.uleb(b, i);
	}

	static function set(b:Buf, i:Int) {
		b.u8(0x21);
		Enc.uleb(b, i);
	}

	static function i32(b:Buf, v:Int) {
		b.u8(0x41);
		Enc.sleb(b, v);
	}

	// the array's length (local 0)
	static function len(m:GcModule, b:Buf) {
		get(b, 0);
		m.castTo(b, m.arrBaseType);
		m.gc(b, 0x02, m.arrBaseType, 0);
	}

	// the array's storage (local 0)
	static function data(m:GcModule, b:Buf, k:String) {
		get(b, 0);
		m.castTo(b, m.arrType(k));
		m.gc(b, 0x02, m.arrType(k), 1);
	}

	public static function arrGet(m:GcModule, k:String):Int {
		var name = "arr_get_" + k;
		var h = m.hasHelper(name);
		if (h != null) return h;
		var b = new Buf();
		get(b, 1);
		len(m, b);
		b.u8(0x49); // i32.lt_u: also false for negative indices
		b.u8(0x04);
		b.u8(valByte(k));
		data(m, b, k);
		get(b, 1);
		m.gc(b, 0x0B, m.dataType(k));
		b.u8(0x05);
		m.constZero(b, k == "b" ? "i" : k);
		b.u8(0x0B);
		return m.addHelper(name, "pi_" + (k == "b" ? "i" : k), b, []);
	}

	// room for n elements (local 0 the array): the storage doubled (at least 4) when short
	static function ensure(m:GcModule, k:String):Int {
		var name = "arr_ensure_" + k;
		var h = m.hasHelper(name);
		if (h != null) return h;
		var b = new Buf();
		// if capacity < n
		data(m, b, k);
		m.gc(b, 0x0F);
		get(b, 1);
		b.u8(0x49);
		b.u8(0x04);
		b.u8(0x40);
		// cap = max(n, capacity * 2, 4) in local 2
		data(m, b, k);
		m.gc(b, 0x0F);
		i32(b, 1);
		b.u8(0x74);
		set(b, 2);
		get(b, 2);
		get(b, 1);
		b.u8(0x49);
		b.u8(0x04);
		b.u8(0x40);
		get(b, 1);
		set(b, 2);
		b.u8(0x0B);
		get(b, 2);
		i32(b, 4);
		b.u8(0x49);
		b.u8(0x04);
		b.u8(0x40);
		i32(b, 4);
		set(b, 2);
		b.u8(0x0B);
		// new storage in local 3, the elements copied
		get(b, 2);
		m.gc(b, 0x07, m.dataType(k));
		set(b, 3);
		get(b, 3);
		m.castTo(b, m.dataType(k));
		i32(b, 0);
		data(m, b, k);
		i32(b, 0);
		len(m, b);
		m.gc(b, 0x11, m.dataType(k), m.dataType(k));
		get(b, 0);
		m.castTo(b, m.arrType(k));
		get(b, 3);
		b.u8(0xFB);
		b.u8(0x16); // ref.cast to the non-null storage
		Enc.sleb(b, m.dataType(k));
		m.gc(b, 0x05, m.arrType(k), 1);
		b.u8(0x0B);
		return m.addHelper(name, "pi_v", b, [Enc.I32, 0x6D]);
	}

	public static function arrSet(m:GcModule, k:String):Int {
		var name = "arr_set_" + k;
		var h = m.hasHelper(name);
		if (h != null) return h;
		var e = ensure(m, k);
		var b = new Buf();
		// past the end: grown, the length the index + 1
		get(b, 1);
		len(m, b);
		b.u8(0x4F); // i32.ge_u
		b.u8(0x04);
		b.u8(0x40);
		get(b, 0);
		get(b, 1);
		i32(b, 1);
		b.u8(0x6A);
		b.u8(0x10);
		Enc.uleb(b, e);
		get(b, 0);
		m.castTo(b, m.arrBaseType);
		get(b, 1);
		i32(b, 1);
		b.u8(0x6A);
		m.gc(b, 0x05, m.arrBaseType, 0);
		b.u8(0x0B);
		data(m, b, k);
		get(b, 1);
		get(b, 2);
		m.gc(b, 0x0E, m.dataType(k));
		return m.addHelper(name, "pi" + (k == "b" ? "i" : k) + "_v", b, []);
	}

	public static function arrPush(m:GcModule, k:String):Int {
		var name = "arr_push_" + k;
		var h = m.hasHelper(name);
		if (h != null) return h;
		var e = ensure(m, k);
		var b = new Buf();
		get(b, 0);
		len(m, b);
		i32(b, 1);
		b.u8(0x6A);
		b.u8(0x10);
		Enc.uleb(b, e);
		data(m, b, k);
		len(m, b);
		get(b, 1);
		m.gc(b, 0x0E, m.dataType(k));
		get(b, 0);
		m.castTo(b, m.arrBaseType);
		len(m, b);
		i32(b, 1);
		b.u8(0x6A);
		m.gc(b, 0x05, m.arrBaseType, 0);
		return m.addHelper(name, "p" + (k == "b" ? "i" : k) + "_v", b, []);
	}

	// Dynamic to a scalar: null gives 0; an Int read as a Float converts, and back
	public static function unbox(m:GcModule, k:String):Int {
		var name = "unbox_" + k;
		var h = m.hasHelper(name);
		if (h != null) return h;
		var r = k == "b" ? "i" : k;
		var b = new Buf();
		var tries = switch k {
			case "i": [TI32, TF64, TBool];
			case "f": [TF64, TI32];
			case "b": [TBool, TI32];
			case _: [TI64, TI32];
		};
		for (t in tries) {
			get(b, 0);
			b.u8(0xFB);
			b.u8(0x14);
			Enc.sleb(b, m.dynType(t));
			b.u8(0x04);
			b.u8(0x40);
			get(b, 0);
			m.castTo(b, m.dynType(t));
			m.gc(b, 0x02, m.dynType(t), 0);
			// convert to the representation asked for
			switch [k, t] {
				case ["i", TF64]: b.u8(0xFC); b.u8(2);
				case ["f", TI32]: b.u8(0xB7);
				case ["l", TI32]: b.u8(0xAC);
				case _:
			}
			b.u8(0x0F);
			b.u8(0x0B);
		}
		m.constZero(b, r);
		return m.addHelper(name, "p_" + r, b, []);
	}

	// x - y * trunc(x / y)
	public static function fmod(m:GcModule):Int {
		var h = m.hasHelper("fmod");
		if (h != null) return h;
		var b = new Buf();
		get(b, 0);
		get(b, 0);
		get(b, 1);
		b.u8(0xA3);
		b.u8(0x9D);
		get(b, 1);
		b.u8(0xA2);
		b.u8(0xA1);
		return m.addHelper("fmod", "ff_f", b, []);
	}

	// whether an object's class implements the interface
	public static function implementsOf(m:GcModule, iface:ClassInfo):Int {
		var name = "implements_" + iface.ident;
		var h = m.hasHelper(name);
		if (h != null) return h;
		var b = new Buf();
		get(b, 0);
		b.u8(0xFB);
		b.u8(0x14);
		Enc.sleb(b, m.objType);
		b.u8(0x04);
		b.u8(0x40);
		get(b, 0);
		m.castTo(b, m.objType);
		m.gc(b, 0x02, m.objType, 0);
		set(b, 1);
		for (c in m.classList())
			if (c.ifaces.indexOf(iface) >= 0) {
				get(b, 1);
				i32(b, m.clsOf(c));
				b.u8(0x46);
				b.u8(0x04);
				b.u8(0x40);
				i32(b, 1);
				b.u8(0x0F);
				b.u8(0x0B);
			}
		b.u8(0x0B);
		i32(b, 0);
		return m.addHelper(name, "p_i", b, [Enc.I32]);
	}

	// the kind of a Dynamic value (hxmc.rt.gc.W.kind): 0 null, 1 Int, 2 Float,
	// 3 Bool, 4 String, 5 class instance, 6 enum, 7 array, 8 function, 9 Int64,
	// 10 anonymous structure, 11 other
	public static function kind(m:GcModule):Int {
		var h = m.hasHelper("kind");
		if (h != null) return h;
		var b = new Buf();
		get(b, 0);
		b.u8(0xD1);
		b.u8(0x04);
		b.u8(0x40);
		i32(b, 0);
		b.u8(0x0F);
		b.u8(0x0B);
		var tests = [
			{t: m.dynType(TI32), k: 1},
			{t: m.dynType(TF64), k: 2},
			{t: m.dynType(TBool), k: 3},
			{t: m.stringType, k: 4},
			{t: m.objType, k: 5},
			{t: m.enumType, k: 6},
			{t: m.arrBaseType, k: 7},
			{t: m.funBaseType, k: 8},
			{t: m.dynType(TI64), k: 9},
			{t: m.anonBaseType, k: 10}
		];
		for (x in tests) {
			if (x.t < 0) continue;
			get(b, 0);
			b.u8(0xFB);
			b.u8(0x14);
			Enc.sleb(b, x.t);
			b.u8(0x04);
			b.u8(0x40);
			i32(b, x.k);
			b.u8(0x0F);
			b.u8(0x0B);
		}
		i32(b, 11);
		return m.addHelper("kind", "p_i", b, []);
	}
}
