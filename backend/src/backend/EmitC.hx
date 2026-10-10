package backend;

import backend.Ir;

// EXPERIMENTAL (bench/WASM-BACKEND.md): IR -> C against backend/rt/rt.h.
// Reference locals live across a call or allocation get shadow-stack slots
// (`fr[k]`, see Roots); everything else is a plain C local.
class EmitC {
	static inline var T_FIRST = 32;

	var p:Program;
	var b = new StringBuf();
	var fn:FuncInfo;
	var refSlot:Map<Local, Int>;
	var loops:Array<{id:Int, tries:Int}>;
	var tries:Array<String>;
	var nextLabel = 0; // per function
	var nextCache = 0; // per function: its inline caches are a static array `ic_` in the function
	var strNames = new Map<String, String>(); // literal -> S_<hash of its content>
	var strOrder:Array<String> = [];
	var strByName = new Map<String, String>();
	var hostProtos = new Map<String, String>(); // runtime functions not declared in rt.h
	var hostOrder:Array<String> = [];
	var fids = new Map<String, Int>();
	var fieldNames:Array<String> = [];
	var cnames = new Map<FuncInfo, String>();
	var usedCNames = new Map<String, Bool>();
	var byCName = new Map<String, FuncInfo>();
	var types:Array<TypeEntry> = [];
	var boundTypes = new Map<Int, Int>(); // sig -> type index of its bound-method closures

	// Function bodies refer to program-wide numbers (type indices, field ids,
	// signature ids, globals, dispatch selectors) by name: TY_*, FID_*, SIG_*,
	// GI_* (index into rt_globals), G_* (scalar globals), DSP_* (dispatch rows),
	// S_* (string literals, named by a hash of their content). Names stay the
	// same when unrelated code changes, so with chunked output (emitChunks) an
	// edit changes few C files. The numbers are defined once: `#define`s in
	// ids.h (HXC_CONST_IDS, folded into the code like literals) or const
	// globals in data.c (the default for chunks: no file but data.c depends
	// on them).
	var ids = new Map<String, Int>(); // id name -> value
	var idOrder:Array<String> = [];
	var typeNames:Array<String> = []; // type index -> C expression (program types: TY_* ids)
	var fidNames = new Map<String, String>();
	var sigNames:Array<String> = [];
	var globalNames:Array<String> = [];
	var selNames:Array<String> = [];
	var refs:Refs; // what the function being emitted refers to
	var dataRefs = new Refs(); // functions the data tables refer to
	var single = true;

	// one C file (the whole program, all functions static)
	public static function emit(p:Program):String
		return new EmitC(p).runSingle();

	// chunked output: hxc.h (program-independent), ids.h, strings.c, data.c and
	// one file per group of modules of about `chunkBytes` of C (see `pack`).
	public static function emitChunks(p:Program, chunkBytes:Int):Array<{name:String, content:String}> {
		var e = new EmitC(p);
		e.single = false;
		return e.runChunks(chunkBytes);
	}

	function new(p)
		this.p = p;

	// ---- names

