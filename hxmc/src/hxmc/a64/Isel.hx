package hxmc.a64;

import hxmc.Mir;
import hxmc.Lir;

// AArch64 LIR operations (LIns.op)
enum abstract AOp(Int) to Int from Int {
	var MOV; // d <- s1 (size 4: a 32-bit move, zero-extending)
	var MOVI; // d <- imm (imm2: high half), or the absolute symbol isym + imm
	var MOVF; // d (fpr) <- f
	var LEA; // d <- address (sym, frame slot, base + disp)
	var LOAD; // d <- [mem] (size; flag: sign-extend)
	var STORE; // [mem] <- s1 (31: the zero register)
	var ALU; // d <- s1 (cond: 0 add, 1 sub, 2 and, 3 orr, 4 eor) s2
	var ALUI; // d <- s1 op imm
	var ADDSH; // d <- s1 + (s2 << imm)
	var MUL;
	var SDIV;
	var MSUB; // d <- s3 - s1 * s2
	var SHIFT; // d <- s1 (cond: 2 lsl, 3 lsr, 4 asr) s2
	var SHIFTI; // d <- s1 op imm
	var NEG;
	var MVN;
	var SXTW;
	var CMP; // flags <- s1 - s2
	var CMPI; // flags <- s1 - imm (or the symbol isym)
	var FCMP;
	var CSET; // d <- cond
	var CSEL; // d <- cond ? s1 : s2
	var FOP2; // d <- s1 (cond: 0 fmul, 1 fdiv, 2 fadd, 3 fsub) s2
	var FOP1; // d <- (cond: 1 fabs, 2 fneg, 3 fsqrt) s1
	var SCVTF; // d (fpr) <- s1 (size)
	var FCVTZS; // d <- s1 (fpr), truncating (size)
	var FMOVTOG; // d <- bits of s1 (fpr)
	var FMOVFROMG; // d (fpr) <- bits of s1
	var CALL; // sym, or s1; uses: argument registers
	var RET;
	var B; // target
	var BCOND; // cond -> target
	var CBZ; // s1 == 0 -> target (flag: cbnz); size
	var JTABLE; // s1: index (in range), table
	var TLSLOAD; // d <- thread-local sym
	var TLSSTORE; // thread-local sym <- s1
	var BRK;
}

// Mir -> LIR for AArch64 (AAPCS64). x16/x17 are the emitter's scratch
// registers and x18 is the platform register: none of them is allocated.
class Isel implements hxmc.Target.Selector {
	public var gprs(default, null):Array<Int>;
	public var fprs(default, null):Array<Int>;

	public static inline var ZR = 31;
	static inline var D0 = 32;

	public static var ARG_GPRS = [0, 1, 2, 3, 4, 5, 6, 7];
	public static var CALLER_SAVED = [
		0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 32, 33, 34, 35, 36, 37, 38, 39, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62,
		63
	];
	public static var CALLEE_SAVED = [19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 40, 41, 42, 43, 44, 45, 46, 47];

	var apple:Bool;
	var m:MFunc;
	var f:LFunc;
	var vreg:Array<Int>;
	var useCount:Array<Int>;
	var lb:Array<LBlock>;
	var cur:LBlock;
	var folded:Array<Bool>;

	public function new(apple:Bool) {
		this.apple = apple;
		gprs = [9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28];
		fprs = [32, 33, 34, 35, 36, 37, 38, 39, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 40, 41, 42, 43, 44, 45, 46, 47];
	}

	// ---- RegTarget

