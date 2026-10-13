package hxmc;

import backend.Ir;

// What a function's machine code depends on, as text (hashed per module by
// Driver to key the object cache): its IR, and of everything else in the
// program only what MirBuild reads: field locations and types, the
// signatures and no-GC flags of callees, layouts of the objects it creates,
// the names of what it refers to. Program-wide numbers (type indices,
// field ids, signatures, global indices) are not in it: native code
// refers to them by name (absolute symbols resolved when linking), as hxc's
// chunked C does, so adding a type, a field or a global elsewhere leaves
// this module's code and key unchanged.
@:access(backend.EmitC)
class Fingerprint {
	var b:StringBuf;
	var prep:Prep;

	public function new(prep:Prep) {
		this.prep = prep;
	}

	// a 64-bit hash of a string (two 32-bit lanes), as 16 hex digits
	public static function hash(s:String):String {
		var h1 = 0x811c9dc5, h2 = 0x2545f491;
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			h1 = (h1 ^ c) * 0x01000193;
			h2 = (h2 ^ c) * 0x5bd1e995;
			h2 ^= h2 >>> 15;
		}
		h1 ^= s.length;
		h1 = (h1 ^ (h1 >>> 16)) * 0x85ebca6b;
		h2 = (h2 ^ (h2 >>> 13)) * 0xc2b2ae35;
		return StringTools.hex(h1 ^ (h2 >>> 7), 8) + StringTools.hex(h2 ^ (h1 >>> 11), 8);
	}

	public function func(f:FuncInfo, out:StringBuf) {
		b = out;
		b.add("F");
		b.add(prep.funcSym(f));
		b.add("(");
		for (a in f.args)
			tyArg(a);
		b.add(")");
		b.add(Ir.repr(f.ret));
		b.add(f.hasTry ? "T" : "_");
		for (l in f.locals)
			tyArg(l);
		b.add("{");
		stmts(f.body);
		b.add("}\n");
	}

	inline function tyArg(l:Local) {
		b.add(l.id);
		b.add(Ir.repr(l.ty));
		b.add(",");
	}

	function ty(t:Ty)
		b.add(Ir.repr(t));

	function tyName(tindex:Int) {
		var s = prep.tySym(tindex);
		b.add(s == null ? Std.string(tindex) : s);
		b.add(";");
	}

	function str(s:String) {
		b.add(s.length);
		b.add(":");
		b.add(s);
	}

	function stmts(ss:Array<Stmt>) {
		b.add("[");
		for (s in ss)
			stmt(s);
		b.add("]");
	}

	function stmt(s:Stmt) {
		switch s {
			case SSet(l, e):
				b.add("=");
				b.add(l.id);
				ex(e);
			case SExpr(e):
				b.add("e");
				ex(e);
			case SSetField(c, idx, o, v):
				b.add("sf");
				b.add(c.locs[idx]);
				ty(c.fields[idx].ty);
				ex(o);
				ex(v);
			case SAnonSet(n, t, o, v):
				b.add("sa");
				str(n);
				ty(t);
				ex(o);
				ex(v);
			case SArrSet(elem, a, i, v):
				b.add("as");
				ty(elem);
				b.add(a.id);
				ex(i);
				ex(v);
			case SArrPush(elem, a, v):
				b.add("ap");
				ty(elem);
				b.add(a.id);
				ex(v);
			case SBoxSet(t, x, v):
				b.add("sb");
				ty(t);
				ex(x);
				ex(v);
			case SSetGlobal(g, v):
				b.add("sg");
				str(prep.p.globals[g].name);
				ty(prep.p.globals[g].ty);
				ex(v);
			case SIf(c, x, y):
				b.add("if");
				ex(c);
				stmts(x);
				stmts(y);
			case SLoop(body):
				b.add("lp");
				stmts(body);
			case SBreak:
				b.add("br");
			case SContinue:
				b.add("ct");
			case SSwitch(e, cases, def):
				b.add("sw");
				ex(e);
				for (c in cases) {
					b.add("c");
					b.add(c.values.join(","));
					stmts(c.body);
				}
				stmts(def);
			case SReturn(e):
				b.add("rt");
				if (e != null) ex(e);
			case SThrow(e):
				b.add("th");
				ex(e);
			case STry(body, catches):
				b.add("try");
				stmts(body);
				for (c in catches) {
					b.add("ca");
					b.add(c.l.id);
					if (c.test != null) ex(c.test(ELocal(c.l)));
					stmts(c.body);
				}
			case SCold(_, x):
				b.add("cold");
				stmt(x);
		}
	}

	function args(xs:Array<Ex>) {
		b.add("(");
		for (x in xs)
			ex(x);
		b.add(")");
	}

	function ex(e:Ex) {
		switch e {
			case EInt(v):
				b.add("i");
				b.add(v);
			case EF64(v):
				var bytes = haxe.io.Bytes.alloc(8);
				bytes.setDouble(0, v);
				b.add("f");
				b.add(bytes.getInt32(0));
				b.add(",");
				b.add(bytes.getInt32(4));
			case EStr(s):
				// (registers the literal: DataGen defines every one, cached modules included)
				prep.strSym(s);
				b.add("s");
				str(s);
			case ENull(_):
				b.add("n");
			case ELocal(l):
				b.add("l");
				b.add(l.id);
			case EGlobal(g, t):
				b.add("g");
				str(prep.p.globals[g].name);
				ty(t);
			case EBin(op, x, y):
				b.add("b");
				b.add(op.getIndex());
				ex(x);
				ex(y);
			case ENot(x):
				b.add("!");
				ex(x);
			case EConv(op, x):
				b.add("cv");
				b.add(op.getIndex());
				ex(x);
			case EBox(t, x):
				b.add("bx");
				ty(t);
				ex(x);
			case EUnbox(t, x):
				b.add("ub");
				ty(t);
				ex(x);
			case EField(c, idx, o):
				b.add("fd");
				b.add(c.locs[idx]);
				ty(c.fields[idx].ty);
				ex(o);
			case EAnonGet(n, t, o, hint):
				b.add("ag");
				str(n);
				ty(t);
				if (hint != null && hint.tindex >= 0) {
					tyName(hint.tindex);
					b.add(hint.locs[hint.slot(n) - 1]);
				}
				ex(o);
			case ECast(_, x):
				ex(x);
			case EInstOf(c, x):
				b.add("io");
				tyName(c.tindex);
				ex(x);
			case EEnumTag(x, en):
				b.add("et");
				if (en != null && en.ctors.length > 0) {
					tyName(en.ctors[0].tindex);
					b.add(en.ctors[0].tag);
				}
				ex(x);
			case EEnumParam(c, idx, x):
				b.add("ep");
				b.add(idx);
				for (t in c.params)
					ty(t);
				ex(x);
			case EArrLen(a):
				b.add("al");
				ex(a);
			case EArrGet(elem, a, i):
				b.add("ag");
				ty(elem);
				ex(a);
				ex(i);
			case EArrGetU(elem, a, i):
				b.add("au");
				ty(elem);
				ex(a);
				ex(i);
			case EBoxGet(t, x):
				b.add("bg");
				ty(t);
				ex(x);
			case ECapture(l, idx, c):
				b.add("cp");
				b.add(idx);
				for (x in l.captures)
					ty(x.ty);
				ex(c);
			case EType(t):
				b.add("ty");
				b.add(switch t {
					case TRClass(c): prep.typeObjSym(c.tindex);
					case TREnum(e): prep.typeObjSym(e.tindex);
					case TRBuiltin(n): n;
				});
			case ECall(f, xs):
				b.add("cl");
				b.add(prep.funcSym(f));
				b.add(f.noGc ? "N" : "_");
				for (a in f.args)
					ty(a.ty);
				ty(f.ret);
				args(xs);
			case ECallDispatch(sel, sig, xs):
				b.add("cd");
				b.add(prep.selectorSym(sel));
				str(sig.key);
				args(xs);
			case ECallClos(s, c, xs):
				b.add("cc");
				str(s.key);
				ex(c);
				args(xs);
			case ECallAnon(n, s, o, xs):
				b.add("ca");
				str(n);
				str(s.key);
				ex(o);
				args(xs);
			case ECallHost(n, xs, r):
				b.add("ch");
				str(n);
				ty(r);
				args(xs);
			case ENewObj(c):
				b.add("no");
				tyName(c.tindex);
				b.add(c.nslots);
			case ENewEnum(c, xs):
				b.add("ne");
				tyName(c.tindex);
				for (t in c.params)
					ty(t);
				args(xs);
			case ENewArr(elem, xs):
				b.add("na");
				ty(elem);
				args(xs);
			case ENewClos(l, xs):
				b.add("nc");
				tyName(l.tindex);
				b.add(prep.funcSym(l.fn));
				for (c in l.captures)
					ty(c.ty);
				args(xs);
			case ENewBox(t, x):
				b.add("nb");
				ty(t);
				ex(x);
			case ENewAnon(sh, xs):
				b.add("nn");
				tyName(sh.tindex);
				b.add(sh.nslots);
				for (i in 0...sh.fields.length) {
					b.add(sh.locs[i]);
					ty(sh.fields[i].ty);
				}
				args(xs);
		}
	}
}
