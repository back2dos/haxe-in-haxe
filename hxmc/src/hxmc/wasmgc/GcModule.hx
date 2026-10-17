package hxmc.wasmgc;

import hxmc.Buf;
import hxmc.ir.Ir;
import hxmc.wasm.Enc;
import hxmc.wasmgc.GcGen.Reach;

// A WasmGC module from the reached part of the IR (GcGen). Every Haxe
// reference is an eqref (locals, parameters, fields, globals), cast to its
// concrete type where it is used: the IR's unchecked casts and coercions
// between references are nothing here. All types are in one recursion
// group, so that two of the same structure stay distinct (a String is not
// another array of i16) and the class hierarchy is the subtyping one:
//   $Obj (root class): struct {cls: i32, its fields...}, each class a subtype
//     with its own fields after its superclass's; virtual and interface calls
//     go through a funcref table indexed by class x selector (call_indirect)
//   $String: array (mut i16), UTF-16
//   $ArrBase {len}, $Arr_k {len, data: $Data_k} (k: i32, i64, f64, eqref)
//   $Enum {tag}, a constructor with arguments a subtype {tag, args...}
//   $Clos_s {fn: (ref $Fn_s)}, a closure a subtype with its captures; $Fn_s
//     takes the closure first
//   $Box_k {v} (a captured local), $Dyn_k {v} (a scalar in Dynamic), $Shape_n
// Exceptions are the legacy try/catch instructions with one tag carrying the
// value (node 22 runs them without flags).
class GcModule {
	final prog:Program;
	public final reach:Reach;

	// ---- types
	final types:Array<Buf> = []; // each subtype's encoding, in index order
	final funcTypes = new Map<String, Int>();
	var tObj = -1;
	var tString = -1;
	var tBytes = -1; // haxe.io.Bytes: array (mut i8)
	var tArrBase = -1;
	final tData = new Map<String, Int>(); // by kind
	final tArr = new Map<String, Int>();
	var tEnum = -1;
	var tFunBase = -1; // every closure's supertype
	var tAnonBase = -1; // every anonymous structure's: {overflow}
	final tDyn = new Map<String, Int>(); // i, f, l, b
	final tBox = new Map<String, Int>(); // i, f, l, p
	final tClass = new Map<ClassInfo, Int>();
	final tCtor = new Map<CtorInfo, Int>();
	final tEnumOf = new Map<EnumInfo, Int>(); // each enum's type, under $Enum: its constructors' supertype
	final tClos = new Map<String, Int>(); // by SigInfo key
	final tFn = new Map<String, Int>();
	final tLambda = new Map<LambdaInfo, Int>();
	final tShape = new Map<ShapeInfo, Int>();

	// ---- functions
	final imports:Array<{mod:String, name:String, type:Int}> = [];
	final importIndex = new Map<String, Int>();
	final funcIndex = new Map<FuncInfo, Int>();
	final funcs:Array<FuncInfo> = [];
	final helpers:Array<{name:String, type:Int, body:Buf, locals:Array<Int>}> = [];
	final helperIndex = new Map<String, Int>();
	final declared = new Map<Int, Bool>(); // functions taken by ref.func
	final exports:Array<{name:String, func:Int}> = [];

	// ---- dispatch
	final clsIndex = new Map<ClassInfo, Int>();
	final clsList:Array<ClassInfo> = [];
	final selIndex = new Map<Int, Int>();
	var nsel = 0;

	// ---- globals: the program's, then the string literals
	final globals:Array<{type:Buf, init:Buf, mut:Bool}> = [];
	final progGlobal = new Map<Int, Int>();
	final strGlobal = new Map<String, Int>();

	public final meta:Meta;

	public function new(prog:Program, reach:Reach) {
		this.prog = prog;
		this.reach = reach;
		meta = new Meta(this);
	}

	// a mutable eqref global, null at first (set by _start: Meta's tables)
	public function mutableGlobal():Int {
		var tb = new Buf();
		valType(tb, "p");
		var ib = new Buf();
		constZero(ib, "p");
		ib.u8(0x0B);
		globals.push({type: tb, init: ib, mut: true});
		return globals.length - 1;
	}

	public function typeType():Int {
		if (tType < 0) tType = structType([{r: "i", mut: false}, {r: "i", mut: false}, {r: "p", mut: false}], -1, false);
		return tType;
	}

	// ======== value types

	static inline var EQREF = 0x6D;

	public static function repr(t:Ty):String
		return switch t {
			case TI32 | TBool: "i";
			case TF64: "f";
			case TI64: "l";
			case TVoid: "v";
			case TRef(_): "p";
			case TStruct(n, _): throw 'hxmc: -D hxmc.wasm-gc: struct values ($n) are not supported';
		}