	public function defsUses(i:LIns, defs:hxmc.Regalloc.RegList, uses:hxmc.Regalloc.RegList) {
		inline function u(r:Int)
			if (r >= 0 && r != ZR) uses.push(r);
		inline function mem() {
			if (i.base >= 0) u(i.base);
			if (i.index >= 0) u(i.index);
		}
		switch (i.op : AOp) {
			case MOV | NEG | MVN | SXTW | FOP1 | SCVTF | FCVTZS | FMOVTOG | FMOVFROMG | SHIFTI | ALUI:
				defs.push(i.d);
				u(i.s1);
			case MOVI | MOVF | CSET | TLSLOAD:
				defs.push(i.d);
			case LEA | LOAD:
				defs.push(i.d);
				mem();
			case STORE:
				u(i.s1);
				mem();
			case ALU | ADDSH | MUL | SDIV | SHIFT | FOP2 | CSEL:
				defs.push(i.d);
				u(i.s1);
				u(i.s2);
			case MSUB:
				defs.push(i.d);
				u(i.s1);
				u(i.s2);
				u(i.s3);
			case CMP | FCMP:
				u(i.s1);
				u(i.s2);
			case CMPI | CBZ | JTABLE | TLSSTORE:
				u(i.s1);
			case CALL:
				if (i.s1 >= 0) uses.push(i.s1);
				for (x in i.uses)
					uses.push(x);
				for (r in CALLER_SAVED)
					defs.push(r);
			case RET:
				if (i.uses != null) for (x in i.uses)
					uses.push(x);
			case B | BCOND | BRK:
		}
	}

	public function isMove(i:LIns):Bool
		return i.op == MOV;

	public var callResults(default, null):Array<Int> = [0, 32];

	public function isCall(i:LIns):Bool
		return i.op == CALL;

	public function spillLoad(r:Int, slot:Int, float:Bool):LIns {
		var i = new LIns(LOAD);
		i.d = r;
		i.base = LIns.FRAME;
		i.slot = slot;
		i.size = 8;
		return i;
	}

	public function spillStore(slot:Int, r:Int, float:Bool):LIns {
		var i = new LIns(STORE);
		i.s1 = r;
		i.base = LIns.FRAME;
		i.slot = slot;
		i.size = 8;
		return i;
	}

	// ---- selection

	var pending:Null<LIns>;

	function emit(op:AOp):LIns {
		flush();
		pending = new LIns(op);
		return pending;
	}

	function flush() {
		if (pending != null) {
			cur.ins.push(pending);
			pending = null;
		}
	}

	function push(i:LIns)
		cur.ins.push(i);

	inline function sz(t:MTy):Int
		return t == I32 ? 4 : 8;

	function reg(v:Int):Int {
		var r = vreg[v];
		if (r < 0) {
			r = f.newReg(m.vals[v].ty == F64);
			vreg[v] = r;
		}
		return r;
	}

	// an operand where the zero register can stand for 0 (store values, the
	// second operand of register operations, csel)
	function useZ(v:Int):Int {
		var i = m.vals[v];
		if (folded[v] && i.op == Const && i.sym == null && i.imm == 0 && (i.ty == I32 || i.imm2 == 0)) return ZR;
		return use(v);
	}

	function use(v:Int):Int {
		if (folded[v]) {
			var i = m.vals[v];
			var r = f.newReg(i.ty == F64);
			materialize(i, r);
			return r;
		}
		return reg(v);
	}

	function mov(d:Int, s:Int, size = 8) {
		if (d == s) return;
		var i = emit(MOV);
		i.d = d;
		i.s1 = s;
		i.size = size;
		if (d >= LFunc.NPHYS) f.setHint(d, s);
		if (s >= LFunc.NPHYS) f.setHint(s, d);
	}

	function isymOf(v:Int):Null<String> {
		var i = m.vals[v];
		return i.op == Const ? i.sym : null;
	}

	// a plain constant that fits in 32 bits (sign-extended for 64-bit values)
	function immOf(v:Int):Null<Int> {
		var i = m.vals[v];
		if (i.op != Const || i.sym != null) return null;
		if (i.ty == I32) return i.imm;
		if (i.imm2 == (i.imm < 0 ? -1 : 0)) return i.imm;
		return null;
	}

	static inline function addImm(v:Int):Bool
		return v >= -4095 && v <= 4095;

