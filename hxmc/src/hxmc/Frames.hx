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
		var vals = f.vals;
		var cfg = f.cfg();
		var order = cfg.rpo;
		var n = order.length;
		// one walk in reverse postorder (a value before its uses, but a
		// phi's): the frame's address and those derived from it (r + a
		// constant: the push's new top) by offset; the slot each load or
		// store of the frame accesses (an array store's rooted array: the
		// runtime reads its slot); the push, pops and high-water test; the
		// operations that take the frame (OInfo.fr: a cold site's spill
		// slots, an array store's rooted array)
		var off = MFunc.ints(vals.length, NONE);
		off[r.id] = 0;
		inline function derived(v:Int):Bool
			return v >= 0 && off[v] != NONE;
		var slot = MFunc.ints(vals.length, -1);
		var nslots = 0, stores = 0, reads = 0;
		var manage:Array<MIns> = [], takers:Array<MIns> = [], phis:Array<MIns> = [];
		for (b in order)
			for (i in b.ins) {
				if (i.dead) continue;
				switch i.op {
					case Call if (i.returnsTwice):
						return; // (a try: its handlers read the slots)
					case Phi:
						phis.push(i);
						continue;
					case Add if (derived(i.a)):
						var c = vals[i.b];
						if (c.op != Const || c.sym != null || c.imm2 != (c.imm < 0 ? -1 : 0)) return;
						off[i.id] = off[i.a] + c.imm;
						continue;
					case Load | Store if (derived(i.a)):
						if (i.b >= 0 || i.size != 8 || i.op == Store && derived(i.c)) return;
						var s = off[i.a] + i.imm;
						if (s < 0 || s & 7 != 0) return;
						slot[i.id] = s >> 3;
						if ((s >> 3) >= nslots) nslots = (s >> 3) + 1;
						if (i.op == Store) stores++ else reads++;
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
						if (!i.isObj() || !i.info.fr || k != i.info.nspill || i.args[k] != r.id) return;
						takes = true;
					}
				if (takes) {
					takers.push(i);
					var s = i.info.rootSlot;
					if (s >= 0) {
						slot[i.id] = s;
						if (s >= nslots) nslots = s + 1;
						reads++;
					}
				}
			}
		for (p in phis)
			for (x in p.args)
				if (derived(x)) return;
		if (nslots == 0 && takers.length == 0) return;
		inline function isStore(i:MIns):Bool
			return i.op == Store && slot[i.id] >= 0;
		if (reads == 0) {
			// nothing reads the frame: no store is seen
			for (b in order)
				for (i in b.ins)
					if (isStore(i)) {
						i.dead = true;
						storesRemoved++;
					}
		} else if (stores > 0) {
			// the slots live at each point: read by a later load before a
			// store replaces them
			var inOrder = f.newMark();
			for (k in 0...n) {
				order[k].mark = inOrder;
				order[k].tmp = k;
			}
			var gen = new Vector<Bits>(n), kill = new Vector<Bits>(n), liveIn = new Vector<Bits>(n);
			for (k in 0...n) {
				var g = new Bits(nslots), x = new Bits(nslots);
				var ins = order[k].ins;
				var q = ins.length;
				while (q-- > 0) {
					var i = ins[q];
					var s = slot[i.id];
					if (s < 0 || i.dead) continue;
					if (i.op == Store) {
						x.set(s);
						g.clear(s);
					} else g.set(s);
				}
				gen[k] = g;
				kill[k] = x;
				liveIn[k] = g.copy();
			}
			var out = new Bits(nslots);
			function liveOut(k:Int) {
				out.w.fill(0);
				for (s in order[k].succs)
					if (s.mark == inOrder) out.union(liveIn[s.tmp]);
			}
			var changed = true;
			while (changed) {
				changed = false;
				var k = n;
				while (k-- > 0) {
					liveOut(k);
					// liveIn = gen | (out & ~kill)
					var w = out.w, kw = kill[k].w, gw = gen[k].w, iw = liveIn[k].w;
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
			for (k in 0...n) {
				liveOut(k);
				var ins = order[k].ins;
				var q = ins.length;
				while (q-- > 0) {
					var i = ins[q];
					var s = slot[i.id];
					if (s < 0 || i.dead) continue;
					if (i.op != Store) out.set(s) else if (!out.get(s)) {
						i.dead = true;
						storesRemoved++;
					} else out.clear(s);
				}
			}
		}
		// a frame nothing reads: not pushed (its operations push their
		// spills on their slow paths)
		if (reads == 0) {
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
