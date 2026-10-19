package hxmc.interp;

import hxmc.Mir;
import hxmc.Obj;
import hxmc.ir.Ir;

// The operations of the interpreter's code: hxmc/std/hxmc/rt/Interp.hx runs
// them (IOp there: the same numbers, the operands described there).
enum abstract IOp(Int) to Int {
	var PARAM = 0;
	var CONST32;
	var CONST64;
	var SYM;
	var TLSLD;
	var TLSST;
	var TLSST_HCUR;
	var SADDR;
	var MOV;
	var ADD;
	var SUB;
	var MUL;
	var AND;
	var OR;
	var XOR;
	var NEG;
	var NOT;
	var SHL32;
	var SHL64;
	var SAR32;
	var SAR64;
	var SHR32;
	var SHR64;
	var DIV32;
	var DIV64;
	var REM32;
	var REM64;
	var ROTR32;
	var ROTR64;
	var FADD;
	var FSUB;
	var FMUL;
	var FDIV;
	var FNEG;
	var FSQRT;
	var FABS;
	var CMP32;
	var CMP64;
	var CMPF;
	var SEXT;
	var ZEXT;
	var TRUNC;
	var I2F32;
	var I2F64;
	var F2I32;
	var F2I64;
	var SELECT;
	var LD1S;
	var LD1U;
	var LD2S;
	var LD2U;
	var LD4S;
	var LD4U;
	var LD8;
	var LDF4;
	var ST1;
	var ST2;
	var ST4;
	var ST8;
	var STF4;
	var CALLN;
	var CALLNI;
	var CALLI;
	var SETJMP;
	var JMP;
	var BR;
	var SWITCH;
	var RET;
	var RETV;
	var UNREACH;
}

// The functions -D hxmc.interp interprets: those of the program's modules
// (not the runtime's, hxmc.rt), or of the modules named (prefixes,
// comma-separated), except the ones C enters with structs by value.
class InterpSet {
	final prefixes:Null<Array<String>>;
	// the symbols of the functions interpreted (a call of one: CALLI)
	public final syms = new Map<String, Bool>();

	public function new(spec:String, prep:Prep) {
		prefixes = spec == "" || spec == "1" ? null : [for (p in spec.split(",")) if (StringTools.trim(p) != "") StringTools.trim(p)];
		for (f in prep.p.funcs)
			if (wants(f)) syms.set(prep.funcSym(f), true);
	}

	public function wants(f:FuncInfo):Bool {
		if (f.module == null || StringTools.startsWith(f.module, "hxmc.rt.") || f.cAbi != null) return false;
		if (prefixes == null) return true;
		for (p in prefixes)
			if (StringTools.startsWith(f.module, p)) return true;
		return false;
	}
}

// One function's Mir (after the optimizations) for the interpreter
// (hxmc.rt.Interp): its descriptor in the module's .data (DESC + its
// symbol: a header, the code, the symbol table its code reads addresses
// from), its entry stub (a native function of its symbol, so that whatever
// calls it, code, dispatch rows, closures, C, finds it as before) and the
// call-out stubs its calls of native code go through (local functions of
// the module's object, one per callee and signature).
//
// Registers are the Mir's values (by id), then scratch ones for the edges
// whose moves overlap. Phis are the moves of the edges into their block:
// an edge record (its target, its moves) after the code.
@:access(hxmc.MirBuild)
class InterpGen {
	public static inline var DESC = "hxmc_i$";
	static inline var STUB = "hxmc_ic$";
	static inline var MAGIC = 0x31495848;
	static inline var HEADER = 32;
	// the runtime's thread-local variables the interpreter reads itself (Interp.T_*)
	static var TLS = [
		"rt_sp" => 0, "rt_sp_hw" => 1, "rt_hcur" => 2, "rt_exn" => 3, "rt_young_ptr" => 4, "rt_young_limit" => 5, "rt_young_rlimit" => 6,
		"rt_mut" => 7
	];

	final prep:Prep;
	final abi:Abi;
	final obj:Obj;
	final mf:MFunc;
	final set:InterpSet;
	// compiles a stub into the module's object (global or not)
	final compile:(MFunc, Bool) -> Void;
	final code:Array<Int> = [];
	final syms:Array<{name:String, addend:Int}> = [];
	final symIndex = new Map<String, Int>();
	final edges:Array<{at:Int, from:MBlock, to:MBlock}> = [];
	var scratch = 0;