	static function valType(b:Buf, r:String)
		switch r {
			case "i": b.u8(Enc.I32);
			case "f": b.u8(Enc.F64);
			case "l": b.u8(Enc.I64);
			case "p": b.u8(EQREF);
			case _: throw "valType " + r;
		}

	function refType(b:Buf, t:Int, nullable = true) {
		b.u8(nullable ? 0x63 : 0x64);
		Enc.sleb(b, t);
	}

	// ======== the type section

	function newType():Int {
		types.push(new Buf());
		return types.length - 1;
	}

	// a struct type (sup: its supertype or -1; final unless open)
	function structType(fields:Array<{r:String, mut:Bool}>, sup:Int, open:Bool, ?fieldTypes:Array<Buf->Void>):Int {
		var t = newType();
		var b = types[t];
		b.u8(open ? 0x50 : 0x4F);
		if (sup >= 0) superOf.set(t, sup);
		if (sup >= 0) {
			b.u8(1);
			Enc.uleb(b, sup);
		} else b.u8(0);
		b.u8(0x5F);
		Enc.uleb(b, fields.length);
		for (i in 0...fields.length) {
			var f = fields[i];
			if (fieldTypes != null && fieldTypes[i] != null) fieldTypes[i](b) else valType(b, f.r);
			b.u8(f.mut ? 1 : 0);
		}
		return t;
	}

	function arrayType(elem:Buf->Void):Int {
		var t = newType();
		var b = types[t];
		b.u8(0x4F);
		b.u8(0);
		b.u8(0x5E);
		elem(b);
		b.u8(1);
		return t;
	}

	// a function type by its representation ("pi_f": eqref, i32 -> f64)
	function funcType(key:String):Int {
		var t = funcTypes.get(key);
		if (t != null) return t;
		t = newType();
		var b = types[t];
		b.u8(0x4F);
		b.u8(0);
		b.u8(0x60);
		var parts = key.split("_");
		Enc.uleb(b, parts[0].length);
		for (i in 0...parts[0].length)
			valType(b, parts[0].charAt(i));
		if (parts[1] == "v") b.u8(0) else {
			b.u8(1);
			valType(b, parts[1]);
		}
		funcTypes.set(key, t);
		return t;
	}

	// a function type by tokens: "i", "f", "l", "p" or "t<type>" (ref null type); "v" no result
	function funcTypeTokens(params:Array<String>, ret:String):Int {
		var key = params.join(",") + ">" + ret;
		var t = funcTypes.get(key);
		if (t != null) return t;
		t = newType();
		var b = types[t];
		b.u8(0x4F);
		b.u8(0);
		b.u8(0x60);
		function tok(x:String)
			if (x.charAt(0) == "t") refType(b, Std.parseInt(x.substr(1))) else valType(b, x);
		Enc.uleb(b, params.length);
		for (p in params)
			tok(p);
		if (ret == "v") b.u8(0) else {
			b.u8(1);
			tok(ret);
		}
		funcTypes.set(key, t);
		return t;
	}

	// a type the IR's type proves (a class's, an array's, an enum's, a closure's),
	// else the representation (as FuncGen's locals)
	public function keyOf(t:Ty):String
		return switch t {
			case TRef(RObj(c)) if (!c.isInterface): "t" + classType(c);
			case TRef(RStr): "t" + tString;
			case TRef(RArr(_)): "t" + tArrBase;
			case TRef(REnum(e)): "t" + (e == null ? tEnum : tEnumOf.get(e));
			case TRef(RClos(s)): "t" + closType(s);
			case TRef(RNative("haxe_io_Bytes")): "t" + tBytes;
			case _: repr(t);
		}

	// not a closure's body or an export: its signature is its own, its parameters
	// (a method's this: its class) and result typed (keyOf); the dispatch table
	// and structural calls reach a method through a wrapper of the table's
	// signature (tableFunc)
	public function precise(f:FuncInfo):Bool
		return f.lambda == null && f.cSymbol == null;

	public function paramKey(f:FuncInfo, i:Int):String
		return !precise(f) ? repr(f.args[i].ty) : i == 0 && f.selfClass != null ? "t" + classType(f.selfClass) : keyOf(f.args[i].ty);

	public function retKey(f:FuncInfo):String
		return precise(f) ? keyOf(f.ret) : repr(f.ret);

	// the function of f with the table's signature (by representation): f, or its wrapper
	public function tableFunc(f:FuncInfo):Int {
		var fi = funcOf(f);
		if (!precise(f)) return fi;
		var name = "table:" + fi;
		var h = hasHelper(name);
		if (h != null) return h;
		var b = new Buf();
		for (i in 0...f.args.length) {
			b.u8(0x20);
			Enc.uleb(b, i);
			var k = paramKey(f, i);
			if (k.charAt(0) == "t") castTo(b, Std.parseInt(k.substr(1)));
		}
		b.u8(0x10);
		Enc.uleb(b, fi);
		return addHelper(name, funcKey(f), b, []);
	}