	static function ident(s:String):String {
		var r = new StringBuf();
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			r.addChar((c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code) || c == "_".code ? c : "_".code);
		}
		return r.toString();
	}

	function cname(f:FuncInfo):String {
		var n = cnames.get(f);
		if (n != null) return n;
		var base = "F_" + ident(f.name);
		n = base;
		var i = 1;
		while (usedCNames.exists(n))
			n = base + "_" + i++;
		usedCNames.set(n, true);
		cnames.set(f, n);
		return n;
	}

	function fid(name:String):Int {
		var f = fids.get(name);
		if (f == null) throw "field name not collected: " + name;
		return f;
	}

	// a field id in function bodies
	function fidRef(name:String):String {
		fid(name);
		return useId(fidNames.get(name));
	}

	function useId(n:String):String {
		refs.ids.set(n, true);
		return n;
	}

	function typeRef(tindex:Int):String
		return tindex < T_FIRST ? Std.string(tindex) : useId(typeNames[tindex]);

	function sigRef(s:SigInfo):String
		return useId(sigNames[s.id]);

	function globalRef(g:Int):String {
		if (Ir.isRef(p.globals[g].ty)) return 'rt_globals[${useId(globalNames[g])}]';
		refs.globals.set(g, true);
		return "G_" + globalNames[g].substr(3);
	}

	function funcRef(f:FuncInfo):String {
		var n = cname(f);
		refs.funcs.set(n, true);
		return n;
	}

	function str(s:String):String {
		var n = strNames.get(s);
		if (n == null) {
			// the hash of the UTF-16 units (an ASCII rendering: injective)
			n = "S_" + haxe.crypto.Md5.encode([for (i in 0...s.length) StringTools.hex(s.charCodeAt(i))].join(",")).substr(0, 16);
			if (strByName.exists(n)) throw "string literal hash collision: " + n;
			strByName.set(n, s);
			strNames.set(s, n);
			strOrder.push(s);
		}
		refs.strs.set(n, true);
		return '((void *)&$n.len)';
	}

	function strDef(s:String):String {
		var units = [for (i in 0...s.length) s.charCodeAt(i)];
		var nslots = Std.int((8 + 2 * units.length + 7) / 8);
		units.push(0);
		var init = '{MKHDR($nslots, K_RAW, T_STRING), ${s.length}, 0, {${units.join(",")}}};\n';
		if (single) return 'static struct { uint64_t h; int32_t len, hash; uint16_t c[${units.length}]; } ${strNames.get(s)} = $init';
		// strings.c: a named type per length (a variable of an unnamed type would have internal linkage in C++, i.e. Emscripten)
		var n = units.length;
		var decl = strTypes.exists(n) ? "" : 'struct hx_s$n { uint64_t h; int32_t len, hash; uint16_t c[$n]; };\n';
		strTypes.set(n, true);
		return '${decl}struct hx_s$n ${strNames.get(s)} = $init';
	}

	var strTypes = new Map<Int, Bool>();

	// C names for keys: `prefix` + the key as an identifier; keys mapping to the
	// same identifier get a suffix by their sorted rank. Values become ids.
	function nameIds(prefix:String, keys:Array<String>, values:Null<Array<Int>>):Array<String> {
		var cands = [for (k in keys) prefix + ident(k)];
		var groups = new Map<String, Array<String>>();
		for (i in 0...keys.length) {
			var g = groups.get(cands[i]);
			if (g == null) groups.set(cands[i], g = []);
			g.push(keys[i]);
		}
		var names = [];
		for (i in 0...keys.length) {
			var g = groups.get(cands[i]);
			var n = cands[i];
			if (g.length > 1) {
				g.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
				n += "_" + g.indexOf(keys[i]);
			}
			names.push(n);
			if (values != null) {
				if (ids.exists(n)) throw "duplicate C name " + n;
				ids.set(n, values[i]);
				idOrder.push(n);
			}
		}
		return names;
	}

	function assignNames() {
		var keys = [], vals = [];
		for (i in T_FIRST...types.length) {
			keys.push(types[i].key);
			vals.push(i);
		}
		var tn = nameIds("TY_", keys, vals);
		typeNames = [for (i in 0...types.length) i < T_FIRST ? Std.string(i) : tn[i - T_FIRST]];
		var fn = nameIds("FID_", fieldNames, [for (i in 0...fieldNames.length) i]);
		for (i in 0...fieldNames.length)
			fidNames.set(fieldNames[i], fn[i]);
		sigNames = nameIds("SIG_", [for (s in p.sigs) s.key], [for (s in p.sigs) s.id]);
		globalNames = nameIds("GI_", [for (g in p.globals) g.name], null);
		// reference globals are slots of rt_globals (GI_*: the index); scalar ones are variables (G_*)
		for (i in 0...p.globals.length)
			if (Ir.isRef(p.globals[i].ty)) {
				if (ids.exists(globalNames[i])) throw "duplicate C name " + globalNames[i];
				ids.set(globalNames[i], i);
				idOrder.push(globalNames[i]);
			}
		selNames = nameIds("DSP_", [for (s in p.selectors) s.name], null);
	}

	// ---- types

	static function cty(t:Ty):String
		return switch t {
			case TI32 | TBool: "int32_t";
			case TF64: "double";
			case TVoid: "void";
			case TRef(_): "void *";
		}

	// C type of a pure expression (arguments of runtime calls)
	static function ctyOf(e:Ex):String
		return switch e {
			case EInt(_) | EEnumTag(_) | EArrLen(_) | ENot(_) | EInstOf(_, _): "int32_t";
			case EF64(_): "double";
			case ENull(t) | EGlobal(_, t) | EUnbox(t, _) | EAnonGet(_, t, _) | ECast(t, _) | EArrGet(t, _, _) | EBoxGet(t, _): cty(t);
			case ELocal(l): cty(l.ty);
			case EField(c, idx, _): cty(c.fields[idx].ty);
			case EEnumParam(c, idx, _): cty(c.params[idx]);
			case ECapture(l, idx, _): cty(l.captures[idx].ty);
			case EConv(I2F | FNeg, _): "double";
			case EConv(F2I, _): "int32_t";
			case EBin(FAdd | FSub | FMul | FDiv | FMod, _, _): "double";
			case EBin(_, _, _): "int32_t";
			case ECallHost(_, _, t): cty(t);
			case _: "void *";
		}

	static function kindChar(t:Ty):String
		return switch t {
			case TI32: "i";
			case TBool: "b";
			case TF64: "f";
			case _: "p";
		}

	function sigType(ret:Ty, args:Array<String>):String
		return '${cty(ret)} (*)(${args.length == 0 ? "void" : args.join(", ")})';

	function addType(t:TypeEntry):Int {
		types.push(t);
		return types.length - 1;
	}

	static function entry(name:String, tk:String, slots:Array<Null<Ty>>, key:String):TypeEntry
		return {
			key: key,
			name: name,
			tk: tk,
			sup: -1,
			slots: slots,
			fields: [],
			methods: [],
			ifaces: [],
			tag: 0,
			ctors: []
		};

	// Field layout of classes and anonymous structures: fields in order, one
	// 8-byte slot each, except that Int/Bool fields are packed two per slot
	// (the second fills the free half of the previous one). A class's fields
	// start with its superclass's, so the layout of a subclass extends the
	// superclass's. Returns per field its location (see `at`); appends the
	// physical slots (for the pointer map) to `slots`.
	static function layout(slots:Array<Null<Ty>>, tys:Array<Ty>):Array<Int> {
		var locs = [], half = -1;
		for (t in tys)
			switch t {
				case TI32 | TBool:
					if (half >= 0) {
						locs.push(2 * half + 1);
						half = -1;
					} else {
						half = slots.length;
						locs.push(2 * half);
						slots.push(TI32);
					}
				case _:
					locs.push(slots.length);
					slots.push(t);
			}
		return locs;
	}

	// the location of a value of type t in slot `slot` of an unpacked layout:
	// Int/Bool are addressed by 4-byte index (FH), the rest by slot
	static function at(slot:Int, t:Ty):Int
		return t.match(TI32 | TBool) ? 2 * slot : slot;

	function assignTypes() {
		var rtNames = ["None", "String", "Int", "Float", "Bool", "Array", "ArrayData", "ArrayData", "haxe.io.Bytes", "haxe.io.BytesBuffer", "StringBuf", "Ref", "Ref", "Ref", "Class", "Overflow", "Native", "ArrayIterator"];
		var rtSlots:Array<Array<Null<Ty>>> = [[], [], [TI32], [TF64], [TBool], [TI32, TRef(RAny)], [], [], [], [TI32, TRef(RAny)], [TI32, TRef(RAny)], [TRef(RAny)], [TI32], [TF64], [TI32], [], [], [TRef(RAny), TI32]];
		for (i in 0...T_FIRST)
			addType(entry(i < rtNames.length ? rtNames[i] : "Reserved", "TK_RUNTIME", i < rtSlots.length ? rtSlots[i] : [], "rt" + i));
		for (c in p.classes) {
			var slots:Array<Null<Ty>> = [];
			c.locs = layout(slots, [for (f in c.fields) f.ty]);
			c.nslots = slots.length;
			var t = entry(c.name, "TK_CLASS", slots, c.name);
			t.fields = [for (i in 0...c.fields.length) {name: c.fields[i].name, slot: c.locs[i], ty: c.fields[i].ty}];
			c.tindex = addType(t);
		}
		for (c in p.classes)
			types[c.tindex].sup = c.sup == null ? -1 : c.sup.tindex;
		for (c in p.interfaces)
			c.tindex = addType(entry(c.name, "TK_INTERFACE", [], c.name));
		for (c in p.classes)
			types[c.tindex].ifaces = [for (i in c.ifaces) i.tindex];
		for (e in p.enums) {
			var et = entry(e.name, "TK_ENUM", [], e.name);
			et.tag = e.ctors.length;
			e.tindex = addType(et);
			for (c in e.ctors) {
				// no tag slot: the constructor is the type index (rt.h)
				var slots:Array<Null<Ty>> = [for (pt in c.params) pt];
				var t = entry(c.name, "TK_CTOR", slots, e.name + "." + c.name);
				t.sup = e.tindex;
				t.tag = c.tag;
				t.fields = [for (i in 0...c.params.length) {name: c.paramNames[i], slot: at(i, c.params[i]), ty: c.params[i]}];
				c.tindex = addType(t);
			}
			types[e.tindex].ctors = [for (c in e.ctors) c.tindex];
		}
		for (s in p.shapes) {
			var slots:Array<Null<Ty>> = [TRef(RAny)];
			s.locs = layout(slots, [for (f in s.fields) f.ty]);
			s.nslots = slots.length;
			var t = entry("{}", "TK_ANON", slots, "anon." + haxe.crypto.Md5.encode([for (f in s.fields) f.name + ":" + Ir.repr(f.ty)].join(",")).substr(0, 16));
			t.fields = [for (i in 0...s.fields.length) {name: s.fields[i].name, slot: s.locs[i], ty: s.fields[i].ty}];
			s.tindex = addType(t);
		}
		for (l in p.lambdas) {
			var slots:Array<Null<Ty>> = [TI32];
			for (c in l.captures)
				slots.push(c.ty);
			var t = entry("<closure>", "TK_CLOSURE", slots, "clos." + cname(l.fn));
			t.sup = l.sig.id;
			l.tindex = addType(t);
		}
		// class methods for structural and dynamic access: the effective implementation of every name
		for (c in p.classes) {
			var seen = new Map<String, Bool>();
			var k = c;
			var ms = [];
			while (k != null) {
				for (name => m in k.methods)
					if (!seen.exists(name)) {
						seen.set(name, true);
						var sig = p.sig([for (i in 1...m.args.length) m.args[i].ty], m.ret);
						ms.push({name: name, fn: cname(m), sig: sig.id});
					}
				k = k.sup;
			}
			types[c.tindex].methods = ms;
		}
		// the runtime's array iterator (Iterable.iterator() on an Array): methods in rt_dyn.c
		types[17].methods = [
			{name: "hasNext", fn: "hx_arrayiter_hasNext", sig: p.sig([], TBool).id},
			{name: "next", fn: "hx_arrayiter_next", sig: p.sig([], TRef(RAny)).id}
		];
		// one bound-method closure type per signature: code, this, method
		for (s in p.sigs) {
			var t = entry("<bound>", "TK_BOUND", [TI32, TRef(RAny), TI32], "bound." + s.key);
			t.sup = s.id;
			boundTypes.set(s.id, addType(t));
		}
	}

	// ---- field names: collected from the whole program, sorted, so the runtime can search them

	function collectNames() {
		var names = new Map<String, Bool>();
		for (t in types) {
			for (f in t.fields)
				names.set(f.name, true);
			for (m in t.methods)
				names.set(m.name, true);
		}
		for (e in p.enums)
			for (c in e.ctors)
				names.set(c.name, true);
		for (c in p.classes)
			if (c.statics != null)
				for (s in c.statics)
					names.set(s.name, true);
		function ex(e:Ex) {
			switch e {
				case EAnonGet(n, _, o):
					names.set(n, true);
					ex(o);
				case ECallAnon(n, _, o, args):
					names.set(n, true);
					ex(o);
					for (a in args)
						ex(a);
				case ECallHost("hx_dyn_get" | "hx_dyn_set" | "hx_dyn_call_field", args, _) if (args[1].match(EStr(_))):
					switch args[1] {
						case EStr(n): names.set(n, true);
						case _:
					}
					for (a in args)
						ex(a);
				case _:
					iterEx(ex, e);
			}
		}
		function st(s:Stmt) {
			switch s {
				case SAnonSet(n, _, o, v):
					names.set(n, true);
					ex(o);
					ex(v);
				case _:
					iterStmt(st, ex, s);
			}
		}
		for (f in p.funcs)
			for (s in f.body)
				st(s);
		fieldNames = [for (k in names.keys()) k];
		fieldNames.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		for (i in 0...fieldNames.length)
			fids.set(fieldNames[i], i);
	}

	public static function iterEx(f:Ex->Void, e:Ex) {
		switch e {
			case EInt(_) | EF64(_) | EStr(_) | ENull(_) | ELocal(_) | EGlobal(_, _) | EType(_):
			case EBin(_, a, b):
				f(a);
				f(b);
			case ENot(a) | EConv(_, a) | EBox(_, a) | EUnbox(_, a) | EField(_, _, a) | EAnonGet(_, _, a) | ECast(_, a) | EInstOf(_, a) | EEnumTag(a, _) | EEnumParam(_, _, a) | EArrLen(a) | EBoxGet(_, a) | ECapture(_, _, a) | ENewBox(_, a):
				f(a);
			case EArrGet(_, a, i):
				f(a);
				f(i);
			case ECall(_, args) | ECallDispatch(_, _, args) | ECallHost(_, args, _) | ENewEnum(_, args) | ENewArr(_, args) | ENewClos(_, args) | ENewAnon(_, args):
				for (a in args)
					f(a);
			case ECallClos(_, c, args) | ECallAnon(_, _, c, args):
				f(c);
				for (a in args)
					f(a);
			case ENewObj(_):
		}
	}

	public static function iterStmt(fs:Stmt->Void, fe:Ex->Void, s:Stmt) {
		switch s {
			case SSet(_, e) | SExpr(e) | SThrow(e) | SSetGlobal(_, e):
				fe(e);
			case SSetField(_, _, o, v) | SAnonSet(_, _, o, v) | SBoxSet(_, o, v):
				fe(o);
				fe(v);
			case SArrSet(_, _, i, v):
				fe(i);
				fe(v);
			case SArrPush(_, _, v):
				fe(v);
			case SIf(c, a, b):
				fe(c);
				for (x in a)
					fs(x);
				for (x in b)
					fs(x);
			case SLoop(body):
				for (x in body)
					fs(x);
			case SBreak | SContinue:
			case SSwitch(e, cases, def):
				fe(e);
				for (c in cases)
					for (x in c.body)
						fs(x);
				for (x in def)
					fs(x);
			case SReturn(e):
				if (e != null) fe(e);
			case STry(body, catches):
				for (x in body)
					fs(x);
				for (c in catches) {
					if (c.test != null) fe(c.test(ELocal(c.l)));
					for (x in c.body)
						fs(x);
				}
		}
	}

	// ---- output

	// names, types, field ids; then every function body (with what it refers to)
	var bodies = new Map<FuncInfo, {text:String, refs:Refs}>();

	function prepare() {
		for (f in p.funcs)
			byCName.set(cname(f), f);
		assignTypes();
		collectNames();
		assignNames();
		var saved = b;
		for (f in p.funcs) {
			b = new StringBuf();
			refs = new Refs();
			func(f);
			bodies.set(f, {text: b.toString(), refs: refs});
		}
		b = saved;
	}

	function runSingle():String {
		prepare();
		b.add("// Generated by backend/ (EXPERIMENTAL)\n#include \"rt.h\"\n#include <stdio.h>\n#include <math.h>\n\n");
		b.add(PRELUDE);
		b.add(idsHeader());
		b.add('const char *const rt_field_names[] = {${[for (n in fieldNames) cstr(n)].join(", ")}};\nconst int rt_nfield_names = ${fieldNames.length};\n');
		for (s in strOrder)
			b.add(strDef(s));
		for (n in hostOrder)
			b.add(hostProtos.get(n) + ";\n");
		for (f in p.funcs)
			b.add(proto(f, true) + ";\n");
		b.add(data());
		for (f in p.funcs)
			b.add(proto(f, true) + " " + bodies.get(f).text);
		b.add(mainBody());
		return b.toString();
	}

	// #defines of the ids (single file, ids.h)
	function idsHeader():String {
		var r = new StringBuf();
		for (n in idOrder)
			r.add('#define $n ${ids.get(n)}\n');
		return r.toString();
	}

	// tables and globals: everything but the function bodies and main
	function data():String {
		var saved = b;
		b = new StringBuf();
		var st = single ? "static " : "";
		for (s in p.sigs)
			b.add(sigFunctions(s));
		b.add('const rt_dyncall rt_dyncalls[] = {${[for (s in p.sigs) "DYN" + s.id].join(", ")}};\n');
		b.add('const char *const rt_sig_keys[] = {${[for (s in p.sigs) cstr(s.key)].join(", ")}};\nconst int rt_nsigs = ${p.sigs.length};\n');
		b.add('void *const rt_bound_tramps[] = {${[for (s in p.sigs) "(void *)BT" + s.id].join(", ")}};\n');
		b.add('const int32_t rt_bound_types[] = {${[for (s in p.sigs) boundTypes.get(s.id)].join(", ")}};\n');
		for (i in 0...p.globals.length)
			if (!Ir.isRef(p.globals[i].ty)) b.add('$st${cty(p.globals[i].ty)} ${scalarGlobal(i)}; // ${p.globals[i].name}\n');
		emitTypes();
		var nc = p.classes.length;
		for (s in 0...p.selectors.length) {
			var row = [];
			for (c in p.classes) {
				var m = c.findMethod(p.selectors[s].name);
				row.push(m != null && m.dispatchSel == s ? "(void *)" + dataFunc(m) : "0");
			}
			b.add('${single ? "static " : "extern "}void *const ${selNames[s]}[$nc] = {${row.join(", ")}};\n');
		}
		var r = b.toString();
		b = saved;
		return r;
	}

	function scalarGlobal(g:Int):String
		return "G_" + globalNames[g].substr(3);

	function dataFunc(f:FuncInfo):String {
		var n = cname(f);
		dataRefs.funcs.set(n, true);
		return n;
	}

	function mainBody():String {
		var r = new StringBuf();
		r.add('static void hx_main_body(void) {\n');
		for (i in 0...p.globals.length) {
			var c = p.globals[i].init;
			if (c != null) r.add('\trt_globals[$i] = rt_alloc(1, ${c.tindex}, K_OBJ);\n');
		}
		for (f in p.inits)
			r.add('\t${dataFunc(f)}();\n');
		r.add('\t${dataFunc(p.main)}();\n}\n');
		r.add('int main(int argc, char **argv) {\n\trt_init(${p.globals.length}, argc, argv);\n\trt_run_main(hx_main_body);\n\treturn 0;\n}\n');
		return r.toString();
	}

	// ---- chunked output

	static final HEADER = "// Generated by backend/ (EXPERIMENTAL): shared by every C file of the program