	public function select(mf:MFunc, layout:Array<MBlock>):LFunc {
		m = mf;
		f = new LFunc(mf.name, 32);
		for (s in mf.slots)
			f.slot(s.size, s.align);
		vreg = hxmc.Lir.Arrays.filled(mf.vals.length, -1);
		useCount = hxmc.Lir.Arrays.filled(mf.vals.length, 0);
		folded = [for (_ in mf.vals) false];
		for (b in mf.blocks)
			for (i in b.ins) {
				for (x in [i.a, i.b, i.c])
					if (x >= 0) useCount[x]++;
				if (i.args != null) for (x in i.args)
					useCount[x]++;
			}
		for (b in mf.blocks)
			for (i in b.ins)
				if (i.op == Const || i.op == SymAddr || i.op == StackAddr) folded[i.id] = true;
		lb = [];
		var maxId = 0;
		for (b in mf.blocks)
			if (b.id >= maxId) maxId = b.id + 1;
		for (_ in 0...maxId)
			lb.push(null);
		for (b in layout) {
			var l = new LBlock(f.blocks.length);
			l.cold = b.cold;
			lb[b.id] = l;
			f.blocks.push(l);
		}
		for (bi in 0...layout.length) {
			var b = layout[bi];
			cur = lb[b.id];
			var next = bi + 1 < layout.length ? layout[bi + 1] : null;
			for (i in b.ins)
				ins(i, b, next);
			flush();
		}
		for (l in f.blocks) {
			l.succs = [];
			for (i in l.ins) {
				if (i.target != null && l.succs.indexOf(i.target) < 0) l.succs.push(i.target);
				if (i.table != null)
					for (t in i.table)
						if (l.succs.indexOf(t) < 0) l.succs.push(t);
			}
		}
		for (l in f.blocks)
			for (s in l.succs)
				s.preds.push(l);
		return f;
	}

	function materialize(i:MIns, r:Int) {
		if (r < LFunc.NPHYS) flush();
		switch i.op {
			case Const:
				var x = new LIns(MOVI);
				push(x);
				x.d = r;
				x.imm = i.imm;
				x.isym = i.sym;
				x.imm2 = i.ty == I32 ? 0 : i.imm2;
				x.size = sz(i.ty);
			case SymAddr:
				var x = new LIns(LEA);
				push(x);
				x.d = r;
				x.sym = i.sym;
				x.disp = i.imm;
			case StackAddr:
				var x = new LIns(LEA);
				push(x);
				x.d = r;
				x.base = LIns.FRAME;
				x.slot = i.imm;
			case _:
				throw "hxmc: cannot materialize " + MFunc.opName(i.op);
		}
	}

	// base + index * scale + disp; the emitter handles what an instruction cannot encode
	function memOf(x:LIns, base:Int, index:Int, scale:Int, disp:Int, size:Int) {
		var bi = m.vals[base];
		x.disp = disp;
		x.scale = scale;
		if (folded[base] && bi.op == SymAddr && index < 0) {
			x.sym = bi.sym;
			x.disp += bi.imm;
			return;
		}
		if (folded[base] && bi.op == StackAddr && index < 0) {
			x.base = LIns.FRAME;
			x.slot = bi.imm;
			return;
		}
		var b = use(base);
		if (index >= 0) {
			var ix = use(index);
			// [b + ix << log2(size)] or [b + ix] encode directly
			if (disp == 0 && (scale == size || scale == 1)) {
				x.base = b;
				x.index = ix;
				return;
			}
			var t = f.newReg(false);
			var a = new LIns(ADDSH);
			push(a);
			a.d = t;
			a.s1 = b;
			a.s2 = ix;
			a.imm = scale == 8 ? 3 : scale == 4 ? 2 : scale == 2 ? 1 : 0;
			x.base = t;
			x.scale = 1;
			return;
		}
		x.base = b;
	}