	public static function sigKey(args:Array<Ty>, ret:Ty):String
		return [for (a in args) repr(a)].join("") + "_" + repr(ret);

	static function funcKey(f:FuncInfo):String
		return sigKey([for (a in f.args) a.ty], f.ret);

	function buildTypes() {
		tString = arrayType(b -> b.u8(0x77));
		tBytes = arrayType(b -> b.u8(0x78));
		tArrBase = structType([{r: "i", mut: true}], -1, true);
		// (Bool arrays apart from Int ones: the runtime prints them as Bools)
		for (k in ["i", "f", "l", "p", "b"]) {
			var d = arrayType(b -> valType(b, k == "b" ? "i" : k));
			tData.set(k, d);
			tArr.set(k, structType([{r: "i", mut: true}, {r: "p", mut: true}], tArrBase, false, [null, b -> refType(b, d, false)]));
		}
		// {tag, enum}: the enum's index (prog.enums) makes getEnum a table read
		tEnum = structType([{r: "i", mut: false}, {r: "i", mut: false}], -1, true);
		tFunBase = structType([], -1, true);
		// {added fields (GcFields), layout index}
		tAnonBase = structType([{r: "p", mut: true}, {r: "i", mut: false}], -1, true);
		for (k in ["i", "f", "l", "b"])
			tDyn.set(k, structType([{r: k == "b" ? "i" : k, mut: false}], -1, false));
		for (k in ["i", "f", "l", "p"])
			tBox.set(k, structType([{r: k, mut: true}], -1, false));
		// (before the classes: their fields may be of these types)
		for (e in prog.enums) {
			var te = structType([{r: "i", mut: false}, {r: "i", mut: false}], tEnum, Lambda.exists(e.ctors, c -> c.params.length > 0));
			tEnumOf.set(e, te);
			for (c in e.ctors)
				if (c.params.length > 0)
					tCtor.set(c, structType([{r: "i", mut: false}, {r: "i", mut: false}].concat([for (p in c.params) {r: repr(p), mut: false}]), te, false));
		}
		// classes in preorder: a superclass before its subclasses
		var cs = [for (c in reach.classes.keys()) c];
		cs.sort((a, b) -> a.id - b.id);
		for (c in cs) {
			classType(c);
			clsIndex.set(c, clsList.length);
			clsList.push(c);
			if (c.sup == null) tObj = tClass.get(c);
		}
		for (l in reach.lambdas.keys())
			lambdaType(l);
		for (s in prog.shapes)
			tShape.set(s, structType([{r: "p", mut: true}, {r: "i", mut: false}].concat([for (f in s.fields) {r: repr(f.ty), mut: true}]), tAnonBase, false));
	}

	function closType(s:SigInfo):Int {
		var t = tClos.get(s.key);
		if (t != null) return t;
		var fk = "p" + [for (a in s.args) repr(a)].join("") + "_" + repr(s.ret);
		var ft = funcType(fk);
		tFn.set(s.key, ft);
		t = structType([{r: "p", mut: false}], tFunBase, true, [b -> refType(b, ft, false)]);
		tClos.set(s.key, t);
		return t;
	}

	function lambdaType(l:LambdaInfo):Int {
		var t = tLambda.get(l);
		if (t != null) return t;
		var base = closType(l.sig);
		var ft = tFn.get(l.sig.key);
		var fields = [{r: "p", mut: false}].concat([for (c in l.captures) {r: repr(c.ty), mut: false}]);
		var ftys:Array<Buf->Void> = [b -> refType(b, ft, false)];
		t = structType(fields, base, false, ftys);
		tLambda.set(l, t);
		return t;
	}

	// ======== building