#pragma once
#include \"rt.h\"
#include <stdio.h>
#include <math.h>
// a string literal (strings.c defines each with its exact length)
typedef struct { uint64_t h; int32_t len, hash; uint16_t c[1]; } hx_slit;
// HXC_CONST_IDS: the program's ids are #defines (ids.h), folded into the code
// like literals, and every C file depends on ids.h; else they are const
// globals defined in data.c and only data.c changes when they do
#ifdef HXC_CONST_IDS
#include \"ids.h\"
#define ID(x)
#else
#define ID(x) extern const int32_t x;
#endif
";

	function runChunks(chunkBytes:Int):Array<{name:String, content:String}> {
		prepare();
		var files = [];
		files.push({name: "hxc.h", content: HEADER + PRELUDE});
		files.push({name: "ids.h", content: "// Generated by backend/ (EXPERIMENTAL): the program's ids for HXC_CONST_IDS builds\n" + idsHeader()});
		var sb = new StringBuf();
		sb.add("// Generated by backend/ (EXPERIMENTAL): string literals\n#include \"hxc.h\"\n");
		var sorted = strOrder.copy();
		sorted.sort((x, y) -> cmp(strNames.get(x), strNames.get(y)));
		for (s in sorted)
			sb.add(strDef(s));
		files.push({name: "strings.c", content: sb.toString()});
		var dataText = data() + mainBody();
		var chunks = packChunks(chunkBytes);
		// a function stays static unless the data tables or another chunk refer to it
		var chunkOf = new Map<String, Int>();
		for (i in 0...chunks.length)
			for (f in chunks[i].funcs)
				chunkOf.set(cname(f), i);
		var exported = new Map<String, Bool>();
		for (n in dataRefs.funcs.keys())
			exported.set(n, true);
		for (i in 0...chunks.length)
			for (f in chunks[i].funcs)
				for (n in bodies.get(f).refs.funcs.keys())
					if (chunkOf.get(n) != i) exported.set(n, true);
		var d = new StringBuf();
		d.add("// Generated by backend/ (EXPERIMENTAL): tables, globals and main\n#include \"hxc.h\"\n");
		d.add('const char *const rt_field_names[] = {${[for (n in fieldNames) cstr(n)].join(", ")}};\nconst int rt_nfield_names = ${fieldNames.length};\n');
		var dn = [for (n in dataRefs.funcs.keys()) if (byCName.exists(n)) n];
		dn.sort(cmp);
		for (n in dn)
			d.add(proto(byCName.get(n), false) + ";\n");
		d.add("#ifndef HXC_CONST_IDS\n");
		for (n in idOrder)
			d.add('extern const int32_t $n = ${ids.get(n)};\n');
		d.add("#endif\n");
		d.add(dataText);
		files.push({name: "data.c", content: d.toString()});
		for (i in 0...chunks.length) {
			var c = chunks[i];
			var all = new Refs();
			for (f in c.funcs)
				all.add(bodies.get(f).refs);
			var r = new StringBuf();
			r.add('// Generated by backend/ (EXPERIMENTAL): ${c.modules.join(", ")}\n#include "hxc.h"\n');
			var xs = [for (n in all.ids.keys()) n];
			xs.sort(cmp);
			for (n in xs)
				r.add('ID($n)\n');
			var xs = [for (n in all.strs.keys()) n];
			xs.sort(cmp);
			for (n in xs)
				r.add('extern hx_slit $n;\n');
			var gs = [for (g in all.globals.keys()) g];
			gs.sort((a, b) -> cmp(scalarGlobal(a), scalarGlobal(b)));
			for (g in gs)
				r.add('extern ${cty(p.globals[g].ty)} ${scalarGlobal(g)};\n');
			var xs = [for (sel in all.dsps.keys()) selNames[sel]];
			xs.sort(cmp);
			for (n in xs)
				r.add('extern void *const $n[];\n');
			var xs = [for (n in all.hosts.keys()) n];
			xs.sort(cmp);
			for (n in xs)
				r.add(hostProtos.get(n) + ";\n");
			var xs = [for (n in all.funcs.keys()) if (chunkOf.get(n) != i) n];
			xs.sort(cmp);
			for (n in xs)
				r.add(proto(byCName.get(n), false) + ";\n");
			for (f in c.funcs)
				r.add(proto(f, !exported.exists(cname(f))) + ";\n");
			for (f in c.funcs)
				r.add(proto(f, !exported.exists(cname(f))) + " " + bodies.get(f).text);
			files.push({name: c.name + ".c", content: r.toString()});
		}
		return files;
	}

	static function cmp(a:String, b:String):Int
		return a < b ? -1 : a > b ? 1 : 0;

	// Chunks: the functions of a module (sorted by name) stay together, modules
	// in name order; a module larger than twice the target is split. A chunk
	// ends after a unit once it holds `target` bytes, at a unit whose name
	// hashes to 0 mod 4 (or past twice the target): boundaries depend on the
	// names, so when an edit moves one, the next ones realign (as
	// content-defined chunking does). A chunk's file name is its first unit's.
	function packChunks(target:Int):Array<{name:String, modules:Array<String>, funcs:Array<FuncInfo>}> {
		var byModule = new Map<String, Array<FuncInfo>>();
		for (f in p.funcs) {
			var m = f.module == null ? "_" : f.module;
			var fs = byModule.get(m);
			if (fs == null) byModule.set(m, fs = []);
			fs.push(f);
		}
		var modules = [for (m in byModule.keys()) m];
		modules.sort(cmp);
		var units:Array<Unit> = [];
		for (m in modules) {
			var fs = byModule.get(m);
			fs.sort((a, b) -> cmp(cname(a), cname(b)));
			var fus:Array<Unit> = [for (f in fs) {name: cname(f), modules: [m], funcs: [f], size: bodies.get(f).text.length}];
			var total = 0;
			for (u in fus)
				total += u.size;
			if (total <= 2 * target) units.push({name: m, modules: [m], funcs: fs, size: total});
			else {
				var parts = cut(fus, target);
				for (k in 0...parts.length)
					units.push({name: k == 0 ? m : m + "." + parts[k].name, modules: [m], funcs: parts[k].funcs, size: parts[k].size});
			}
		}
		var chunks = cut(units, target);
		var names = nameIds("m_", [for (c in chunks) c.name], null);
		return [for (i in 0...chunks.length) {name: names[i], modules: chunks[i].modules, funcs: chunks[i].funcs}];
	}

	// groups consecutive units (named by their first)
	static function cut(units:Array<Unit>, target:Int):Array<Unit> {
		var r:Array<Unit> = [];
		var cur:Unit = null;
		for (u in units) {
			if (cur == null) cur = {name: u.name, modules: [], funcs: [], size: 0};
			for (m in u.modules)
				if (cur.modules.indexOf(m) < 0) cur.modules.push(m);
			for (f in u.funcs)
				cur.funcs.push(f);
			cur.size += u.size;
			if (cur.size >= target && (cur.size >= 2 * target || (hash(u.name) & 3) == 0)) {
				r.push(cur);
				cur = null;
			}
		}
		if (cur != null) r.push(cur);
		return r;
	}

	static function hash(s:String):Int {
		var h = 5381;
		for (i in 0...s.length)
			h = ((h << 5) + h + s.charCodeAt(i)) & 0xFFFFFF;
		return h;
	}

	static function cstr(s:String):String {
		var r = new StringBuf();
		r.add('"');
		var bytes = haxe.io.Bytes.ofString(s);
		for (i in 0...bytes.length) {
			var c = bytes.get(i);
			if (c == '"'.code || c == "\\".code) {
				r.add("\\");
				r.addChar(c);
			} else if (c < 32 || c >= 127 || c == "?".code) r.add("\\" + Std.string(c >> 6) + Std.string((c >> 3) & 7) + Std.string(c & 7)) else r.addChar(c);
		}
		r.add('"');
		return r.toString();
	}

	function emitTypes() {
		var all = new StringBuf();
		var staticsOf = new Map<Int, Array<{name:String, clos:Null<LambdaInfo>, global:Int}>>();
		for (c in p.classes)
			if (c.statics != null && c.statics.length > 0) staticsOf.set(c.tindex, c.statics);
		for (i in 0...types.length) {
			var t = types[i];
			var ss = staticsOf.get(i);
			if (ss != null) {
				ss = ss.copy();
				ss.sort((a, b) -> fid(a.name) - fid(b.name));
				// closure: lambda type index + code; variable: global index (pointer globals) or address
				b.add('static const rt_static SS$i[] = {${[for (s in ss) if (s.clos != null) '{${fid(s.name)}, \'c\', ${s.clos.tindex}, (void *)${dataFunc(s.clos.fn)}}' else {
					var gt = p.globals[s.global].ty;
					Ir.isRef(gt) ? '{${fid(s.name)}, \'p\', ${s.global}, 0}' : '{${fid(s.name)}, \'${kindChar(gt)}\', -1, &${scalarGlobal(s.global)}}';
				}].join(", ")}};\n');
			}
			var n = t.slots.length;
			var words = [];
			for (w in 0...Std.int((n + 63) / 64)) {
				var lo = 0, hi = 0;
				for (j in w * 64...Std.int(Math.min(n, w * 64 + 64))) {
					var s = t.slots[j];
					if (s != null && Ir.isRef(s)) {
						var k = j - w * 64;
						if (k < 32) lo |= 1 << k else hi |= 1 << (k - 32);
					}
				}
				words.push('0x${StringTools.hex(hi, 8)}${StringTools.hex(lo, 8)}ull');
			}
			if (words.length > 0) b.add('static const uint64_t PM$i[] = {${words.join(", ")}};\n');
			var fs = t.fields.copy();
			fs.sort((a, b) -> fid(a.name) - fid(b.name));
			if (fs.length > 0) b.add('static const rt_field FS$i[] = {${[for (f in fs) '{${fid(f.name)}, ${f.slot}, \'${kindChar(f.ty)}\'}'].join(", ")}};\n');
			var ms = t.methods.copy();
			ms.sort((a, b) -> fid(a.name) - fid(b.name));
			for (m in ms)
				dataRefs.funcs.set(m.fn, true);
			if (ms.length > 0) b.add('static const rt_method MS$i[] = {${[for (m in ms) '{${fid(m.name)}, (void *)${m.fn}, ${m.sig}}'].join(", ")}};\n');
			if (t.ifaces.length > 0) b.add('static const int32_t IF$i[] = {${t.ifaces.join(", ")}};\n');
			if (t.ctors.length > 0) b.add('static const int32_t CT$i[] = {${t.ctors.join(", ")}};\n');
			all.add('{${cstr(t.name)}, ${t.tk}, ${t.sup}, $n, ${words.length > 0 ? "PM" + i : "0"}, ${fs.length}, ${fs.length > 0 ? "FS" + i : "0"}, ${ms.length}, ${ms.length > 0 ? "MS" + i : "0"}, ${t.ifaces.length}, ${t.ifaces.length > 0 ? "IF" + i : "0"}, ${t.tag}, ${t.ctors.length > 0 ? "CT" + i : "0"}, ${ss != null ? ss.length : 0}, ${ss != null ? "SS" + i : "0"}},\n');
		}
		b.add('const rt_type rt_types[] = {\n${all.toString()}};\nconst int rt_ntypes = ${types.length};\n');
		b.add('uint64_t rt_type_objs[${2 * types.length}];\n');
	}

	// per signature: DYN<s> calls a closure with boxed arguments; BT<s> is the code of bound-method closures
	function sigFunctions(s:SigInfo):String {
		var r = new StringBuf();
		var params = ["void *c"].concat([for (i in 0...s.args.length) cty(s.args[i]) + " a" + i]);
		var argNames = [for (i in 0...s.args.length) "a" + i];
		var mty = sigType(s.ret, ["void *"].concat([for (a in s.args) cty(a)]));
		r.add('static ${cty(s.ret)} BT${s.id}(${params.join(", ")}) {\n\t${s.ret == TVoid ? "" : "return "}((${mty})FP(c, 2))(${["FP(c, 1)"].concat(argNames).join(", ")});\n}\n');
		var unboxed = [for (i in 0...s.args.length) unboxFrom('args[$i]', s.args[i])];
		var call = '((${mty})CLOS_FN(c))(${["c"].concat(unboxed).join(", ")})';
		r.add('static void *DYN${s.id}(void *c, void **args) {\n');
		r.add(switch s.ret {
			case TVoid: '\t$call;\n\treturn 0;\n';
			case TI32: '\treturn hx_box_int($call);\n';
			case TBool: '\treturn hx_box_bool($call);\n';
			case TF64: '\treturn hx_box_float($call);\n';
			case TRef(_): '\treturn $call;\n';
		});
		r.add("}\n");
		return r.toString();
	}

	static function unboxFrom(x:String, t:Ty):String
		return switch t {
			case TI32: 'hx_unbox_int($x)';
			case TBool: 'hx_unbox_bool($x)';
			case TF64: 'hx_unbox_float($x)';
			case _: x;
		}

	function proto(f:FuncInfo, isStatic:Bool):String
		return '${isStatic ? "static " : ""}${cty(f.ret)} ${cname(f)}(${f.args.length == 0 ? "void" : [for (a in f.args) cty(a.ty) + " a" + a.id].join(", ")})';

	// ---- functions

	function func(f:FuncInfo) {
		fn = f;
		refSlot = new Map();
		loops = [];
		tries = [];
		var roots = Roots.analyze(f);
		var n = 0;
		for (l => slot in roots.slots) {
			refSlot.set(l, slot);
			if (slot >= n) n = slot + 1;
		}
		var outer = b;
		b = new StringBuf();
		nextLabel = 0;
		nextCache = 0;
		if (n > 0) b.add('\tvoid **fr = rt_sp;\n\trt_sp += $n;\n\tmemset(fr, 0, $n * sizeof(void *));\n');
		var vol = f.hasTry ? "volatile " : "";
		for (a in f.args)
			if (refSlot.exists(a)) b.add('\tfr[${refSlot.get(a)}] = a${a.id};\n');
			else b.add('\t$vol${cty(a.ty)} l${a.id} = a${a.id};\n');
		for (l in f.locals)
			if (!refSlot.exists(l)) b.add('\t$vol${cty(l.ty)} l${l.id} = 0;\n');
		stmts(f.body, "\t");
		if (f.ret == TVoid) b.add(n > 0 ? "\trt_sp = fr;\n" : "");
		else b.add('${n > 0 ? "\trt_sp = fr;\n" : ""}\treturn ${f.ret == TF64 ? "0.0" : "0"};\n');
		// the function's inline caches (structural access sites)
		outer.add("{\n" + (nextCache > 0 ? '\tstatic rt_icache ic_[$nextCache];\n' : "") + b.toString() + "}\n\n");
		b = outer;
	}

	function popFrame():String
		return refSlot.keys().hasNext() ? "rt_sp = fr; " : "";

	function stmts(ss:Array<Stmt>, ind:String) {
		for (s in ss)
			stmt(s, ind);
	}

	function stmt(s:Stmt, ind:String) {
		switch s {
			case SSet(l, e):
				b.add('$ind${local(l)} = ${expr(e)};\n');
			case SExpr(e):
				b.add('$ind${expr(e)};\n');
			case SSetField(c, idx, obj, v):
				b.add(ind + store(expr(obj), Std.string(c.locs[idx]), c.fields[idx].ty, expr(v)) + ";\n");
			case SBoxSet(t, bx, v):
				b.add(ind + store(expr(bx), "0", t, expr(v)) + ";\n");
			case SSetGlobal(g, v):
				b.add(ind + globalRef(g) + ' = ${expr(v)};\n');
			case SAnonSet(name, t, obj, v):
				var ic = nextCache++;
				var k = kindChar(t);
				var match = k == "b" || k == "i" ? "(c_->kind == 'i' || c_->kind == 'b')" : 'c_->kind == \'$k\'';
				b.add('$ind{\n$ind\tvoid *o_ = ${expr(obj)};\n$ind\trt_icache *c_ = rt_ic(o_, ${fidRef(name)}, &ic_[$ic]);\n');
				b.add('$ind\tif (c_->slot > 0 && $match) ${store("o_", "c_->slot - 1", t, expr(v))};\n');
				b.add('$ind\telse { void *b_ = ${box(expr(v), t)}; hx_anon_set_slow(${expr(obj)}, ${fidRef(name)}, b_); }\n$ind}\n');
			case SArrSet(elem, a, i, v):
				var slot = '&${local(a)}';
				switch elem {
					case TF64: b.add('${ind}hx_aset_f($slot, ${expr(i)}, ${expr(v)});\n');
					case TI32 | TBool: b.add('${ind}hx_aset_i($slot, ${expr(i)}, ${expr(v)});\n');
					case _: b.add('$ind{ int32_t i_ = ${expr(i)}; *rt_sp++ = ${expr(v)}; hx_aset_p($slot, i_, rt_sp - 1); rt_sp--; }\n');
				}
			case SArrPush(elem, a, v):
				var slot = '&${local(a)}';
				switch elem {
					case TF64: b.add('${ind}hx_apush_f($slot, ${expr(v)});\n');
					case TI32 | TBool: b.add('${ind}hx_apush_i($slot, ${expr(v)});\n');
					case _: b.add('$ind{ *rt_sp++ = ${expr(v)}; hx_apush_p($slot, rt_sp - 1); rt_sp--; }\n');
				}
			case SIf(c, x, y):
				b.add('${ind}if (${expr(c)}) {\n');
				stmts(x, ind + "\t");
				if (y.length > 0) {
					b.add('$ind} else {\n');
					stmts(y, ind + "\t");
				}
				b.add('$ind}\n');
			case SLoop(body):
				var id = nextLabel++;
				loops.push({id: id, tries: tries.length});
				b.add('${ind}for (;;) {\n');
				stmts(body, ind + "\t");
				b.add('$ind}\n${ind}brk$id:;\n');
				loops.pop();
			case SBreak:
				var lp = loops[loops.length - 1];
				b.add(ind + unwindTo(lp.tries) + 'goto brk${lp.id};\n');
			case SContinue:
				var lp = loops[loops.length - 1];
				b.add(ind + unwindTo(lp.tries) + "continue;\n");
			case SSwitch(e, cases, def):
				b.add('${ind}switch (${expr(e)}) {\n');
				var seen = new Map<Int, Bool>();
				for (c in cases) {
					var labels = [for (v in c.values) if (!seen.exists(v)) v];
					for (v in labels)
						seen.set(v, true);
					if (labels.length == 0) continue;
					for (v in labels)
						b.add('${ind}case ${intLit(v)}:\n');
					b.add('$ind{\n');
					stmts(c.body, ind + "\t");
					b.add('$ind\tbreak;\n$ind}\n');
				}
				b.add('${ind}default: {\n');
				stmts(def, ind + "\t");
				b.add('$ind}\n$ind}\n');
			case SReturn(null):
				b.add(ind + unwindTo(0) + popFrame() + "return;\n");
			case SReturn(e):
				b.add('$ind{ ${cty(fn.ret)} r = ${expr(e)}; ${unwindTo(0)}${popFrame()}return r; }\n');
			case SThrow(e):
				b.add('${ind}rt_throw(${expr(e)});\n');
			case STry(body, catches):
				var h = "h" + nextLabel++;
				b.add('${ind}RT_TRY($h)\n');
				tries.push(h);
				stmts(body, ind + "\t");
				tries.pop();
				b.add('${ind}RT_CATCH($h)\n');
				for (c in catches)
					b.add('$ind\t${local(c.l)} = rt_exn;\n');
				b.add('$ind\trt_exn = 0;\n');
				var first = true;
				var catchAll = false;
				for (c in catches) {
					var cond = c.test == null ? "1" : expr(c.test(ELocal(c.l)));
					b.add('$ind\t${first ? "" : "else "}if ($cond) {\n');
					stmts(c.body, ind + "\t\t");
					b.add('$ind\t}\n');
					first = false;
					if (c.test == null) {
						catchAll = true;
						break;
					}
				}
				// the catch locals are rooted (a test may allocate): rethrow from one of them
				if (!catchAll) b.add('$ind\telse rt_throw(${local(catches[0].l)});\n');
				b.add('${ind}RT_END_TRY($h)\n');
		}
	}

	// pops the exception handlers entered since `depth`
	function unwindTo(depth:Int):String
		return tries.length > depth ? 'RT_POP(${tries[depth]}) ' : "";

	function local(l:Local):String {
		var s = refSlot.get(l);
		return s != null ? 'fr[$s]' : 'l${l.id}';
	}

	static function arrKind(t:Ty):String
		return switch t {
			case TI32 | TBool: "AK_I32";
			case TF64: "AK_F64";
			case _: "AK_PTR";
		}

	static function store(o:String, idx:String, t:Ty, v:String):String {
		return switch t {
			case TRef(_): 'rt_set_ptr($o, &FP($o, $idx), $v)';
			case TF64: 'FD($o, $idx) = $v';
			case _: 'FH($o, $idx) = $v';
		}
	}

	static function load(o:String, idx:String, t:Ty):String
		return switch t {
			case TRef(_): 'FP($o, $idx)';
			case TF64: 'FD($o, $idx)';
			case _: 'FH($o, $idx)';
		}

	static function box(x:String, t:Ty):String
		return switch t {
			case TI32: 'hx_box_int($x)';
			case TBool: 'hx_box_bool($x)';
			case TF64: 'hx_box_float($x)';
			case _: x;
		}

	static function intLit(v:Int):String
		return v == -2147483648 ? "(-2147483647 - 1)" : Std.string(v);

	static function floatLit(v:Float):String {
		if (Math.isNaN(v)) return "(0.0 / 0.0)";
		if (!Math.isFinite(v)) return v > 0 ? "(1.0 / 0.0)" : "(-1.0 / 0.0)";
		var s = Std.string(v);
		if (s.indexOf(".") < 0 && s.indexOf("e") < 0) s += ".0";
		return s;
	}

	function typeIndex(t:TypeRef):Int
		return switch t {
			case TRClass(c): c.tindex;
			case TREnum(e): e.tindex;
			case TRBuiltin(n):
				switch n {
					case "String": 1;
					case "Int": 2;
					case "Float": 3;
					case "Bool": 4;
					case "Array": 5;
					case "haxe_io_Bytes": 8;
					case _: 0;
				}
		}

	// packs a value into a uint64 (slow structural calls)
	static function pack(x:String, t:Ty):String
		return switch t {
			case TF64: 'hx_d2u($x)';
			case TRef(_): '(uint64_t)(uintptr_t)($x)';
			case _: '(uint64_t)(uint32_t)($x)';
		}

	static function unpack(x:String, t:Ty):String
		return switch t {
			case TF64: 'hx_u2d($x)';
			case TRef(_): '(void *)(uintptr_t)($x)';
			case TVoid: x;
			case _: '(int32_t)($x)';
		}

	function expr(e:Ex):String {
		return switch e {
			case EInt(v): intLit(v);
			case EF64(v): floatLit(v);
			case EStr(s): str(s);
			case ENull(_): "((void *)0)";
			case ELocal(l): local(l);
			case EGlobal(g, t): globalRef(g);
			case EBin(op, x, y):
				var a = expr(x), c = expr(y);
				switch op {
					case Add: 'IADD($a, $c)';
					case Sub: 'ISUB($a, $c)';
					case Mul: 'IMUL($a, $c)';
					case Mod: 'IMOD($a, $c)';
					case And: '($a & $c)';
					case Or: '($a | $c)';
					case Xor: '($a ^ $c)';
					case Shl: 'ISHL($a, $c)';
					case Shr: 'ISHR($a, $c)';
					case UShr: 'IUSHR($a, $c)';
					case Eq | RefEq | FEq: '($a == $c)';
					case Ne | RefNe | FNe: '($a != $c)';
					case Lt | FLt: '($a < $c)';
					case Le | FLe: '($a <= $c)';
					case Gt | FGt: '($a > $c)';
					case Ge | FGe: '($a >= $c)';
					case FAdd: '($a + $c)';
					case FSub: '($a - $c)';
					case FMul: '($a * $c)';
					case FDiv: '($a / $c)';
					case FMod: 'fmod($a, $c)';
				}
			case ENot(x): '!(${expr(x)})';
			case EConv(I2F, x): '((double)(${expr(x)}))';
			case EConv(F2I, x): 'hx_f2i(${expr(x)})';
			case EConv(FNeg, x): '(-(${expr(x)}))';
			case EBox(t, x): box(expr(x), t);
			case EUnbox(t, x): unboxFrom(expr(x), t);
			case EField(c, idx, obj): load(expr(obj), Std.string(c.locs[idx]), c.fields[idx].ty);
			case EAnonGet(name, t, obj):
				var ic = nextCache++;
				var k = kindChar(t);
				var match = k == "b" || k == "i" ? "(c_->kind == 'i' || c_->kind == 'b')" : 'c_->kind == \'$k\'';
				var f = fidRef(name);
				'({ void *o_ = ${expr(obj)}; rt_icache *c_ = rt_ic(o_, $f, &ic_[$ic]); c_->slot > 0 && $match ? ${load("o_", "c_->slot - 1", t)} : ${unboxFrom('hx_anon_get_slow(o_, $f)', t)}; })';
			case ECast(_, x): expr(x);
			case EInstOf(c, x): 'hx_inst(${expr(x)}, ${typeRef(c.tindex)}, ${typeRef(c.tindex + c.lastDescendant - c.id)})';
			case EEnumTag(x, en):
				// constructors of an enum have consecutive type indices in tag order
				var base = en == null || en.ctors.length == 0 ? null : en.ctors[0].tindex - en.ctors[0].tag;
				if (base != null)
					for (c in en.ctors)
						if (c.tindex - c.tag != base) base = null;
				var c0 = en == null || en.ctors.length == 0 ? null : en.ctors[0];
				base != null ? '((int32_t)TINDEX(${expr(x)}) - ${c0.tag == 0 ? typeRef(c0.tindex) : '(${typeRef(c0.tindex)} - ${c0.tag})'})' : 'rt_types[TINDEX(${expr(x)})].tag';
			case EEnumParam(c, idx, x): load(expr(x), Std.string(at(idx, c.params[idx])), c.params[idx]);
			case EArrLen(a): 'ARR_LEN(${expr(a)})';
			case EArrGet(elem, a, i):
				switch elem {
					case TF64: 'hx_aget_f(${expr(a)}, ${expr(i)})';
					case TI32 | TBool: 'hx_aget_i(${expr(a)}, ${expr(i)})';
					case _: 'hx_aget_p(${expr(a)}, ${expr(i)})';
				}
			case EBoxGet(t, bx): load(expr(bx), "0", t);
			case ECapture(l, idx, clos): load(expr(clos), Std.string(at(idx + 1, l.captures[idx].ty)), l.captures[idx].ty);
			case EType(t): 'TYPE_OBJ(${typeRef(typeIndex(t))})';
			case ECall(f, args): '${funcRef(f)}(${[for (a in args) expr(a)].join(", ")})';
			case ECallDispatch(sel, sig, args):
				var ft = sigType(sig.ret, [for (t in sig.args) cty(t)]);
				var o = expr(args[0]);
				refs.dsps.set(sel, true);
				'((${ft})${selNames[sel]}[TINDEX($o) - $T_FIRST])(${[for (a in args) expr(a)].join(", ")})';
			case ECallClos(s, clos, args):
				var ft = sigType(s.ret, ["void *"].concat([for (t in s.args) cty(t)]));
				var c = expr(clos);
				'((${ft})CLOS_FN($c))(${[c].concat([for (a in args) expr(a)]).join(", ")})';
			case ECallAnon(name, s, obj, args):
				var ic = nextCache++;
				var ft = sigType(s.ret, ["void *"].concat([for (t in s.args) cty(t)]));
				var xs = [for (a in args) expr(a)];
				var f = fidRef(name);
				var sid = sigRef(s);
				var r = s.ret == TVoid ? "" : "r_ = ";
				var decl = s.ret == TVoid ? "" : '${cty(s.ret)} r_; ';
				var packed = [for (i in 0...args.length) pack(xs[i], s.args[i])];
				var slow = 'uint64_t av_[] = {${packed.length == 0 ? "0" : packed.join(", ")}}; uint64_t u_ = hx_anon_call_slow(o_, $f, $sid, av_); ${s.ret == TVoid ? "(void)u_;" : 'r_ = ${unpack("u_", s.ret)};'}';
				'({ ${decl}void *o_ = ${expr(obj)}; rt_icache *c_ = rt_ic(o_, $f, &ic_[$ic]); '
					+ 'if (c_->slot == 0 && c_->sig == $sid) ${r}((${ft})c_->fn)(${["o_"].concat(xs).join(", ")}); '
					+ 'else if (c_->slot > 0 && c_->kind == \'p\' && hx_is_sig(FP(o_, c_->slot - 1), $sid)) { void *k_ = FP(o_, c_->slot - 1); ${r}((${ft})CLOS_FN(k_))(${["k_"].concat(xs).join(", ")}); } '
					+ 'else { $slow } ${s.ret == TVoid ? "" : "r_; "}})';
			// Dynamic access by a literal name: the field id is known here
			case ECallHost("hx_dyn_get" | "hx_dyn_set" | "hx_dyn_call_field", args, _) if (args[1].match(EStr(_))):
				var n = switch args[1] {
					case EStr(n): n;
					case _: throw "unreachable";
				};
				var fn = switch e {
					case ECallHost(f, _, _): f + "_fid";
					case _: throw "unreachable";
				};
				'$fn(${[for (i in 0...args.length) i == 1 ? fidRef(n) : expr(args[i])].join(", ")})';
			case ECallHost(name, args, ret):
				if (!StringTools.startsWith(name, "hx_") && name != "String_length" && name != "String_charCodeAt_i" && !hostProtos.exists(name)) {
					hostProtos.set(name, '${cty(ret)} $name(${args.length == 0 ? "void" : [for (a in args) ctyOf(a)].join(", ")})');
					hostOrder.push(name);
				}
				if (hostProtos.exists(name)) refs.hosts.set(name, true);
				'$name(${[for (a in args) expr(a)].join(", ")})';
			case ENewObj(c): 'rt_alloc(${Std.int(Math.max(1, c.nslots))}, ${typeRef(c.tindex)}, K_OBJ)';
			case ENewEnum(c, args):
				var s = '({ void *o = rt_alloc_init(${c.params.length == 0 ? 1 : c.params.length}, ${typeRef(c.tindex)}, K_OBJ); ' + (c.params.length == 0 ? 'FP(o, 0) = 0; ' : '');
				for (i in 0...args.length) {
					if (c.params[i].match(TI32 | TBool)) s += 'FP(o, $i) = 0; ';
					s += load("o", Std.string(at(i, c.params[i])), c.params[i]) + ' = ${expr(args[i])}; ';
				}
				s + "o; })";
			case ENewArr(elem, vs):
				var s = '({ void *o = hx_arr_new(${arrKind(elem)}, ${vs.length}); ';
				for (i in 0...vs.length)
					s += switch elem {
						case TF64: '((double *)ARR_DATA(o))[$i] = ${expr(vs[i])}; ';
						case TI32 | TBool: '((int32_t *)ARR_DATA(o))[$i] = ${expr(vs[i])}; ';
						case _: 'rt_set_ptr(ARR_DATA(o), &FP(ARR_DATA(o), $i), ${expr(vs[i])}); ';
					};
				s + "o; })";
			case ENewClos(l, caps):
				var s = '({ void *o = rt_alloc_init(${l.captures.length + 1}, ${typeRef(l.tindex)}, K_OBJ); FP(o, 0) = (void *)${funcRef(l.fn)}; ';
				for (i in 0...caps.length)
					s += load("o", Std.string(at(i + 1, l.captures[i].ty)), l.captures[i].ty) + ' = ${expr(caps[i])}; ';
				s + "o; })";
			case ENewBox(t, v):
				var tt = switch t {
					case TF64: "T_REFBOX_F";
					case TI32 | TBool: "T_REFBOX_I";
					case _: "T_REFBOX_P";
				};
				'({ void *o = rt_alloc_init(1, $tt, K_OBJ); FP(o, 0) = 0; ${load("o", "0", t)} = ${expr(v)}; o; })';
			case ENewAnon(sh, vals):
				var s = '({ void *o = rt_alloc(${sh.nslots}, ${typeRef(sh.tindex)}, K_OBJ); ';
				for (i in 0...vals.length)
					s += load("o", Std.string(sh.locs[i]), sh.fields[i].ty) + ' = ${expr(vals[i])}; ';
				s + "o; })";
		}
	}

	static final PRELUDE = "
