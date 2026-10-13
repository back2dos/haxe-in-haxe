package hxmc;

import backend.Ir;
import hxmc.Mir;

// hxc's IR (backend.Ir: structured statements in A-normal form) of one
// function to Mir, mirroring what EmitC writes in C statement by statement
// (the runtime's inline helpers of rt.h and EmitC.PRELUDE are expanded
// here), so the native code and the C agree on every detail:
// - reference locals that Roots puts in shadow-stack slots live in memory
//   (fr[k]); in functions with a try block every local lives in memory (C:
//   volatile), so values survive the second return of setjmp; the other
//   locals become SSA values (Braun et al., "Simple and Efficient
//   Construction of Static Single Assignment Form", on the structured input);
// - cold sites (SCold) root the references live across them only on the
//   slow path of the allocation or array store.
// Constructs not handled yet throw Unsupported: in development builds the
// function is then compiled as C (CWriter).
class MirBuild {
	var p:Prep;
	var abi:Abi;
	var fn:FuncInfo;
	var f:MFunc;
	var cur:MBlock;
	var roots:Roots;
	var refSlot = new Map<Local, Int>();
	var nslots = 0;
	var fr = -1; // the frame's shadow-stack slots (value)
	var memSlot = new Map<Local, Int>(); // try functions: frame slot of a scalar local
	var defs:Array<BlockDefs> = [];
	var incomplete:Array<Map<Int, MIns>> = [];
	var varTy = new Map<Int, MTy>();
	var nextVar = 0;
	var loops:Array<{cont:MBlock, brk:MBlock, tries:Int}> = [];
	var tries:Array<Int> = []; // frame slots of the enclosing handlers
	var coldList:Null<Array<Local>> = null;
	public var icaches = 0; // inline caches of this function (bss: <name>__ic, IC_SIZE each)
	public var icSym:String;

	public function new(p:Prep, abi:Abi, fn:FuncInfo) {
		this.p = p;
		this.abi = abi;
		this.fn = fn;
	}

	public static function mty(t:Ty):MTy
		return switch t {
			case TI32 | TBool: I32;
			case TF64: F64;
			case TI64: I64;
			case TVoid: Void;
			case TRef(_): I64;
		};

	// ---- instruction helpers

	function add(i:MIns):Int {
		i.id = f.vals.length;
		f.vals.push(i);
		i.block = cur;
		cur.ins.push(i);
		return i.id;
	}

	inline function mk(op:Op, ty:MTy):MIns
		return new MIns(op, ty);

	function op2(op:Op, ty:MTy, a:Int, b:Int):Int {
		var i = mk(op, ty);
		i.a = a;
		i.b = b;
		return add(i);
	}

	function op1(op:Op, ty:MTy, a:Int):Int {
		// a constant widened: a constant
		var x = f.vals[a];
		if (x.op == Const && x.sym == null && x.ty == I32) {
			if (op == SExt) return lconst32(x.imm);
			if (op == ZExt) return lconst(x.imm, 0);
		}
		var i = mk(op, ty);
		i.a = a;
		return add(i);
	}

	function iconst(v:Int):Int {
		var i = mk(Const, I32);
		i.imm = v;
		return add(i);
	}

	// a program-wide number (Prep.tySym...): an absolute symbol + addend, or a plain constant
	function idConst(sym:Null<String>, value:Int, addend = 0, t:MTy = I32):Int {
		if (sym == null) return t == I32 ? iconst(value + addend) : lconst32(value + addend);
		var i = mk(Const, t);
		i.sym = sym;
		i.imm = addend;
		return add(i);
	}

	inline function tyConst(tindex:Int, addend = 0):Int
		return idConst(p.tySym(tindex), tindex, addend);

	inline function fidConst(name:String):Int
		return idConst(p.fidSym(name), 0);

	inline function sigConst(s:SigInfo):Int
		return idConst(p.sigSym(s), 0);

	// the address of rt_globals[g]
	function globalAddr(g:Int):Int
		return op2(Add, I64, loadM(Opt.MConst, I64, 8, symAddr("rt_globals"), 0), idConst(p.globalOffSym(g), 0, 0, I64));

	function lconst(lo:Int, hi:Int):Int {
		var i = mk(Const, I64);
		i.imm = lo;
		i.imm2 = hi;
		return add(i);
	}

	inline function lconst32(v:Int):Int
		return lconst(v, v < 0 ? -1 : 0);

	function fconst(v:Float):Int {
		var i = mk(ConstF, F64);
		i.f = v;
		return add(i);
	}

	function symAddr(s:String, addend = 0):Int {
		var i = mk(SymAddr, I64);
		i.sym = s;
		i.imm = addend;
		return add(i);
	}

	function tlsLoad(s:String):Int {
		var i = mk(TlsLoad, I64);
		i.sym = s;
		return add(i);
	}

	function tlsStore(s:String, v:Int) {
		var i = mk(TlsStore, Void);
		i.sym = s;
		i.a = v;
		add(i);
	}

	// a constant index: part of the displacement
	inline function constIndex(index:Int):Bool {
		if (index < 0) return false;
		var x = f.vals[index];
		return x.op == Const && x.sym == null && x.ty == I64 && x.imm2 == (x.imm < 0 ? -1 : 0) && x.imm >= -0x1000000 && x.imm < 0x1000000;
	}

	function load(ty:MTy, size:Int, base:Int, disp:Int, signed = false, index = -1, scale = 1):Int {
		if (constIndex(index)) {
			disp += f.vals[index].imm * scale;
			index = -1;
		}
		var i = mk(Load, ty);
		i.mem = memCls;
		i.a = base;
		i.b = index;
		i.imm = disp;
		i.imm2 = scale;
		i.size = size;
		i.signed = signed;
		return add(i);
	}

	// the memory class of the loads and stores made (Opt.MOther...)
	var memCls = 0;

	function loadM(cls:Int, ty:MTy, size:Int, base:Int, disp:Int, signed = false, index = -1, scale = 1):Int {
		memCls = cls;
		var r = load(ty, size, base, disp, signed, index, scale);
		memCls = 0;
		return r;
	}

	function storeM(cls:Int, size:Int, base:Int, disp:Int, v:Int, index = -1, scale = 1) {
		memCls = cls;
		store(size, base, disp, v, index, scale);
		memCls = 0;
	}

	function store(size:Int, base:Int, disp:Int, v:Int, index = -1, scale = 1) {
		if (constIndex(index)) {
			disp += f.vals[index].imm * scale;
			index = -1;
		}
		var i = mk(Store, Void);
		i.mem = memCls;
		i.a = base;
		i.b = index;
		i.c = v;
		i.imm = disp;
		i.imm2 = scale;
		i.size = size;
		add(i);
	}

	function cmp(c:Cond, a:Int, b:Int):Int {
		// (x op y) == 0 is the inverse comparison, (x op y) != 0 the same one
		// (the inner comparison is left unused: instruction selection drops it)
		var x = f.vals[a], z = f.vals[b];
		if ((c == CEq || c == CNe) && x.op == Cmp && z.op == Const && z.imm == 0) {
			var inner:Cond = x.imm;
			if (c == CNe) return cmp(inner, x.a, x.b);
			var inv = invert(inner);
			if (inv >= 0) return cmp(inv, x.a, x.b);
		}
		var i = mk(Cmp, I32);
		i.imm = c;
		i.a = a;
		i.b = b;
		return add(i);
	}

	// the comparison true exactly when c is false, or -1 (ordered double
	// comparisons are false with NaN either way)
	static function invert(c:Cond):Int {
		return switch c {
			case CEq: CNe;
			case CNe: CEq;
			case CLt: CGe;
			case CGe: CLt;
			case CLe: CGt;
			case CGt: CLe;
			case CULt: CUGe;
			case CUGe: CULt;
			case CULe: CUGt;
			case CUGt: CULe;
			case FEq: FNe;
			case FNe: FEq;
			case _: -1;
		}
	}

	function tyOfVal(v:Int):MTy
		return f.vals[v].ty;

	function call(sym:String, args:Array<Int>, ret:MTy, noReturn = false):Int {
		var i = mk(Call, ret);
		i.sym = sym;
		i.args = args;
		i.argTys = [for (a in args) tyOfVal(a)];
		i.noReturn = noReturn;
		return add(i);
	}

	function callInd(fnv:Int, args:Array<Int>, ret:MTy, ?argTys:Array<MTy>):Int {
		var i = mk(Call, ret);
		i.a = fnv;
		i.args = args;
		i.argTys = argTys != null ? argTys : [for (a in args) tyOfVal(a)];
		return add(i);
	}