	public function build():haxe.io.Bytes {
		buildTypes();
		// imports first: their indices come before the module's functions
		importFunc("hxmc", "write", "ip_v");
		importFunc("hxmc", "now", "_f");
		importFunc("hxmc", "fmt", "f_p");
		importFunc("hxmc", "parseFloat", "p_f");
		importFunc("hxmc", "math", "iff_f");
		importFunc("hxmc", "random", "_f");
		importFunc("hxmc", "sysStr", "ipp_p");
		importFunc("hxmc", "sysNum", "ippf_f");
		importFunc("hxmc", "readFile", "p_p");
		importFunc("hxmc", "writeFile", "ppi_i");
		importFunc("hxmc", "dateNum", "ifiiiiii_f");
		var tagType = funcType("p_v");
		for (f in reach.funcs) {
			funcIndex.set(f, imports.length + funcs.length);
			funcs.push(f);
			typeOfFunc(f);
		}
		// the program's globals
		for (i in 0...prog.globals.length) {
			var g = prog.globals[i];
			var r = repr(g.ty);
			var tb = new Buf();
			valType(tb, r);
			var ib = new Buf();
			if (g.init != null && g.init.params.length == 0) {
				// an enum singleton: its constructor's tag
				ib.u8(0x41);
				Enc.sleb(ib, g.init.tag);
				ib.u8(0x41);
				Enc.sleb(ib, enumId(g.init.en));
				gc(ib, 0x00, tEnumOf.get(g.init.en));
			} else constZero(ib, r);
			ib.u8(0x0B);
			progGlobal.set(i, globals.length);
			globals.push({type: tb, init: ib, mut: true});
		}
		// selectors
		for (s in reach.sels.keys()) {
			selIndex.set(s, nsel++);
		}
		var trace = Sys.getEnv("HXMC_GC_TRACE") == "1";
		var codes = [
			for (f in funcs) {
				if (trace) Sys.println("wasm-gc: " + f.name);
				new FuncGen(this, f).emit();
			}
		];
		if (dynCallBody != null) writeDynCall();
		// (the table's wrappers, before the module is written)
		for (c in clsList)
			for (s in reach.sels.keys()) {
				var f = c.findMethod(prog.selectors[s].name);
				if (f != null && funcIndex.exists(f)) tableFunc(f);
			}
		// the start: Meta's tables, the initializers, then main
		var start = new Buf();
		var startIdx = addHelper("_start", "_v", start, []);
		exports.push({name: "_start", func: startIdx});
		strHelpers();
		var run = new Buf();
		meta.fill(run);
		for (f in prog.inits)
			if (funcIndex.exists(f)) {
				run.u8(0x10);
				Enc.uleb(run, funcIndex.get(f));
			}
		run.u8(0x10);
		Enc.uleb(run, funcIndex.get(prog.main));
		// (the long literals first: made when every one is known)
		lateStrings(start);
		start.buf(run);
		return write(tagType, codes);
	}

	function importFunc(mod:String, name:String, key:String) {
		importIndex.set(mod + "." + name, imports.length);
		imports.push({mod: mod, name: name, type: funcType(key)});
	}

	public function importOf(name:String):Int
		return importIndex.get(name);

	// a function written here (its body without the final end), after the program's;
	// its locals' types (a value type's byte, or -1 - t: a (ref null t))
	public function addHelper(name:String, key:String, body:Buf, locals:Array<Int>):Int {
		var i = helperIndex.get(name);
		if (i != null) return i;
		i = imports.length + funcs.length + helpers.length;
		helpers.push({name: name, type: funcType(key), body: body, locals: locals});
		helperIndex.set(name, i);
		return i;
	}

	public function hasHelper(name:String):Null<Int>
		return helperIndex.get(name);

	// what JavaScript reads a string with
	function strHelpers() {
		var len = new Buf();
		len.u8(0x20);
		len.u8(0);
		castTo(len, tString);
		gc(len, 0x0F);
		exports.push({name: "hxmc_str_len", func: addHelper("hxmc_str_len", "p_i", len, [])});
		var get = new Buf();
		get.u8(0x20);
		get.u8(0);
		castTo(get, tString);
		get.u8(0x20);
		get.u8(1);
		gc(get, 0x0D, tString);
		exports.push({name: "hxmc_str_get", func: addHelper("hxmc_str_get", "pi_i", get, [])});
		var nw = new Buf();
		nw.u8(0x20);
		nw.u8(0);
		gc(nw, 0x07, tString);
		exports.push({name: "hxmc_str_new", func: addHelper("hxmc_str_new", "i_p", nw, [])});
		var st = new Buf();
		st.u8(0x20);
		st.u8(0);
		castTo(st, tString);
		st.u8(0x20);
		st.u8(1);
		st.u8(0x20);
		st.u8(2);
		gc(st, 0x0E, tString);
		exports.push({name: "hxmc_str_set", func: addHelper("hxmc_str_set", "pii_v", st, [])});
		// and its bytes
		var bn = new Buf();
		bn.u8(0x20);
		bn.u8(0);
		gc(bn, 0x07, tBytes);
		exports.push({name: "hxmc_bytes_new", func: addHelper("hxmc_bytes_new", "i_p", bn, [])});
		var bl = new Buf();
		bl.u8(0x20);
		bl.u8(0);
		castTo(bl, tBytes);
		gc(bl, 0x0F);
		exports.push({name: "hxmc_bytes_len", func: addHelper("hxmc_bytes_len", "p_i", bl, [])});
		var bg = new Buf();
		bg.u8(0x20);
		bg.u8(0);
		castTo(bg, tBytes);
		bg.u8(0x20);
		bg.u8(1);
		gc(bg, 0x0D, tBytes);
		exports.push({name: "hxmc_bytes_get", func: addHelper("hxmc_bytes_get", "pi_i", bg, [])});
		var bs = new Buf();
		bs.u8(0x20);
		bs.u8(0);
		castTo(bs, tBytes);
		bs.u8(0x20);
		bs.u8(1);
		bs.u8(0x20);
		bs.u8(2);
		gc(bs, 0x0E, tBytes);
		exports.push({name: "hxmc_bytes_set", func: addHelper("hxmc_bytes_set", "pii_v", bs, [])});
	}

