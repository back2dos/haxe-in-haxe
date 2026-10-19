package hxmc.rt;

import hxmc.I64;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The operations of the interpreter's code (hxmc/src/hxmc/interp/InterpGen.hx
// writes them: the same numbers). Operands are words after the operation:
// d the register written, a, b, c the registers read.
enum abstract IOp(Int) from Int to Int {
	var PARAM = 0; // d i
	var CONST32; // d v
	var CONST64; // d lo hi
	var SYM; // d k: entry k of the symbol table (S + A)
	var TLSLD; // d t
	var TLSST; // a t
	var TLSST_HCUR; // a prevOff: a try's handler set or popped
	var SADDR; // d off: a frame slot's address
	var MOV; // d a
	var ADD; // d a b (64 bits; an I32's upper half is never read)
	var SUB;
	var MUL;
	var AND;
	var OR;
	var XOR;
	var NEG; // d a
	var NOT;
	var SHL32; // d a b
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
	var FNEG; // d a
	var FSQRT;
	var FABS;
	var CMP32; // d a b cond
	var CMP64;
	var CMPF;
	var SEXT; // d a
	var ZEXT;
	var TRUNC;
	var I2F32;
	var I2F64;
	var F2I32;
	var F2I64;
	var SELECT; // d a b c
	var LD1S; // d base index scale disp (index -1: none)
	var LD1U;
	var LD2S;
	var LD2U;
	var LD4S;
	var LD4U;
	var LD8;
	var LDF4;
	var ST1; // base index scale disp v
	var ST2;
	var ST4;
	var ST8;
	var STF4;
	var CALLN; // k d n args: the call-out stub of symbol table entry k (d -1: no result)
	var CALLNI; // k f d n args: the call-out stub k calling the code at f
	var CALLI; // k d n args: the interpreted function whose descriptor is entry k
	var SETJMP; // d h: a try's setjmp on the handler h
	var JMP; // e: an edge record (target, n, n moves d s)
	var BR; // a e1 e2
	var SWITCH; // a n (v e)*n e
	var RET; // a
	var RETV;
	var UNREACH;
}

// An interpreter of hxmc's Mir inside the running program (-D hxmc.interp):
// the functions the tool interprets are their Mir after its optimizations,
// encoded as words (a descriptor per function, InterpGen), run here with
// the program's memory, layouts and runtime; only their instructions are
// executed by this loop rather than by the CPU. Native code reaches an
// interpreted function through its entry stub (a native function of its
// symbol: its arguments into a buffer, then hxmc_interp_enter); an
// interpreted function calls native code through call-out stubs (one per
// callee and signature: the arguments from a buffer, the call as the tool
// compiles it, the result into the buffer), so every ABI detail stays the
// code generator's.
//
// Registers (one per Mir value, 8 bytes) and frame slots are on a stack of
// this thread's (isp), never in the collector's heap: the interpreter
// allocates nothing a collection could move, and the code it runs keeps its
// references across GC points in the shadow stack as native code does.
//
// A try's setjmp: the interpreted code links its handler h (rt_hcur) and
// calls setjmp(h); enterTry runs the rest of the frame inside a native try,
// whose handler is linked above h, so a throw (rt_throw: longjmp to the
// innermost handler) lands there, and the frame goes on at the setjmp with
// 1. When the interpreted code unlinks h (its try ended: rt_hcur set to h's
// previous handler) the native try is left: exec returns the level popped
// to the enterTry of that level.
@:access(hxmc.rt.Gc)
@:access(hxmc.rt.Threads)
class Interp {
	// a descriptor (InterpGen): magic, registers, frame bytes, code words,
	// the symbol table's offset; the code from HEADER
	static inline var HEADER = 32;
	static inline var MAGIC = 0x31495848; // "HXI1"
	// a frame (on the interpreter's stack): its code, symbol table,
	// registers, slots, arguments, end, pc, the tries entered, their handlers
	static inline var F_CODE = 0;
	static inline var F_SYMS = 8;
	static inline var F_REGS = 16;
	static inline var F_SLOTS = 24;
	static inline var F_ARGS = 32;
	static inline var F_TOP = 40;
	static inline var F_PC = 48;
	static inline var F_NTRIES = 52;
	static inline var F_TRIES = 56;
	static inline var MAX_TRIES = 16;
	static inline var FRAME = 192;
	// exec's results: the function returned, a try ended (enterTry goes on),
	// or the level of the try popped
	static inline var RETURNED = -1;
	static inline var CONTINUE = -2;
	// the runtime's thread-local variables (InterpGen.TLS)
	static inline var T_SP = 0;
	static inline var T_SP_HW = 1;
	static inline var T_HCUR = 2;
	static inline var T_EXN = 3;
	static inline var T_YPTR = 4;
	static inline var T_YLIM = 5;
	static inline var T_YRLIM = 6;
	static inline var T_MUT = 7;
	static inline var STACK_BYTES = 16 << 20;