	function newBlock():MBlock {
		var b = f.newBlock();
		defs.push(new BlockDefs());
		incomplete.push(new Map());
		return b;
	}

	function edge(from:MBlock, to:MBlock) {
		from.succs.push(to);
		to.preds.push(from);
	}

	inline function terminated():Bool
		return cur.term() != null;

	function jmp(to:MBlock) {
		if (terminated()) return;
		var i = mk(Jmp, Void);
		i.targets = [to];
		add(i);
		edge(cur, to);
	}

	function br(c:Int, t:MBlock, e:MBlock) {
		var i = mk(Br, Void);
		i.a = c;
		i.targets = [t, e];
		add(i);
		edge(cur, t);
		edge(cur, e);
	}

	// a new block reached only from where control is now
	function split():MBlock {
		var b = newBlock();
		jmp(b);
		seal(b);
		cur = b;
		return b;
	}

	// statements after a return/break/throw: an unreachable block of their own
	function deadBlock() {
		var b = newBlock();
		seal(b);
		cur = b;
	}

	// ---- SSA variables (locals by id; temporaries above)

	function newVar(t:MTy):Int {
		var v = nextVar++;
		varTy.set(v, t);
		return v;
	}

	function writeVar(v:Int, b:MBlock, val:Int)
		defs[b.id].set(v, val);

	function readVar(v:Int, b:MBlock):Int {
		var d = defs[b.id].get(v);
		if (d != null) return d;
		return readVarRec(v, b);
	}

	function newPhi(b:MBlock, t:MTy):MIns {
		var i = mk(Phi, t);
		i.args = [];
		i.id = f.vals.length;
		f.vals.push(i);
		i.block = b;
		var k = 0;
		while (k < b.ins.length && b.ins[k].op == Phi)
			k++;
		b.ins.insert(k, i);
		return i;
	}

	function readVarRec(v:Int, b:MBlock):Int {
		var t = varTy.get(v);
		var val:Int;
		if (!b.sealed) {
			var phi = newPhi(b, t);
			incomplete[b.id].set(v, phi);
			val = phi.id;
		} else if (b.preds.length == 0) {
			// never assigned (C: the local starts as 0)
			val = zeroAt(b, t);
		} else if (b.preds.length == 1) {
			val = readVar(v, b.preds[0]);
		} else {
			var phi = newPhi(b, t);
			writeVar(v, b, phi.id);
			for (pr in b.preds)
				phi.args.push(readVar(v, pr));
			val = phi.id;
		}
		writeVar(v, b, val);
		return val;
	}

	// a zero constant at the start of b (after its phis)
	function zeroAt(b:MBlock, t:MTy):Int {
		var i = t == F64 ? mk(ConstF, F64) : mk(Const, t == Void ? I32 : t);
		i.id = f.vals.length;
		f.vals.push(i);
		i.block = b;
		var k = 0;
		while (k < b.ins.length && b.ins[k].op == Phi)
			k++;
		b.ins.insert(k, i);
		return i.id;
	}

	function seal(b:MBlock) {
		if (b.sealed) return;
		b.sealed = true;
		for (v => phi in incomplete[b.id])
			for (pr in b.preds)
				phi.args.push(readVar(v, pr));
		incomplete[b.id] = new Map();
	}

	// ---- locals

	function readLocal(l:Local):Int {
		var s = refSlot.get(l);
		if (s != null) return loadM(Opt.MFrame, I64, 8, fr, 8 * s);
		var m = memSlot.get(l);
		if (m != null) {
			var t = mty(l.ty);
			var a = stackAddr(m);
			return load(t, t == I32 ? 4 : 8, a, 0);
		}
		return readVar(l.id, cur);
	}

	function writeLocal(l:Local, v:Int) {
		var s = refSlot.get(l);
		if (s != null) {
			storeM(Opt.MFrame, 8, fr, 8 * s, v);
			return;
		}
		var m = memSlot.get(l);
		if (m != null) {
			var t = mty(l.ty);
			store(t == I32 ? 4 : 8, stackAddr(m), 0, v);
			return;
		}
		writeVar(l.id, cur, v);
	}

	function stackAddr(slot:Int):Int {
		var i = mk(StackAddr, I64);
		i.imm = slot;
		return add(i);
	}

	// ---- entry

	// a function made up by hxmc (closure trampolines, main): `body` uses the
	// instruction helpers (@:access) and must end every path with a return
	public static function synthetic(p:Prep, abi:Abi, name:String, params:Array<MTy>, ret:MTy, body:(MirBuild, Array<Int>) -> Void):MFunc {
		var mb = new MirBuild(p, abi, null);
		var f = mb.f = new MFunc(name);
		f.params = params;
		f.ret = ret;
		var entry = mb.newBlock();
		f.entry = entry;
		mb.seal(entry);
		mb.cur = entry;
		var ps = [];
		for (i in 0...params.length) {
			var pi = mb.mk(Param, params[i]);
			pi.imm = i;
			ps.push(mb.add(pi));
		}
		body(mb, ps);
		for (b in f.blocks)
			if (!b.sealed) mb.seal(b);
		mb.prune();
		mb.removeTrivialPhis();
		return f;
	}

	public function build():MFunc {
		f = new MFunc(p.funcSym(fn));
		for (a in fn.args)
			f.params.push(mty(a.ty));
		f.ret = mty(fn.ret);
		var maxId = 0;
		for (l in fn.args.concat(fn.locals)) {
			if (l.id >= maxId) maxId = l.id + 1;
			varTy.set(l.id, mty(l.ty) == Void ? I32 : mty(l.ty));
		}
		nextVar = maxId;
		roots = Roots.analyze(fn);
		for (l in fn.args.concat(fn.locals)) {
			var s = roots.slots[l.id];
			if (s >= 0) refSlot.set(l, s);
		}
		nslots = roots.nslots;
		var entry = newBlock();
		f.entry = entry;
		seal(entry);
		cur = entry;
		var params = [];
		for (i in 0...fn.args.length) {
			var pi = mk(Param, f.params[i]);
			pi.imm = i;
			params.push(add(pi));
		}
		if (nslots > 0) {
			fr = push(nslots);
			if (fn.hasTry) {
				var z = lconst(0, 0);
				for (k in 0...nslots)
					store(8, fr, 8 * k, z);
			} else {
				var zero = new Map<Int, Bool>();
				var unset = Roots.maybeUnset(fn);
				for (l in fn.locals)
					if (unset.get(l.id) && refSlot.exists(l)) zero.set(refSlot.get(l), true);
				if (zero.keys().hasNext()) {
					var z = lconst(0, 0);
					var ks = [for (k in zero.keys()) k];
					ks.sort((x, y) -> x - y);
					for (k in ks)
						store(8, fr, 8 * k, z);
				}
			}
		}
		if (fn.hasTry)
			for (l in fn.args.concat(fn.locals))
				if (!refSlot.exists(l)) {
					var t = mty(l.ty);
					memSlot.set(l, f.slot(8, 8));
				}
		for (i in 0...fn.args.length)
			writeLocal(fn.args[i], params[i]);
		if (fn.hasTry)
			for (l in fn.locals)
				if (memSlot.exists(l)) {
					var t = mty(l.ty);
					writeLocal(l, t == F64 ? fconst(0) : t == I64 ? lconst(0, 0) : iconst(0));
				}
		stmts(fn.body);
		if (!terminated()) {
			popFrame();
			if (f.ret == Void) ret(-1) else ret(f.ret == F64 ? fconst(0) : f.ret == I64 ? lconst(0, 0) : iconst(0));
		}
		for (b in f.blocks)
			if (!b.sealed) seal(b);
		prune();
		removeTrivialPhis();
		return f;
	}

	// drops the blocks not reachable from the entry (and their phi operands)
	function prune() {
		var reach = new Map<Int, Bool>();
		var stack = [f.entry];
		reach.set(f.entry.id, true);
		while (stack.length > 0) {
			var b = stack.pop();
			for (s in b.succs)
				if (!reach.exists(s.id)) {
					reach.set(s.id, true);
					stack.push(s);
				}
		}
		for (b in f.blocks) {
			if (reach.exists(b.id)) continue;
			for (s in b.succs) {
				var k = s.preds.indexOf(b);
				if (k < 0) continue;
				s.preds.splice(k, 1);
				for (i in s.ins)
					if (i.op == Phi) i.args.splice(k, 1);
			}
		}
		f.blocks = [for (b in f.blocks) if (reach.exists(b.id)) b];
	}

