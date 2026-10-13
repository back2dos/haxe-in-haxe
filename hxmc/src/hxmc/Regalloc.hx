package hxmc;

import hxmc.Lir;

// What the register allocator needs to know about a target.
interface RegTarget {
	// the registers an instruction reads and writes, including fixed
	// physical ones and the registers a call clobbers (as definitions)
	function defsUses(i:LIns, defs:Array<Int>, uses:Array<Int>):Void;
	// a register to register copy: d <- s1
	function isMove(i:LIns):Bool;
	// allocatable registers in order of preference (caller-saved first)
	var gprs(default, null):Array<Int>;
	var fprs(default, null):Array<Int>;
	function spillLoad(r:Int, slot:Int, float:Bool):LIns;
	function spillStore(slot:Int, r:Int, float:Bool):LIns;
}

// Linear-scan register allocation (Poletto and Sarkar) with one live range
// per virtual register, on the block layout order. Physical registers
// named by instructions (call arguments and results, fixed operands, call
// clobbers) are fixed ranges no interval may overlap, so a value live across
// a call ends up in a callee-saved register or in memory. A spilled register
// lives in a frame slot: every use loads it into a fresh short-lived
// register and every definition stores it, and the allocation runs again.
class Regalloc {
	var f:LFunc;
	var t:RegTarget;
	public var assigned:Array<Int>; // register -> physical register
	public var usedRegs = new Map<Int, Bool>(); // physical registers used
	var noSpill = new Map<Int, Bool>(); // registers made by spill code

	public function new(f:LFunc, t:RegTarget) {
		this.f = f;
		this.t = t;
	}

