package hxmc;

import backend.Ir;
import hxmc.Mir;

// Inlining of small functions into their callers, on Mir (after MirBuild,
// before Opt): the callee's blocks are copied in place of the call, its
// parameters replaced by the arguments, its returns by jumps to the rest of
// the caller's block (a phi joins the results).
//
// Candidates are decided on hxc's IR (`candidate`: no try, a small body),
// so that Fingerprint can put a candidate's body into the key of every
// module calling it; the final decision is on the callee's Mir: no
// shadow-stack frame (its references never live across a GC point, so the
// caller's roots are unchanged), no inline caches (their storage is the
// callee's), few instructions on its fast path.
class Inline {
	public static inline var MAX_IR = 40; // IR nodes of a candidate
	// instructions outside slow paths: of a callee inlined anywhere, and at a
	// call in a loop (size against speed; HXMC_INLINE=<flat>,<loop>)
	public static var MAX_FLAT = limit(0, 16);
	public static var MAX_LOOP = limit(1, 48);

	static function limit(k:Int, def:Int):Int {
		var e = Sys.getEnv("HXMC_INLINE");
		if (e == null) return def;
		var p = e.split(",");
		return k < p.length ? Std.parseInt(p[k]) : def;
	}
	public static inline var DEPTH = 2; // levels of inlining (Fingerprint keys callers to that depth)

	// whether f may be inlined (the IR test)
	public static function candidate(f:FuncInfo):Bool {
		if (f.hasTry) return false;
		var n = 0;
		function ex(e:Ex) {
			if (++n > MAX_IR) return;
			backend.EmitC.iterEx(ex, e);
		}
		function st(s:Stmt) {
			if (++n > MAX_IR) return;
			backend.EmitC.iterStmt(st, ex, s);
		}
		for (s in f.body) {
			st(s);
			if (n > MAX_IR) return false;
		}
		return true;
	}

	// the callee's Mir when it can be inlined (built once per caller module)
	public static function template(mb:MirBuild, mf:MFunc):Null<Template> {
		// (a callee with a shadow-stack frame keeps it: its copy pushes and pops it)
		var n = 0;
		for (b in mf.blocks)
			if (!b.cold)
				for (i in b.ins) {
					if (i.op == Call && i.returnsTwice) return null;
					// (constants and addresses fold into their users)
					if (i.op != Const && i.op != ConstF && i.op != SymAddr && i.op != StackAddr && i.op != Param) n++;
				}
		return n <= MAX_LOOP ? {mf: mf, sites: mb.inlineSites, size: n, icSym: mb.icSym, icaches: mb.icaches} : null;
	}

	// drops the blocks no longer reachable (after a callee that never returns)
	static function prune(f:MFunc) {
		var reach = new Map<Int, Bool>();
		var stack = [f.entry];
		reach.set(f.entry.id, true);
		while (stack.length > 0) {
			var b = stack.pop();
			for (s in b.succs)
				if (!reach.exists(s.id)) {
					reach.set(s.id, true);
					stack.push(s);
				}
		}
		for (b in f.blocks) {
			if (reach.exists(b.id)) continue;
			for (s in b.succs) {
				var k = s.preds.indexOf(b);
				if (k < 0) continue;
				s.preds.splice(k, 1);
				for (i in s.ins)
					if (i.op == Phi) i.args.splice(k, 1);
			}
		}
		f.blocks = [for (b in f.blocks) if (reach.exists(b.id)) b];
	}

	// the blocks of f in loops (a back edge in reverse postorder closes a
	// loop over the blocks between)
	public static function loopBlocks(f:MFunc):Map<MBlock, Bool> {
		var order = [];
		var seen = new Map<Int, Bool>();
		var stack = [f.entry], idx = [0];
		seen.set(f.entry.id, true);
		var post = [];
		while (stack.length > 0) {
			var top = stack.length - 1;
			var b = stack[top];
			if (idx[top] < b.succs.length) {
				var s = b.succs[idx[top]++];
				if (!seen.exists(s.id)) {
					seen.set(s.id, true);
					stack.push(s);
					idx.push(0);
				}
			} else {
				stack.pop();
				idx.pop();
				post.push(b);
			}
		}
		post.reverse();
		var pos = new Map<MBlock, Int>();
		for (k in 0...post.length)
			pos.set(post[k], k);
		var inLoop = new Map<MBlock, Bool>();
		for (k in 0...post.length)
			for (p in post[k].preds) {
				var pk = pos.get(p);
				if (pk != null && pk >= k)
					for (q in k...pk + 1)
						inLoop.set(post[q], true);
			}
		return inLoop;
	}