	function ret(v:Int) {
		var i = mk(Ret, Void);
		i.a = v;
		add(i);
	}

	// rt_push(n): the frame's slots on the shadow stack
	function push(n:Int):Int {
		var sp = tlsLoad("rt_sp");
		var top = op2(Add, I64, sp, lconst32(8 * n));
		tlsStore("rt_sp", top);
		var hw = tlsLoad("rt_sp_hw");
		var s = mk(Select, I64);
		s.a = cmp(CUGt, top, hw);
		s.b = top;
		s.c = hw;
		tlsStore("rt_sp_hw", add(s));
		return sp;
	}

	function popFrame() {
		if (nslots > 0) tlsStore("rt_sp", fr);
	}

	// replaces phis whose operands are one value (or the phi itself), until none is left
	function removeTrivialPhis() {
		var repl = new Map<Int, Int>();
		function find(v:Int):Int {
			while (repl.exists(v))
				v = repl.get(v);
			return v;
		}
		var changed = true;
		while (changed) {
			changed = false;
			for (b in f.blocks)
				for (i in b.ins) {
					if (i.op != Phi || i.dead) continue;
					var same = -1;
					var trivial = true;
					for (a in i.args) {
						var x = find(a);
						if (x == i.id || x == same) continue;
						if (same >= 0) {
							trivial = false;
							break;
						}
						same = x;
					}
					if (trivial && same >= 0) {
						repl.set(i.id, same);
						i.dead = true;
						changed = true;
					}
				}
		}
		if (!repl.keys().hasNext()) return;
		for (b in f.blocks) {
			b.ins = [for (i in b.ins) if (!i.dead) i];
			for (i in b.ins) {
				if (i.a >= 0) i.a = find(i.a);
				if (i.b >= 0) i.b = find(i.b);
				if (i.c >= 0) i.c = find(i.c);
				if (i.args != null)
					for (k in 0...i.args.length)
						i.args[k] = find(i.args[k]);
			}
		}
	}

	// ---- statements

	function stmts(ss:Array<Stmt>) {
		for (s in ss) {
			if (terminated()) deadBlock();
			stmt(s);
		}
	}

	function stmt(s:Stmt) {
		switch s {
			case SCold(id, x):
				var list = roots.spills.get(id);
				coldList = list == null ? [] : [for (l in list) if (!refSlot.exists(l)) l];
				coldStmt(x);
				coldList = null;
			case SSet(l, e):
				writeLocal(l, ex(e));
			case SExpr(e):
				ex(e);
			case SSetField(c, idx, obj, v):
				var o = ex(obj);
				var x = ex(v);
				storeSlot(o, c.locs[idx], c.fields[idx].ty, x, isNullConst(v));
			case SBoxSet(t, bx, v):
				var o = ex(bx);
				var x = ex(v);
				storeSlot(o, 0, t, x, isNullConst(v));
			case SSetGlobal(g, v):
				var x = ex(v);
				var t = p.p.globals[g].ty;
				if (Ir.isRef(t)) {
					storeM(Opt.MGlobal, 8, globalAddr(g), 0, x);
				} else storeM(Opt.MGlobal, t == TI32 || t == TBool ? 4 : 8, symAddr(p.scalarGlobalSym(g)), 0, x);
			case SAnonSet(name, t, obj, v):
				anonSet(name, t, obj, v);
			case SArrSet(elem, a, i, v):
				arrSet(elem, a, i, v, false);
			case SArrPush(elem, a, v):
				arrPush(elem, a, v, false);
			case SIf(c, x, y):
				var cv = ex(c);
				var t = newBlock(), e = y.length > 0 ? newBlock() : null, join = newBlock();
				br(cv, t, y.length > 0 ? e : join);
				seal(t);
				cur = t;
				stmts(x);
				jmp(join);
				if (y.length > 0) {
					seal(e);
					cur = e;
					stmts(y);
					jmp(join);
				}
				seal(join);
				cur = join;
				if (join.preds.length == 0) {
					var i = mk(Unreachable, Void);
					add(i);
				}
			case SLoop(body):
				var head = newBlock(), exit = newBlock();
				jmp(head);
				cur = head;
				loops.push({cont: head, brk: exit, tries: tries.length});
				stmts(body);
				jmp(head);
				loops.pop();
				seal(head);
				seal(exit);
				cur = exit;
				if (exit.preds.length == 0) add(mk(Unreachable, Void));
			case SBreak:
				var lp = loops[loops.length - 1];
				unwindTo(lp.tries);
				jmp(lp.brk);
			case SContinue:
				var lp = loops[loops.length - 1];
				unwindTo(lp.tries);
				jmp(lp.cont);
			case SSwitch(e, cases, def):
				var v = ex(e);
				var seen = new Map<Int, Bool>();
				var join = newBlock();
				var vals = [], targets = [], bodies = [];
				for (c in cases) {
					var labels = [for (x in c.values) if (!seen.exists(x)) x];
					for (x in labels)
						seen.set(x, true);
					if (labels.length == 0) continue;
					var b = newBlock();
					bodies.push({b: b, body: c.body});
					for (x in labels) {
						vals.push(x);
						targets.push(b);
					}
				}
				var db = newBlock();
				targets.push(db);
				var sw = mk(Switch, Void);
				sw.a = v;
				sw.cases = vals;
				sw.targets = targets;
				add(sw);
				var from = cur;
				var done = new Map<Int, Bool>();
				for (t in targets)
					if (!done.exists(t.id)) {
						done.set(t.id, true);
						edge(from, t);
					}
				for (x in bodies) {
					seal(x.b);
					cur = x.b;
					stmts(x.body);
					jmp(join);
				}
				seal(db);
				cur = db;
				stmts(def);
				jmp(join);
				seal(join);
				cur = join;
				if (join.preds.length == 0) add(mk(Unreachable, Void));
			case SReturn(null):
				unwindTo(0);
				popFrame();
				ret(-1);
			case SReturn(e):
				var v = ex(e);
				unwindTo(0);
				popFrame();
				ret(v);
			case SThrow(e):
				var v = ex(e);
				call("rt_throw", [v], Void, true);
				add(mk(Unreachable, Void));
			case STry(body, catches):
				tryStmt(body, catches);
		}
	}

	// RT_POP of the handler at `depth` (the outermost one left)
	function unwindTo(depth:Int) {
		if (tries.length > depth) {
			var h = stackAddr(tries[depth]);
			tlsStore("rt_hcur", load(I64, 8, h, abi.handlerPrev));
		}
	}

	function tryStmt(body:Array<Stmt>, catches:Array<{test:Null<Ex->Ex>, l:Local, body:Array<Stmt>}>) {
		var slot = f.slot(abi.handlerSize, abi.handlerAlign < 16 ? 16 : abi.handlerAlign);
		var h = stackAddr(slot);
		store(8, h, abi.handlerPrev, tlsLoad("rt_hcur"));
		store(8, h, abi.handlerSp, tlsLoad("rt_sp"));
		tlsStore("rt_hcur", h);
		var sj = mk(Call, I32);
		sj.sym = abi.setjmp;
		sj.args = abi.os == "windows" && !abi.arm ? [h, lconst(0, 0)] : [h];
		sj.argTys = [for (_ in sj.args) I64];
		sj.returnsTwice = true;
		var r = add(sj);
		var tb = newBlock(), hb = newBlock(), join = newBlock();
		hb.handler = true;
		br(cmp(CEq, r, iconst(0)), tb, hb);
		seal(tb);
		seal(hb);
		cur = tb;
		tries.push(slot);
		stmts(body);
		tries.pop();
		if (!terminated()) {
			var h2 = stackAddr(slot);
			tlsStore("rt_hcur", load(I64, 8, h2, abi.handlerPrev));
			jmp(join);
		}
		cur = hb;
		var h3 = stackAddr(slot);
		tlsStore("rt_hcur", load(I64, 8, h3, abi.handlerPrev));
		tlsStore("rt_sp", load(I64, 8, h3, abi.handlerSp));
		var exn = tlsLoad("rt_exn");
		for (c in catches)
			writeLocal(c.l, exn);
		tlsStore("rt_exn", lconst(0, 0));
		var catchAll = false;
		for (c in catches) {
			if (c.test == null) {
				stmts(c.body);
				jmp(join);
				catchAll = true;
				break;
			}
			var t = ex(c.test(ELocal(c.l)));
			var yes = newBlock(), no = newBlock();
			br(t, yes, no);
			seal(yes);
			seal(no);
			cur = yes;
			stmts(c.body);
			jmp(join);
			cur = no;
		}
		if (!catchAll) {
			call("rt_throw", [readLocal(catches[0].l)], Void, true);
			add(mk(Unreachable, Void));
		}
		seal(join);
		cur = join;
		if (join.preds.length == 0) add(mk(Unreachable, Void));
	}