static inline int hx_inst(void *o, uint32_t lo, uint32_t hi) {
	return o && KIND(o) == K_OBJ && TINDEX(o) >= lo && TINDEX(o) <= hi;
}
static inline int32_t hx_aget_i(void *a, int32_t i) {
	if (ARR_KIND(a) == AK_I32 && (uint32_t)i < (uint32_t)ARR_LEN(a)) return ((int32_t *)ARR_DATA(a))[i];
	return hx_aget_i_slow(a, i);
}
static inline double hx_aget_f(void *a, int32_t i) {
	if (ARR_KIND(a) == AK_F64 && (uint32_t)i < (uint32_t)ARR_LEN(a)) return ((double *)ARR_DATA(a))[i];
	return hx_aget_f_slow(a, i);
}
static inline void *hx_aget_p(void *a, int32_t i) {
	if (ARR_KIND(a) == AK_PTR && (uint32_t)i < (uint32_t)ARR_LEN(a)) return FP(ARR_DATA(a), i);
	return hx_aget_p_slow(a, i);
}
static inline uint64_t hx_d2u(double d) { uint64_t u; memcpy(&u, &d, 8); return u; }
static inline double hx_u2d(uint64_t u) { double d; memcpy(&d, &u, 8); return d; }
static inline void hx_aset_i(void **slot, int32_t i, int32_t v) {
	void *a = *slot;
	if (ARR_KIND(a) == AK_I32 && (uint32_t)i < (uint32_t)ARR_LEN(a)) ((int32_t *)ARR_DATA(a))[i] = v;
	else hx_aset_slow(slot, i, AK_I32, (uint64_t)(uint32_t)v);
}
static inline void hx_aset_f(void **slot, int32_t i, double v) {
	void *a = *slot;
	if (ARR_KIND(a) == AK_F64 && (uint32_t)i < (uint32_t)ARR_LEN(a)) ((double *)ARR_DATA(a))[i] = v;
	else hx_aset_slow(slot, i, AK_F64, hx_d2u(v));
}
static inline void hx_aset_p(void **slot, int32_t i, void **v) {
	void *a = *slot;
	if (ARR_KIND(a) == AK_PTR && (uint32_t)i < (uint32_t)ARR_LEN(a)) { void *d = ARR_DATA(a); rt_set_ptr(d, &FP(d, i), *v); }
	else hx_aset_slow(slot, i, AK_PTR, (uint64_t)(uintptr_t)v);
}
static inline void hx_apush_i(void **slot, int32_t v) {
	void *a = *slot;
	void *d = ARR_DATA(a);
	if (ARR_KIND(a) == AK_I32 && d && (uint32_t)ARR_LEN(a) < (uint32_t)DATA_CAP(d, AK_I32)) ((int32_t *)d)[ARR_LEN(a)++] = v;
	else hx_apush_slow(slot, AK_I32, (uint64_t)(uint32_t)v);
}
static inline void hx_apush_f(void **slot, double v) {
	void *a = *slot;
	void *d = ARR_DATA(a);
	if (ARR_KIND(a) == AK_F64 && d && (uint32_t)ARR_LEN(a) < NSLOTS(d)) ((double *)d)[ARR_LEN(a)++] = v;
	else hx_apush_slow(slot, AK_F64, hx_d2u(v));
}
static inline void hx_apush_p(void **slot, void **v) {
	void *a = *slot;
	void *d = ARR_DATA(a);
	if (ARR_KIND(a) == AK_PTR && d && (uint32_t)ARR_LEN(a) < NSLOTS(d)) { rt_set_ptr(d, &FP(d, ARR_LEN(a)), *v); ARR_LEN(a)++; }
	else hx_apush_slow(slot, AK_PTR, (uint64_t)(uintptr_t)v);
}
static inline int hx_is_sig(void *c, int32_t sig) {
	return c && (rt_types[TINDEX(c)].tk == TK_CLOSURE || rt_types[TINDEX(c)].tk == TK_BOUND) && rt_types[TINDEX(c)].super == sig;
}

