package hxmc;

import hxmc.Mir;
import core.ds.VectorTools.vector;

// Shrink-wrapping of a function's shadow-stack frame (after Opt, native
// targets): MirBuild pushes the frame in the entry block (rt_sp += size,
// rt_sp_hw raised on a cold path), then stores the parameters it roots and
// zeroes the slots that may be read unassigned. When the paths that use the
// frame (its slots' loads and stores) all pass through a block D that the
// entry does not reach only through D, the push and those first stores move
// to the start of D, so that the paths that return before D (a function's
// early exits, after Opt forwarded the parameters' slots to their values)
// neither push nor store. The pops (rt_sp = the value read at the entry)
// stay where they are: on a path that did not push, rt_sp holds that value
// already. D also dominates every call (a possible collection) on a way to
// the frame's uses, since the parameters live in registers until the push,
// and no inlined callee's frame is pushed on a way to D (rt_sp must be the
// entry's value there). D is not in a loop (the push would run again).
// Nothing changes for a function with a try (setjmp) or when no such D
// exists. Opt-in, -D hxmc.shrink-wrap (or HXMC_SHRINKWRAP=1): it takes
// tsc-haxe's type check 1.4% fewer instructions and 2% less time, but the
// HaxeBenchmarks' nbody 8% more time (a frame pushed later on a path that
// always reaches it costs a jump). HXMC_SW_LOG=1 prints each
// function's outcome, HXMC_SW_ONLY=<symbol> and HXMC_SW_HASH=<lo>-<hi> (the
// symbol's hash mod 1000) bisect a miscompilation.
class ShrinkWrap {
	var f:MFunc;

	public static var moved = 0; // (statistics)
	static var log = Sys.getEnv("HXMC_SW_LOG") == "1";

	public function new(f:MFunc)
		this.f = f;

	inline function base(v:Int):Int {
		// an address of the frame: its base, or base + constant
		var x = f.vals[v];
		return x.op == Add && f.vals[x.b].op == Const ? x.a : v;
	}

	static var hashRange:Null<Array<Int>> = {
		var e = Sys.getEnv("HXMC_SW_HASH");
		e == null ? null : [for (x in e.split("-")) Std.parseInt(x)];
	};

	static var only = Sys.getEnv("HXMC_SW_ONLY");

	inline function no(why:String):Bool {
		if (log) Sys.println("shrink-wrap: " + f.name + ": no (" + why + ")");
		return false;
	}

