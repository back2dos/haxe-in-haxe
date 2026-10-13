package hxmc;

import hxmc.Lir;
import hxmc.Lir.Arrays;

// What the register allocator needs to know about a target.
interface RegTarget {
	// the registers an instruction reads and writes, including fixed
	// physical ones and the registers a call clobbers (as definitions)
	function defsUses(i:LIns, defs:RegList, uses:RegList):Void;
	// a register to register copy: d <- s1
	function isMove(i:LIns):Bool;
	// allocatable registers in order of preference (caller-saved first)
	var gprs(default, null):Array<Int>;
	var fprs(default, null):Array<Int>;
	function spillLoad(r:Int, slot:Int, float:Bool):LIns;
	function spillStore(slot:Int, r:Int, float:Bool):LIns;
	// calls: the registers that hold their results (the other registers a
	// call defines are clobbered)
	function isCall(i:LIns):Bool;
	var callResults(default, null):Array<Int>;
}

// a list of registers that keeps its storage (defsUses fills one per instruction)
class RegList {
	public var a:Array<Int> = Arrays.filled(64, 0);
	public var n = 0;

	public function new() {}

	public inline function push(r:Int) {
		if (n == a.length) a.push(r) else a[n] = r;
		n++;
	}
}

// The allocator's working storage, kept from one function to the next (one
// per thread): the arrays keep their capacity, so a round allocates little.
class Scratch {
	public var defs = new RegList();
	public var uses = new RegList();
	public var start:Array<Int> = [];
	public var end:Array<Int> = [];
	public var fixedFrom:Array<Array<Int>> = [for (_ in 0...LFunc.NPHYS) []];
	public var fixedTo:Array<Array<Int>> = [for (_ in 0...LFunc.NPHYS) []];
	public var openFixed:Array<Int> = Arrays.filled(LFunc.NPHYS, -1);
	public var exposedHead:Array<Int> = [];
	public var exposedBlock:Array<Int> = [];
	public var exposedNext:Array<Int> = [];
	public var defStamp:Array<Int> = [];
	public var defHead:Array<Int> = [];
	public var defBlock:Array<Int> = [];
	public var defNext:Array<Int> = [];
	public var defines:Array<Int> = [];
	public var liveInSeen:Array<Int> = [];
	public var liveOutSeen:Array<Int> = [];
	public var work:Array<Int> = [];
	public var count:Array<Int> = [];
	public var order:Array<Int> = [];
	public var assigned:Array<Int> = [];
	public var holder:Array<Int> = [];
	// per physical register: whether a call leaves its result there; 1 for
	// the allocatable float registers, 2 for the integer ones
	public var isResult:Array<Bool> = [for (_ in 0...LFunc.NPHYS) false];
	public var isFpr:Array<Int> = Arrays.filled(LFunc.NPHYS, 0);

	public function new(t:RegTarget) {
		for (r in t.callResults)
			isResult[r] = true;
		for (c in t.fprs)
			isFpr[c] = 1;
		for (c in t.gprs)
			isFpr[c] = 2;
	}

	// a resized to n copies of v
	public static function fill(a:Array<Int>, n:Int, v:Int):Array<Int> {
		a.resize(n);
		for (i in 0...n)
			a[i] = v;
		return a;
	}
}

// Linear-scan register allocation (Poletto and Sarkar) with one live range
// per virtual register, on the block layout order. Physical registers
// named by instructions (call arguments and results, fixed operands, call
// clobbers) are fixed ranges no interval may overlap, so a value live across
// a call ends up in a callee-saved register or in memory. A spilled register
// lives in a frame slot: every use loads it into a fresh short-lived
// register and every definition stores it, and the allocation runs again.
class Regalloc {
	static inline var NPHYS = LFunc.NPHYS;
	var f:LFunc;
	var t:RegTarget;
	public var assigned:Array<Int>; // register -> physical register
	public var usedRegs = [for (_ in 0...LFunc.NPHYS) false]; // physical registers used
	var noSpillFrom = 0x7fffffff; // registers made by spill code are numbered from here