	public function new(prep, abi, obj, mf, set, compile) {
		this.prep = prep;
		this.abi = abi;
		this.obj = obj;
		this.mf = mf;
		this.set = set;
		this.compile = compile;
	}

	public function run() {
		if (abi.wasm) throw new MirBuild.Unsupported("-D hxmc.interp: not on WebAssembly");
		// the frame slots' offsets
		var slotOff = [];
		var frame = 0;
		for (s in mf.slots) {
			if (s.align > 16) throw new MirBuild.Unsupported("-D hxmc.interp: a frame slot aligned to more than 16 bytes");
			frame = (frame + s.align - 1) & ~(s.align - 1);
			slotOff.push(frame);
			frame += s.size;
		}
		frame = (frame + 15) & ~15;
		var blocks = hxmc.Driver.Layout.order(mf);
		// the parameters first: the entry stub's buffer holds references no collection sees
		for (b in blocks)
			for (i in b.ins)
				if (i.op == Param && !i.dead) emit([PARAM, i.id, i.imm]);
		var pcOf = new Map<Int, Int>();
		for (b in blocks) {
			pcOf.set(b.id, code.length);
			for (i in b.ins)
				if (!i.dead) ins(i, b, slotOff);
		}
		// the edges' records, after the code
		for (e in edges) {
			code[e.at] = code.length;
			code.push(pcOf.get(e.to.id));
			var moves = [];
			var idx = e.to.preds.indexOf(e.from);
			for (p in e.to.ins)
				if (p.op == Phi && !p.dead && p.args[idx] != p.id) moves.push({d: p.id, s: p.args[idx]});
			var overlap = false;
			for (m in moves)
				for (m2 in moves)
					if (m != m2 && m.s == m2.d) overlap = true;
			if (overlap) {
				if (moves.length > scratch) scratch = moves.length;
				code.push(2 * moves.length);
				for (k in 0...moves.length) {
					code.push(mf.vals.length + k);
					code.push(moves[k].s);
				}
				for (k in 0...moves.length) {
					code.push(moves[k].d);
					code.push(mf.vals.length + k);
				}
			} else {
				code.push(moves.length);
				for (m in moves) {
					code.push(m.d);
					code.push(m.s);
				}
			}
		}
		// the descriptor
		var sec = obj.section(".data", SecKind.Data, 16);
		var b = sec.buf;
		b.align(16);
		var start = b.len;
		var symOff = (HEADER + 4 * code.length + 7) & ~7;
		b.u32(MAGIC);
		b.u32(mf.vals.length + scratch);
		b.u32(frame);
		b.u32(code.length);
		b.u32(symOff);
		b.u32(0);
		b.u32(0);
		b.u32(0);
		for (w in code)
			b.u32(w);
		b.align(8);
		for (s in syms) {
			sec.relocs.push(new Reloc(b.len, RelKind.RAbs64, obj.sym(s.name), s.addend));
			b.u64(0, 0);
		}
		obj.define(DESC + mf.name, sec, start, b.len - start, true);
		entryStub();
	}

	function sym(name:String, addend:Int):Int {
		var k = name + "+" + addend;
		var i = symIndex.get(k);
		if (i == null) {
			i = syms.length;
			syms.push({name: name, addend: addend});
			symIndex.set(k, i);
		}
		return i;
	}

	inline function emit(xs:Array<Int>)
		for (x in xs)
			code.push(x);

	function edge(from:MBlock, to:MBlock) {
		edges.push({at: code.length, from: from, to: to});
		code.push(-1);
	}

	function ty(v:Int):MTy
		return mf.vals[v].ty;