	public function run():Bool {
		if (only != null && f.name != only) return false;
		if (hashRange != null) {
			var h = 0;
			for (k in 0...f.name.length)
				h = (h * 31 + StringTools.fastCodeAt(f.name, k)) & 0xFFFFF;
			h = h % 1000;
			if (h < hashRange[0] || h > hashRange[1]) return false;
		}
		var entry = f.entry;
		// the push: r = TlsLoad rt_sp; top = Add r, C; TlsStore rt_sp, top;
		// hw = TlsLoad rt_sp_hw; c = Cmp UGt top, hw; Br c -> up, done
		var push:MIns = null;
		for (i in entry.ins)
			if (i.op == TlsStore && i.sym == "rt_sp") {
				push = i;
				break;
			}
		if (push == null) return no("no push");
		var top = f.vals[push.a];
		if (top.op != Add || top.block != entry) return no("push shape");
		var r = f.vals[top.a];
		var cst = f.vals[top.b];
		if (r.op != TlsLoad || r.sym != "rt_sp" || r.block != entry || cst.op != Const || cst.sym != null) return no("push shape");
		var br = entry.term();
		if (br == null || br.op != Br) return no("push shape");
		var cmp = f.vals[br.a];
		if (cmp.op != Cmp || cmp.imm != (CUGt : Int) || cmp.a != top.id) return no("push shape");
		var hw = f.vals[cmp.b];
		if (hw.op != TlsLoad || hw.sym != "rt_sp_hw" || hw.block != entry) return no("push shape");
		var up = br.targets[0], done = br.targets[1];
		if (!up.cold || up.preds.length != 1 || done.preds.length != 2 || up.succs.length != 1 || up.succs[0] != done) return no("push shape");
		if (up.ins.length != 2 || up.ins[0].op != TlsStore || up.ins[0].sym != "rt_sp_hw" || up.ins[0].a != top.id) return no("push shape");
		// the entry after the push holds nothing else that matters here
		var k = entry.ins.indexOf(push);
		for (j in k + 1...entry.ins.length) {
			var i = entry.ins[j];
			if (i != hw && i != cmp && i != br) return no("push shape");
		}
		for (b in f.blocks)
			for (i in b.ins)
				if (i.op == Call && i.returnsTwice) return no("setjmp");
		// uses of the frame (r or top, directly or as base + constant)
		var initStores:Array<MIns> = [];
		var needed:Array<MBlock> = [];
		var neededMark = f.newMark();
		inline function need(b:MBlock) {
			if (b.mark != neededMark) {
				b.mark = neededMark;
				needed.push(b);
			}
		}
		// the values derived from the frame's addresses (r, top, and what
		// arithmetic, copies and phis make of them), to a fixed point
		var derived = MFunc.ints(f.vals.length, 0);
		derived[r.id] = 1;
		derived[top.id] = 2; // (2: from top, defined where the push moves: such a value must be after it)
		var grew = true;
		while (grew) {
			grew = false;
			for (b in f.blocks)
				for (i in b.ins) {
					if (derived[i.id] != 0) continue;
					var d = 0;
					switch i.op {
						case Add | Sub | Copy | And | Or | Xor:
							if (i.a >= 0 && derived[i.a] > d) d = derived[i.a];
							if (i.b >= 0 && derived[i.b] > d) d = derived[i.b];
						case Phi:
							for (x in i.args)
								if (derived[x] > d) d = derived[x];
						case _:
					}
					if (d != 0) {
						derived[i.id] = d;
						grew = true;
					}
				}
		}
		var initPhase = true;
		for (bk in 0...f.blocks.length) {
			var b = f.blocks[bk];
			for (i in b.ins) {
				if (i == push || i == hw || i == cmp || i == br || i == top || i == r) continue;
				if (b == up) continue;
				var uses = false;
				for (x in [i.a, i.b, i.c])
					if (x >= 0 && derived[x] != 0) uses = true;
				for (x in i.args)
					if (derived[x] != 0) uses = true;
				// (a derived value itself is not a use, its uses are; but one
				// made from top must come after the push)
				if (derived[i.id] == 1) uses = false;
				if (!uses) {
					// (the first block's leading stores of parameters and zeros, then anything else ends them)
					if (b == done && i.op != Const && i.op != Param) initPhase = false;
					continue;
				}
				// the pops: rt_sp = r
				if (i.op == TlsStore && i.sym == "rt_sp" && i.a == r.id) continue;
				if (b == done && initPhase && i.op == Store && i.a == r.id && i.b < 0 && i.c != r.id && i.c != top.id) {
					var v = f.vals[i.c];
					if (v.op == Param || v.op == Const && v.sym == null) {
						initStores.push(i);
						continue;
					}
				}
				if (b == done) initPhase = false;
				need(b);
			}
		}
		if (needed.length == 0) return no("frame unused"); // (Escape removes unused frames)
		// the calls (collections) on the ways to them need the frame too: the
		// parameters whose stores move are in registers until the push
		{
			var reach = f.newMark();
			var stack = needed.copy();
			for (b in stack)
				b.mark = reach;
			while (stack.length > 0) {
				var b = stack.pop();
				for (p in b.preds)
					if (p.mark != reach && p.mark != neededMark) {
						p.mark = reach;
						stack.push(p);
					}
			}
			// (needed blocks were re-marked: collect the reaching set first)
			var calls = [];
			for (b in f.blocks)
				if (b.mark == reach)
					for (i in b.ins)
						if (i.op == Call && !i.keepsFrame) {
							calls.push(b);
							break;
						}
			for (b in calls)
				if (needed.indexOf(b) < 0) needed.push(b);
		}
		// D: the nearest common dominator of the blocks that need the frame
		var order = rpo();
		var idx = new Map<Int, Int>();
		for (n in 0...order.length)
			idx.set(order[n].id, n);
		var idom = dominators(order, idx);
		var d = idx.get(needed[0].id);
		for (b in needed) {
			if (!idx.exists(b.id)) return no("unreachable use");
			d = intersect(idom, d, idx.get(b.id));
		}
		// out of loops
		while (d > 0 && inLoop(order[d]))
			d = idom[d];
		// no call (a collection) on a way from the entry to D: the parameters
		// whose stores move to D are in registers until then, and a
		// collection would leave them pointing at objects' old places
		var db = order[d];
		if (db == entry || db == done || db == up || db.handler) return no("no block after the entry");
		if (callBefore(db, push, up)) return no("a call or frame before");
		// D must not be reached from the entry only through D (some path avoids it)
		if (!avoidable(db)) return no("every path passes");
		// the init stores' values are defined in the entry (parameters, constants)
		for (s in initStores)
			if (f.vals[s.c].block != entry && f.vals[s.c].block != done) return no("init values");
		transform(db, push, top, hw, cmp, br, up, done, initStores);
		if (log) Sys.println("shrink-wrap: " + f.name + " at b" + db.id);
		moved++;
		return true;
	}

	// whether a block from which db is reachable (not passing db) calls, or
	// pushes or pops a frame of its own (an inlined callee's: at db, rt_sp
	// must be the value read at the entry)
	function callBefore(db:MBlock, push:MIns, up:MBlock):Bool {
		var seen = f.newMark();
		var stack = db.preds.copy();
		for (p in stack)
			p.mark = seen;
		while (stack.length > 0) {
			var b = stack.pop();
			for (i in b.ins) {
				if (i.op == Call && !i.keepsFrame) return true;
				if (i.op == TlsStore && (i.sym == "rt_sp" || i.sym == "rt_sp_hw") && i != push && b != up) return true;
			}
			for (p in b.preds)
				if (p != db && p.mark != seen) {
					p.mark = seen;
					stack.push(p);
				}
		}
		return false;
	}