	// ======== shared encodings

	public function gc(b:Buf, op:Int, ?a:Int, ?c:Int) {
		b.u8(0xFB);
		Enc.uleb(b, op);
		if (a != null) Enc.uleb(b, a);
		if (c != null) Enc.uleb(b, c);
	}

	// ref.cast to (ref null t)
	public function castTo(b:Buf, t:Int) {
		b.u8(0xFB);
		b.u8(0x17);
		Enc.sleb(b, t);
	}

	public function constZero(b:Buf, r:String)
		switch r {
			case "i":
				b.u8(0x41);
				b.u8(0);
			case "l":
				b.u8(0x42);
				b.u8(0);
			case "f":
				b.u8(0x44);
				for (_ in 0...8)
					b.u8(0);
			case "p":
				// (none: the bottom, null of every reference type)
				b.u8(0xD0);
				b.u8(0x71);
			case _:
		}

	// ======== what FuncGen asks

	// the runtime's function exported under the symbol (@:hxmc.export), which Reach added
	public function exportOf(sym:String):Int {
		for (f in funcs)
			if (f.cSymbol == sym) return funcIndex.get(f);
		throw 'hxmc: -D hxmc.wasm-gc: the runtime has no $sym';
	}

	public function reached(f:FuncInfo):Bool
		return funcIndex.exists(f);

	public function funcOf(f:FuncInfo):Int {
		var i = funcIndex.get(f);
		if (i == null) throw 'hxmc: -D hxmc.wasm-gc: ${f.name} was not reached';
		return i;
	}

	public function typeOfFunc(f:FuncInfo):Int
		return precise(f) ? funcTypeTokens([for (i in 0...f.args.length) paramKey(f, i)], retKey(f)) : funcType(funcKey(f));

	// the classes some class extends (the others' types are final: a cast to one compares the type alone)
	var extended:Null<Map<ClassInfo, Bool>>;

	// a class's type, made when first asked for (after its superclass's; its index
	// taken before its fields are written: they may name classes that name it)
	public function classType(c:ClassInfo):Int {
		if (extended == null) {
			extended = new Map();
			for (k in prog.classes)
				if (k.sup != null) extended.set(k.sup, true);
		}
		var t = tClass.get(c);
		if (t != null) return t;
		var sup = c.sup == null ? -1 : classType(c.sup);
		t = tClass.get(c);
		if (t != null) return t;
		t = newType();
		tClass.set(c, t);
		if (sup >= 0) superOf.set(t, sup);
		var b = types[t];
		b.u8(extended.exists(c) ? 0x50 : 0x4F);
		if (sup >= 0) {
			b.u8(1);
			Enc.uleb(b, sup);
		} else b.u8(0);
		b.u8(0x5F);
		Enc.uleb(b, c.fields.length + 1);
		valType(b, "i");
		b.u8(0);
		for (f in c.fields) {
			var k = keyOf(f.ty);
			if (k.charAt(0) == "t") refType(b, Std.parseInt(k.substr(1))) else valType(b, repr(f.ty));
			b.u8(1);
		}
		return t;
	}

	// a class field's type (its key, as keyOf)
	public function fieldKey(c:ClassInfo, idx:Int):String
		return keyOf(c.fields[idx].ty);

	// whether type a is t or a subtype (by the declared supertypes)
	final superOf = new Map<Int, Int>();

	public function isSubtype(a:Int, t:Int):Bool {
		var k:Null<Int> = a;
		while (k != null) {
			if (k == t) return true;
			k = superOf.get(k);
		}
		return false;
	}

	public function classReached(c:ClassInfo):Bool
		return tClass.exists(c);

	public function clsOf(c:ClassInfo):Int
		return clsIndex.get(c);

	public function ctorType(c:CtorInfo):Int
		return tCtor.get(c);

	// an enum's index (prog.enums: its type value's id)
	public function enumId(e:EnumInfo):Int
		return prog.enums.indexOf(e);

	public function shapeId(s:ShapeInfo):Int
		return prog.shapes.indexOf(s);

	public function enumTypeOf(e:EnumInfo):Int
		return tEnumOf.get(e);

	public function enumList():Array<EnumInfo>
		return prog.enums;

	public function shapeList():Array<ShapeInfo>
		return prog.shapes;

	public var enumType(get, never):Int;

	function get_enumType()
		return tEnum;

	public var stringType(get, never):Int;

	function get_stringType()
		return tString;

	public var bytesType(get, never):Int;

	function get_bytesType()
		return tBytes;

	public var objType(get, never):Int;

	function get_objType()
		return tObj;

	public var arrBaseType(get, never):Int;

	function get_arrBaseType()
		return tArrBase;

