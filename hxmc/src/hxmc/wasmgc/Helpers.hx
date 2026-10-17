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

	// (an array of another kind than the code expects, as map's: through the
	// boxed path, unboxed or boxed for this kind)
	static function otherKind(m:GcModule, b:Buf, k:String) {
		get(b, 0);
		b.u8(0xFB);
		b.u8(0x14);
		Enc.sleb(b, m.arrType(k));
		b.u8(0x45);
		b.u8(0x04);
		b.u8(0x40);
	}

	public static function arrGet(m:GcModule, k:String):Int {
		var name = "arr_get_" + k;
		var h = m.hasHelper(name);
		if (h != null) return h;
		var b = new Buf();
		var idx = m.addHelper(name, "pi_" + (k == "b" ? "i" : k), b, []);
		otherKind(m, b, k);
		get(b, 0);
		get(b, 1);
		b.u8(0x10);
		Enc.uleb(b, arrGetDyn(m));
		if (k != "p") {
			b.u8(0x10);
			Enc.uleb(b, unbox(m, k));
		}
		b.u8(0x0F);
		b.u8(0x0B);
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
		return idx;
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
		var idx = m.addHelper(name, "pi" + (k == "b" ? "i" : k) + "_v", b, []);
		otherKind(m, b, k);
		get(b, 0);
		get(b, 1);
		get(b, 2);
		box(m, b, k);
		b.u8(0x10);
		Enc.uleb(b, arrSetDyn(m));
		b.u8(0x0F);
		b.u8(0x0B);
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
		return idx;
	}

	public static function arrPush(m:GcModule, k:String):Int {
		var name = "arr_push_" + k;
		var h = m.hasHelper(name);
		if (h != null) return h;
		var e = ensure(m, k);
		var b = new Buf();
		var idx = m.addHelper(name, "p" + (k == "b" ? "i" : k) + "_v", b, []);
		otherKind(m, b, k);
		get(b, 0);
		len(m, b);
		get(b, 1);
		box(m, b, k);
		b.u8(0x10);
		Enc.uleb(b, arrSetDyn(m));
		b.u8(0x0F);
		b.u8(0x0B);
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
		return idx;
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

	// obj.name(args) on a class instance (ECallAnon): its class's method of that
	// name, called directly; else the field through the runtime (a closure)
	public static function anonCall(m:GcModule, name:String, s:SigInfo):Int {
		var key = "anon_call_" + name + "_" + s.key;
		var h = m.hasHelper(key);
		if (h != null) return h;
		var params = "p" + [for (a in s.args) GcModule.repr(a)].join("");
		var b = new Buf();
		var idx = m.addHelper(key, params + "_" + GcModule.repr(s.ret), b, [Enc.I32]);
		get(b, 0);
		m.castTo(b, m.objType);
		m.gc(b, 0x02, m.objType, 0);
		set(b, s.args.length + 1);
		for (c in m.classList()) {
			var f = c.findMethod(name);
			if (f == null || !m.reached(f)) continue;
			// (the method's representation must be the call's)
			if (GcModule.sigKey([for (a in f.args) a.ty], f.ret) != params + "_" + GcModule.repr(s.ret)) continue;
			get(b, s.args.length + 1);
			i32(b, m.clsOf(c));
			b.u8(0x46);
			b.u8(0x04);
			b.u8(0x40);
			for (i in 0...s.args.length + 1)
				get(b, i);
			b.u8(0x10);
			Enc.uleb(b, m.funcOf(f));
			b.u8(0x0F);
			b.u8(0x0B);
		}
		// (no such method: the field, a closure)
		get(b, 0);
		b.u8(0x23);
		Enc.uleb(b, m.strLit(name));
		b.u8(0x10);
		Enc.uleb(b, m.exportOf("gc_anon_get"));
		b.u8(0x41);
		Enc.sleb(b, s.args.length);
		for (i in 0...s.args.length) {
			get(b, i + 1);
			if (GcModule.repr(s.args[i]) != "p") m.gc(b, 0x00, m.dynType(s.args[i]));
		}
		m.gc(b, 0x08, m.dataType("p"), s.args.length);
		m.gc(b, 0x00, m.arrType("p"));
		b.u8(0x10);
		Enc.uleb(b, m.dynCall());
		var r = GcModule.repr(s.ret);
		if (r == "v") b.u8(0x1A) else if (r != "p") {
			b.u8(0x10);
			Enc.uleb(b, unbox(m, s.ret == TBool ? "b" : r));
		}
		return idx;
	}

	// two references of enum arguments equal: the same, else both enums
	// (enumEq), else as Dynamic (dynEq)
	public static function refEq3(m:GcModule, enumEq:Int, dynEq:Int):Int {
		var h = m.hasHelper("ref_eq3");
		if (h != null) return h;
		var b = new Buf();
		get(b, 0);
		get(b, 1);
		b.u8(0xD3);
		b.u8(0x04);
		b.u8(0x40);
		i32(b, 1);
		b.u8(0x0F);
		b.u8(0x0B);
		get(b, 0);
		b.u8(0xFB);
		b.u8(0x14);
		Enc.sleb(b, m.enumType);
		get(b, 1);
		b.u8(0xFB);
		b.u8(0x14);
		Enc.sleb(b, m.enumType);
		b.u8(0x71);
		b.u8(0x04);
		b.u8(0x40);
		get(b, 0);
		get(b, 1);
		b.u8(0x10);
		Enc.uleb(b, enumEq);
		b.u8(0x0F);
		b.u8(0x0B);
		get(b, 0);
		get(b, 1);
		b.u8(0x10);
		Enc.uleb(b, dynEq);
		return m.addHelper("ref_eq3", "pp_i", b, []);
	}

	// the kind of a Dynamic value (hxmc.rt.gc.W.kind): 0 null, 1 Int, 2 Float,
	// 3 Bool, 4 String, 5 class instance, 6 enum, 7 array, 8 function, 9 Int64,
	// 10 anonymous structure, 11 other, 12 a type value (Class, Enum)
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
			{t: m.anonBaseType, k: 10},
			{t: m.typeType(), k: 12}
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

	static final KINDS = ["i", "f", "l", "p", "b"];

	// the box of a value of kind k on the stack (p: itself)
	static function box(m:GcModule, b:Buf, k:String)
		switch k {
			case "i": m.gc(b, 0x00, m.dynType(TI32));
			case "f": m.gc(b, 0x00, m.dynType(TF64));
			case "l": m.gc(b, 0x00, m.dynType(TI64));
			case "b": m.gc(b, 0x00, m.dynType(TBool));
			case _:
		}

	// if local 0 is an array of kind k (then ... end)
	static function ifKind(m:GcModule, b:Buf, k:String, result = 0x40) {
		get(b, 0);
		b.u8(0xFB);
		b.u8(0x14);
		Enc.sleb(b, m.arrType(k));
		b.u8(0x04);
		b.u8(result);
	}

	// an array's kind: 0 Int, 1 Float, 2 Int64, 3 references, 4 Bool; -1 not an array
	public static function arrKind(m:GcModule):Int {
		var h = m.hasHelper("arr_kind");
		if (h != null) return h;
		var b = new Buf();
		for (i in 0...KINDS.length) {
			ifKind(m, b, KINDS[i]);
			i32(b, i);
			b.u8(0x0F);
			b.u8(0x0B);
		}
		i32(b, -1);
		return m.addHelper("arr_kind", "p_i", b, []);
	}

	// a[i] boxed (null out of range or not an array)
	public static function arrGetDyn(m:GcModule):Int {
		var h = m.hasHelper("arr_get_dyn");
		if (h != null) return h;
		var b = new Buf();
		var idx = m.addHelper("arr_get_dyn", "pi_p", b, []);
		for (k in KINDS) {
			var g = arrGet(m, k);
			ifKind(m, b, k);
			get(b, 0);
			get(b, 1);
			b.u8(0x10);
			Enc.uleb(b, g);
			box(m, b, k);
			b.u8(0x0F);
			b.u8(0x0B);
		}
		m.constZero(b, "p");
		return idx;
	}

	// a[i] = v (unboxed for the array's kind)
	public static function arrSetDyn(m:GcModule):Int {
		var h = m.hasHelper("arr_set_dyn");
		if (h != null) return h;
		var b = new Buf();
		var idx = m.addHelper("arr_set_dyn", "pip_v", b, []);
		for (k in KINDS) {
			var st = arrSet(m, k);
			ifKind(m, b, k);
			get(b, 0);
			get(b, 1);
			get(b, 2);
			if (k != "p") {
				b.u8(0x10);
				Enc.uleb(b, unbox(m, k));
			}
			b.u8(0x10);
			Enc.uleb(b, st);
			b.u8(0x0F);
			b.u8(0x0B);
		}
		return idx;
	}

	// a new array of the kind (arrKind's numbers) and length, its elements zero
	public static function arrNew(m:GcModule):Int {
		var h = m.hasHelper("arr_new");
		if (h != null) return h;
		var b = new Buf();
		for (i in 0...KINDS.length) {
			var k = KINDS[i];
			get(b, 0);
			i32(b, i);
			b.u8(0x46);
			b.u8(0x04);
			b.u8(0x40);
			get(b, 1);
			get(b, 1);
			m.gc(b, 0x07, m.dataType(k));
			m.gc(b, 0x00, m.arrType(k));
			b.u8(0x0F);
			b.u8(0x0B);
		}
		b.u8(0x00);
		return m.addHelper("arr_new", "ii_p", b, []);
	}

	// the array's length set to n: grown with zeros, or cut (what is cut cleared)
	public static function arrSetLen(m:GcModule):Int {
		var h = m.hasHelper("arr_set_len");
		if (h != null) return h;
		var b = new Buf();
		for (k in KINDS) {
			var e = ensure(m, k);
			ifKind(m, b, k);
			get(b, 0);
			get(b, 1);
			b.u8(0x10);
			Enc.uleb(b, e);
			// (cut: [n, length) cleared)
			get(b, 1);
			len(m, b);
			b.u8(0x48);
			b.u8(0x04);
			b.u8(0x40);
			data(m, b, k);
			get(b, 1);
			m.constZero(b, k == "b" ? "i" : k);
			len(m, b);
			get(b, 1);
			b.u8(0x6B);
			m.gc(b, 0x10, m.dataType(k));
			b.u8(0x0B);
			get(b, 0);
			m.castTo(b, m.arrBaseType);
			get(b, 1);
			m.gc(b, 0x05, m.arrBaseType, 0);
			b.u8(0x0F);
			b.u8(0x0B);
		}
		return m.addHelper("arr_set_len", "pi_v", b, []);
	}

	// dst[di...di+n] = src[si...si+n] (arrays of one kind, dst long enough)
	public static function arrBlit(m:GcModule):Int {
		var h = m.hasHelper("arr_blit");
		if (h != null) return h;
		var b = new Buf();
		for (k in KINDS) {
			ifKind(m, b, k);
			data(m, b, k);
			get(b, 1);
			get(b, 2);
			m.castTo(b, m.arrType(k));
			m.gc(b, 0x02, m.arrType(k), 1);
			get(b, 3);
			get(b, 4);
			m.gc(b, 0x11, m.dataType(k), m.dataType(k));
			b.u8(0x0F);
			b.u8(0x0B);
		}
		return m.addHelper("arr_blit", "pipii_v", b, []);
	}

	// little-endian loads and stores in a Bytes (an array of i8): n bytes at local 1
	public static function bytesGet(m:GcModule, wide:Bool):Int {
		var name = wide ? "bytes_get_i64" : "bytes_get_i32";
		var h = m.hasHelper(name);
		if (h != null) return h;
		var b = new Buf();
		var n = wide ? 8 : 4;
		for (i in 0...n) {
			get(b, 0);
			m.castTo(b, m.bytesType);
			get(b, 1);
			if (i > 0) {
				i32(b, i);
				b.u8(0x6A);
			}
			m.gc(b, 0x0D, m.bytesType);
			if (wide) b.u8(0xAD); // i64.extend_i32_u
			if (i > 0) {
				if (wide) {
					b.u8(0x42);
					Enc.sleb(b, 8 * i);
					b.u8(0x86);
					b.u8(0x84);
				} else {
					i32(b, 8 * i);
					b.u8(0x74);
					b.u8(0x72);
				}
			}
		}
		return m.addHelper(name, wide ? "pi_l" : "pi_i", b, []);
	}

	public static function bytesSet(m:GcModule, wide:Bool):Int {
		var name = wide ? "bytes_set_i64" : "bytes_set_i32";
		var h = m.hasHelper(name);
		if (h != null) return h;
		var b = new Buf();
		var n = wide ? 8 : 4;
		for (i in 0...n) {
			get(b, 0);
			m.castTo(b, m.bytesType);
			get(b, 1);
			if (i > 0) {
				i32(b, i);
				b.u8(0x6A);
			}
			get(b, 2);
			if (i > 0) {
				if (wide) {
					b.u8(0x42);
					Enc.sleb(b, 8 * i);
					b.u8(0x88);
				} else {
					i32(b, 8 * i);
					b.u8(0x76);
				}
			}
			if (wide) b.u8(0xA7);
			m.gc(b, 0x0E, m.bytesType);
		}
		return m.addHelper(name, wide ? "pil_v" : "pii_v", b, []);
	}
}