	public function run() {
		for (round in 0...8) {
			var spilled = allocate();
			if (spilled.length == 0) {
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
		var defs = [], uses = [];
		// positions
		var pos = 0;
		for (b in f.blocks) {
			b.from = pos;
			pos += 2 * b.ins.length;
			b.to = pos;
			pos += 2;
		}
		// liveness of virtual registers
		var useB = [], defB = [];
		for (b in f.blocks) {
			var u = new Bits(n), d = new Bits(n);
			for (i in b.ins) {
				defs.resize(0);
				uses.resize(0);
				t.defsUses(i, defs, uses);
				for (r in uses)
					if (r >= 32 && !d.get(r)) u.set(r);
				for (r in defs)
					if (r >= 32) d.set(r);
			}
			useB.push(u);
			defB.push(d);
			b.liveIn = new Bits(n);
			b.liveOut = new Bits(n);
		}
		var changed = true;
		while (changed) {
			changed = false;
			var k = f.blocks.length;
			while (k-- > 0) {
				var b = f.blocks[k];
				for (s in b.succs)
					b.liveOut.union(s.liveIn);
				// in = use | (out & ~def)
				var inn = b.liveIn;
				var o = b.liveOut.w, u = useB[k].w, d = defB[k].w;
				for (j in 0...inn.w.length) {
					var v = u[j] | (o[j] & ~d[j]);
					if (v != inn.w[j]) {
						inn.w[j] = v;
						changed = true;
					}
				}
			}
		}
		// intervals and fixed ranges
		start = [for (_ in 0...n) 0x7fffffff];
		end = [for (_ in 0...n) -1];
		fixedFrom = [for (_ in 0...32) []];
		fixedTo = [for (_ in 0...32) []];
		var openFixed = [for (_ in 0...32) -1];
		var calls:Array<Int> = [];
		for (bi in 0...f.blocks.length) {
			var b = f.blocks[bi];
			for (r in 32...n) {
				if (b.liveIn.get(r) && start[r] > b.from) start[r] = b.from;
				if (b.liveOut.get(r) && end[r] < b.to) end[r] = b.to;
			}
			for (k in 0...32)
				openFixed[k] = -1;
			var p = b.from;
			for (i in b.ins) {
				defs.resize(0);
				uses.resize(0);
				t.defsUses(i, defs, uses);
				for (r in uses) {
					if (r >= 32) {
						if (end[r] < p) end[r] = p;
						if (start[r] > p) start[r] = p;
					} else if (r >= 0) {
						var from = openFixed[r] >= 0 ? openFixed[r] : b.from;
						addFixed(r, from, p);
					}
				}
				for (r in defs) {
					if (r >= 32) {
						if (start[r] > p + 1) start[r] = p + 1;
						if (end[r] < p + 1) end[r] = p + 1;
					} else if (r >= 0) {
						openFixed[r] = p + 1;
						addFixed(r, p + 1, p + 1);
					}
				}
				p += 2;
			}
		}
		for (r in 0...32)
			sortFixed(r);
		// linear scan
		var order = [for (r in 32...n) if (end[r] >= 0) r];
		order.sort((a, b) -> start[a] != start[b] ? start[a] - start[b] : a - b);
		assigned = [for (r in 0...n) r < 32 ? r : -1];
		var active:Array<Int> = [];
		var spilled = [];
		var spillSet = new Map<Int, Bool>();
		for (r in order) {
			// expire
			var k = 0;
			while (k < active.length) {
				if (end[active[k]] < start[r]) active.splice(k, 1) else k++;
			}
			var float = f.floatReg(r);
			var regs = float ? t.fprs : t.gprs;
			var busy = new Map<Int, Bool>();
			for (a in active)
				busy.set(assigned[a], true);
			var choice = -1;
			var h = f.hints.get(r);
			if (h != null) {
				var hr = h < 32 ? h : assigned[h];
				if (hr >= 0 && !busy.exists(hr) && regs.indexOf(hr) >= 0 && !fixedOverlap(hr, start[r], end[r])) choice = hr;
			}
			if (choice < 0)
				for (c in regs)
					if (!busy.exists(c) && !fixedOverlap(c, start[r], end[r])) {
						choice = c;
						break;
					}
			if (choice < 0) {
				// spill the active interval that ends last, if it ends after this one
				var victim = -1;
				for (a in active)
					if (f.floatReg(a) == float && !noSpill.exists(a) && !fixedOverlap(assigned[a], start[r], end[r])
						&& (victim < 0 || end[a] > end[victim]))
						victim = a;
				if (victim >= 0 && (end[victim] > end[r] || noSpill.exists(r))) {
					choice = assigned[victim];
					assigned[victim] = -1;
					active.remove(victim);
					spilled.push(victim);
					spillSet.set(victim, true);
				} else {
					if (noSpill.exists(r)) throw "hxmc: out of registers in " + f.name;
					spilled.push(r);
					spillSet.set(r, true);
					continue;
				}
			}
			assigned[r] = choice;
			active.push(r);
		}
		return spilled;
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

	function sortFixed(r:Int) {
		var fr = fixedFrom[r], tr = fixedTo[r];
		var idx = [for (i in 0...fr.length) i];
		idx.sort((a, b) -> fr[a] - fr[b]);
		fixedFrom[r] = [for (i in idx) fr[i]];
		fixedTo[r] = [for (i in idx) tr[i]];
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
		var slotOf = new Map<Int, Int>();
		for (r in spilled)
			slotOf.set(r, f.slot(8, 8));
		var defs = [], uses = [];
		for (b in f.blocks) {
			var out = [];
			for (i in b.ins) {
				defs.resize(0);
				uses.resize(0);
				t.defsUses(i, defs, uses);
				var map = new Map<Int, Int>();
				for (r in uses)
					if (slotOf.exists(r) && !map.exists(r)) {
						var nr = f.newReg(f.floatReg(r));
						noSpill.set(nr, true);
						map.set(r, nr);
						out.push(t.spillLoad(nr, slotOf.get(r), f.floatReg(r)));
					}
				var stores = [];
				for (r in defs)
					if (slotOf.exists(r)) {
						var nr = map.get(r);
						if (nr == null) {
							nr = f.newReg(f.floatReg(r));
							noSpill.set(nr, true);
							map.set(r, nr);
						}
						stores.push(t.spillStore(slotOf.get(r), nr, f.floatReg(r)));
					}
				if (map.keys().hasNext()) rename(i, r -> map.exists(r) ? map.get(r) : r);
				out.push(i);
				for (s in stores)
					out.push(s);
			}
			b.ins = out;
		}
		// the hints of spilled registers no longer apply
		for (r in spilled)
			f.hints.remove(r);
	}

	public static function rename(i:LIns, m:Int->Int) {
		if (i.d >= 32) i.d = m(i.d);
		if (i.s1 >= 32) i.s1 = m(i.s1);
		if (i.s2 >= 32) i.s2 = m(i.s2);
		if (i.s3 >= 32) i.s3 = m(i.s3);
		if (i.base >= 32) i.base = m(i.base);
		if (i.index >= 32) i.index = m(i.index);
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
					if (r >= 0 && r < 32) usedRegs.set(r, true);
			}
	}
}
