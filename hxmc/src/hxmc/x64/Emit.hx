package hxmc.x64;

import hxmc.Lir;
import hxmc.Obj;
import hxmc.x64.Asm;
import hxmc.x64.Isel.XOp;

// Allocated LIR -> x86-64 machine code in a text section: frame layout,
// prologue and epilogues, jump tables, the constant pool.
class Emit {
	var obj:Obj;
	var text:Section;
	var rodata:Section;
	var a:Asm;
	var pool = new Map<String, Symbol>();
	var npool = 0;

	public function new(obj:Obj) {
		this.obj = obj;
		text = obj.section(".text", Text, 16);
		rodata = obj.section(".rodata", RoData, 16);
		a = new Asm(text);
	}

	// a 16-byte constant (low, high 64 bits as hex strings of their halves)
	function constant(lo0:Int, lo1:Int, hi0:Int, hi1:Int):Symbol {
		var key = '$lo0,$lo1,$hi0,$hi1';
		var s = pool.get(key);
		if (s != null) return s;
		rodata.buf.align(16);
		var off = rodata.buf.len;
		rodata.buf.u32(lo0);
		rodata.buf.u32(lo1);
		rodata.buf.u32(hi0);
		rodata.buf.u32(hi1);
		s = obj.define(".Lk" + npool++, rodata, off, 16, false);
		pool.set(key, s);
		return s;
	}

	function floatConst(v:Float):Symbol {
		var bits = haxe.io.Bytes.alloc(8);
		bits.setDouble(0, v);
		return constant(bits.getInt32(0), bits.getInt32(4), 0, 0);
	}

	var slotOff:Array<Int>;
	var frameSize = 0;
	var saved:Array<Int>;

	public function func(f:LFunc, usedRegs:Map<Int, Bool>, global:Bool):Symbol {
		text.buf.align(16, 0xcc);
		var start = text.buf.len;
		a.reset();
		// frame: outgoing arguments, then the slots
		var off = f.outArgs;
		slotOff = [];
		for (s in f.slots) {
			var al = s.align < 8 ? 8 : s.align;
			off = (off + al - 1) & ~(al - 1);
			slotOff.push(off);
			off += s.size;
		}
		saved = [for (r in Isel.CALLEE_SAVED) if (usedRegs.exists(r)) r];
		var x = off;
		while ((8 + 8 * saved.length + x) % 16 != 0)
			x += 8;
		// leaf functions without slots keep rsp as it is
		if (!f.hasCalls && f.slots.length == 0 && f.outArgs == 0) x = 0;
		frameSize = x;
		for (r in saved)
			a.push(r);
		if (frameSize > 0) a.aluRI(Asm.SUB, 8, Asm.RSP, frameSize);
		for (b in f.blocks)
			b.label = a.newLabel();
		var tables:Array<{label:Int, entries:Array<LBlock>}> = [];
		for (bi in 0...f.blocks.length) {
			var b = f.blocks[bi];
			a.bind(b.label);
			var next = bi + 1 < f.blocks.length ? f.blocks[bi + 1] : null;
			for (i in b.ins)
				ins(i, next, tables);
		}
		a.finish(start);
		// jump tables: 32-bit offsets from the table
		for (t in tables) {
			text.buf.align(4, 0);
			a.bind(t.label);
			var at = text.buf.len;
			for (e in t.entries)
				text.buf.u32(a.labelPos(e.label) - at);
		}
		a.patchLabelRefs();
		var sym = obj.define(f.name, text, start, text.buf.len - start, global);
		return sym;
	}

	function mem(i:LIns):Mem {
		if (i.sym != null) return Mem.rip(obj.sym(i.sym), i.disp);
		if (i.base == LIns.FRAME) return new Mem(Asm.RSP, slotOff[i.slot] + i.disp);
		if (i.base == -3) return new Mem(Asm.RSP, frameSize + 8 * saved.length + 8 + i.disp);
		if (i.base == -4) return new Mem(Asm.RSP, i.disp);
		return new Mem(i.base, i.disp, i.index, i.scale);
	}

	function tlsSym(name:String):Symbol {
		var s = obj.sym(name);
		s.tls = true;
		return s;
	}

	static inline function isX(r:Int):Bool
		return r >= 16;

	function epilogue() {
		if (frameSize > 0) a.aluRI(Asm.ADD, 8, Asm.RSP, frameSize);
		var k = saved.length;
		while (k-- > 0)
			a.pop(saved[k]);
		a.ret();
	}