	function jmp(t:LBlock) {
		var x = emit(B);
		x.target = t;
	}

	function bcond(c:Int, t:LBlock) {
		var x = emit(BCOND);
		x.cond = c;
		x.target = t;
	}

	static function cond(c:Int):Int
		return switch (c : Cond) {
			case CEq | FEq: Asm.EQ;
			case CNe | FNe: Asm.NE;
			case CLt: Asm.LT;
			case CLe: Asm.LE;
			case CGt: Asm.GT;
			case CGe: Asm.GE;
			case CULt: Asm.LO;
			case CULe: Asm.LS;
			case CUGt: Asm.HI;
			case CUGe: Asm.HS;
			case FLt: Asm.MI;
			case FLe: Asm.LS;
			case FGt: Asm.GT;
			case FGe: Asm.GE;
		};

	static function swap(c:Int):Int
		return switch (c : Cond) {
			case CLt: CGt;
			case CLe: CGe;
			case CGt: CLt;
			case CGe: CLe;
			case CULt: CUGt;
			case CULe: CUGe;
			case CUGt: CULt;
			case CUGe: CULe;
			case c: c;
		};

	// sets the flags; returns the AArch64 condition
	function compare(c:Int, a:Int, b:Int):Int {
		var t = m.vals[a].ty;
		if (t == F64) {
			var x = emit(FCMP);
			x.s1 = use(a);
			x.s2 = use(b);
			return cond(c);
		}
		var ib = immOf(b);
		if (ib != null && addImm(ib)) {
			var x = emit(CMPI);
			x.s1 = use(a);
			x.imm = ib;
			x.size = sz(t);
			return cond(c);
		}
		var ia = immOf(a);
		if (ia != null && addImm(ia)) {
			var x = emit(CMPI);
			x.s1 = use(b);
			x.imm = ia;
			x.size = sz(t);
			return cond(swap(c));
		}
		var x = emit(CMP);
		x.s1 = use(a);
		x.s2 = use(b);
		x.size = sz(t);
		return cond(c);
	}

	function phiCopies(from:MBlock, to:MBlock) {
		var k = to.preds.indexOf(from);
		var phis = [for (i in to.ins) if (i.op == Phi) i];
		if (phis.length == 0) return;
		var needTemp = false;
		for (p in phis)
			for (q in phis)
				if (p.args[k] == q.id && p != q) needTemp = true;
		if (!needTemp) {
			for (p in phis)
				if (p.args[k] != p.id) copyTo(reg(p.id), p.args[k]);
			return;
		}
		var temps = [];
		for (p in phis) {
			var t = f.newReg(p.ty == F64);
			copyTo(t, p.args[k]);
			temps.push(t);
		}
		for (j in 0...phis.length)
			mov(reg(phis[j].id), temps[j], 8);
	}

	function copyTo(d:Int, v:Int) {
		if (folded[v]) materialize(m.vals[v], d) else mov(d, reg(v), 8);
	}

	function edgeTarget(b:MBlock, to:MBlock):LBlock {
		if (!(to.ins.length > 0 && to.ins[0].op == Phi)) return lb[to.id];
		flush();
		var e = new LBlock(f.blocks.length);
		e.cold = lb[to.id].cold;
		f.blocks.push(e);
		var saved = cur;
		cur = e;
		phiCopies(b, to);
		jmp(lb[to.id]);
		flush();
		cur = saved;
		return e;
	}

	function fusable(i:MIns, b:MBlock):Bool {
		if (useCount[i.id] != 1) return false;
		var t = b.term();
		if (t == null || t.op != Br || t.a != i.id) return false;
		if (b.ins.length < 2 || b.ins[b.ins.length - 2] != i) return false;
		folded[i.id] = true;
		return true;
	}

	function aluOp(op:Op):Int
		return switch op {
			case Add: 0;
			case Sub: 1;
			case And: 2;
			case Or: 3;
			case _: 4;
		};