	public function new(f:LFunc, t:RegTarget, ?s:Scratch) {
		this.f = f;
		this.t = t;
		this.s = s != null ? s : new Scratch(t);
	}

	public var rounds = 0; // allocation rounds run (statistics)
	public var insns = 0; // instructions they went through

	public function run() {
		for (round in 0...8) {
			rounds++;
			for (b in f.blocks)
				insns += b.ins.length;
			var spilled = allocate();
			if (spilled.length == 0) {
				coldSaves();
				rewrite();
				return;
			}
			insertSpills(spilled);
		}
		throw "hxmc: register allocation does not converge in " + f.name;
	}

	// ---- one round

	var start:Array<Int>;
	var end:Array<Int>;
	var fixedFrom:Array<Array<Int>>; // per physical register: sorted ranges
	var fixedTo:Array<Array<Int>>;
	var s:Scratch;

	function allocate():Array<Int> {
		var n = f.nregs;
		var s = this.s;
		coldCalls.resize(0);
		coldSaved.resize(0);
		coldSavedAt.resize(0);
		var defs = s.defs, uses = s.uses;
		var isResult = s.isResult;
		// positions
		var pos = 0;
		for (b in f.blocks) {
			b.from = pos;
			pos += 2 * b.ins.length;
			b.to = pos;
			pos += 2;
		}
		// intervals: per virtual register its first and last position, from
		// its definitions and uses, extended over the blocks it is live
		// across (found by walking back from each use to the definitions)
		start = Scratch.fill(s.start, n, 0x7fffffff);
		end = Scratch.fill(s.end, n, -1);
		fixedFrom = s.fixedFrom;
		fixedTo = s.fixedTo;
		for (k in 0...NPHYS) {
			fixedFrom[k].resize(0);
			fixedTo[k].resize(0);
		}
		var openFixed = s.openFixed;
		var nb = f.blocks.length;
		for (bi in 0...nb)
			f.blocks[bi].id = bi;
		// per register: the blocks with a use not preceded by a definition in the block (upward-exposed)
		var exposedHead = Scratch.fill(s.exposedHead, n, -1);
		var exposedBlock = s.exposedBlock, exposedNext = s.exposedNext;
		exposedBlock.resize(0);
		exposedNext.resize(0);
		// per block and register: defined in the block (stamped by block),
		// and per register the blocks defining it (a list through defNext)
		var defStamp = Scratch.fill(s.defStamp, n, -1);
		var defHead = Scratch.fill(s.defHead, n, -1);
		var defBlock = s.defBlock, defNext = s.defNext;
		defBlock.resize(0);
		defNext.resize(0);
		for (bi in 0...nb) {
			var b = f.blocks[bi];
			for (k in 0...NPHYS)
				openFixed[k] = -1;
			var p = b.from;
			var cold = b.cold;
			for (i in b.ins) {
				defs.n = 0;
				uses.n = 0;
				t.defsUses(i, defs, uses);
				// a call on a slow path clobbers only its result registers here:
				// what lives across it is saved and restored around it (coldSaves)
				var coldCall = cold && t.isCall(i);
				if (coldCall) coldCalls.push(p);
				var ua = uses.a;
				for (k in 0...uses.n) {
					var r = ua[k];
					if (r >= NPHYS) {
						if (end[r] < p) end[r] = p;
						if (start[r] > p) start[r] = p;
						if (defStamp[r] != bi) {
							// the first exposed use in this block: record once
							var h = exposedHead[r];
							if (h < 0 || exposedBlock[h] != bi) {
								exposedBlock.push(bi);
								exposedNext.push(h);
								exposedHead[r] = exposedBlock.length - 1;
							}
						}
					} else if (r >= 0) {
						var from = openFixed[r] >= 0 ? openFixed[r] : b.from;
						addFixed(r, from, p);
					}
				}
				var da = defs.a;
				for (k in 0...defs.n) {
					var r = da[k];
					if (r >= NPHYS) {
						if (start[r] > p + 1) start[r] = p + 1;
						if (end[r] < p + 1) end[r] = p + 1;
						if (defStamp[r] != bi) {
							defStamp[r] = bi;
							defBlock.push(bi);
							defNext.push(defHead[r]);
							defHead[r] = defBlock.length - 1;
						}
					} else if (r >= 0) {
						if (coldCall && !isResult[r]) continue;
						openFixed[r] = p + 1;
						addFixed(r, p + 1, p + 1);
					}
				}
				p += 2;
			}
		}
		var defines = Scratch.fill(s.defines, nb, -1); // stamped by register
		var liveInSeen = Scratch.fill(s.liveInSeen, nb, -1);
		var liveOutSeen = Scratch.fill(s.liveOutSeen, nb, -1);
		// a stack of blocks (pop of an Array<Int> would box its result)
		var work = s.work;
		var wn = 0;
		var blocks = f.blocks;
		for (r in NPHYS...n) {
			var e = exposedHead[r];
			if (e < 0) continue;
			var d = defHead[r];
			while (d >= 0) {
				defines[defBlock[d]] = r;
				d = defNext[d];
			}
			while (e >= 0) {
				var x = exposedBlock[e];
				if (wn == work.length) work.push(x) else work[wn] = x;
				wn++;
				e = exposedNext[e];
			}
			var st = start[r], en = end[r];
			while (wn > 0) {
				var bi = work[--wn];
				if (liveInSeen[bi] == r) continue;
				liveInSeen[bi] = r;
				var b = blocks[bi];
				if (st > b.from) st = b.from;
				for (pr in b.preds) {
					var pi = pr.id;
					if (liveOutSeen[pi] != r) {
						liveOutSeen[pi] = r;
						if (en < pr.to) en = pr.to;
						if (st > pr.to) st = pr.to;
					}
					if (defines[pi] != r) {
						if (wn == work.length) work.push(pi) else work[wn] = pi;
						wn++;
					}
				}
			}
			start[r] = st;
			end[r] = en;
		}
		for (r in 0...NPHYS)
			sortFixed(r);
		// linear scan: intervals by start (a counting sort on positions; ties by register)
		var count = Scratch.fill(s.count, pos + 2, 0);
		var live = 0;
		for (r in NPHYS...n)
			if (end[r] >= 0) {
				count[start[r] + 1]++;
				live++;
			}
		for (p in 1...pos + 2)
			count[p] += count[p - 1];
		var order = Scratch.fill(s.order, live, 0);
		for (r in NPHYS...n)
			if (end[r] >= 0) order[count[start[r]]++] = r;
		assigned = Scratch.fill(s.assigned, n, -1);
		for (r in 0...NPHYS)
			assigned[r] = r;
		// per physical register: the interval holding it (free once that ends)
		var holder = Scratch.fill(s.holder, NPHYS, -1);
		var isFpr = s.isFpr;
		var spilled = [];
		// the slow-path calls, in position order: when the scan passes one,
		// the registers held across it are recorded (coldSaves)
		var ci = 0, nc = coldCalls.length;
		for (r in order) {
			var rs = start[r], re = end[r];
			while (ci < nc && coldCalls[ci] < rs) {
				snapshot(coldCalls[ci], holder);
				ci++;
			}
			var float = f.floatReg(r);
			var regs = float ? t.fprs : t.gprs;
			var choice = -1;
			var h = f.hint(r);
			if (h >= 0) {
				var hr = h < NPHYS ? h : assigned[h];
				if (hr >= 0 && isFpr[hr] == (float ? 1 : 2) && (holder[hr] < 0 || end[holder[hr]] < rs) && !fixedOverlap(hr, rs, re)) choice = hr;
			}
			if (choice < 0)
				for (c in regs) {
					var o = holder[c];
					if ((o < 0 || end[o] < rs) && !fixedOverlap(c, rs, re)) {
						choice = c;
						break;
					}
				}
			if (choice < 0) {
				// spill the live interval that ends last, if it ends after this one
				var victim = -1;
				for (c in regs) {
					var a = holder[c];
					if (a >= 0 && end[a] >= rs && a < noSpillFrom && (victim < 0 || end[a] > end[victim]) && !fixedOverlap(c, rs, re))
						victim = a;
				}
				if (victim >= 0 && (end[victim] > re || r >= noSpillFrom)) {
					choice = assigned[victim];
					assigned[victim] = -1;
					spilled.push(victim);
				} else {
					if (r >= noSpillFrom) throw "hxmc: out of registers in " + f.name;
					spilled.push(r);
					continue;
				}
			}
			assigned[r] = choice;
			holder[choice] = r;
		}
		while (ci < nc) {
			snapshot(coldCalls[ci], holder);
			ci++;
		}
		return spilled;
	}