	@:hxmc.threadLocal("rt_interp_sp") static var isp:Ptr;
	@:hxmc.threadLocal("rt_interp_end") static var iend:Ptr;

	static function initStack() {
		var n:I64 = STACK_BYTES;
		var p = LibC.malloc(n);
		if (p.isNull()) throw "hxmc interp: no memory for the interpreter's stack";
		isp = p;
		iend = p.addL(n);
	}

	// native code calling an interpreted function (its entry stub): the
	// arguments are 8-byte words at args, the result is written at args
	@:hxmc.export("hxmc_interp_enter") static function enter(desc:Ptr, args:Ptr):Void {
		if (isp.isNull()) initStack();
		var base = isp;
		try {
			run(desc, args);
		} catch (e:Dynamic) {
			// (a native handler catches: this entry's frames are given back)
			isp = base;
			throw e;
		}
	}

	static function run(desc:Ptr, args:Ptr) {
		if (Mem.getI32(desc, 0) != MAGIC) throw "hxmc interp: not a function's descriptor";
		var nregs = Mem.getI32(desc, 4);
		var fr = isp;
		var regs = fr.add(FRAME);
		var slots = regs.add((nregs * 8 + 15) & ~15);
		var top = slots.add(Mem.getI32(desc, 8));
		if (!top.ult(iend)) throw "hxmc interp: stack overflow";
		isp = top;
		Mem.setPtr(fr, F_CODE, desc.add(HEADER));
		Mem.setPtr(fr, F_SYMS, desc.add(Mem.getI32(desc, 16)));
		Mem.setPtr(fr, F_REGS, regs);
		Mem.setPtr(fr, F_SLOTS, slots);
		Mem.setPtr(fr, F_ARGS, args);
		Mem.setPtr(fr, F_TOP, top);
		Mem.setI32(fr, F_NTRIES, 0);
		exec(fr, 0);
		isp = fr;
	}

	// the frame's try at the setjmp (level: the tries entered before), the
	// frame going on after it at pc
	static function enterTry(fr:Ptr, pc:Int, d:Int, h:Ptr):Int {
		var level = Mem.getI32(fr, F_NTRIES);
		if (level == MAX_TRIES) throw "hxmc interp: tries nested too deep";
		Mem.setPtr(fr, F_TRIES + 8 * level, h);
		Mem.setI32(fr, F_NTRIES, level + 1);
		var regs = Mem.getPtr(fr, F_REGS);
		var st = RETURNED;
		var caught = false;
		var hc = Ptr.nil();
		try {
			Mem.setI64At(regs, 0, d, 0);
			st = exec(fr, pc);
			hc = Gc.hcur;
		} catch (e:Dynamic) {
			caught = true;
			// (deeper frames were left by the longjmp: given back; the handler
			// the interpreted code reads its exception from)
			isp = Mem.getPtr(fr, F_TOP);
			Mem.setI32(fr, F_NTRIES, level);
			Gc.exn = Mem.addr(e);
		}
		if (caught) {
			Mem.setI64At(regs, 0, d, 1);
			st = exec(fr, pc);
			return st == level ? CONTINUE : st;
		}
		// (leaving the native try relinked its handler's previous one, h: as the interpreted code left it)
		Gc.hcur = hc;
		return st == level ? CONTINUE : st;
	}

	static inline function w(code:Ptr, pc:Int, k:Int):Int
		return Mem.getI32At(code, k << 2, pc);