	// replaces each call (in f) by a copy of its callee's template
	// (returns the calls to candidates in the copies: inlined in turn, to a depth)
	public static function run(f:MFunc, sites:Array<{call:MIns, callee:Template}>, ic:IcAlloc):Array<{call:MIns, fn:FuncInfo}> {
		var more = [];
		if (sites.length == 0) return more;
		var nextBlock = 0;
		for (b in f.blocks)
			if (b.id >= nextBlock) nextBlock = b.id + 1;
		var repl = new Map<Int, Int>(); // call value -> result value
		for (site in sites) {
			var c = site.call, g = site.callee.mf;
			var b = c.block;
			var k = b.ins.indexOf(c);
			if (k < 0) continue;
			// the rest of the block after the call
			var tail = new MBlock(nextBlock++);
			tail.cold = b.cold;
			f.blocks.push(tail);
			tail.ins = b.ins.slice(k + 1);
			for (i in tail.ins)
				i.block = tail;
			b.ins = b.ins.slice(0, k);
			tail.succs = b.succs;
			for (s in tail.succs) {
				var q = s.preds.indexOf(b);
				while (q >= 0) {
					s.preds[q] = tail;
					q = s.preds.indexOf(b);
				}
			}
			b.succs = [];
			// the copy
			var vmap = new Map<Int, Int>();
			var bmap = new Map<Int, MBlock>();
			for (gb in g.blocks) {
				var nb = new MBlock(nextBlock++);
				nb.cold = gb.cold || b.cold;
				nb.sealed = nb.filled = true;
				bmap.set(gb.id, nb);
				f.blocks.push(nb);
			}
			var slotBase = f.slots.length;
			var icBase = ic.count;
			ic.count += site.callee.icaches;
			for (s in g.slots)
				f.slots.push(s);
			// values first (operands may refer forward: phis)
			for (gb in g.blocks)
				for (i in gb.ins) {
					if (i.op == Param) {
						vmap.set(i.id, c.args[i.imm]);
						continue;
					}
					var x = new MIns(i.op, i.ty);
					x.id = f.vals.length;
					f.vals.push(x);
					vmap.set(i.id, x.id);
				}
			var rets:Array<{block:MBlock, v:Int}> = [];
			for (gb in g.blocks) {
				var nb = bmap.get(gb.id);
				nb.preds = [for (p in gb.preds) bmap.get(p.id)];
				nb.succs = [for (s in gb.succs) bmap.get(s.id)];
				for (i in gb.ins) {
					if (i.op == Param) continue;
					var x = f.vals[vmap.get(i.id)];
					inline function m(v:Int):Int
						return v < 0 ? v : vmap.get(v);
					x.a = m(i.a);
					x.b = m(i.b);
					x.c = m(i.c);
					x.imm = i.imm;
					x.imm2 = i.imm2;
					x.f = i.f;
					x.size = i.size;
					x.signed = i.signed;
					x.sym = i.sym;
					x.mem = i.mem;
					x.noReturn = i.noReturn;
					x.returnsTwice = i.returnsTwice;
					x.argTys = i.argTys;
					x.cases = i.cases;
					if (i.args != null) x.args = [for (v in i.args) m(v)];
					if (i.targets != null) x.targets = [for (t in i.targets) bmap.get(t.id)];
					if (i.op == StackAddr) x.imm = i.imm + slotBase;
					if (i.op == SymAddr && i.sym == site.callee.icSym) {
						x.sym = ic.sym;
						x.imm = i.imm + Abi.IC_SIZE * icBase;
					}
					x.block = nb;
					if (i.op == Ret) {
						// a jump to the rest of the caller's block
						rets.push({block: nb, v: x.a});
						x.op = Jmp;
						x.ty = Void;
						x.a = -1;
						x.targets = [tail];
						nb.succs = [tail];
					}
					nb.ins.push(x);
				}
			}
			// into the callee
			var j = new MIns(Jmp, Void);
			j.id = f.vals.length;
			f.vals.push(j);
			j.block = b;
			var entry = bmap.get(g.entry.id);
			j.targets = [entry];
			b.ins.push(j);
			b.succs = [entry];
			entry.preds.push(b);
			tail.preds = [for (r in rets) r.block];
			// the result
			if (c.ty != Void) {
				if (rets.length == 1) repl.set(c.id, rets[0].v) else if (rets.length > 1) {
					var phi = new MIns(Phi, c.ty);
					phi.id = f.vals.length;
					f.vals.push(phi);
					phi.block = tail;
					phi.args = [for (r in rets) r.v];
					tail.ins.unshift(phi);
					repl.set(c.id, phi.id);
				}
			}
			c.dead = true;
			for (s in site.callee.sites)
				if (vmap.exists(s.call.id)) more.push({call: f.vals[vmap.get(s.call.id)], fn: s.fn});
			// a later site in the same block now lives in the tail
		}
		prune(f);
		// uses of the calls' results
		inline function r(v:Int):Int {
			if (v < 0) return v;
			var x = repl.get(v);
			while (x != null) {
				v = x;
				x = repl.get(v);
			}
			return v;
		}
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.a >= 0) i.a = r(i.a);
				if (i.b >= 0) i.b = r(i.b);
				if (i.c >= 0) i.c = r(i.c);
				if (i.args != null)
					for (q in 0...i.args.length)
						i.args[q] = r(i.args[q]);
			}
		return [for (m in more) if (!m.call.dead && m.call.block != null) m];
	}
}

typedef Template = {mf:MFunc, sites:Array<{call:MIns, fn:FuncInfo}>, size:Int, icSym:String, icaches:Int};

// the caller's inline caches: copies of a callee's get their own entries
typedef IcAlloc = {sym:String, count:Int};