	function ins(i:MIns, b:MBlock, slotOff:Array<Int>) {
		var d = i.id;
		switch i.op {
			case Param: // (at the start: run)
			case Const:
				if (i.sym != null) emit([SYM, d, sym(i.sym, i.imm)]) else if (i.ty == I32) emit([CONST32, d, i.imm]) else emit([CONST64, d, i.imm, i.imm2]);
			case ConstF:
				emit([CONST64, d, haxe.io.FPHelper.doubleLow(i.f), haxe.io.FPHelper.doubleHigh(i.f)]);
			case SymAddr:
				emit([SYM, d, sym(i.sym, i.imm)]);
			case TlsLoad:
				var t = TLS.get(i.sym);
				if (t != null) emit([TLSLD, d, t]) else callOut(tlsStub(i.sym, false), d, []);
			case TlsStore:
				if (i.sym == "rt_hcur") emit([TLSST_HCUR, i.a, abi.handlerPrev]) else {
					var t = TLS.get(i.sym);
					if (t != null) emit([TLSST, i.a, t]) else callOut(tlsStub(i.sym, true), -1, [i.a]);
				}
			case StackAddr:
				emit([SADDR, d, slotOff[i.imm]]);
			case Copy | BitsToF | FToBits:
				emit([MOV, d, i.a]);
			case Phi:
			case Add:
				emit([ADD, d, i.a, i.b]);
			case Sub:
				emit([SUB, d, i.a, i.b]);
			case Mul:
				emit([MUL, d, i.a, i.b]);
			case And:
				emit([AND, d, i.a, i.b]);
			case Or:
				emit([OR, d, i.a, i.b]);
			case Xor:
				emit([XOR, d, i.a, i.b]);
			case Shl:
				emit([i.ty == I32 ? SHL32 : SHL64, d, i.a, i.b]);
			case Sar:
				emit([i.ty == I32 ? SAR32 : SAR64, d, i.a, i.b]);
			case Shr:
				emit([i.ty == I32 ? SHR32 : SHR64, d, i.a, i.b]);
			case Neg:
				emit([NEG, d, i.a]);
			case Not:
				emit([NOT, d, i.a]);
			case Div:
				emit([i.ty == I32 ? DIV32 : DIV64, d, i.a, i.b]);
			case Rem:
				emit([i.ty == I32 ? REM32 : REM64, d, i.a, i.b]);
			case Rotr:
				emit([i.ty == I32 ? ROTR32 : ROTR64, d, i.a, i.b]);
			case FAdd:
				emit([FADD, d, i.a, i.b]);
			case FSub:
				emit([FSUB, d, i.a, i.b]);
			case FMul:
				emit([FMUL, d, i.a, i.b]);
			case FDiv:
				emit([FDIV, d, i.a, i.b]);
			case FNeg:
				emit([FNEG, d, i.a]);
			case FSqrt:
				emit([FSQRT, d, i.a]);
			case FAbs:
				emit([FABS, d, i.a]);
			case Cmp:
				var t = ty(i.a);
				emit([t == F64 ? CMPF : t == I64 ? CMP64 : CMP32, d, i.a, i.b, i.imm]);
			case SExt:
				emit([SEXT, d, i.a]);
			case ZExt:
				emit([ZEXT, d, i.a]);
			case Trunc:
				emit([TRUNC, d, i.a]);
			case I2F:
				emit([ty(i.a) == I32 ? I2F32 : I2F64, d, i.a]);
			case F2I:
				emit([i.ty == I32 ? F2I32 : F2I64, d, i.a]);
			case Select:
				emit([SELECT, d, i.a, i.b, i.c]);
			case Load:
				var op:IOp = if (i.ty == F64) i.size == 4 ? LDF4 : LD8 else switch i.size {
					case 1: i.signed ? LD1S : LD1U;
					case 2: i.signed ? LD2S : LD2U;
					case 4: i.ty == I64 && !i.signed ? LD4U : LD4S;
					case _: LD8;
				}
				emit([op, d, i.a, i.b, i.imm2, i.imm]);
			case Store:
				var op:IOp = if (ty(i.c) == F64 && i.size == 4) STF4 else switch i.size {
					case 1: ST1;
					case 2: ST2;
					case 4: ST4;
					case _: ST8;
				}
				emit([op, i.a, i.b, i.imm2, i.imm, i.c]);
			case Call:
				var res = i.ty == Void ? -1 : d;
				if (i.returnsTwice) emit([SETJMP, d, i.args[0]]) else if (i.sym != null && set.syms.exists(i.sym)) {
					emit([CALLI, sym(DESC + i.sym, 0), res, i.args.length]);
					emit(i.args);
				} else if (i.sym != null) callOut(callStub(i), res, i.args) else {
					emit([CALLNI, sym(callStub(i), 0), i.a, res, i.args.length]);
					emit(i.args);
				}
			case Jmp:
				code.push(JMP);
				edge(b, i.targets[0]);
			case Br:
				emit([BR, i.a]);
				edge(b, i.targets[0]);
				edge(b, i.targets[1]);
			case Switch:
				emit([SWITCH, i.a, i.cases.length]);
				for (k in 0...i.cases.length) {
					code.push(i.cases[k]);
					edge(b, i.targets[k]);
				}
				edge(b, i.targets[i.targets.length - 1]);
			case Ret:
				if (i.a >= 0) emit([RET, i.a]) else code.push(RETV);
			case Unreachable:
				code.push(UNREACH);
		}
	}

