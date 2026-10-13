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

	public function new(f:LFunc, t:RegTarget) {
		this.f = f;
		this.t = t;
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

	function allocate():Array<Int> {
		var n = f.nregs;
		coldCalls = [];
		var defs = new RegList(), uses = new RegList();
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
		start = hxmc.Lir.Arrays.filled(n, 0x7fffffff);
		end = hxmc.Lir.Arrays.filled(n, -1);
		fixedFrom = [for (_ in 0...NPHYS) []];
		fixedTo = [for (_ in 0...NPHYS) []];
		var openFixed = hxmc.Lir.Arrays.filled(NPHYS, -1);
		var nb = f.blocks.length;
		for (bi in 0...nb)
			f.blocks[bi].id = bi;
		// per register: the blocks with a use not preceded by a definition in the block (upward-exposed)
		var exposedHead = hxmc.Lir.Arrays.filled(n, -1);
		var exposedBlock:Array<Int> = [], exposedNext:Array<Int> = [];
		// per block and register: defined in the block (stamped by block)
		var defStamp = hxmc.Lir.Arrays.filled(n, -1);
		var defsIn:Array<Array<Int>> = [];
		for (bi in 0...nb) {
			var b = f.blocks[bi];
			for (k in 0...NPHYS)
				openFixed[k] = -1;
			var p = b.from;
			var dl = [];
			for (i in b.ins) {
				defs.n = 0;
				uses.n = 0;
				t.defsUses(i, defs, uses);
				// a call on a slow path clobbers only its result registers here:
				// what lives across it is saved and restored around it (coldSaves)
				var coldCall = b.cold && t.isCall(i);
				if (coldCall) coldCalls.push(p);
				for (k in 0...uses.n) {
					var r = uses.a[k];
					if (r >= NPHYS) {
						if (end[r] < p) end[r] = p;
						if (start[r] > p) start[r] = p;
						if (defStamp[r] != bi) {
							// the first exposed use in this block: record once
							if (exposedHead[r] < 0 || exposedBlock[exposedHead[r]] != bi) {
								exposedBlock.push(bi);
								exposedNext.push(exposedHead[r]);
								exposedHead[r] = exposedBlock.length - 1;
							}
						}
					} else if (r >= 0) {
						var from = openFixed[r] >= 0 ? openFixed[r] : b.from;
						addFixed(r, from, p);
					}
				}
				for (k in 0...defs.n) {
					var r = defs.a[k];
					if (r >= NPHYS) {
						if (start[r] > p + 1) start[r] = p + 1;
						if (end[r] < p + 1) end[r] = p + 1;
						if (defStamp[r] != bi) {
							defStamp[r] = bi;
							dl.push(r);
						}
					} else if (r >= 0) {
						if (coldCall && t.callResults.indexOf(r) < 0) continue;
						openFixed[r] = p + 1;
						addFixed(r, p + 1, p + 1);
					}
				}
				p += 2;
			}
			defsIn.push(dl);
		}
		// which blocks define each register
		var defHead = hxmc.Lir.Arrays.filled(n, -1);
		var defBlock:Array<Int> = [], defNext:Array<Int> = [];
		for (bi in 0...nb)
			for (r in defsIn[bi]) {
				defBlock.push(bi);
				defNext.push(defHead[r]);
				defHead[r] = defBlock.length - 1;
			}
		var defines = hxmc.Lir.Arrays.filled(nb, -1); // stamped by register
		var liveInSeen = hxmc.Lir.Arrays.filled(nb, -1);
		var liveOutSeen = hxmc.Lir.Arrays.filled(nb, -1);
		var work:Array<Int> = [];
		for (r in NPHYS...n) {
			var e = exposedHead[r];
			if (e < 0) continue;
			var d = defHead[r];
			while (d >= 0) {
				defines[defBlock[d]] = r;
				d = defNext[d];
			}
			while (e >= 0) {
				work.push(exposedBlock[e]);
				e = exposedNext[e];
			}
			while (work.length > 0) {
				var bi = work.pop();
				if (liveInSeen[bi] == r) continue;
				liveInSeen[bi] = r;
				var b = f.blocks[bi];
				if (start[r] > b.from) start[r] = b.from;
				for (pr in b.preds) {
					if (liveOutSeen[pr.id] != r) {
						liveOutSeen[pr.id] = r;
						if (end[r] < pr.to) end[r] = pr.to;
						if (start[r] > pr.to) start[r] = pr.to;
					}
					if (defines[pr.id] != r) work.push(pr.id);
				}
			}
		}
		for (r in 0...NPHYS)
			sortFixed(r);
		// linear scan: intervals by start (a counting sort on positions; ties by register)
		var count = hxmc.Lir.Arrays.filled(pos + 2, 0);
		var live = 0;
		for (r in NPHYS...n)
			if (end[r] >= 0) {
				count[start[r] + 1]++;
				live++;
			}
		for (p in 1...pos + 2)
			count[p] += count[p - 1];
		var order = hxmc.Lir.Arrays.filled(live, 0);
		for (r in NPHYS...n)
			if (end[r] >= 0) order[count[start[r]]++] = r;
		assigned = hxmc.Lir.Arrays.filled(n, -1);
		for (r in 0...NPHYS)
			assigned[r] = r;
		// per physical register: the interval holding it (free once that ends)
		var holder = hxmc.Lir.Arrays.filled(NPHYS, -1);
		var isFpr = hxmc.Lir.Arrays.filled(NPHYS, 0);
		for (c in t.fprs)
			isFpr[c] = 1;
		for (c in t.gprs)
			isFpr[c] = 2;
		var spilled = [];
		for (r in order) {
			var s = start[r], e = end[r];
			var float = f.floatReg(r);
			var regs = float ? t.fprs : t.gprs;
			var choice = -1;
			var h = f.hint(r);
			if (h >= 0) {
				var hr = h < NPHYS ? h : assigned[h];
				if (hr >= 0 && isFpr[hr] == (float ? 1 : 2) && (holder[hr] < 0 || end[holder[hr]] < s) && !fixedOverlap(hr, s, e)) choice = hr;
			}
			if (choice < 0)
				for (c in regs) {
					var o = holder[c];
					if ((o < 0 || end[o] < s) && !fixedOverlap(c, s, e)) {
						choice = c;
						break;
					}
				}
			if (choice < 0) {
				// spill the live interval that ends last, if it ends after this one
				var victim = -1;
				for (c in regs) {
					var a = holder[c];
					if (a >= 0 && end[a] >= s && a < noSpillFrom && (victim < 0 || end[a] > end[victim]) && !fixedOverlap(c, s, e))
						victim = a;
				}
				if (victim >= 0 && (end[victim] > e || r >= noSpillFrom)) {
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
		return spilled;
	}

	var coldCalls:Array<Int> = []; // positions of the calls in cold blocks (the last round's)

	// Saves the caller-saved registers live across each slow-path call into
	// frame slots before it and reloads them after it (allocate let values
	// stay in such registers across those calls).
	function coldSaves() {
		if (coldCalls.length == 0) return;
		// coldCalls is sorted (positions in order); per call, the physical
		// registers of the values live across it
		var saves:Array<Array<Int>> = [for (_ in coldCalls) null];
		for (r in NPHYS...f.nregs) {
			var a = assigned[r];
			if (a < 0 || end[r] < 0 || t.callResults.indexOf(a) >= 0) continue;
			// the first call after start[r]
			var lo = 0, hi = coldCalls.length;
			while (lo < hi) {
				var mid = (lo + hi) >> 1;
				if (coldCalls[mid] <= start[r]) lo = mid + 1 else hi = mid;
			}
			while (lo < coldCalls.length && coldCalls[lo] + 1 < end[r]) {
				var l = saves[lo];
				if (l == null) saves[lo] = l = [];
				if (l.indexOf(a) < 0) l.push(a);
				lo++;
			}
		}
		var index = new Map<Int, Int>();
		for (k in 0...coldCalls.length)
			index.set(coldCalls[k], k);
		var slotOf = [for (_ in 0...NPHYS) -1];
		var defs = new RegList(), uses = new RegList();
		for (b in f.blocks) {
			if (!b.cold) continue;
			var out = [];
			var p = b.from;
			for (i in b.ins) {
				var k = index.get(p);
				var save = k == null ? null : saves[k];
				if (save != null) {
					// only what the call clobbers
					defs.n = 0;
					uses.n = 0;
					t.defsUses(i, defs, uses);
					var after = [];
					for (a in save) {
						var clobbered = false;
						for (j in 0...defs.n)
							if (defs.a[j] == a) clobbered = true;
						if (!clobbered) continue;
						if (slotOf[a] < 0) slotOf[a] = f.slot(8, 8);
						out.push(t.spillStore(slotOf[a], a, a >= f.fprBase));
						after.push(t.spillLoad(a, slotOf[a], a >= f.fprBase));
					}
					out.push(i);
					for (x in after)
						out.push(x);
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