	static function isNullConst(e:Ex):Bool
		return e.match(ENull(_));

	// ---- object slots

	function slotLoad(o:Int, loc:Int, t:Ty):Int
		return switch t {
			case TRef(_): loadM(Opt.MField, I64, 8, o, 8 * loc);
			case TF64: loadM(Opt.MField, F64, 8, o, 8 * loc);
			case TI64: loadM(Opt.MField, I64, 8, o, 8 * loc);
			case TVoid: iconst(0);
			case _: loadM(Opt.MField, I32, 4, o, 4 * loc);
		};

	// a store into a heap object; references go through the write barrier
	function storeSlot(o:Int, loc:Int, t:Ty, v:Int, isNull:Bool) {
		switch t {
			case TRef(_):
				if (isNull) storeM(Opt.MField, 8, o, 8 * loc, v) else setPtr(o, op2(Add, I64, o, lconst32(8 * loc)), v, Opt.MField);
			case TF64 | TI64: storeM(Opt.MField, 8, o, 8 * loc, v);
			case TVoid:
			case _: storeM(Opt.MField, 4, o, 4 * loc, v);
		}
	}

	// rt_set_ptr(obj, slot, val)
	function setPtr(obj:Int, slot:Int, val:Int, cls = 0) {
		var prev = loadM(cls, I64, 8, slot, 0);
		storeM(cls, 8, slot, 0, val);
		var ys = loadM(Opt.MCallOnly, I64, 8, symAddr("rt_young_start"), 0);
		var ye = loadM(Opt.MCallOnly, I64, 8, symAddr("rt_young_end"), 0);
		var size = op2(Sub, I64, ye, ys);
		var done = newBlock();
		var b2 = newBlock(), b3 = newBlock(), b4 = newBlock();
		b2.cold = true;
		b3.cold = true;
		b4.cold = true;
		// the object is not young
		br(cmp(CULt, op2(Sub, I64, obj, ys), size), done, b2);
		seal(b2);
		cur = b2;
		br(cmp(CULt, op2(Sub, I64, val, ys), size), b3, done);
		seal(b3);
		cur = b3;
		br(cmp(CULt, op2(Sub, I64, prev, ys), size), done, b4);
		seal(b4);
		cur = b4;
		call("rt_write_barrier", [obj, slot, val], Void);
		jmp(done);
		seal(done);
		cur = done;
	}

	function tindex(o:Int):Int
		return loadM(Opt.MConst, I32, 2, o, Abi.HDR_TINDEX);

	// ---- allocation

	static function hdrLo(nslots:Int, kind:Int):Int
		return nslots | (kind << 28);

	// an object of n slots: inline bump allocation; the slow path collects.
	// zero: clear the slots (rt_alloc); at a cold site the live references
	// are stored on the shadow stack around the slow call only
	function alloc(n:Int, tidx:Int, kind:Int, zero:Bool):Int {
		var bytes = 8 * (n + 1);
		var ptr = tlsLoad("rt_young_ptr");
		var lim = tlsLoad("rt_young_limit");
		var res = newVar(I64);
		var fast = newBlock(), slow = newBlock(), join = newBlock();
		slow.cold = true;
		br(cmp(CGe, op2(Sub, I64, lim, ptr), lconst32(bytes)), fast, slow);
		seal(fast);
		seal(slow);
		cur = fast;
		tlsStore("rt_young_ptr", op2(Add, I64, ptr, lconst32(bytes)));
		storeM(Opt.MInit, 4, ptr, 0, iconst(hdrLo(n, kind)));
		storeM(Opt.MInit, 4, ptr, 4, tyConst(tidx));
		var o = op2(Add, I64, ptr, lconst32(8));
		if (zero) {
			if (n <= 16) {
				var z = lconst(0, 0);
				for (k in 0...n)
					storeM(Opt.MInit, 8, o, 8 * k, z);
			} else call("memset", [o, iconst(0), lconst32(8 * n)], I64);
		}
		writeVar(res, cur, o);
		jmp(join);
		cur = slow;
		var list = coldList;
		var sp = spillOpen(list, 0);
		var hdr = op2(Or, I64, lconst(hdrLo(n, kind), 0), op2(Shl, I64, op1(ZExt, I64, tyConst(tidx)), iconst(32)));
		var r = call("rt_alloc_slow", [hdr, iconst(bytes)], I64);
		spillClose(list, sp);
		writeVar(res, cur, r);
		jmp(join);
		seal(join);
		cur = join;
		return readVar(res, cur);
	}

	// stores the cold site's references in a pushed area (null: none)
	function spillOpen(list:Null<Array<Local>>, extra:Int):Int {
		if (list == null || list.length + extra == 0) return -1;
		var sp = tlsLoad("rt_sp");
		var top = op2(Add, I64, sp, lconst32(8 * (list.length + extra)));
		tlsStore("rt_sp", top);
		var hw = tlsLoad("rt_sp_hw");
		var s = mk(Select, I64);
		s.a = cmp(CUGt, top, hw);
		s.b = top;
		s.c = hw;
		tlsStore("rt_sp_hw", add(s));
		for (k in 0...list.length)
			store(8, sp, 8 * k, readLocal(list[k]));
		return sp;
	}

	function spillClose(list:Null<Array<Local>>, sp:Int) {
		if (sp < 0) return;
		for (k in 0...list.length)
			writeLocal(list[k], load(I64, 8, sp, 8 * k));
		tlsStore("rt_sp", sp);
	}

	// ---- cold statements

	function coldStmt(s:Stmt) {
		switch s {
			case SSet(l, e):
				writeLocal(l, ex(e));
			case SArrSet(elem, a, i, v):
				arrSet(elem, a, i, v, true);
			case SArrPush(elem, a, v):
				arrPush(elem, a, v, true);
			case _:
				throw new Unsupported("cold statement");
		}
	}

	// ---- arrays

	static function arrKind(t:Ty):Int
		return switch t {
			case TI32 | TBool: Abi.AK_I32;
			case TF64: Abi.AK_F64;
			case TI64: Abi.AK_I64;
			case _: Abi.AK_PTR;
		};

	static function elemSize(t:Ty):Int
		return switch t {
			case TI32 | TBool: 4;
			case _: 8;
		};

	function bits64(t:Ty, v:Int):Int
		return switch t {
			case TF64: op1(FToBits, I64, v);
			case TI32 | TBool: op1(ZExt, I64, v);
			case _: v;
		};

	// the address of the slot holding array local `a` (rooted, or in the cold site's spill area)
	function arrSlot(a:Local, sp:Int, list:Null<Array<Local>>):Int {
		var s = refSlot.get(a);
		if (s != null) return op2(Add, I64, fr, lconst32(8 * s));
		if (sp < 0 || list == null || list.indexOf(a) < 0) throw new Unsupported("array local neither rooted nor spilled");
		return op2(Add, I64, sp, lconst32(8 * list.indexOf(a)));
	}

	function arrSet(elem:Ty, a:Local, i:Ex, v:Ex, cold:Bool) {
		var list = cold ? coldList : null;
		var iv = ex(i);
		var vv = ex(v);
		var av = readLocal(a);
		var k = arrKind(elem);
		var fast = newBlock(), slow = newBlock(), join = newBlock(), chk = newBlock();
		slow.cold = true;
		var kind = loadM(Opt.MHdr, I32, 4, av, 4);
		var len = loadM(Opt.MHdr, I32, 4, av, 0);
		var d = loadM(Opt.MHdr, I64, 8, av, 8);
		br(cmp(CEq, kind, iconst(k)), chk, slow);
		seal(chk);
		cur = chk;
		br(cmp(CULt, iv, len), fast, slow);
		seal(fast);
		seal(slow);
		cur = fast;
		var ix = op1(SExt, I64, iv);
		if (k == Abi.AK_PTR) {
			setPtr(d, op2(Add, I64, d, op2(Shl, I64, ix, iconst(3))), vv, Opt.MElem);
		} else storeM(Opt.MElem, elemSize(elem), d, 0, vv, ix, elemSize(elem));
		jmp(join);
		cur = slow;
		if (k == Abi.AK_PTR) {
			// the value is rooted in a pushed slot (after the spilled references)
			var n = list == null ? 0 : list.length;
			var sp = spillOpen(list == null ? [] : list, 1);
			store(8, sp, 8 * n, vv);
			call("hx_aset_slow", [arrSlot(a, sp, list), iv, iconst(k), op2(Add, I64, sp, lconst32(8 * n))], Void);
			spillClose(list == null ? [] : list, sp);
		} else {
			var sp = spillOpen(list, 0);
			call("hx_aset_slow", [arrSlot(a, sp, list), iv, iconst(k), bits64(elem, vv)], Void);
			spillClose(list, sp);
		}
		jmp(join);
		seal(join);
		cur = join;
	}