	var coldCalls:Array<Int> = []; // positions of the calls in cold blocks (the last round's)
	// per slow-path call (in order): the physical registers held by values
	// live across it, from coldSavedAt[k] to coldSavedAt[k + 1]
	var coldSaved:Array<Int> = [];
	var coldSavedAt:Array<Int> = [];

	function snapshot(p:Int, holder:Array<Int>) {
		coldSavedAt.push(coldSaved.length);
		for (c in 0...NPHYS) {
			var h = holder[c];
			if (h >= 0 && start[h] < p && end[h] > p + 1) coldSaved.push(c);
		}
	}

	// Saves the caller-saved registers live across each slow-path call into
	// frame slots before it and reloads them after it (allocate let values
	// stay in such registers across those calls).
	function coldSaves() {
		var nc = coldCalls.length;
		if (nc == 0) return;
		coldSavedAt.push(coldSaved.length);
		var slotOf = [for (_ in 0...NPHYS) -1];
		var defs = s.defs, uses = s.uses;
		var clobbered = [for (_ in 0...NPHYS) -1]; // stamped by call
		var ci = 0;
		for (b in f.blocks) {
			if (!b.cold || ci >= nc || coldCalls[ci] >= b.to) continue;
			var out = [];
			var p = b.from;
			for (i in b.ins) {
				if (ci < nc && coldCalls[ci] == p) {
					defs.n = 0;
					uses.n = 0;
					t.defsUses(i, defs, uses);
					for (k in 0...defs.n) {
						var d = defs.a[k];
						if (d >= 0 && d < NPHYS && !s.isResult[d]) clobbered[d] = ci;
					}
					var after = [];
					for (k in coldSavedAt[ci]...coldSavedAt[ci + 1]) {
						var a = coldSaved[k];
						if (clobbered[a] != ci) continue;
						if (slotOf[a] < 0) slotOf[a] = f.slot(8, 8);
						out.push(t.spillStore(slotOf[a], a, a >= f.fprBase));
						after.push(t.spillLoad(a, slotOf[a], a >= f.fprBase));
					}
					out.push(i);
					for (x in after)
						out.push(x);
					ci++;
				} else out.push(i);
				p += 2;
			}
			b.ins = out;
		}
	}

