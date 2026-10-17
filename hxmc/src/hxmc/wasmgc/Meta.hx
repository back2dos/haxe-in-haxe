package hxmc.wasmgc;

import hxmc.Buf;
import hxmc.ir.Ir;
import hxmc.wasm.Enc;

// Reflection for the runtime (hxmc.rt.gc.GcNative, through W): tables made
// by _start before anything runs (class types by class index, field names by
// class and by anonymous structure, enum types, constructor names), and the
// functions that read and write a field by its index, make an empty
// instance, an enum value, read an enum value's arguments.
class Meta {
	final m:GcModule;
	public var clsTypes(default, null) = -1;
	public var clsFields(default, null) = -1;
	public var enumTypes(default, null) = -1;
	public var enumNames(default, null) = -1;
	public var shapeNames(default, null) = -1;

	public function new(m:GcModule)
		this.m = m;

	// ---- the tables (mutable globals, set by _start)

	function table():Int
		return m.mutableGlobal();

	public function need() {
		if (clsTypes >= 0) return;
		clsTypes = table();
		clsFields = table();
		enumTypes = table();
		enumNames = table();
		shapeNames = table();
	}

	// _start's code that fills them
	public function fill(b:Buf) {
		if (clsTypes < 0) return;
		var pt = m.dataType("p");
		inline function setGlobal(g:Int) {
			b.u8(0x24);
			Enc.uleb(b, g);
		}
		// a Haxe Array<String> of the names
		function names(ns:Array<String>) {
			b.u8(0x41);
			Enc.sleb(b, ns.length);
			for (n in ns) {
				b.u8(0x23);
				Enc.uleb(b, m.strLit(n));
			}
			m.gc(b, 0x08, pt, ns.length);
			m.gc(b, 0x00, m.arrType("p"));
		}
		var cls = m.classList();
		for (c in cls) {
			b.u8(0x23);
			Enc.uleb(b, m.typeValue(TRClass(c)));
		}
		m.gc(b, 0x08, pt, cls.length);
		setGlobal(clsTypes);
		for (c in cls)
			names([for (f in c.fields) f.name]);
		m.gc(b, 0x08, pt, cls.length);
		setGlobal(clsFields);
		var es = m.enumList();
		for (e in es) {
			b.u8(0x23);
			Enc.uleb(b, m.typeValue(TREnum(e)));
		}
		m.gc(b, 0x08, pt, es.length);
		setGlobal(enumTypes);
		for (e in es)
			names([for (c in e.ctors) c.name]);
		m.gc(b, 0x08, pt, es.length);
		setGlobal(enumNames);
		var ss = m.shapeList();
		for (s in ss)
			names([for (f in s.fields) f.name]);
		m.gc(b, 0x08, pt, ss.length);
		setGlobal(shapeNames);
	}

	// ---- encodings

	static function get(b:Buf, i:Int) {
		b.u8(0x20);
		Enc.uleb(b, i);
	}

	static function i32(b:Buf, v:Int) {
		b.u8(0x41);
		Enc.sleb(b, v);
	}

	function test(b:Buf, t:Int) {
		b.u8(0xFB);
		b.u8(0x14);
		Enc.sleb(b, t);
	}

	function box(b:Buf, t:Ty)
		switch t {
			case TI32: m.gc(b, 0x00, m.dynType(TI32));
			case TBool: m.gc(b, 0x00, m.dynType(TBool));
			case TF64: m.gc(b, 0x00, m.dynType(TF64));
			case TI64: m.gc(b, 0x00, m.dynType(TI64));
			case _:
		}

	function unbox(b:Buf, t:Ty)
		if (GcModule.repr(t) != "p") {
			b.u8(0x10);
			Enc.uleb(b, Helpers.unbox(m, t == TBool ? "b" : GcModule.repr(t)));
		}

	// the class index of local 0 (an object)
	function clsOf(b:Buf) {
		get(b, 0);
		m.castTo(b, m.objType);
		m.gc(b, 0x02, m.objType, 0);
	}

	static function storable(t:Ty):Bool
		return !t.match(TStruct(_));

	// a table, as the array it is
	function tableGet(b:Buf, g:Int) {
		b.u8(0x23);
		Enc.uleb(b, g);
		m.castTo(b, m.dataType("p"));
	}

	// ---- the functions

	function helper(name:String, key:String, locals:Array<Int>, body:Buf->Void):Int {
		var h = m.hasHelper(name);
		if (h != null) return h;
		need();
		var b = new Buf();
		var i = m.addHelper(name, key, b, locals);
		body(b);
		return i;
	}

	// the class of an object (its type value), null for anything else
	public function classOf():Int
		return helper("meta_class_of", "p_p", [], b -> {
			get(b, 0);
			test(b, m.objType);
			b.u8(0x04);
			b.u8(0x6D);
			tableGet(b, clsTypes);
			clsOf(b);
			m.gc(b, 0x0B, m.dataType("p"));
			b.u8(0x05);
			m.constZero(b, "p");
			b.u8(0x0B);
		});