";
}

// what a function body refers to by name (chunked output declares them)
class Refs {
	public var funcs = new Map<String, Bool>(); // C names
	public var strs = new Map<String, Bool>();
	public var ids = new Map<String, Bool>();
	public var hosts = new Map<String, Bool>();
	public var dsps = new Map<Int, Bool>();
	public var globals = new Map<Int, Bool>(); // scalar globals

	public function new() {}

	public function add(r:Refs) {
		for (k in r.funcs.keys())
			funcs.set(k, true);
		for (k in r.strs.keys())
			strs.set(k, true);
		for (k in r.ids.keys())
			ids.set(k, true);
		for (k in r.hosts.keys())
			hosts.set(k, true);
		for (k in r.dsps.keys())
			dsps.set(k, true);
		for (k in r.globals.keys())
			globals.set(k, true);
	}
}

typedef Unit = {name:String, modules:Array<String>, funcs:Array<FuncInfo>, size:Int};

typedef TypeEntry = {
	key:String, // stable across unrelated changes: its C name (TY_*) derives from it
	name:String,
	tk:String,
	sup:Int,
	slots:Array<Null<Ty>>,
	fields:Array<{name:String, slot:Int, ty:Ty}>,
	methods:Array<{name:String, fn:String, sig:Int}>,
	ifaces:Array<Int>,
	tag:Int,
	ctors:Array<Int>
};