	static inline function gl(regs:Ptr, r:Int):I64
		return Mem.getI64At(regs, 0, r);

	static inline function sl(regs:Ptr, r:Int, v:I64)
		Mem.setI64At(regs, 0, r, v);

	static inline function gi(regs:Ptr, r:Int):Int
		return Mem.getI32(regs, r << 3);

	static inline function si(regs:Ptr, r:Int, v:Int)
		Mem.setI64At(regs, 0, r, v);

	static inline function gf(regs:Ptr, r:Int):Float
		return Mem.getF64At(regs, 0, r);

	static inline function sf(regs:Ptr, r:Int, v:Float)
		Mem.setF64At(regs, 0, r, v);

	static inline function zext(v:Int):I64
		return ((v : I64) << 32) >>> 32;

	// the address of a load or store: base + index * scale + disp
	static inline function addr(code:Ptr, regs:Ptr, pc:Int, k:Int):Ptr {
		var x = gl(regs, w(code, pc, k));
		var i = w(code, pc, k + 1);
		if (i >= 0) x += gl(regs, i) * w(code, pc, k + 2);
		return Ptr.ofI64(x + w(code, pc, k + 3));
	}

	// an edge: its moves (a phi's value from this predecessor), then its target
	static inline function follow(code:Ptr, regs:Ptr, e:Int):Int {
		var n = w(code, e, 1);
		for (k in 0...n)
			sl(regs, w(code, e, 2 + 2 * k), gl(regs, w(code, e, 3 + 2 * k)));
		return w(code, e, 0);
	}

	static function cmp32(c:Int, x:Int, y:Int):Bool
		return switch c {
			case 0: x == y;
			case 1: x != y;
			case 2: x < y;
			case 3: x <= y;
			case 4: x > y;
			case 5: x >= y;
			case 6: (x ^ 0x80000000) < (y ^ 0x80000000);
			case 7: (x ^ 0x80000000) <= (y ^ 0x80000000);
			case 8: (x ^ 0x80000000) > (y ^ 0x80000000);
			case _: (x ^ 0x80000000) >= (y ^ 0x80000000);
		}

	static function cmp64(c:Int, x:I64, y:I64):Bool
		return switch c {
			case 0: x == y;
			case 1: x != y;
			case 2: x < y;
			case 3: x <= y;
			case 4: x > y;
			case 5: x >= y;
			case 6: Mem.ult(x, y);
			case 7: !Mem.ult(y, x);
			case 8: Mem.ult(y, x);
			case _: !Mem.ult(x, y);
		}

	static function cmpf(c:Int, x:Float, y:Float):Bool
		return switch c {
			case 10: x == y;
			case 11: x != y;
			case 12: x < y;
			case 13: x <= y;
			case 14: x > y;
			case _: x >= y;
		}

	static function tlsGet(t:Int):I64
		return switch t {
			case T_SP: Gc.sp.toI64();
			case T_SP_HW: Gc.hw.toI64();
			case T_HCUR: Gc.hcur.toI64();
			case T_EXN: Gc.exn.toI64();
			case T_YPTR: Gc.yptr.toI64();
			case T_YLIM: Gc.ylim.toI64();
			case T_YRLIM: Gc.yrlim.toI64();
			case _: Threads.self.toI64();
		}

	static function tlsSet(t:Int, v:I64)
		switch t {
			case T_SP: Gc.sp = Ptr.ofI64(v);
			case T_SP_HW: Gc.hw = Ptr.ofI64(v);
			case T_HCUR: Gc.hcur = Ptr.ofI64(v);
			case T_EXN: Gc.exn = Ptr.ofI64(v);
			case T_YPTR: Gc.yptr = Ptr.ofI64(v);
			case T_YLIM: Gc.ylim = Ptr.ofI64(v);
			case T_YRLIM: Gc.yrlim = Ptr.ofI64(v);
			case _: Threads.self = Ptr.ofI64(v);
		}