	// the index of an anonymous structure's layout, -1 when not one
	public function shapeIndex():Int
		return helper("meta_shape_index", "p_i", [], b -> {
			var ss = m.shapeList();
			for (i in 0...ss.length) {
				get(b, 0);
				test(b, m.shapeType(ss[i]));
				b.u8(0x04);
				b.u8(0x40);
				i32(b, i);
				b.u8(0x0F);
				b.u8(0x0B);
			}
			i32(b, -1);
		});

	// the names of an object's fields (class or anonymous structure; null otherwise), by index
	public function fieldNames():Int {
		var si = shapeIndex();
		return helper("meta_field_names", "p_p", [Enc.I32], b -> {
			get(b, 0);
			test(b, m.objType);
			b.u8(0x04);
			b.u8(0x40);
			tableGet(b, clsFields);
			clsOf(b);
			m.gc(b, 0x0B, m.dataType("p"));
			b.u8(0x0F);
			b.u8(0x0B);
			get(b, 0);
			b.u8(0x10);
			Enc.uleb(b, si);
			b.u8(0x22);
			b.u8(1);
			i32(b, 0);
			b.u8(0x4E);
			b.u8(0x04);
			b.u8(0x40);
			tableGet(b, shapeNames);
			get(b, 1);
			m.gc(b, 0x0B, m.dataType("p"));
			b.u8(0x0F);
			b.u8(0x0B);
			m.constZero(b, "p");
		});
	}

	// o's field i (of fieldNames), boxed
	public function objGet():Int
		return helper("meta_obj_get", "pi_p", [Enc.I32], b -> {
			get(b, 0);
			test(b, m.objType);
			b.u8(0x04);
			b.u8(0x40);
			clsOf(b);
			b.u8(0x21);
			b.u8(2);
			for (c in m.classList()) {
				get(b, 2);
				i32(b, m.clsOf(c));
				b.u8(0x46);
				b.u8(0x04);
				b.u8(0x40);
				for (j in 0...c.fields.length) {
					if (!storable(c.fields[j].ty)) continue;
					get(b, 1);
					i32(b, j);
					b.u8(0x46);
					b.u8(0x04);
					b.u8(0x40);
					get(b, 0);
					m.castTo(b, m.classType(c));
					m.gc(b, 0x02, m.classType(c), j + 1);
					box(b, c.fields[j].ty);
					b.u8(0x0F);
					b.u8(0x0B);
				}
				b.u8(0x0B);
			}
			b.u8(0x0B);
			for (s in m.shapeList()) {
				get(b, 0);
				test(b, m.shapeType(s));
				b.u8(0x04);
				b.u8(0x40);
				for (j in 0...s.fields.length) {
					if (!storable(s.fields[j].ty)) continue;
					get(b, 1);
					i32(b, j);
					b.u8(0x46);
					b.u8(0x04);
					b.u8(0x40);
					get(b, 0);
					m.castTo(b, m.shapeType(s));
					m.gc(b, 0x02, m.shapeType(s), j + 1);
					box(b, s.fields[j].ty);
					b.u8(0x0F);
					b.u8(0x0B);
				}
				b.u8(0x0B);
			}
			m.constZero(b, "p");
		});

	// o's field i = v (unboxed)
	public function objSet():Int
		return helper("meta_obj_set", "pip_v", [Enc.I32], b -> {
			get(b, 0);
			test(b, m.objType);
			b.u8(0x04);
			b.u8(0x40);
			clsOf(b);
			b.u8(0x21);
			b.u8(3);
			for (c in m.classList()) {
				get(b, 3);
				i32(b, m.clsOf(c));
				b.u8(0x46);
				b.u8(0x04);
				b.u8(0x40);
				for (j in 0...c.fields.length) {
					if (!storable(c.fields[j].ty)) continue;
					get(b, 1);
					i32(b, j);
					b.u8(0x46);
					b.u8(0x04);
					b.u8(0x40);
					get(b, 0);
					m.castTo(b, m.classType(c));
					get(b, 2);
					unbox(b, c.fields[j].ty);
					m.gc(b, 0x05, m.classType(c), j + 1);
					b.u8(0x0F);
					b.u8(0x0B);
				}
				b.u8(0x0B);
			}
			b.u8(0x0B);
			for (s in m.shapeList()) {
				get(b, 0);
				test(b, m.shapeType(s));
				b.u8(0x04);
				b.u8(0x40);
				for (j in 0...s.fields.length) {
					if (!storable(s.fields[j].ty)) continue;
					get(b, 1);
					i32(b, j);
					b.u8(0x46);
					b.u8(0x04);
					b.u8(0x40);
					get(b, 0);
					m.castTo(b, m.shapeType(s));
					get(b, 2);
					unbox(b, s.fields[j].ty);
					m.gc(b, 0x05, m.shapeType(s), j + 1);
					b.u8(0x0F);
					b.u8(0x0B);
				}
				b.u8(0x0B);
			}
		});