// Which reference locals must live in shadow-stack slots: those live across a
// GC point (a call or allocation), like the live slots an OCaml frame table
// records. The others stay in C locals (registers). Slots are colored so
// locals never live together share one. Functions with a try block root
// every reference local, since a handler may observe them after any call.
class Roots {
	var rooted = new Map<Local, Bool>();
	var points:Array<Map<Local, Bool>> = []; // live sets after each statement
	public var slots = new Map<Local, Int>();
	var brk:Array<Map<Local, Bool>> = [];
	var cont:Array<Map<Local, Bool>> = [];

	function new() {}

	public static function analyze(f:FuncInfo):Roots {
		var r = new Roots();
		if (f.hasTry) {
			var n = 0;
			for (l in f.args.concat(f.locals))
				if (Ir.isRef(l.ty)) r.slots.set(l, n++);
			return r;
		}
		var entry = r.seq(f.body, new Map());
		r.points.push(entry);
		r.color(f);
		return r;
	}

	function color(f:FuncInfo) {
		var interfere = new Map<Local, Map<Local, Bool>>();
		for (l in rooted.keys())
			interfere.set(l, new Map());
		for (pt in points) {
			var live = [for (l in pt.keys()) if (rooted.exists(l)) l];
			for (a in live)
				for (b in live)
					if (a != b) interfere.get(a).set(b, true);
		}
		var args = [for (a in f.args) if (rooted.exists(a)) a];
		for (a in args)
			for (b in args)
				if (a != b) interfere.get(a).set(b, true);
		for (l in f.args.concat(f.locals)) {
			if (!rooted.exists(l)) continue;
			var used = new Map<Int, Bool>();
			for (o in interfere.get(l).keys())
				if (slots.exists(o)) used.set(slots.get(o), true);
			var s = 0;
			while (used.exists(s))
				s++;
			slots.set(l, s);
		}
	}