	// runs the frame from pc: RETURNED, or the level of the try its code
	// ended (the frame's pc saved)
	static function exec(fr:Ptr, pc:Int):Int {
		var code = Mem.getPtr(fr, F_CODE);
		var syms = Mem.getPtr(fr, F_SYMS);
		var regs = Mem.getPtr(fr, F_REGS);
		var slots = Mem.getPtr(fr, F_SLOTS);
		var args = Mem.getPtr(fr, F_ARGS);
		while (true) {
			switch (w(code, pc, 0) : IOp) {
				case PARAM:
					sl(regs, w(code, pc, 1), Mem.getI64At(args, 0, w(code, pc, 2)));
					pc += 3;
				case CONST32:
					si(regs, w(code, pc, 1), w(code, pc, 2));
					pc += 3;
				case CONST64:
					sl(regs, w(code, pc, 1), ((w(code, pc, 3) : I64) << 32) | zext(w(code, pc, 2)));
					pc += 4;
				case SYM:
					sl(regs, w(code, pc, 1), Mem.getI64At(syms, 0, w(code, pc, 2)));
					pc += 3;
				case TLSLD:
					sl(regs, w(code, pc, 1), tlsGet(w(code, pc, 2)));
					pc += 3;
				case TLSST:
					tlsSet(w(code, pc, 2), gl(regs, w(code, pc, 1)));
					pc += 3;
				case TLSST_HCUR:
					var v = Ptr.ofI64(gl(regs, w(code, pc, 1)));
					var prevOff = w(code, pc, 2);
					Gc.hcur = v;
					pc += 3;
					// (a try of this frame's ended: back to its enterTry)
					var j = Mem.getI32(fr, F_NTRIES) - 1;
					while (j >= 0 && Mem.getPtr(Mem.getPtr(fr, F_TRIES + 8 * j), prevOff) != v)
						j--;
					if (j >= 0) {
						Mem.setI32(fr, F_NTRIES, j);
						Mem.setI32(fr, F_PC, pc);
						return j;
					}
				case SADDR:
					sl(regs, w(code, pc, 1), slots.add(w(code, pc, 2)).toI64());
					pc += 3;
				case MOV:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)));
					pc += 3;
				case ADD:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) + gl(regs, w(code, pc, 3)));
					pc += 4;
				case SUB:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) - gl(regs, w(code, pc, 3)));
					pc += 4;
				case MUL:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) * gl(regs, w(code, pc, 3)));
					pc += 4;
				case AND:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) & gl(regs, w(code, pc, 3)));
					pc += 4;
				case OR:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) | gl(regs, w(code, pc, 3)));
					pc += 4;
				case XOR:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) ^ gl(regs, w(code, pc, 3)));
					pc += 4;
				case NEG:
					sl(regs, w(code, pc, 1), -gl(regs, w(code, pc, 2)));
					pc += 3;
				case NOT:
					sl(regs, w(code, pc, 1), ~gl(regs, w(code, pc, 2)));
					pc += 3;
				case SHL32:
					si(regs, w(code, pc, 1), gi(regs, w(code, pc, 2)) << (gi(regs, w(code, pc, 3)) & 31));
					pc += 4;
				case SHL64:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) << (gi(regs, w(code, pc, 3)) & 63));
					pc += 4;
				case SAR32:
					si(regs, w(code, pc, 1), gi(regs, w(code, pc, 2)) >> (gi(regs, w(code, pc, 3)) & 31));
					pc += 4;
				case SAR64:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) >> (gi(regs, w(code, pc, 3)) & 63));
					pc += 4;
				case SHR32:
					si(regs, w(code, pc, 1), gi(regs, w(code, pc, 2)) >>> (gi(regs, w(code, pc, 3)) & 31));
					pc += 4;
				case SHR64:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) >>> (gi(regs, w(code, pc, 3)) & 63));
					pc += 4;
				case DIV32:
					var x:I64 = gi(regs, w(code, pc, 2)), y:I64 = gi(regs, w(code, pc, 3));
					si(regs, w(code, pc, 1), (x / y).toInt());
					pc += 4;
				case DIV64:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) / gl(regs, w(code, pc, 3)));
					pc += 4;
				case REM32:
					si(regs, w(code, pc, 1), gi(regs, w(code, pc, 2)) % gi(regs, w(code, pc, 3)));
					pc += 4;
				case REM64:
					sl(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)) % gl(regs, w(code, pc, 3)));
					pc += 4;
				case ROTR32:
					var x = gi(regs, w(code, pc, 2)), k = gi(regs, w(code, pc, 3)) & 31;
					si(regs, w(code, pc, 1), k == 0 ? x : (x >>> k) | (x << (32 - k)));
					pc += 4;
				case ROTR64:
					var x = gl(regs, w(code, pc, 2)), k = gi(regs, w(code, pc, 3)) & 63;
					sl(regs, w(code, pc, 1), k == 0 ? x : (x >>> k) | (x << (64 - k)));
					pc += 4;
				case FADD:
					sf(regs, w(code, pc, 1), gf(regs, w(code, pc, 2)) + gf(regs, w(code, pc, 3)));
					pc += 4;
				case FSUB:
					sf(regs, w(code, pc, 1), gf(regs, w(code, pc, 2)) - gf(regs, w(code, pc, 3)));
					pc += 4;
				case FMUL:
					sf(regs, w(code, pc, 1), gf(regs, w(code, pc, 2)) * gf(regs, w(code, pc, 3)));
					pc += 4;
				case FDIV:
					sf(regs, w(code, pc, 1), gf(regs, w(code, pc, 2)) / gf(regs, w(code, pc, 3)));
					pc += 4;
				case FNEG:
					sf(regs, w(code, pc, 1), -gf(regs, w(code, pc, 2)));
					pc += 3;
				case FSQRT:
					sf(regs, w(code, pc, 1), Math.sqrt(gf(regs, w(code, pc, 2))));
					pc += 3;
				case FABS:
					sf(regs, w(code, pc, 1), Math.abs(gf(regs, w(code, pc, 2))));
					pc += 3;
				case CMP32:
					si(regs, w(code, pc, 1), cmp32(w(code, pc, 4), gi(regs, w(code, pc, 2)), gi(regs, w(code, pc, 3))) ? 1 : 0);
					pc += 5;
				case CMP64:
					si(regs, w(code, pc, 1), cmp64(w(code, pc, 4), gl(regs, w(code, pc, 2)), gl(regs, w(code, pc, 3))) ? 1 : 0);
					pc += 5;
				case CMPF:
					si(regs, w(code, pc, 1), cmpf(w(code, pc, 4), gf(regs, w(code, pc, 2)), gf(regs, w(code, pc, 3))) ? 1 : 0);
					pc += 5;
				case SEXT:
					sl(regs, w(code, pc, 1), (gi(regs, w(code, pc, 2)) : I64));
					pc += 3;
				case ZEXT:
					sl(regs, w(code, pc, 1), zext(gi(regs, w(code, pc, 2))));
					pc += 3;
				case TRUNC:
					si(regs, w(code, pc, 1), gl(regs, w(code, pc, 2)).toInt());
					pc += 3;
				case I2F32:
					sf(regs, w(code, pc, 1), gi(regs, w(code, pc, 2)));
					pc += 3;
				case I2F64:
					var f:Float = cast gl(regs, w(code, pc, 2));
					sf(regs, w(code, pc, 1), f);
					pc += 3;
				case F2I32:
					si(regs, w(code, pc, 1), Std.int(gf(regs, w(code, pc, 2))));
					pc += 3;
				case F2I64:
					var l:I64 = cast gf(regs, w(code, pc, 2));
					sl(regs, w(code, pc, 1), l);
					pc += 3;
				case SELECT:
					sl(regs, w(code, pc, 1), gi(regs, w(code, pc, 2)) != 0 ? gl(regs, w(code, pc, 3)) : gl(regs, w(code, pc, 4)));
					pc += 5;
				case LD1S:
					si(regs, w(code, pc, 1), Mem.getI8(addr(code, regs, pc, 2), 0));
					pc += 6;
				case LD1U:
					si(regs, w(code, pc, 1), Mem.getU8(addr(code, regs, pc, 2), 0));
					pc += 6;
				case LD2S:
					si(regs, w(code, pc, 1), Mem.getI16(addr(code, regs, pc, 2), 0));
					pc += 6;
				case LD2U:
					si(regs, w(code, pc, 1), Mem.getU16(addr(code, regs, pc, 2), 0));
					pc += 6;
				case LD4S:
					si(regs, w(code, pc, 1), Mem.getI32(addr(code, regs, pc, 2), 0));
					pc += 6;
				case LD4U:
					sl(regs, w(code, pc, 1), zext(Mem.getI32(addr(code, regs, pc, 2), 0)));
					pc += 6;
				case LD8:
					sl(regs, w(code, pc, 1), Mem.getI64(addr(code, regs, pc, 2), 0));
					pc += 6;
				case LDF4:
					sf(regs, w(code, pc, 1), Mem.getF32(addr(code, regs, pc, 2), 0));
					pc += 6;
				case ST1:
					Mem.setI8(addr(code, regs, pc, 1), 0, gi(regs, w(code, pc, 5)));
					pc += 6;
				case ST2:
					Mem.setI16(addr(code, regs, pc, 1), 0, gi(regs, w(code, pc, 5)));
					pc += 6;
				case ST4:
					Mem.setI32(addr(code, regs, pc, 1), 0, gi(regs, w(code, pc, 5)));
					pc += 6;
				case ST8:
					Mem.setI64(addr(code, regs, pc, 1), 0, gl(regs, w(code, pc, 5)));
					pc += 6;
				case STF4:
					Mem.setF32(addr(code, regs, pc, 1), 0, gf(regs, w(code, pc, 5)));
					pc += 6;
				case CALLN:
					var n = w(code, pc, 3);
					var buf = isp;
					for (k in 0...n)
						Mem.setI64At(buf, 8, k, gl(regs, w(code, pc, 4 + k)));
					isp = buf.add((8 * n + 23) & ~15);
					Mem.callRef2(Mem.getPtr(syms, w(code, pc, 1) << 3), null, buf);
					isp = buf;
					var d = w(code, pc, 2);
					if (d >= 0) sl(regs, d, Mem.getI64(buf, 0));
					pc += 4 + n;
				case CALLNI:
					var n = w(code, pc, 4);
					var buf = isp;
					Mem.setI64(buf, 0, gl(regs, w(code, pc, 2)));
					for (k in 0...n)
						Mem.setI64At(buf, 8, k, gl(regs, w(code, pc, 5 + k)));
					isp = buf.add((8 * n + 23) & ~15);
					Mem.callRef2(Mem.getPtr(syms, w(code, pc, 1) << 3), null, buf);
					isp = buf;
					var d = w(code, pc, 3);
					if (d >= 0) sl(regs, d, Mem.getI64(buf, 0));
					pc += 5 + n;
				case CALLI:
					var n = w(code, pc, 3);
					var buf = isp;
					for (k in 0...n)
						Mem.setI64At(buf, 0, k, gl(regs, w(code, pc, 4 + k)));
					isp = buf.add((8 * n + 15) & ~15 | 16);
					run(Mem.getPtr(syms, w(code, pc, 1) << 3), buf);
					isp = buf;
					var d = w(code, pc, 2);
					if (d >= 0) sl(regs, d, Mem.getI64(buf, 0));
					pc += 4 + n;
				case SETJMP:
					var r = enterTry(fr, pc + 3, w(code, pc, 1), Ptr.ofI64(gl(regs, w(code, pc, 2))));
					if (r != CONTINUE) return r;
					pc = Mem.getI32(fr, F_PC);
				case JMP:
					pc = follow(code, regs, w(code, pc, 1));
				case BR:
					pc = follow(code, regs, gi(regs, w(code, pc, 1)) != 0 ? w(code, pc, 2) : w(code, pc, 3));
				case SWITCH:
					var v = gi(regs, w(code, pc, 1));
					var n = w(code, pc, 2);
					var e = w(code, pc, 3 + 2 * n);
					for (k in 0...n)
						if (w(code, pc, 3 + 2 * k) == v) {
							e = w(code, pc, 4 + 2 * k);
							break;
						}
					pc = follow(code, regs, e);
				case RET:
					Mem.setI64(args, 0, gl(regs, w(code, pc, 1)));
					return RETURNED;
				case RETV:
					return RETURNED;
				case UNREACH:
					throw "hxmc interp: unreachable code reached";
			}
		}
	}
}