	function arrPush(elem:Ty, a:Local, v:Ex, cold:Bool) {
		var list = cold ? coldList : null;
		var vv = ex(v);
		var av = readLocal(a);
		var k = arrKind(elem);
		var fast = newBlock(), slow = newBlock(), join = newBlock(), c1 = newBlock(), c2 = newBlock();
		slow.cold = true;
		br(cmp(CEq, loadM(Opt.MHdr, I32, 4, av, 4), iconst(k)), c1, slow);
		seal(c1);
		cur = c1;
		var d = loadM(Opt.MHdr, I64, 8, av, 8);
		br(cmp(CNe, d, lconst(0, 0)), c2, slow);
		seal(c2);
		cur = c2;
		var len = loadM(Opt.MHdr, I32, 4, av, 0);
		var cap = op2(And, I32, loadM(Opt.MHdr, I32, 4, d, -8), iconst(0x0FFFFFFF));
		if (k == Abi.AK_I32) cap = op2(Shl, I32, cap, iconst(1));
		br(cmp(CULt, len, cap), fast, slow);
		seal(fast);
		seal(slow);
		cur = fast;
		var ix = op1(SExt, I64, len);
		if (k == Abi.AK_PTR) setPtr(d, op2(Add, I64, d, op2(Shl, I64, ix, iconst(3))), vv, Opt.MElem) else storeM(Opt.MElem, elemSize(elem), d, 0, vv, ix, elemSize(elem));
		storeM(Opt.MHdr, 4, av, 0, op2(Add, I32, len, iconst(1)));
		jmp(join);
		cur = slow;
		if (k == Abi.AK_PTR) {
			var n = list == null ? 0 : list.length;
			var sp = spillOpen(list == null ? [] : list, 1);
			store(8, sp, 8 * n, vv);
			call("hx_apush_slow", [arrSlot(a, sp, list), iconst(k), op2(Add, I64, sp, lconst32(8 * n))], I32);
			spillClose(list == null ? [] : list, sp);
		} else {
			var sp = spillOpen(list, 0);
			call("hx_apush_slow", [arrSlot(a, sp, list), iconst(k), bits64(elem, vv)], I32);
			spillClose(list, sp);
		}
		jmp(join);
		seal(join);
		cur = join;
	}

	function arrGet(elem:Ty, a:Ex, i:Ex, checked:Bool):Int {
		var av = ex(a);
		var iv = ex(i);
		var k = arrKind(elem);
		var t = mty(elem);
		var res = newVar(t);
		var fast = newBlock(), slow = newBlock(), join = newBlock();
		slow.cold = true;
		// the header is read before the checks (every array has one): later
		// accesses the first dominates reuse it (Opt)
		var kind = loadM(Opt.MHdr, I32, 4, av, 4);
		var len = checked ? loadM(Opt.MHdr, I32, 4, av, 0) : -1;
		var d = loadM(Opt.MHdr, I64, 8, av, 8);
		if (checked) {
			var chk = newBlock();
			br(cmp(CEq, kind, iconst(k)), chk, slow);
			seal(chk);
			cur = chk;
			br(cmp(CULt, iv, len), fast, slow);
		} else br(cmp(CEq, kind, iconst(k)), fast, slow);
		seal(fast);
		seal(slow);
		cur = fast;
		writeVar(res, cur, loadM(Opt.MElem, t, elemSize(elem), d, 0, false, op1(SExt, I64, iv), elemSize(elem)));
		jmp(join);
		cur = slow;
		var name = switch k {
			case Abi.AK_I32: "hx_aget_i_slow";
			case Abi.AK_F64: "hx_aget_f_slow";
			case Abi.AK_I64: "hx_aget_l_slow";
			case _: "hx_aget_p_slow";
		};
		writeVar(res, cur, call(name, [av, iv], t));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(res, cur);
	}

	// ---- structural access

	function icache():Int {
		var k = icaches++;
		return symAddr(icSym, Abi.IC_SIZE * k);
	}

	// rt_ic: the site's cache entry for the object's type (fid: a value)
	function ic(o:Int, fid:Int):Int {
		var c = icache();
		var res = newVar(I64);
		writeVar(res, cur, c);
		var miss = newBlock(), join = newBlock();
		miss.cold = true;
		br(cmp(CNe, load(I32, 4, c, 0), tindex(o)), miss, join);
		seal(miss);
		cur = miss;
		writeVar(res, cur, call("rt_icache_miss", [o, fid, c], I64));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(res, cur);
	}

	function kindMatch(c:Int, t:Ty):Int {
		var kind = load(I32, 1, c, Abi.IC_KIND);
		return switch t {
			case TI32 | TBool:
				var r = newVar(I32);
				writeVar(r, cur, cmp(CEq, kind, iconst("i".code)));
				var no = newBlock(), join = newBlock();
				br(readVar(r, cur), join, no);
				seal(no);
				cur = no;
				writeVar(r, cur, cmp(CEq, kind, iconst("b".code)));
				jmp(join);
				seal(join);
				cur = join;
				readVar(r, cur);
			case TF64: cmp(CEq, kind, iconst("f".code));
			case TI64: cmp(CEq, kind, iconst("l".code));
			case _: cmp(CEq, kind, iconst("p".code));
		}
	}

	function unboxTo(t:Ty, v:Int):Int
		return switch t {
			case TI32: call("hx_unbox_int", [v], I32);
			case TBool: call("hx_unbox_bool", [v], I32);
			case TF64: call("hx_unbox_float", [v], F64);
			case TI64: call("hx_unbox_i64", [v], I64);
			case _: v;
		};

	function boxFrom(t:Ty, v:Int):Int
		return switch t {
			case TI32: call("hx_box_int", [v], I64);
			case TBool: call("hx_box_bool", [v], I64);
			case TF64: call("hx_box_float", [v], I64);
			case TI64: call("hx_box_i64", [v], I64);
			case _: v;
		};

	// a field at a dynamic location (rt_icache.slot - 1)
	function slotLoadDyn(o:Int, loc:Int, t:Ty):Int {
		var ix = op1(SExt, I64, loc);
		return switch t {
			case TRef(_) | TI64: loadM(Opt.MField, I64, 8, o, 0, false, ix, 8);
			case TF64: loadM(Opt.MField, F64, 8, o, 0, false, ix, 8);
			case _: loadM(Opt.MField, I32, 4, o, 0, false, ix, 4);
		}
	}

	function anonGet(name:String, t:Ty, obj:Ex, hint:Null<ShapeInfo>):Int {
		var o = ex(obj);
		var fid = fidConst(name);
		var mt = mty(t);
		var res = newVar(mt);
		var join = newBlock();
		if (hint != null && hint.tindex >= 0) {
			var direct = newBlock(), other = newBlock();
			other.cold = false;
			br(cmp(CEq, tindex(o), tyConst(hint.tindex)), direct, other);
			seal(direct);
			seal(other);
			cur = direct;
			var i = hint.slot(name) - 1;
			writeVar(res, cur, slotLoad(o, hint.locs[i], t));
			jmp(join);
			cur = other;
		}
		var c = ic(o, fid);
		var hit = newBlock(), miss = newBlock(), chk = newBlock();
		miss.cold = true;
		var slot = load(I32, 4, c, Abi.IC_SLOT);
		br(cmp(CGt, slot, iconst(0)), chk, miss);
		seal(chk);
		cur = chk;
		br(kindMatch(c, t), hit, miss);
		seal(hit);
		seal(miss);
		cur = hit;
		writeVar(res, cur, slotLoadDyn(o, op2(Sub, I32, slot, iconst(1)), t));
		jmp(join);
		cur = miss;
		writeVar(res, cur, unboxTo(t, call("hx_anon_get_slow", [o, fid], I64)));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(res, cur);
	}