	// hx_dyn_call(f, args): f called with the arguments of the array, unboxed
	// as its signature takes them, its result boxed (null for Void); written
	// once every closure type is known
	var dynCallBody:Null<Buf> = null;

	public function dynCall():Int {
		if (dynCallBody == null) {
			dynCallBody = new Buf();
			addHelper("dyn_call", "pp_p", dynCallBody, []);
		}
		return helperIndex.get("dyn_call");
	}

	function writeDynCall() {
		var b = dynCallBody;
		var get = Helpers.arrGet(this, "p");
		var keys = [for (k in tClos.keys()) k];
		keys.sort(Reflect.compare);
		for (key in keys) {
			var s = sigOfKey(key);
			b.u8(0x20);
			b.u8(0);
			b.u8(0xFB);
			b.u8(0x14);
			Enc.sleb(b, tClos.get(key));
			b.u8(0x04);
			b.u8(0x40);
			b.u8(0x20);
			b.u8(0);
			for (i in 0...s.args.length) {
				b.u8(0x20);
				b.u8(1);
				b.u8(0x41);
				Enc.sleb(b, i);
				b.u8(0x10);
				Enc.uleb(b, get);
				var r = repr(s.args[i]);
				if (r != "p") {
					b.u8(0x10);
					Enc.uleb(b, Helpers.unbox(this, s.args[i] == TBool ? "b" : r));
				}
			}
			b.u8(0x20);
			b.u8(0);
			castTo(b, tClos.get(key));
			gc(b, 0x02, tClos.get(key), 0);
			b.u8(0x14);
			Enc.uleb(b, tFn.get(key));
			switch repr(s.ret) {
				case "v":
					constZero(b, "p");
				case "p":
				case _:
					box(b, s.ret);
			}
			b.u8(0x0F);
			b.u8(0x0B);
		}
		b.u8(0x00);
	}

	public function sigOfKey(key:String):SigInfo {
		for (s in prog.sigs)
			if (s.key == key) return s;
		throw "no signature " + key;
	}

	public function typeOfSig(s:SigInfo):Int
		return funcType(sigKey(s.args, s.ret));

	public var funBaseType(get, never):Int;

	function get_funBaseType()
		return tFunBase;

	public var anonBaseType(get, never):Int;

	function get_anonBaseType()
		return tAnonBase;

	public function classList():Array<ClassInfo>
		return clsList;

	public function arrType(k:String):Int
		return tArr.get(k);

	public function dataType(k:String):Int
		return tData.get(k);

	// an array's element kind in the IR: b for Bool, else its representation
	public static function elemKind(t:Ty):String
		return t == TBool ? "b" : repr(t);

	// the scalar of type t on the stack boxed as Dynamic (Ints: Helpers.boxInt)
	public function box(b:Buf, t:Ty)
		switch t {
			case TI32:
				b.u8(0x10);
				Enc.uleb(b, Helpers.boxInt(this));
			case TBool | TF64 | TI64: gc(b, 0x00, dynType(t));
			case _:
		}

	// a global of the type and constant initializer
	public function newGlobal(type:Buf, init:Buf, mut:Bool):Int {
		globals.push({type: type, init: init, mut: mut});
		return globals.length - 1;
	}

	public function dynType(t:Ty):Int
		return tDyn.get(t == TBool ? "b" : repr(t));

	public function boxType(t:Ty):Int
		return tBox.get(repr(t));

	public function closTypeOf(s:SigInfo):Int
		return closType(s);

	public function fnTypeOf(s:SigInfo):Int {
		closType(s);
		return tFn.get(s.key);
	}

	public function lambdaTypeOf(l:LambdaInfo):Int
		return lambdaType(l);

	public function shapeType(s:ShapeInfo):Int
		return tShape.get(s);

	public function declare(f:Int)
		declared.set(f, true);

	public function globalOf(g:Int):Int
		return progGlobal.get(g);

	public function selOf(sel:Int):Int
		return selIndex.get(sel);

	public var selCount(get, never):Int;

	function get_selCount()
		return nsel;

	public var tableType(get, never):Int;

	function get_tableType()
		return 0;

	// a runtime type (Class<T>, Enum<T>): an immutable global {kind, id, name}
	// (kind 0 a class, 1 an enum, 2 a builtin)
	var tType = -1;
	final typeGlobal = new Map<String, Int>();