	function callOut(stub:String, res:Int, args:Array<Int>) {
		emit([CALLN, sym(stub, 0), res, args.length]);
		emit(args);
	}

	// ---- stubs

	function defined(name:String):Bool
		return obj.exists(name) && obj.sym(name).section != null;

	static function tyKey(t:MTy):String
		return switch t {
			case I32: "i";
			case I64: "l";
			case F64: "f";
			case Void: "v";
		}

	// the call-out stub of a call: (unused, buf) -> 0: the function at buf[0]
	// (an indirect call) called with the arguments at buf[8...], as the call
	// does it, its result written at buf[0]
	function callStub(c:MIns):String {
		var k = new StringBuf();
		k.add(c.sym != null ? c.sym : "*");
		k.add("|" + tyKey(c.ty) + "|" + [for (a in c.args) tyKey(ty(a))].join(""));
		k.add("|" + (c.argTys == null ? "" : [for (t in c.argTys) tyKey(t)].join("")));
		k.add("|" + c.cSizes + "|" + c.cGroups + "|" + (c.cRet == null ? "" : [for (p in c.cRet) p.off + ":" + p.size + ":" + p.float].join(",")));
		k.add("|" + c.variadic + "|" + c.noReturn);
		var name = STUB + haxe.crypto.Md5.encode(k.toString()).substr(0, 16);
		if (defined(name)) return name;
		var argTys = [for (a in c.args) ty(a)];
		compile(MirBuild.synthetic(prep, abi, name, [I64, I64], I64, (b, ps) -> {
			var buf = ps[1];
			var xs = [for (n in 0...argTys.length) b.load(argTys[n], argTys[n] == I32 ? 4 : 8, buf, 8 + 8 * n, true)];
			var x = b.mk(Call, c.ty);
			if (c.sym != null) x.sym = c.sym else x.a = b.load(I64, 8, buf, 0);
			x.args = xs;
			x.argTys = c.argTys != null ? c.argTys.copy() : [for (t in argTys) t];
			x.cSizes = c.cSizes;
			x.cGroups = c.cGroups;
			x.cRet = c.cRet;
			x.variadic = c.variadic;
			x.noReturn = c.noReturn;
			var r = b.add(x);
			if (c.noReturn) {
				b.add(b.mk(Unreachable, Void));
				return;
			}
			if (c.ty != Void) b.store(c.ty == I32 ? 4 : 8, buf, 0, r);
			b.ret(b.lconst(0, 0));
		}), false);
		return name;
	}

	// a thread-local variable of the program's (@:hxmc.threadLocal) read or set
	function tlsStub(tls:String, set:Bool):String {
		var name = STUB + (set ? "tset$" : "tget$") + tls;
		if (defined(name)) return name;
		compile(MirBuild.synthetic(prep, abi, name, [I64, I64], I64, (b, ps) -> {
			if (set) b.tlsStore(tls, b.load(I64, 8, ps[1], 8)) else b.store(8, ps[1], 0, b.tlsLoad(tls));
			b.ret(b.lconst(0, 0));
		}), false);
		return name;
	}

	// the function's own symbol: its arguments into a buffer of 8-byte
	// words, the interpreter, its result from the buffer
	function entryStub() {
		var params = mf.params, ret = mf.ret;
		var desc = DESC + mf.name;
		compile(MirBuild.synthetic(prep, abi, mf.name, params, ret, (b, ps) -> {
			var buf = b.stackAddr(b.f.slot(8 * (params.length > 0 ? params.length : 1), 16));
			for (n in 0...params.length)
				b.store(params[n] == I32 ? 4 : 8, buf, 8 * n, ps[n]);
			b.call("hxmc_interp_enter", [b.symAddr(desc), buf], Void);
			b.ret(ret == Void ? -1 : b.load(ret, ret == I32 ? 4 : 8, buf, 0, true));
		}), true);
	}
}