	function ins(i:MIns, b:MBlock, next:Null<MBlock>) {
		switch i.op {
			case Phi | Const | SymAddr | StackAddr:
			case Param:
				var k = i.imm;
				var gi = 0, fi = 0, si = 0;
				for (j in 0...k)
					if (m.params[j] == F64) {
						if (fi < 8) fi++ else si++;
					} else {
						if (gi < 8) gi++ else si++;
					}
				var d = reg(i.id);
				if (i.ty == F64 && fi < 8) mov(d, D0 + fi) else if (i.ty != F64 && gi < 8) mov(d, ARG_GPRS[gi]) else {
					var x = emit(LOAD);
					x.d = d;
					x.base = -3;
					x.disp = 8 * si;
					x.size = 8;
				}
			case ConstF:
				var x = emit(MOVF);
				x.d = reg(i.id);
				x.f = i.f;
			case TlsLoad:
				var x = emit(TLSLOAD);
				x.d = reg(i.id);
				x.sym = i.sym;
			case TlsStore:
				var x = emit(TLSSTORE);
				x.s1 = use(i.a);
				x.sym = i.sym;
			case Copy:
				mov(reg(i.id), use(i.a));
			case Add | Sub | And | Or | Xor:
				var size = sz(i.ty);
				var imm = immOf(i.b);
				var op = aluOp(i.op);
				if (imm != null && (op <= 1 && addImm(imm) || op >= 2 && Asm.bitmask(imm, imm < 0 ? -1 : 0, size == 8) >= 0)) {
					var x = emit(ALUI);
					x.d = reg(i.id);
					x.s1 = use(i.a);
					x.cond = op;
					x.imm = imm;
					x.size = size;
					return;
				}
				var ia = immOf(i.a);
				if (ia != null && op != 1 && (op == 0 && addImm(ia) || op >= 2 && Asm.bitmask(ia, ia < 0 ? -1 : 0, size == 8) >= 0)) {
					var x = emit(ALUI);
					x.d = reg(i.id);
					x.s1 = use(i.b);
					x.cond = op;
					x.imm = ia;
					x.size = size;
					return;
				}
				var x = emit(ALU);
				x.d = reg(i.id);
				x.s1 = use(i.a);
				x.s2 = useZ(i.b);
				x.cond = op;
				x.size = size;
			case Mul:
				var x = emit(MUL);
				x.d = reg(i.id);
				x.s1 = use(i.a);
				x.s2 = use(i.b);
				x.size = sz(i.ty);
			case Div:
				var x = emit(SDIV);
				x.d = reg(i.id);
				x.s1 = use(i.a);
				x.s2 = use(i.b);
				x.size = sz(i.ty);
			case Rem:
				var a = use(i.a), bb = use(i.b);
				var q = f.newReg(false);
				var x = emit(SDIV);
				x.d = q;
				x.s1 = a;
				x.s2 = bb;
				x.size = sz(i.ty);
				var y = emit(MSUB);
				y.d = reg(i.id);
				y.s1 = q;
				y.s2 = bb;
				y.s3 = a;
				y.size = sz(i.ty);
			case Shl | Sar | Shr:
				var size = sz(i.ty);
				var o = i.op == Shl ? 2 : i.op == Shr ? 3 : 4;
				var imm = immOf(i.b);
				if (imm != null) {
					var x = emit(SHIFTI);
					x.d = reg(i.id);
					x.s1 = use(i.a);
					x.cond = o;
					x.imm = imm & (size == 8 ? 63 : 31);
					x.size = size;
				} else {
					var x = emit(SHIFT);
					x.d = reg(i.id);
					x.s1 = use(i.a);
					x.s2 = use(i.b);
					x.cond = o;
					x.size = size;
				}
			case Neg | Not:
				var x = emit(i.op == Neg ? NEG : MVN);
				x.d = reg(i.id);
				x.s1 = use(i.a);
				x.size = sz(i.ty);
			case FAdd | FSub | FMul | FDiv:
				var x = emit(FOP2);
				x.d = reg(i.id);
				x.s1 = use(i.a);
				x.s2 = use(i.b);
				x.cond = switch i.op {
					case FMul: 0;
					case FDiv: 1;
					case FAdd: 2;
					case _: 3;
				};
			case FSqrt | FNeg | FAbs:
				var x = emit(FOP1);
				x.d = reg(i.id);
				x.s1 = use(i.a);
				x.cond = i.op == FAbs ? 1 : i.op == FNeg ? 2 : 3;
			case Cmp:
				if (fusable(i, b)) return;
				var cc = compare(i.imm, i.a, i.b);
				var x = emit(CSET);
				x.d = reg(i.id);
				x.cond = cc;
			case Select:
				var cv = m.vals[i.a];
				var cc:Int;
				if (cv.op == Cmp && useCount[cv.id] == 1 && cv.block == b) {
					cc = compare(cv.imm, cv.a, cv.b);
				} else {
					var x = emit(CMPI);
					x.s1 = use(i.a);
					x.imm = 0;
					x.size = 4;
					cc = Asm.NE;
				}
				var x = emit(CSEL);
				x.d = reg(i.id);
				x.s1 = useZ(i.b);
				x.s2 = useZ(i.c);
				x.cond = cc;
				x.size = sz(i.ty);
			case SExt:
				var x = emit(SXTW);
				x.d = reg(i.id);
				x.s1 = use(i.a);
			case ZExt | Trunc:
				mov(reg(i.id), use(i.a), 4);
			case I2F:
				var x = emit(SCVTF);
				x.d = reg(i.id);
				x.s1 = use(i.a);
				x.size = sz(m.vals[i.a].ty);
			case F2I:
				var x = emit(FCVTZS);
				x.d = reg(i.id);
				x.s1 = use(i.a);
				x.size = sz(i.ty);
			case BitsToF:
				var x = emit(FMOVFROMG);
				x.d = reg(i.id);
				x.s1 = use(i.a);
			case FToBits:
				var x = emit(FMOVTOG);
				x.d = reg(i.id);
				x.s1 = use(i.a);
			case Load:
				var x = emit(LOAD);
				x.d = reg(i.id);
				x.size = i.size;
				x.flag = i.signed;
				memOf(x, i.a, i.b, i.imm2, i.imm, i.size);
			case Store:
				var x = emit(STORE);
				x.size = i.size;
				x.s1 = useZ(i.c);
				memOf(x, i.a, i.b, i.imm2, i.imm, i.size);
			case Call:
				call(i);
			case Jmp:
				phiCopies(b, i.targets[0]);
				jmp(lb[i.targets[0].id]);
			case Br:
				var t = i.targets[0], e = i.targets[1];
				var cv = m.vals[i.a];
				var lt:LBlock, le:LBlock;
				if (folded[cv.id] && cv.op == Cmp) {
					var cc = compare(cv.imm, cv.a, cv.b);
					lt = edgeTarget(b, t);
					le = edgeTarget(b, e);
					// unordered compares: FNe is true, the others false, as NE/MI/LS/GT/GE/EQ give
					bcond(cc, lt);
				} else {
					var r = use(i.a);
					lt = edgeTarget(b, t);
					le = edgeTarget(b, e);
					var x = emit(CBZ);
					x.s1 = r;
					x.flag = true;
					x.size = 4;
					x.target = lt;
				}
				jmp(le);
			case Switch:
				switchIns(i, b);
			case Ret:
				var x = new LIns(RET);
				if (i.a >= 0) {
					var r = m.vals[i.a].ty == F64 ? D0 : 0;
					mov(r, use(i.a), 8);
					x.uses = [r];
				}
				flush();
				push(x);
			case Unreachable:
				emit(BRK);
		}
	}