	public function typeValue(tr:TypeRef):Int {
		var kind = 0, id = 0, name = "";
		switch tr {
			case TRClass(c):
				id = c.id;
				name = c.name;
			case TREnum(e):
				kind = 1;
				id = prog.enums.indexOf(e);
				name = e.name;
			case TRBuiltin(n):
				kind = 2;
				name = n;
		}
		var key = kind + ":" + name;
		var g = typeGlobal.get(key);
		if (g != null) return g;
		typeType();
		var s = strLit(name, true);
		var tb = new Buf();
		refType(tb, tType, false);
		var ib = new Buf();
		ib.u8(0x41);
		Enc.sleb(ib, kind);
		ib.u8(0x41);
		Enc.sleb(ib, id);
		ib.u8(0x23);
		Enc.uleb(ib, s);
		gc(ib, 0x00, tType);
		ib.u8(0x0B);
		g = globals.length;
		globals.push({type: tb, init: ib, mut: false});
		typeGlobal.set(key, g);
		return g;
	}

	// a string literal: a global made by array.new_fixed (immutable: constant,
	// for other globals' initializers), or when long one _start makes from a
	// data segment (lateStrings: 1 byte a character for Latin-1, else 2)
	public function strLit(s:String, constant = false):Int {
		var g = strGlobal.get(s);
		if (g != null && (!constant || !lateStr.exists(g))) return g;
		if (!constant && s.length >= LATE_STR) {
			var tb = new Buf();
			refType(tb, tString);
			var ib = new Buf();
			constZero(ib, "p");
			ib.u8(0x0B);
			g = globals.length;
			globals.push({type: tb, init: ib, mut: true});
			strGlobal.set(s, g);
			lateStr.set(g, s);
			lateOrder.push(g);
			return g;
		}
		var tb = new Buf();
		refType(tb, tString, false);
		var ib = new Buf();
		var n = 0;
		for (i in 0...s.length) {
			ib.u8(0x41);
			Enc.sleb(ib, StringTools.fastCodeAt(s, i));
			n++;
		}
		gc(ib, 0x08, tString, n);
		ib.u8(0x0B);
		g = globals.length;
		globals.push({type: tb, init: ib, mut: false});
		strGlobal.set(s, g);
		return g;
	}

	static inline var LATE_STR = 24;
	final lateStr = new Map<Int, String>();
	final lateOrder:Array<Int> = [];
	final dataSegs:Array<haxe.io.Bytes> = [];

	// _start's code that makes the long literals (strLit) from their data segments
	function lateStrings(b:Buf) {
		var latin1 = -1;
		for (g in lateOrder) {
			var s = lateStr.get(g);
			var narrow = true;
			for (i in 0...s.length)
				if (StringTools.fastCodeAt(s, i) > 255) narrow = false;
			var d = haxe.io.Bytes.alloc(narrow ? s.length : 2 * s.length);
			for (i in 0...s.length)
				if (narrow) d.set(i, StringTools.fastCodeAt(s, i)) else d.setUInt16(2 * i, StringTools.fastCodeAt(s, i));
			b.u8(0x41);
			b.u8(0);
			b.u8(0x41);
			Enc.sleb(b, s.length);
			gc(b, 0x09, narrow ? tBytes : tString, dataSegs.length);
			dataSegs.push(d);
			if (narrow) {
				if (latin1 < 0) latin1 = latin1Helper();
				b.u8(0x10);
				Enc.uleb(b, latin1);
				castTo(b, tString);
			}
			b.u8(0x24);
			Enc.uleb(b, g);
		}
	}

	// a string of the bytes (Latin-1)
	function latin1Helper():Int {
		var b = new Buf();
		// (local 1: the string, local 2: the index)
		b.u8(0x20);
		b.u8(0);
		castTo(b, tBytes);
		gc(b, 0x0F);
		gc(b, 0x07, tString);
		b.u8(0x21);
		b.u8(1);
		b.u8(0x02);
		b.u8(0x40);
		b.u8(0x03);
		b.u8(0x40);
		b.u8(0x20);
		b.u8(2);
		b.u8(0x20);
		b.u8(1);
		gc(b, 0x0F);
		b.u8(0x4E);
		b.u8(0x0D);
		b.u8(1);
		b.u8(0x20);
		b.u8(1);
		b.u8(0x20);
		b.u8(2);
		b.u8(0x20);
		b.u8(0);
		castTo(b, tBytes);
		b.u8(0x20);
		b.u8(2);
		gc(b, 0x0D, tBytes);
		gc(b, 0x0E, tString);
		b.u8(0x20);
		b.u8(2);
		b.u8(0x41);
		b.u8(1);
		b.u8(0x6A);
		b.u8(0x21);
		b.u8(2);
		b.u8(0x0C);
		b.u8(0);
		b.u8(0x0B);
		b.u8(0x0B);
		b.u8(0x20);
		b.u8(1);
		return addHelper("str_latin1", "p_p", b, [-1 - tString, Enc.I32]);
	}

	// the reached selectors in the order of their table columns
	function sortedSels():Array<Int> {
		var a = [for (s in reach.sels.keys()) s];
		a.sort((x, y) -> selIndex.get(x) - selIndex.get(y));
		return a;
	}

	// ======== the binary