	static function copy(m:Map<Local, Bool>):Map<Local, Bool> {
		var r = new Map();
		for (k in m.keys())
			r.set(k, true);
		return r;
	}

	static function union(a:Map<Local, Bool>, b:Map<Local, Bool>):Map<Local, Bool> {
		var r = copy(a);
		for (k in b.keys())
			r.set(k, true);
		return r;
	}

	static function same(a:Map<Local, Bool>, b:Map<Local, Bool>):Bool {
		for (k in a.keys())
			if (!b.exists(k)) return false;
		for (k in b.keys())
			if (!a.exists(k)) return false;
		return true;
	}

	function across(live:Map<Local, Bool>) {
		for (l in live.keys())
			if (Ir.isRef(l.ty)) rooted.set(l, true);
	}

	static function uses(e:Ex, acc:Map<Local, Bool>) {
		switch e {
			case ELocal(l): acc.set(l, true);
			case _: EmitC.iterEx(x -> uses(x, acc), e);
		}
	}

	// GC point of an expression; 2: operands are read after an allocation
	static function gcPoint(e:Ex):Int
		return switch e {
			case ECall(_) | ECallDispatch(_) | ECallClos(_) | ECallAnon(_) | EBox(_) | EAnonGet(_) | EArrGet(TRef(RAny), _, _): 1;
			case ECallHost(n, _, _): FnLower.PURE.exists(n) ? 0 : 1;
			case ENewObj(_) | ENewEnum(_) | ENewArr(_) | ENewClos(_) | ENewBox(_) | ENewAnon(_): 2;
			case _: 0;
		}