	function switchIns(i:MIns, b:MBlock) {
		var v = use(i.a);
		var def = edgeTarget(b, i.targets[i.targets.length - 1]);
		var n = i.cases.length;
		if (n == 0) {
			jmp(def);
			return;
		}
		var lo = i.cases[0], hi = i.cases[0];
		for (c in i.cases) {
			if (c < lo) lo = c;
			if (c > hi) hi = c;
		}
		var targets = [for (k in 0...n) edgeTarget(b, i.targets[k])];
		var span = hi - lo + 1;
		if (n >= 4 && span > 0 && span <= 3 * n + 8) {
			var idx = f.newReg(false);
			if (lo != 0) {
				if (addImm(lo)) {
					var a = emit(ALUI);
					a.d = idx;
					a.s1 = v;
					a.cond = 1;
					a.imm = lo;
					a.size = 4;
				} else {
					var k = f.newReg(false);
					var mi = emit(MOVI);
					mi.d = k;
					mi.imm = lo;
					mi.size = 4;
					var a = emit(ALU);
					a.d = idx;
					a.s1 = v;
					a.s2 = k;
					a.cond = 1;
					a.size = 4;
				}
			} else mov(idx, v, 4);
			var c = emit(CMPI);
			c.s1 = idx;
			c.imm = span - 1;
			c.size = 4;
			if (span - 1 > 4095) {
				var k = f.newReg(false);
				pending = null;
				var mi = emit(MOVI);
				mi.d = k;
				mi.imm = span - 1;
				mi.size = 4;
				var cr = emit(CMP);
				cr.s1 = idx;
				cr.s2 = k;
				cr.size = 4;
			}
			bcond(Asm.HI, def);
			var table = [for (_ in 0...span) def];
			for (k in 0...n)
				table[i.cases[k] - lo] = targets[k];
			var j = emit(JTABLE);
			j.s1 = idx;
			j.table = table;
			return;
		}
		for (k in 0...n) {
			var cv = i.cases[k];
			if (addImm(cv)) {
				var c = emit(CMPI);
				c.s1 = v;
				c.imm = cv;
				c.size = 4;
			} else {
				var t = f.newReg(false);
				var mi = emit(MOVI);
				mi.d = t;
				mi.imm = cv;
				mi.size = 4;
				var c = emit(CMP);
				c.s1 = v;
				c.s2 = t;
				c.size = 4;
			}
			bcond(Asm.EQ, targets[k]);
		}
		jmp(def);
	}