	function write(tagType:Int, codes:Array<Buf>):haxe.io.Bytes {
		var out = new Buf();
		out.u32(0x6D736100);
		out.u32(1);
		function section(id:Int, body:Buf) {
			out.u8(id);
			Enc.sized(out, body);
		}
		// types: one recursion group
		var ts = new Buf();
		ts.u8(1);
		ts.u8(0x4E);
		Enc.uleb(ts, types.length);
		for (t in types)
			ts.buf(t);
		section(1, ts);
		// imports
		var is = new Buf();
		Enc.uleb(is, imports.length);
		for (im in imports) {
			Enc.name(is, im.mod);
			Enc.name(is, im.name);
			is.u8(0);
			Enc.uleb(is, im.type);
		}
		section(2, is);
		// functions
		var fs = new Buf();
		Enc.uleb(fs, funcs.length + helpers.length);
		for (f in funcs)
			Enc.uleb(fs, typeOfFunc(f));
		for (h in helpers)
			Enc.uleb(fs, h.type);
		section(3, fs);
		// the dispatch table
		var ncls = clsList.length;
		var size = ncls * nsel;
		var tb = new Buf();
		tb.u8(1);
		tb.u8(0x70);
		tb.u8(0);
		Enc.uleb(tb, size);
		section(4, tb);
		// the exception tag
		var tg = new Buf();
		tg.u8(1);
		tg.u8(0);
		Enc.uleb(tg, tagType);
		section(13, tg);
		// globals
		var gs = new Buf();
		Enc.uleb(gs, globals.length);
		for (g in globals) {
			gs.buf(g.type);
			gs.u8(g.mut ? 1 : 0);
			gs.buf(g.init);
		}
		section(6, gs);
		// exports
		var es = new Buf();
		Enc.uleb(es, exports.length);
		for (e in exports) {
			Enc.name(es, e.name);
			es.u8(0);
			Enc.uleb(es, e.func);
		}
		section(7, es);
		// elements: the dispatch table, then the functions taken by ref.func
		var el = new Buf();
		var segs = 0;
		var seg = new Buf();
		if (size > 0) {
			segs++;
			seg.u8(4);
			seg.u8(0x41);
			seg.u8(0);
			seg.u8(0x0B);
			Enc.uleb(seg, size);
			for (c in clsList)
				for (s in sortedSels()) {
					var m = c.findMethod(prog.selectors[s].name);
					if (m != null && funcIndex.exists(m)) {
						seg.u8(0xD2);
						Enc.uleb(seg, tableFunc(m));
					} else {
						seg.u8(0xD0);
						seg.u8(0x70);
					}
					seg.u8(0x0B);
				}
		}
		var decl = [for (k in declared.keys()) k];
		if (decl.length > 0) {
			segs++;
			decl.sort((a, b) -> a - b);
			seg.u8(3);
			seg.u8(0);
			Enc.uleb(seg, decl.length);
			for (d in decl)
				Enc.uleb(seg, d);
		}
		Enc.uleb(el, segs);
		el.buf(seg);
		section(9, el);
		if (dataSegs.length > 0) {
			var dc = new Buf();
			Enc.uleb(dc, dataSegs.length);
			section(12, dc);
		}
		// code
		var cs = new Buf();
		Enc.uleb(cs, codes.length + helpers.length);
		for (c in codes)
			Enc.sized(cs, c);
		for (h in helpers) {
			var body = new Buf();
			Enc.uleb(body, h.locals.length);
			for (l in h.locals) {
				body.u8(1);
				if (l >= 0) body.u8(l) else {
					body.u8(0x63);
					Enc.sleb(body, -l - 1);
				}
			}
			body.buf(h.body);
			body.u8(0x0B);
			Enc.sized(cs, body);
		}
		section(10, cs);
		// the long literals' characters (passive segments)
		if (dataSegs.length > 0) {
			var ds = new Buf();
			Enc.uleb(ds, dataSegs.length);
			for (d in dataSegs) {
				ds.u8(1);
				Enc.uleb(ds, d.length);
				ds.bytes(d);
			}
			section(11, ds);
		}
		// the functions' names (stack traces, profiles)
		var names = new Buf();
		Enc.name(names, "name");
		var fn = new Buf();
		Enc.uleb(fn, imports.length + funcs.length + helpers.length);
		for (i in 0...imports.length) {
			Enc.uleb(fn, i);
			Enc.name(fn, imports[i].mod + "." + imports[i].name);
		}
		for (i in 0...funcs.length) {
			Enc.uleb(fn, imports.length + i);
			Enc.name(fn, funcs[i].display != null ? funcs[i].display : funcs[i].name);
		}
		for (i in 0...helpers.length) {
			Enc.uleb(fn, imports.length + funcs.length + i);
			Enc.name(fn, "hxmc." + helpers[i].name);
		}
		names.u8(1);
		Enc.sized(names, fn);
		section(0, names);
		return out.toBytes();
	}
}