	function ins(i:LIns, next:Null<LBlock>, tables:Array<{label:Int, entries:Array<LBlock>}>) {
		switch (i.op : XOp) {
			case MOV:
				if (isX(i.d) && isX(i.s1)) a.movsdRR(i.d, i.s1) else if (isX(i.d)) a.movqXR(i.d, i.s1) else if (isX(i.s1)) a.movqRX(i.d, i.s1) else if (i.flag)
					a.movsxdR(i.d, i.s1)
				else if (i.d != i.s1 || i.size == 4) a.movRR(i.size == 4 ? 4 : 8, i.d, i.s1);
			case MOVI:
				if (i.flag && i.imm == 0 && (i.size == 4 || i.imm2 == 0)) a.movImm32(i.d, 0) else if (i.size == 4) a.movRI(4, i.d, i.imm) else a.movRI64(i.d, i.imm, i.imm2);
			case MOVF:
				if (i.f == 0 && 1 / i.f > 0) a.xorpd(i.d, i.d) else a.movsdRM(i.d, Mem.rip(floatConst(i.f)));
			case LEA:
				a.lea(8, i.d, mem(i));
			case LOAD:
				var m = mem(i);
				if (isX(i.d)) a.movsdRM(i.d, m) else switch i.size {
					case 1: if (i.flag) a.movsx8(4, i.d, m) else a.movzx8(i.d, m);
					case 2: if (i.flag) a.movsx16(4, i.d, m) else a.movzx16(i.d, m);
					case 4: a.load(4, i.d, m);
					case _: a.load(8, i.d, m);
				}
			case STORE:
				var m = mem(i);
				if (isX(i.s1)) a.movsdMR(m, i.s1) else a.store(i.size, m, i.s1);
			case STOREI:
				a.storeI(i.size, mem(i), i.imm);
			case ALU:
				a.aluRR(i.cond, i.size, i.d, i.s1);
			case ALUI:
				a.aluRI(i.cond, i.size, i.d, i.imm);
			case IMUL:
				a.imulRR(i.size, i.d, i.s1);
			case IMULI:
				a.imulRRI(i.size, i.d, i.s1, i.imm);
			case SHIFT:
				a.shiftCl(i.cond, i.size, i.d);
			case SHIFTI:
				if (i.imm != 0) a.shiftI(i.cond, i.size, i.d, i.imm);
			case NEG:
				a.neg(i.size, i.d);
			case NOT:
				a.not(i.size, i.d);
			case CQO:
				a.signExtendAx(i.size);
			case IDIV:
				a.idiv(i.size, i.s1);
			case CMP:
				a.aluRR(Asm.CMP, i.size, i.s1, i.s2);
			case CMPI:
				a.aluRI(Asm.CMP, i.size, i.s1, i.imm);
			case TEST:
				a.testRR(i.size, i.s1, i.s2);
			case UCOMI:
				a.ucomisdRR(i.s1, i.s2);
			case SETCC:
				a.setcc(i.cond, i.d);
				a.movzx8R(i.d, i.d);
			case CMOV:
				a.cmovRR(i.cond, i.size < 4 ? 4 : i.size, i.d, i.s1);
			case FOP:
				a.sdRR(i.cond, i.d, i.s1);
			case FSQRT:
				a.sdRR(0x51, i.d, i.s1);
			case FMASK:
				var k = i.imm == 0 ? constant(0, 0x80000000, 0, 0) : constant(-1, 0x7fffffff, 0, 0);
				a.pdRM(i.cond, i.d, Mem.rip(k));
			case CVTI2F:
				a.xorpd(i.d, i.d);
				a.cvtsi2sd(i.size, i.d, i.s1);
			case CVTF2I:
				a.cvttsd2si(i.size, i.d, i.s1);
			case MOVQXR:
				a.movqXR(i.d, i.s1);
			case MOVQRX:
				a.movqRX(i.d, i.s1);
			case CALL:
				if (i.sym != null) a.callSym(obj.sym(i.sym)) else a.callR(i.s1);
			case RET:
				epilogue();
			case JMP:
				if (i.target != next) a.jmp(i.target.label);
			case JCC:
				a.jcc(i.cond, i.target.label);
			case LEATABLE:
				var l = a.newLabel();
				tables.push({label: l, entries: i.table});
				a.leaLabel(i.d, l);
			case JTABLE:
				a.movsxd(i.s2, new Mem(i.d, 0, i.s1, 4));
				a.aluRR(Asm.ADD, 8, i.d, i.s2);
				a.jmpR(i.d);
			case TLSLOAD:
				a.load(8, i.d, Mem.tlsVar(tlsSym(i.sym)));
			case TLSSTORE:
				a.store(8, Mem.tlsVar(tlsSym(i.sym)), i.s1);
			case UD2:
				a.ud2();
		}
	}
}
