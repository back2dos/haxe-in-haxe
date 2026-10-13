package hxmc;

// Target instructions over registers, before and after register allocation
// (Regalloc). Registers: 0-63 physical (the target numbers them: general
// registers from 0, floating-point/vector ones from LFunc.fprBase), 64 and
// up virtual. Each target's
// instruction selection produces an LFunc and tells the allocator what an
// instruction defines, uses and clobbers (Target).
class LIns {
	public var op:Int;
	public var size:Int = 8; // operation width in bytes
	public var d:Int = -1; // destination register
	public var s1:Int = -1; // sources
	public var s2:Int = -1;
	public var s3:Int = -1;
	// memory operand: base (register, or FRAME with `slot`), index, scale, disp, sym
	public var base:Int = -1;
	public var index:Int = -1;
	public var scale:Int = 1;
	public var disp:Int = 0;
	public var slot:Int = -1; // frame slot (base == FRAME)
	public var sym:Null<String>;
	public var imm:Int = 0;
	public var isym:Null<String>; // the immediate is this absolute symbol + imm
	public var imm2:Int = 0;
	public var cond:Int = 0;
	public var target:Null<LBlock>;
	public var target2:Null<LBlock>;
	public var table:Null<Array<LBlock>>; // jump tables
	public var uses:Null<Array<Int>>; // calls: the argument registers
	public var defs:Null<Array<Int>>; // calls: the result registers
	public var f:Float = 0;
	public var flag:Bool = false; // target specific (zero/sign extension, ...)

	public static inline var FRAME = -2;

	public function new(op:Int)
		this.op = op;
}

class LBlock {
	public var id:Int;
	public var ins:Array<LIns> = [];
	public var succs:Array<LBlock> = [];
	public var preds:Array<LBlock> = [];
	public var label:Int = -1; // the assembler's label
	public var cold = false;
	public var loopDepth = 0;
	// liveness (Regalloc)
	public var liveIn:Null<Bits>;
	public var liveOut:Null<Bits>;
	public var from = 0; // positions
	public var to = 0;

	public function new(id)
		this.id = id;
}

class LFunc {
	public var name:String;
	public var blocks:Array<LBlock> = []; // in layout order
	public var nregs:Int; // registers 0..nregs-1 (physical and virtual)
	public static inline var NPHYS = 64;

	public var isFloat:Array<Bool> = []; // per virtual register (index - NPHYS)
	public var fprBase:Int; // the first floating-point physical register
	public var slots:Array<{size:Int, align:Int}> = []; // frame slots (MIR slots, then spills)
	public var outArgs = 0; // bytes of outgoing stack arguments
	public var hasCalls = false;
	public var hints = new Map<Int, Int>(); // vreg -> preferred register (physical or virtual)

	public function new(name, fprBase:Int) {
		this.name = name;
		this.fprBase = fprBase;
		nregs = NPHYS;
	}

	public function newReg(float:Bool):Int {
		isFloat.push(float);
		return nregs++;
	}

	public inline function floatReg(r:Int):Bool
		return r < NPHYS ? r >= fprBase : isFloat[r - NPHYS];

	public function slot(size:Int, align:Int):Int {
		slots.push({size: size, align: align});
		return slots.length - 1;
	}
}

// a fixed-size bit set
class Bits {
	public var w:Array<Int>;

	public function new(n:Int) {
		w = [for (_ in 0...((n + 31) >> 5)) 0];
	}

	public inline function get(i:Int):Bool
		return (w[i >> 5] & (1 << (i & 31))) != 0;

	public inline function set(i:Int)
		w[i >> 5] |= 1 << (i & 31);

	public inline function clear(i:Int)
		w[i >> 5] &= ~(1 << (i & 31));

	// this |= o; true when it changed
	public function union(o:Bits):Bool {
		var changed = false;
		for (k in 0...w.length) {
			var v = w[k] | o.w[k];
			if (v != w[k]) {
				w[k] = v;
				changed = true;
			}
		}
		return changed;
	}

	public function copy():Bits {
		var b = new Bits(0);
		b.w = w.copy();
		return b;
	}
}