	function call(i:MIns) {
		f.hasCalls = true;
		var gi = 0, fi = 0, stack = 0;
		var uses = [];
		var moves:Array<{d:Int, s:Int}> = [];
		for (k in 0...i.args.length) {
			var a = i.args[k];
			var t = i.argTys[k];
			if (t == F64) {
				if (fi < 8) {
					moves.push({d: D0 + fi, s: a});
					uses.push(D0 + fi);
					fi++;
					continue;
				}
			} else if (gi < 8) {
				moves.push({d: ARG_GPRS[gi], s: a});
				uses.push(ARG_GPRS[gi]);
				gi++;
				continue;
			}
			// stack argument (Apple packs them by size; 8-byte slots elsewhere)
			var x = emit(STORE);
			x.base = -4;
			x.disp = 8 * stack;
			x.size = 8;
			x.s1 = use(a);
			stack++;
		}
		if (apple && stack > 0) throw new hxmc.MirBuild.Unsupported("stack arguments on Apple arm64");
		if (8 * stack > f.outArgs) f.outArgs = 8 * stack;
		var target = i.sym == null ? use(i.a) : -1;
		for (mv in moves)
			if (folded[mv.s]) materialize(m.vals[mv.s], mv.d) else mov(mv.d, reg(mv.s), 8);
		var x = emit(CALL);
		x.sym = i.sym;
		x.s1 = target;
		x.uses = uses;
		if (i.ty != Void) mov(reg(i.id), i.ty == F64 ? D0 : 0, 8);
	}
}