	// a GC point nested inside an expression's operands
	static function nestedGc(e:Ex):Bool {
		var r = false;
		EmitC.iterEx(x -> if (gcPoint(x) > 0 || nestedGc(x)) r = true, e);
		return r;
	}

	function seq(ss:Array<Stmt>, out:Map<Local, Bool>):Map<Local, Bool> {
		var live = out;
		var i = ss.length;
		while (i-- > 0)
			live = stmt(ss[i], live);
		return live;
	}

	function expr(e:Ex, after:Map<Local, Bool>, def:Null<Local>):Map<Local, Bool> {
		var u = new Map();
		uses(e, u);
		var rest = copy(after);
		if (def != null) rest.remove(def);
		var g = gcPoint(e);
		if (nestedGc(e)) g = 2;
		switch g {
			case 1: across(rest);
			case 2: across(union(rest, u));
			case _:
		}
		return union(rest, u);
	}

	function stmt(s:Stmt, out:Map<Local, Bool>):Map<Local, Bool> {
		switch s {
			case SSet(l, _):
				var pt = copy(out);
				pt.set(l, true);
				points.push(pt);
			case _:
				points.push(out);
		}
		return switch s {
			case SSet(l, e): expr(e, out, l);
			case SExpr(e): expr(e, out, null);
			case SSetGlobal(_, v):
				var u = copy(out);
				uses(v, u);
				if (nestedGc(v) || gcPoint(v) > 0) across(u);
				u;
			case SSetField(_, _, o, v) | SBoxSet(_, o, v):
				var u = copy(out);
				uses(o, u);
				uses(v, u);
				if (nestedGc(o) || nestedGc(v) || gcPoint(v) > 0 || gcPoint(o) > 0) across(u);
				u;
			case SAnonSet(_, _, o, v):
				// the slow path boxes the value, then reads the object again
				var u = copy(out);
				uses(o, u);
				uses(v, u);
				across(u);
				u;
			case SArrSet(_, a, i, v):
				rooted.set(a, true); // passed by slot address
				var u = copy(out);
				u.set(a, true);
				uses(i, u);
				uses(v, u);
				across(u);
				u;
			case SArrPush(_, a, v):
				rooted.set(a, true);
				var u = copy(out);
				u.set(a, true);
				uses(v, u);
				across(u);
				u;
			case SIf(c, x, y):
				var u = union(seq(x, out), seq(y, out));
				uses(c, u);
				if (nestedGc(c) || gcPoint(c) > 0) across(u);
				u;
			case SLoop(body):
				var entry = new Map<Local, Bool>();
				while (true) {
					brk.push(out);
					cont.push(entry);
					var n = seq(body, entry);
					brk.pop();
					cont.pop();
					if (same(n, entry)) break;
					entry = union(entry, n);
				}
				entry;
			case SBreak: brk[brk.length - 1];
			case SContinue: cont[cont.length - 1];
			case SSwitch(e, cases, def):
				var u = seq(def, out);
				for (c in cases)
					u = union(u, seq(c.body, out));
				uses(e, u);
				u;
			case SReturn(e):
				var u = new Map();
				if (e != null) uses(e, u);
				u;
			case SThrow(e):
				var u = new Map();
				uses(e, u);
				u;
			case STry(_, _): throw "try in a function without hasTry";
		}
	}
}