	function addFixed(r:Int, from:Int, to:Int) {
		var fr = fixedFrom[r], tr = fixedTo[r];
		var n = fr.length;
		if (n > 0 && fr[n - 1] == from) {
			if (tr[n - 1] < to) tr[n - 1] = to;
			return;
		}
		fr.push(from);
		tr.push(to);
	}

	// the ranges are recorded in position order (blocks in layout order,
	// instructions in order): no sorting needed
	function sortFixed(r:Int) {
		// a running maximum of the ends, so a binary search finds overlaps
		var m = -1;
		var ft = fixedTo[r];
		for (i in 0...ft.length) {
			if (ft[i] < m) ft[i] = m;
			m = ft[i];
		}
	}

	// whether physical register r has a fixed range overlapping [a, b]
	function fixedOverlap(r:Int, a:Int, b:Int):Bool {
		var fr = fixedFrom[r], tr = fixedTo[r];
		// first range whose (running max) end >= a
		var lo = 0, hi = fr.length;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (tr[mid] < a) lo = mid + 1 else hi = mid;
		}
		while (lo < fr.length && fr[lo] <= b) {
			if (fr[lo] <= b && fixedEnd(r, lo) >= a) return true;
			lo++;
		}
		return false;
	}

	inline function fixedEnd(r:Int, i:Int):Int
		return fixedTo[r][i];

	// ---- spill code

	function insertSpills(spilled:Array<Int>) {
		var slotOf = hxmc.Lir.Arrays.filled(f.nregs, -1);
		for (r in spilled)
			slotOf[r] = f.slot(8, 8);
		var defs = new RegList(), uses = new RegList();
		// per instruction: spilled register -> its temporary (stamped by instruction)
		var tmp = hxmc.Lir.Arrays.filled(f.nregs, -1);
		var tmpStamp = hxmc.Lir.Arrays.filled(f.nregs, -1);
		var stamp = 0;
		var nOld = f.nregs;
		if (noSpillFrom > nOld) noSpillFrom = nOld;
		for (b in f.blocks) {
			var out = [];
			var any = false;
			for (i in b.ins) {
				defs.n = 0;
				uses.n = 0;
				t.defsUses(i, defs, uses);
				stamp++;
				var mapped = false;
				for (k in 0...uses.n) {
					var r = uses.a[k];
					if (r < nOld && slotOf[r] >= 0 && tmpStamp[r] != stamp) {
						var nr = f.newReg(f.floatReg(r));
						tmp[r] = nr;
						tmpStamp[r] = stamp;
						mapped = true;
						out.push(t.spillLoad(nr, slotOf[r], f.floatReg(r)));
					}
				}
				var stores = null;
				for (k in 0...defs.n) {
					var r = defs.a[k];
					if (r < nOld && slotOf[r] >= 0) {
						if (tmpStamp[r] != stamp) {
							var nr = f.newReg(f.floatReg(r));
								tmp[r] = nr;
							tmpStamp[r] = stamp;
							mapped = true;
						}
						if (stores == null) stores = [];
						stores.push(t.spillStore(slotOf[r], tmp[r], f.floatReg(r)));
					}
				}
				if (mapped) {
					var st = stamp;
					rename(i, r -> r < nOld && tmpStamp[r] == st ? tmp[r] : r);
					any = true;
				}
				out.push(i);
				if (stores != null)
					for (s in stores)
						out.push(s);
			}
			if (any || out.length != b.ins.length) b.ins = out;
		}
		// the hints of spilled registers no longer apply
		for (r in spilled)
			f.setHint(r, -1);
	}

	public static function rename(i:LIns, m:Int->Int) {
		if (i.d >= NPHYS) i.d = m(i.d);
		if (i.s1 >= NPHYS) i.s1 = m(i.s1);
		if (i.s2 >= NPHYS) i.s2 = m(i.s2);
		if (i.s3 >= NPHYS) i.s3 = m(i.s3);
		if (i.base >= NPHYS) i.base = m(i.base);
		if (i.index >= NPHYS) i.index = m(i.index);
	}

	function rewrite() {
		for (b in f.blocks)
			for (i in b.ins) {
				rename(i, r -> {
					var a = assigned[r];
					if (a < 0) throw "hxmc: unallocated register " + r + " in " + f.name;
					a;
				});
				for (r in [i.d, i.s1, i.s2, i.s3, i.base, i.index])
					if (r >= 0 && r < NPHYS) usedRegs[r] = true;
			}
	}
}