	function anonSet(name:String, t:Ty, obj:Ex, v:Ex) {
		var o = ex(obj);
		var fid = fidConst(name);
		var c = ic(o, fid);
		var hit = newBlock(), miss = newBlock(), chk = newBlock(), join = newBlock();
		miss.cold = true;
		var slot = load(I32, 4, c, Abi.IC_SLOT);
		br(cmp(CGt, slot, iconst(0)), chk, miss);
		seal(chk);
		cur = chk;
		br(kindMatch(c, t), hit, miss);
		seal(hit);
		seal(miss);
		cur = hit;
		var x = ex(v);
		var loc = op1(SExt, I64, op2(Sub, I32, slot, iconst(1)));
		switch t {
			case TRef(_): setPtr(o, op2(Add, I64, o, op2(Shl, I64, loc, iconst(3))), x, Opt.MField);
			case TF64 | TI64: storeM(Opt.MField, 8, o, 0, x, loc, 8);
			case _: storeM(Opt.MField, 4, o, 0, x, loc, 4);
		}
		jmp(join);
		cur = miss;
		// C: the value is boxed, then the object expression evaluated again
		var b = boxFrom(t, ex(v));
		call("hx_anon_set_slow", [ex(obj), fidConst(name), b], Void);
		jmp(join);
		seal(join);
		cur = join;
	}

	// ---- expressions

	function ex(e:Ex):Int {
		return switch e {
			case EInt(v): iconst(v);
			case EF64(v): fconst(v);
			case EStr(s): symAddr(p.strSym(s), 8);
			case ENull(_): lconst(0, 0);
			case ELocal(l): readLocal(l);
			case EGlobal(g, t):
				if (Ir.isRef(t)) loadM(Opt.MGlobal, I64, 8, globalAddr(g), 0) else {
					var mt = mty(t);
					loadM(Opt.MGlobal, mt, mt == I32 ? 4 : 8, symAddr(p.scalarGlobalSym(g)), 0);
				}
			case EBin(op, x, y): bin(op, x, y);
			case ENot(x): cmp(CEq, ex(x), iconst(0));
			case EConv(c, x): conv(c, ex(x));
			case EBox(t, x): boxFrom(t, ex(x));
			case EUnbox(t, x): unboxTo(t, ex(x));
			case EField(c, idx, obj): slotLoad(ex(obj), c.locs[idx], c.fields[idx].ty);
			case EAnonGet(name, t, obj, hint): anonGet(name, t, obj, hint);
			case ECast(_, x): ex(x);
			case EInstOf(c, x): instOf(ex(x), c);
			case EEnumTag(x, en):
				var base:Null<Int> = en == null || en.ctors.length == 0 ? null : en.ctors[0].tindex - en.ctors[0].tag;
				if (base != null)
					for (c in en.ctors)
						if (c.tindex - c.tag != base) base = null;
				var o = ex(x);
				if (base != null) op2(Sub, I32, tindex(o), tyConst(en.ctors[0].tindex, -en.ctors[0].tag)) else {
					var ti = op1(ZExt, I64, tindex(o));
					loadM(Opt.MConst, I32, 4, symAddr("rt_types"), Abi.TYPE_TAG, false, op2(Mul, I64, ti, lconst32(Abi.TYPE_SIZE)), 1);
				}
			case EEnumParam(c, idx, x): slotLoad(ex(x), at(idx, c.params[idx]), c.params[idx]);
			case EArrLen(a): loadM(Opt.MHdr, I32, 4, ex(a), 0);
			case EArrGet(elem, a, i): arrGet(elem, a, i, true);
			case EArrGetU(elem, a, i): arrGet(elem, a, i, false);
			case EBoxGet(t, bx): slotLoad(ex(bx), 0, t);
			case ECapture(l, idx, clos): slotLoad(ex(clos), at(idx + 1, l.captures[idx].ty), l.captures[idx].ty);
			case EType(t): symAddr(p.typeObjSym(typeIndex(t)));
			case ECall(g, args):
				var xs = [for (a in args) ex(a)];
				var c = mk(Call, mty(g.ret));
				c.sym = p.funcSym(g);
				c.args = xs;
				c.argTys = [for (a in g.args) mty(a.ty) == Void ? I32 : mty(a.ty)];
				add(c);
			case ECallDispatch(sel, sig, args):
				var xs = [for (a in args) ex(a)];
				var o = xs[0];
				var row = symAddr(p.selectorSym(sel));
				var ti = op1(ZExt, I64, tindex(o));
				var fp = load(I64, 8, row, -8 * Abi.T_FIRST, false, ti, 8);
				callInd(fp, xs, mty(sig.ret), [for (t in sig.args) mty(t)]);
			case ECallClos(s, clos, args):
				var c = ex(clos);
				var xs = [for (a in args) ex(a)];
				var fp = load(I64, 8, c, 0);
				callInd(fp, [c].concat(xs), mty(s.ret), [I64].concat([for (t in s.args) mty(t)]));
			case ECallAnon(name, s, obj, args): callAnon(name, s, obj, args);
			case ECallHost(name, args, ret): host(name, args, ret);
			case ENewObj(c): alloc(c.nslots < 1 ? 1 : c.nslots, c.tindex, Abi.K_OBJ, true);
			case ENewEnum(c, args):
				var n = c.params.length == 0 ? 1 : c.params.length;
				var o = alloc(n, c.tindex, Abi.K_OBJ, false);
				if (c.params.length == 0) storeM(Opt.MInit, 8, o, 0, lconst(0, 0));
				for (i in 0...args.length) {
					if (c.params[i].match(TI32 | TBool)) storeM(Opt.MInit, 8, o, 8 * i, lconst(0, 0));
					storeInit(o, at(i, c.params[i]), c.params[i], ex(args[i]));
				}
				o;
			case ENewArr(elem, vs): newArr(elem, vs);
			case ENewClos(l, caps):
				var o = alloc(l.captures.length + 1, l.tindex, Abi.K_OBJ, false);
				storeM(Opt.MInit, 8, o, 0, symAddr(p.funcSym(l.fn)));
				for (i in 0...caps.length)
					storeInit(o, at(i + 1, l.captures[i].ty), l.captures[i].ty, ex(caps[i]));
				o;
			case ENewBox(t, v):
				var tt = switch t {
					case TF64 | TI64: Abi.T_REFBOX_F;
					case TI32 | TBool: Abi.T_REFBOX_I;
					case _: Abi.T_REFBOX_P;
				};
				var o = alloc(1, tt, Abi.K_OBJ, false);
				storeM(Opt.MInit, 8, o, 0, lconst(0, 0));
				storeInit(o, 0, t, ex(v));
				o;
			case ENewAnon(sh, vals):
				var o = alloc(sh.nslots, sh.tindex, Abi.K_OBJ, true);
				for (i in 0...vals.length)
					storeInit(o, sh.locs[i], sh.fields[i].ty, ex(vals[i]));
				o;
		}
	}

	// a store into a new (young) object: no barrier (C writes these slots plainly)
	function storeInit(o:Int, loc:Int, t:Ty, v:Int) {
		switch t {
			case TRef(_) | TF64 | TI64: storeM(Opt.MInit, 8, o, 8 * loc, v);
			case TVoid:
			case _: storeM(Opt.MInit, 4, o, 4 * loc, v);
		}
	}