	// a type value's field (0 kind, 1 id, 2 name)
	public function typeField(b:Buf, f:Int) {
		m.castTo(b, m.typeType());
		m.gc(b, 0x02, m.typeType(), f);
	}

	// an instance of the class (a type value) with its fields zero, no constructor run
	public function createEmpty():Int
		return helper("meta_create_empty", "p_p", [Enc.I32], b -> {
			get(b, 0);
			typeField(b, 1);
			b.u8(0x21);
			b.u8(1);
			for (c in m.classList()) {
				get(b, 1);
				i32(b, c.id);
				b.u8(0x46);
				b.u8(0x04);
				b.u8(0x40);
				i32(b, m.clsOf(c));
				for (f in c.fields)
					m.constZero(b, GcModule.repr(f.ty));
				m.gc(b, 0x00, m.classType(c));
				b.u8(0x0F);
				b.u8(0x0B);
			}
			m.constZero(b, "p");
		});

	// the enum of an enum value (its type value), null for anything else
	public function enumOf():Int
		return helper("meta_enum_of", "p_p", [], b -> {
			for (e in m.enumList()) {
				get(b, 0);
				test(b, m.enumTypeOf(e));
				b.u8(0x04);
				b.u8(0x40);
				b.u8(0x23);
				Enc.uleb(b, m.typeValue(TREnum(e)));
				b.u8(0x0F);
				b.u8(0x0B);
			}
			m.constZero(b, "p");
		});

	// the names of an enum's constructors (a type value)
	public function enumNamesOf():Int
		return helper("meta_enum_names", "p_p", [], b -> {
			tableGet(b, enumNames);
			get(b, 0);
			typeField(b, 1);
			m.gc(b, 0x0B, m.dataType("p"));
		});

	// an enum value's arguments, boxed, in an Array<Dynamic>
	public function enumParams():Int
		return helper("meta_enum_params", "p_p", [], b -> {
			for (e in m.enumList())
				for (c in e.ctors) {
					if (c.params.length == 0) continue;
					get(b, 0);
					test(b, m.ctorType(c));
					b.u8(0x04);
					b.u8(0x40);
					i32(b, c.params.length);
					for (k in 0...c.params.length) {
						get(b, 0);
						m.castTo(b, m.ctorType(c));
						m.gc(b, 0x02, m.ctorType(c), k + 1);
						box(b, c.params[k]);
					}
					m.gc(b, 0x08, m.dataType("p"), c.params.length);
					m.gc(b, 0x00, m.arrType("p"));
					b.u8(0x0F);
					b.u8(0x0B);
				}
			i32(b, 0);
			i32(b, 0);
			m.gc(b, 0x07, m.dataType("p"));
			m.gc(b, 0x00, m.arrType("p"));
		});

	// the enum's (a type value) constructor `index` with the arguments (an Array<Dynamic>, unboxed)
	public function enumCreate():Int
		return helper("meta_enum_create", "pip_p", [Enc.I32], b -> {
			get(b, 0);
			typeField(b, 1);
			b.u8(0x21);
			b.u8(3);
			var es = m.enumList();
			var arrGet = Helpers.arrGetDyn(m);
			for (ei in 0...es.length) {
				var e = es[ei];
				get(b, 3);
				i32(b, ei);
				b.u8(0x46);
				b.u8(0x04);
				b.u8(0x40);
				for (c in e.ctors) {
					get(b, 1);
					i32(b, c.tag);
					b.u8(0x46);
					b.u8(0x04);
					b.u8(0x40);
					i32(b, c.tag);
					if (c.params.length == 0) m.gc(b, 0x00, m.enumTypeOf(e)) else {
						for (k in 0...c.params.length) {
							get(b, 2);
							i32(b, k);
							b.u8(0x10);
							Enc.uleb(b, arrGet);
							unbox(b, c.params[k]);
						}
						m.gc(b, 0x00, m.ctorType(c));
					}
					b.u8(0x0F);
					b.u8(0x0B);
				}
				b.u8(0x0B);
			}
			m.constZero(b, "p");
		});

	// the class types, then the enum types: the type at index i (null past the end)
	public function typeAt():Int
		return helper("meta_type_at", "i_p", [], b -> {
			var nc = m.classList().length, ne = m.enumList().length;
			get(b, 0);
			i32(b, nc);
			b.u8(0x48);
			b.u8(0x04);
			b.u8(0x40);
			tableGet(b, clsTypes);
			get(b, 0);
			m.gc(b, 0x0B, m.dataType("p"));
			b.u8(0x0F);
			b.u8(0x0B);
			get(b, 0);
			i32(b, nc + ne);
			b.u8(0x48);
			b.u8(0x04);
			b.u8(0x40);
			tableGet(b, enumTypes);
			get(b, 0);
			i32(b, nc);
			b.u8(0x6B);
			m.gc(b, 0x0B, m.dataType("p"));
			b.u8(0x0F);
			b.u8(0x0B);
			m.constZero(b, "p");
		});
}
