package hxmc;

import hxmc.Mir;
import hxmc.Lir.Bits;
import haxe.ds.Vector;

// The shadow-stack frame after optimization (docs/plans/codegen.md,
// "Object-level Mir"). Roots gives the rooted locals their slots on the IR,
// before inlining, Escape and Opt; after them, a store into a slot that no
// load of the slot can see any more goes (Opt took the stored value where
// nothing could collect in between, or the collection points were inlined
// or replaced away), and a frame left without loads is not pushed at all:
// the cold sites' slow paths push their spills instead. Functions with a
// try (setjmp) keep theirs: a handler reads the slots.
class Frames {
	var f:MFunc;

	public var storesRemoved = 0;
	public var frameRemoved = false;

	public function new(f:MFunc)
		this.f = f;

	static inline var NONE = 0x40000000; // (no offset: not the frame's address)

	public function run() {
		var r:Null<MIns> = null;
		for (i in f.entry.ins)
			if (i.op == TlsLoad && i.sym == "rt_sp" && !i.dead) {
				r = i;
				break;
			}
		if (r == null) return;
		for (b in f.blocks)
			for (i in b.ins)
				if (i.op == Call && i.returnsTwice) return;
		var vals = f.vals;
		// the frame's address and the addresses derived from it (r + a
		// constant: the push's new top), by offset
		var off = MFunc.ints(vals.length, NONE);
		off[r.id] = 0;
		var more = true;
		while (more) {
			more = false;
			for (b in f.blocks)
				for (i in b.ins)
					if (!i.dead && i.op == Add && i.ty == I64 && off[i.id] == NONE && off[i.a] != NONE) {
						var c = vals[i.b];
						if (c.op != Const || c.sym != null || c.imm2 != (c.imm < 0 ? -1 : 0)) return;
						off[i.id] = off[i.a] + c.imm;
						more = true;
					}
		}
		inline function derived(v:Int):Bool
			return v >= 0 && off[v] != NONE;
		// the accesses: slot loads and stores, the push, pops and high-water
		// test, the operations that take the frame (a cold site's spill slots,
		// an array store's rooted array: a load of its slot)
		var slotOf = new Map<Int, Int>(); // load or store -> its slot
		var nslots = 0;
		var manage:Array<MIns> = [];
		var takers:Array<MIns> = [];
		var taken = new Map<Int, Bool>();
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.dead) continue;
				switch i.op {
					case Add if (derived(i.a)):
						continue;
					case Load if (derived(i.a)):
						if (i.b >= 0 || i.size != 8) return;
						var s = off[i.a] + i.imm;
						if (s < 0 || s & 7 != 0) return;
						slotOf.set(i.id, s >> 3);
						if ((s >> 3) >= nslots) nslots = (s >> 3) + 1;
						continue;
					case Store if (derived(i.a)):
						if (i.b >= 0 || i.size != 8 || derived(i.c)) return;
						var s = off[i.a] + i.imm;
						if (s < 0 || s & 7 != 0) return;
						slotOf.set(i.id, s >> 3);
						if ((s >> 3) >= nslots) nslots = (s >> 3) + 1;
						continue;
					case TlsStore if ((i.sym == "rt_sp" || i.sym == "rt_sp_hw") && derived(i.a)):
						manage.push(i);
						continue;
					case Cmp if (derived(i.a) || derived(i.b)):
						if (i.imm != CUGt || !derived(i.a) || derived(i.b)) return;
						manage.push(i);
						continue;
					case _:
				}
				if (derived(i.a) || derived(i.b) || derived(i.c)) return;
				var takes = false;
				for (k in 0...i.args.length)
					if (derived(i.args[k])) {
						// (only as an operation's frame: OInfo.fr)
						if (!i.isObj() || !i.info.fr || k != i.info.nspill || i.args[k] != r.id) return;
						takes = true;
					}
				if (takes) {
					takers.push(i);
					taken.set(i.id, true);
					if (i.info.rootSlot >= nslots) nslots = i.info.rootSlot + 1;
				}
			}
		if (nslots == 0 && takers.length == 0) return;
		// the slots live at each point: read by a later load (or an array
		// store's runtime call) before a store replaces them
		var cfg = f.cfg();
		var order = cfg.rpo;
		var n = order.length;
		var inOrder = f.newMark();
		for (k in 0...n) {
			order[k].mark = inOrder;
			order[k].tmp = k;
		}
		var gen = new Vector<Bits>(n), kill = new Vector<Bits>(n), liveIn = new Vector<Bits>(n);
		inline function reads(i:MIns):Int
			return i.op == Load ? (slotOf.exists(i.id) ? slotOf.get(i.id) : -1) : i.info != null && i.info.rootSlot >= 0 && taken.exists(i.id) ? i.info.rootSlot : -1;
		for (k in 0...n) {
			var g = new Bits(nslots), x = new Bits(nslots);
			var ins = order[k].ins;
			var q = ins.length;
			while (q-- > 0) {
				var i = ins[q];
				if (i.dead) continue;
				if (i.op == Store && slotOf.exists(i.id)) {
					var s = slotOf.get(i.id);
					x.set(s);
					g.clear(s);
				} else {
					var s = reads(i);
					if (s >= 0) g.set(s);
				}
			}
			gen[k] = g;
			kill[k] = x;
			liveIn[k] = g.copy();
		}
		inline function liveOut(k:Int):Bits {
			var o = new Bits(nslots);
			for (s in order[k].succs)
				if (s.mark == inOrder) o.union(liveIn[s.tmp]);
			return o;
		}
		var changed = true;
		while (changed) {
			changed = false;
			var k = n;
			while (k-- > 0) {
				var o = liveOut(k);
				// liveIn = gen | (out & ~kill)
				var w = o.w, kw = kill[k].w, gw = gen[k].w, iw = liveIn[k].w;
				for (j in 0...w.length) {
					var v = gw[j] | (w[j] & ~kw[j]);
					if (v != iw[j]) {
						iw[j] = v;
						changed = true;
					}
				}
			}
		}
		// the stores nothing reads
		var loads = 0;
		for (k in 0...n) {
			var live = liveOut(k);
			var ins = order[k].ins;
			var q = ins.length;
			while (q-- > 0) {
				var i = ins[q];
				if (i.dead) continue;
				if (i.op == Store && slotOf.exists(i.id)) {
					var s = slotOf.get(i.id);
					if (!live.get(s)) {
						i.dead = true;
						storesRemoved++;
					} else live.clear(s);
				} else {
					var s = reads(i);
					if (s >= 0) {
						live.set(s);
						loads++;
					}
				}
			}
		}
		// a frame nothing reads: not pushed (its operations push their
		// spills on their slow paths)
		if (loads == 0) {
			for (i in manage)
				if (i.op == Cmp) {
					i.op = Const;
					i.imm = 0;
					i.imm2 = 0;
					i.a = i.b = -1;
				} else i.dead = true;
			for (i in takers) {
				var o = i.info;
				var a = new Vector<Int>(i.args.length - 1);
				var j = 0;
				for (k in 0...i.args.length)
					if (k != o.nspill) a[j++] = i.args[k];
				i.args = a;
				if (o.ops > o.nspill) o.ops--;
				o.fr = false;
				o.spillBase = -1;
			}
			frameRemoved = true;
		}
		if (storesRemoved > 0 || frameRemoved)
			for (b in f.blocks) {
				var ins = b.ins, k = 0;
				for (i in ins)
					if (!i.dead) ins[k++] = i;
				if (k < ins.length) ins.resize(k);
			}
	}
}