	static function at(slot:Int, t:Ty):Int
		return t.match(TI32 | TBool) ? 2 * slot : slot;

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
		};

	// hx_inst(o, lo, hi): o && KIND(o) == K_OBJ && lo <= TINDEX(o) <= hi
	function instOf(o:Int, c:ClassInfo):Int {
		var r = newVar(I32);
		writeVar(r, cur, iconst(0));
		var nn = newBlock(), join = newBlock();
		br(cmp(CNe, o, lconst(0, 0)), nn, join);
		seal(nn);
		cur = nn;
		var kind = op2(And, I32, op2(Shr, I32, load(I32, 4, o, -8), iconst(28)), iconst(15));
		var k2 = newBlock();
		br(cmp(CEq, kind, iconst(Abi.K_OBJ)), k2, join);
		seal(k2);
		cur = k2;
		var t = tindex(o);
		// lo <= t <= hi as one unsigned comparison
		writeVar(r, cur, cmp(CULe, op2(Sub, I32, t, tyConst(c.tindex)), idConst(p.spanSym(c), 0)));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(r, cur);
	}

	function newArr(elem:Ty, vs:Array<Ex>):Int {
		var k = arrKind(elem);
		var o:Int;
		if (vs.length == 0) {
			o = alloc(2, Abi.T_ARRAY, Abi.K_OBJ, true);
			storeM(Opt.MInit, 4, o, 4, iconst(k));
			return o;
		}
		o = call("hx_arr_new_n", [iconst(k), iconst(vs.length)], I64);
		for (i in 0...vs.length) {
			var d = loadM(Opt.MHdr, I64, 8, o, 8);
			var v = ex(vs[i]);
			switch elem {
				case TF64 | TI64: storeM(Opt.MElem, 8, d, 8 * i, v);
				case TI32 | TBool: storeM(Opt.MElem, 4, d, 4 * i, v);
				case _: setPtr(d, op2(Add, I64, d, lconst32(8 * i)), v, Opt.MElem);
			}
		}
		return o;
	}

	function bin(op:BinOp, x:Ex, y:Ex):Int {
		var a = ex(x), b = ex(y);
		return switch op {
			case Add: op2(Add, I32, a, b);
			case Sub: op2(Sub, I32, a, b);
			case Mul: op2(Mul, I32, a, b);
			case Mod: imod(a, b, I32);
			case And: op2(And, I32, a, b);
			case Or: op2(Or, I32, a, b);
			case Xor: op2(Xor, I32, a, b);
			case Shl: op2(Shl, I32, a, b);
			case Shr: op2(Sar, I32, a, b);
			case UShr: op2(Shr, I32, a, b);
			case Eq | RefEq | LEq: cmp(CEq, a, b);
			case Ne | RefNe | LNe: cmp(CNe, a, b);
			case Lt | LLt: cmp(CLt, a, b);
			case Le | LLe: cmp(CLe, a, b);
			case Gt | LGt: cmp(CGt, a, b);
			case Ge | LGe: cmp(CGe, a, b);
			case FEq: cmp(FEq, a, b);
			case FNe: cmp(FNe, a, b);
			case FLt: cmp(FLt, a, b);
			case FLe: cmp(FLe, a, b);
			case FGt: cmp(FGt, a, b);
			case FGe: cmp(FGe, a, b);
			case FAdd: op2(FAdd, F64, a, b);
			case FSub: op2(FSub, F64, a, b);
			case FMul: op2(FMul, F64, a, b);
			case FDiv: op2(FDiv, F64, a, b);
			case FMod: call("fmod", [a, b], F64);
			case LAdd: op2(Add, I64, a, b);
			case LSub: op2(Sub, I64, a, b);
			case LMul: op2(Mul, I64, a, b);
			case LDiv: ldiv(a, b);
			case LMod: imod(a, b, I64);
			case LAnd: op2(And, I64, a, b);
			case LOr: op2(Or, I64, a, b);
			case LXor: op2(Xor, I64, a, b);
			case LShl: op2(Shl, I64, a, op1(SExt, I64, b));
			case LShr: op2(Sar, I64, a, op1(SExt, I64, b));
			case LUShr: op2(Shr, I64, a, op1(SExt, I64, b));
		}
	}

	function constOf(v:Int):Null<Int> {
		var i = f.vals[v];
		return i.op == Const && i.ty == I32 ? i.imm : null;
	}

	// IMOD (Int): b == 0 or b == -1 give 0; hx_lmod (Int64): b == -1 gives 0
	function imod(a:Int, b:Int, t:MTy):Int {
		var c = t == I32 ? constOf(b) : null;
		if (c != null && c != 0 && c != -1) return op2(Rem, t, a, b);
		var r = newVar(t);
		writeVar(r, cur, t == I32 ? iconst(0) : lconst(0, 0));
		var b1 = newBlock(), b2 = newBlock(), join = newBlock();
		var zero = t == I32 ? iconst(0) : lconst(0, 0);
		var m1 = t == I32 ? iconst(-1) : lconst(-1, -1);
		if (t == I32) {
			br(cmp(CNe, b, zero), b1, join);
			seal(b1);
			cur = b1;
		} else {
			jmp(b1);
			seal(b1);
			cur = b1;
		}
		br(cmp(CNe, b, m1), b2, join);
		seal(b2);
		cur = b2;
		writeVar(r, cur, op2(Rem, t, a, b));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(r, cur);
	}

	// hx_ldiv: b == -1 gives -a (no overflow trap)
	function ldiv(a:Int, b:Int):Int {
		var r = newVar(I64);
		var neg = newBlock(), div = newBlock(), join = newBlock();
		br(cmp(CEq, b, lconst(-1, -1)), neg, div);
		seal(neg);
		seal(div);
		cur = neg;
		writeVar(r, cur, op1(Neg, I64, a));
		jmp(join);
		cur = div;
		writeVar(r, cur, op2(Div, I64, a, b));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(r, cur);
	}

	function conv(c:ConvOp, x:Int):Int {
		return switch c {
			case I2F: op1(I2F, F64, x);
			case F2I: f2i(x);
			case FNeg: op1(FNeg, F64, x);
			case I2L: op1(SExt, I64, x);
			case L2I: op1(Trunc, I32, x);
			case L2F: op1(I2F, F64, x);
			case F2L: f2l(x);
			case LNeg: op1(Neg, I64, x);
		}
	}

	// hx_f2i: truncation in range, else hx_f2i_slow (NaN 0, wrapping)
	function f2i(x:Int):Int {
		var r = newVar(I32);
		var c2 = newBlock(), fast = newBlock(), slow = newBlock(), join = newBlock();
		slow.cold = true;
		br(cmp(FGt, x, fconst(-2147483649.0)), c2, slow);
		seal(c2);
		cur = c2;
		br(cmp(FLt, x, fconst(2147483648.0)), fast, slow);
		seal(fast);
		seal(slow);
		cur = fast;
		writeVar(r, cur, op1(F2I, I32, x));
		jmp(join);
		cur = slow;
		writeVar(r, cur, call("hx_f2i_slow", [x], I32));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(r, cur);
	}

	// hx_f2l: NaN 0, saturating
	function f2l(x:Int):Int {
		var r = newVar(I64);
		writeVar(r, cur, lconst(0, 0));
		var notNan = newBlock(), notBig = newBlock(), big = newBlock(), small = newBlock(), mid = newBlock(), join = newBlock();
		br(cmp(FEq, x, x), notNan, join);
		seal(notNan);
		cur = notNan;
		br(cmp(FGe, x, fconst(9223372036854775808.0)), big, notBig);
		seal(big);
		seal(notBig);
		cur = big;
		writeVar(r, cur, lconst(-1, 0x7fffffff));
		jmp(join);
		cur = notBig;
		br(cmp(FLt, x, fconst(-9223372036854775808.0)), small, mid);
		seal(small);
		seal(mid);
		cur = small;
		writeVar(r, cur, lconst(0, 0x80000000));
		jmp(join);
		cur = mid;
		writeVar(r, cur, op1(F2I, I64, x));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(r, cur);
	}

	function host(name:String, args:Array<Ex>, ret:Ty):Int {
		// Dynamic access by a literal name: the field id is known here
		switch name {
			case "hx_dyn_get" | "hx_dyn_set" | "hx_dyn_call_field" if (args[1].match(EStr(_))):
				var n = switch args[1] {
					case EStr(n): n;
					case _: null;
				};
				var xs = [for (i in 0...args.length) i == 1 ? fidConst(n) : ex(args[i])];
				return call(name + "_fid", xs, mty(ret));
			case _:
		}
		var xs = [for (a in args) ex(a)];
		inline function f1(fn:String):Int
			return call(fn, [xs[0]], F64);
		return switch name {
			case "String_length": loadM(Opt.MConst, I32, 4, xs[0], 0);
			case "String_charCodeAt_i":
				var r = newVar(I32);
				writeVar(r, cur, iconst(0));
				var ok = newBlock(), join = newBlock();
				br(cmp(CULt, xs[1], load(I32, 4, xs[0], 0)), ok, join);
				seal(ok);
				cur = ok;
				writeVar(r, cur, load(I32, 2, xs[0], 8, false, op1(SExt, I64, xs[1]), 2));
				jmp(join);
				seal(join);
				cur = join;
				readVar(r, cur);
			case "hx_str_eq": strEq(xs[0], xs[1]);
			case "Math_NaN": fconst(Math.NaN);
			case "Math_POSITIVE_INFINITY": fconst(Math.POSITIVE_INFINITY);
			case "Math_NEGATIVE_INFINITY": fconst(Math.NEGATIVE_INFINITY);
			case "Math_PI": fconst(3.141592653589793);
			case "Math_abs": op1(FAbs, F64, xs[0]);
			case "Math_sqrt": op1(FSqrt, F64, xs[0]);
			case "Math_acos": f1("acos");
			case "Math_asin": f1("asin");
			case "Math_atan": f1("atan");
			case "Math_cos": f1("cos");
			case "Math_sin": f1("sin");
			case "Math_tan": f1("tan");
			case "Math_exp": f1("exp");
			case "Math_log": f1("log");
			case "Math_atan2": call("atan2", [xs[0], xs[1]], F64);
			case "Math_pow": call("pow", [xs[0], xs[1]], F64);
			case "Math_floor": f2i(f1("floor"));
			case "Math_ceil": f2i(f1("ceil"));
			case "Math_round": f2i(call("floor", [op2(FAdd, F64, xs[0], fconst(0.5))], F64));
			case "Math_ffloor": f1("floor");
			case "Math_fceil": f1("ceil");
			case "Math_fround": call("floor", [op2(FAdd, F64, xs[0], fconst(0.5))], F64);
			case "Math_max" | "Math_min":
				var r = newVar(F64);
				writeVar(r, cur, fconst(Math.NaN));
				var c1 = newBlock(), c2 = newBlock(), join = newBlock();
				br(cmp(FEq, xs[0], xs[0]), c1, join);
				seal(c1);
				cur = c1;
				br(cmp(FEq, xs[1], xs[1]), c2, join);
				seal(c2);
				cur = c2;
				var pick = newBlock(), other = newBlock();
				br(cmp(name == "Math_max" ? FGt : FLt, xs[0], xs[1]), pick, other);
				seal(pick);
				seal(other);
				cur = pick;
				writeVar(r, cur, xs[0]);
				jmp(join);
				cur = other;
				writeVar(r, cur, xs[1]);
				jmp(join);
				seal(join);
				cur = join;
				readVar(r, cur);
			case "Math_isNaN": cmp(FNe, xs[0], xs[0]);
			case "Math_isFinite": cmp(FEq, op2(FSub, F64, xs[0], xs[0]), fconst(0));
			case "StringBuf_addChar": stringBufAddChar(xs[0], xs[1]);
			case _: call(name, xs, mty(ret));
		}
	}

	function strEq(a:Int, b:Int):Int {
		var r = newVar(I32);
		writeVar(r, cur, iconst(1));
		var ne = newBlock(), c2 = newBlock(), c3 = newBlock(), slow = newBlock(), join = newBlock();
		br(cmp(CEq, a, b), join, ne);
		seal(ne);
		cur = ne;
		writeVar(r, cur, iconst(0));
		br(cmp(CEq, a, lconst(0, 0)), join, c2);
		seal(c2);
		cur = c2;
		br(cmp(CEq, b, lconst(0, 0)), join, c3);
		seal(c3);
		cur = c3;
		br(cmp(CEq, load(I32, 4, a, 0), load(I32, 4, b, 0)), slow, join);
		seal(slow);
		cur = slow;
		writeVar(r, cur, call("hx_str_eq_slow", [a, b], I32));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(r, cur);
	}

	// StringBuf_addChar (rt.h): the common case inline
	function stringBufAddChar(b:Int, c:Int):Int {
		var len = load(I32, 4, b, 0);
		var d = load(I64, 8, b, 8);
		var c2 = newBlock(), fast = newBlock(), slow = newBlock(), join = newBlock();
		slow.cold = true;
		br(cmp(CULt, c, iconst(0x10000)), c2, slow);
		seal(c2);
		cur = c2;
		var cap = op2(Shl, I32, op2(And, I32, load(I32, 4, d, -8), iconst(0x0FFFFFFF)), iconst(2));
		br(cmp(CULt, len, cap), fast, slow);
		seal(fast);
		seal(slow);
		cur = fast;
		store(2, d, 0, c, op1(SExt, I64, len), 2);
		store(4, b, 0, op2(Add, I32, len, iconst(1)));
		jmp(join);
		cur = slow;
		call("StringBuf_addChar_slow", [b, c], Void);
		jmp(join);
		seal(join);
		cur = join;
		return iconst(0);
	}

	function callAnon(name:String, s:SigInfo, obj:Ex, args:Array<Ex>):Int {
		var o = ex(obj);
		var xs = [for (a in args) ex(a)];
		var fid = fidConst(name);
		var rt = mty(s.ret);
		var argTys = [for (t in s.args) mty(t)];
		var res = rt == Void ? -1 : newVar(rt);
		var c = ic(o, fid);
		var join = newBlock();
		var m1 = newBlock(), meth = newBlock(), notMeth = newBlock();
		// a method of the object's class with the call's signature
		var slot = load(I32, 4, c, Abi.IC_SLOT);
		br(cmp(CEq, slot, iconst(0)), m1, notMeth);
		seal(m1);
		cur = m1;
		br(cmp(CEq, load(I32, 4, c, Abi.IC_SIG), sigConst(s)), meth, notMeth);
		seal(meth);
		seal(notMeth);
		cur = meth;
		var r = callInd(load(I64, 8, c, Abi.IC_FN), [o].concat(xs), rt, [I64].concat(argTys));
		if (res >= 0) writeVar(res, cur, r);
		jmp(join);
		// a closure in a field
		cur = notMeth;
		var c1 = newBlock(), c2 = newBlock(), clos = newBlock(), slow = newBlock();
		slow.cold = true;
		br(cmp(CGt, slot, iconst(0)), c1, slow);
		seal(c1);
		cur = c1;
		br(cmp(CEq, load(I32, 1, c, Abi.IC_KIND), iconst("p".code)), c2, slow);
		seal(c2);
		cur = c2;
		var k = load(I64, 8, o, 0, false, op1(SExt, I64, op2(Sub, I32, slot, iconst(1))), 8);
		br(isSig(k, s), clos, slow);
		seal(clos);
		seal(slow);
		cur = clos;
		var r2 = callInd(load(I64, 8, k, 0), [k].concat(xs), rt, [I64].concat(argTys));
		if (res >= 0) writeVar(res, cur, r2);
		jmp(join);
		// the slow path: arguments packed in 8-byte words
		cur = slow;
		var n = xs.length == 0 ? 1 : xs.length;
		var area = f.slot(8 * n, 8);
		var av = stackAddr(area);
		if (xs.length == 0) store(8, av, 0, lconst(0, 0));
		for (i in 0...xs.length)
			store(8, av, 8 * i, switch s.args[i] {
				case TF64: op1(FToBits, I64, xs[i]);
				case TI32 | TBool: op1(ZExt, I64, xs[i]);
				case _: xs[i];
			});
		var u = call("hx_anon_call_slow", [o, fid, sigConst(s), av], I64);
		if (res >= 0) writeVar(res, cur, switch s.ret {
			case TF64: op1(BitsToF, F64, u);
			case TI32 | TBool: op1(Trunc, I32, u);
			case _: u;
		});
		jmp(join);
		seal(join);
		cur = join;
		return res >= 0 ? readVar(res, cur) : iconst(0);
	}

	// hx_is_sig(c, sig): a closure (TK_CLOSURE or TK_BOUND) of that signature
	function isSig(k:Int, s:SigInfo):Int {
		var r = newVar(I32);
		writeVar(r, cur, iconst(0));
		var nn = newBlock(), c2 = newBlock(), join = newBlock();
		br(cmp(CNe, k, lconst(0, 0)), nn, join);
		seal(nn);
		cur = nn;
		var ti = op1(ZExt, I64, tindex(k));
		var te = op2(Add, I64, symAddr("rt_types"), op2(Mul, I64, ti, lconst32(Abi.TYPE_SIZE)));
		var tk = load(I32, 1, te, 8);
		// TK_CLOSURE = 6, TK_BOUND = 7
		br(cmp(CULe, op2(Sub, I32, tk, iconst(6)), iconst(1)), c2, join);
		seal(c2);
		cur = c2;
		writeVar(r, cur, cmp(CEq, load(I32, 4, te, 12), sigConst(s)));
		jmp(join);
		seal(join);
		cur = join;
		return readVar(r, cur);
	}
}

// the values of SSA variables at the end of a block (Braun et al.'s
// currentDef for one block): few entries, a linear list
class BlockDefs {
	var keys:Array<Int> = [];
	var vals:Array<Int> = [];

	public function new() {}

	public function get(v:Int):Null<Int> {
		var k = keys.length;
		while (k-- > 0)
			if (keys[k] == v) return vals[k];
		return null;
	}

	public function set(v:Int, val:Int) {
		var k = keys.length;
		while (k-- > 0)
			if (keys[k] == v) {
				vals[k] = val;
				return;
			}
		keys.push(v);
		vals.push(val);
	}
}

class Unsupported {
	public var msg:String;

	public function new(msg)
		this.msg = msg;

	public function toString()
		return msg;
}