	// whether some path from the entry reaches a return without passing db
	function avoidable(db:MBlock):Bool {
		var seen = f.newMark();
		var stack = [f.entry];
		f.entry.mark = seen;
		while (stack.length > 0) {
			var b = stack.pop();
			var t = b.term();
			if (t != null && t.op == Ret) return true;
			for (s in b.succs)
				if (s != db && s.mark != seen) {
					s.mark = seen;
					stack.push(s);
				}
		}
		return false;
	}

	function inLoop(b:MBlock):Bool {
		var seen = f.newMark();
		var stack = b.succs.copy();
		for (s in stack)
			s.mark = seen;
		while (stack.length > 0) {
			var x = stack.pop();
			if (x == b) return true;
			for (s in x.succs)
				if (s.mark != seen) {
					s.mark = seen;
					stack.push(s);
				}
		}
		return false;
	}

	function transform(db:MBlock, push:MIns, top:MIns, hw:MIns, cmp:MIns, br:MIns, up:MBlock, done:MBlock, initStores:Array<MIns>) {
		var entry = f.entry;
		// the entry no longer pushes: it jumps to `done`, `up` goes
		entry.ins.remove(push);
		entry.ins.remove(top);
		entry.ins.remove(hw);
		entry.ins.remove(cmp);
		br.op = Jmp;
		br.a = -1;
		br.targets = vector(done);
		entry.succs = [done];
		done.preds.remove(up);
		for (i in done.ins)
			if (i.op == Phi) throw "hxmc: shrink-wrap: phi after the push";
		f.blocks.remove(up);
		for (s in initStores)
			done.ins.remove(s);
		// db: its phis, then the push and the cold raise of rt_sp_hw, then the
		// init stores and the rest (d2)
		var d2 = newBlock();
		var phis = [], rest = [];
		for (i in db.ins)
			if (i.op == Phi) phis.push(i) else rest.push(i);
		d2.succs = db.succs;
		for (s in d2.succs)
			for (q in 0...s.preds.length)
				if (s.preds[q] == db) s.preds[q] = d2;
		d2.cold = db.cold;
		d2.sealed = d2.filled = true;
		var up2 = newBlock();
		up2.cold = true;
		up2.sealed = up2.filled = true;
		db.ins = phis;
		for (i in [top, push, hw, cmp]) {
			i.block = db;
			db.ins.push(i);
		}
		var nb = new MIns(Br, Void);
		nb.id = f.vals.length;
		f.vals.push(nb);
		nb.block = db;
		nb.a = cmp.id;
		nb.targets = vector(up2, d2);
		db.ins.push(nb);
		db.succs = [up2, d2];
		up2.preds = [db];
		d2.preds = [db, up2];
		var st = up.ins[0];
		st.block = up2;
		var j = new MIns(Jmp, Void);
		j.id = f.vals.length;
		f.vals.push(j);
		j.block = up2;
		j.targets = vector(d2);
		up2.ins = [st, j];
		up2.succs = [d2];
		for (s in initStores) {
			s.block = d2;
			d2.ins.push(s);
		}
		for (i in rest) {
			i.block = d2;
			d2.ins.push(i);
		}
	}

	// a block with an id no other has (MFunc.newBlock numbers by count, and
	// blocks were removed)
	function newBlock():MBlock {
		var id = 0;
		for (b in f.blocks)
			if (b.id >= id) id = b.id + 1;
		var b = new MBlock(id);
		f.blocks.push(b);
		return b;
	}

	// ---- reverse postorder and dominators (Cooper, Harvey and Kennedy)

	function rpo():Array<MBlock> {
		var seen = f.newMark();
		var post:Array<MBlock> = [];
		var stack = [f.entry], state = [0];
		f.entry.mark = seen;
		while (stack.length > 0) {
			var t = stack.length - 1;
			var b = stack[t];
			if (state[t] < b.succs.length) {
				var s = b.succs[state[t]++];
				if (s.mark != seen) {
					s.mark = seen;
					stack.push(s);
					state.push(0);
				}
			} else {
				post.push(b);
				stack.pop();
				state.pop();
			}
		}
		post.reverse();
		return post;
	}

	function dominators(order:Array<MBlock>, idx:Map<Int, Int>):Array<Int> {
		var n = order.length;
		var idom = [for (_ in 0...n) -1];
		idom[0] = 0;
		var changed = true;
		while (changed) {
			changed = false;
			for (k in 1...n) {
				var b = order[k];
				var nd = -1;
				for (p in b.preds) {
					if (!idx.exists(p.id)) continue;
					var pi = idx.get(p.id);
					if (idom[pi] < 0) continue;
					nd = nd < 0 ? pi : intersect(idom, nd, pi);
				}
				if (nd != idom[k]) {
					idom[k] = nd;
					changed = true;
				}
			}
		}
		return idom;
	}

	static function intersect(idom:Array<Int>, a:Int, b:Int):Int {
		while (a != b) {
			while (a > b)
				a = idom[a];
			while (b > a)
				b = idom[b];
		}
		return a;
	}
}
