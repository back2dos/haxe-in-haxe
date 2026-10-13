package hxmc;

import hxmc.Mir;

// Machine-independent optimizations on MIR (target facts stay in Abi and
// the instruction selectors):
//  - redundancy elimination (global value numbering over the dominator
//    tree): a pure operation, or a load, equal to one in a dominating
//    position is replaced by it. Loads also need the same version of the
//    memory they read: memory is told apart by class (MIns.mem, set by
//    MirBuild: array headers, elements, object fields, globals,
//    shadow-stack slots, memory only calls change, immutable memory); a
//    store or call that may write a class gives it a new version, and so
//    does a join where the predecessors disagree, or a loop header whose
//    loop writes it.
//  - dead code: pure operations and loads nothing uses.
class Opt {
	// memory classes (MIns.mem)
	public static inline var MOther = 0; // anything: written by any store or call
	public static inline var MHdr = 1; // array headers (length, kind, data)
	public static inline var MElem = 2; // array elements
	public static inline var MField = 3; // object fields
	public static inline var MGlobal = 4; // global variables
	public static inline var MCallOnly = 5; // changed only by calls (rt_globals, the nursery bounds, inline caches)
	public static inline var MFrame = 6; // shadow-stack slots (calls may move what they hold)
	public static inline var MConst = 7; // never written (type tables, string lengths, object type indices)
	public static inline var MInit = 8; // stores initializing a fresh object (no load can see it before)
	static inline var MTls = 9; // thread-local variables (TlsLoad)
	static inline var NCLS = 10;

	// runtime functions that write no memory the code reads and do not collect
	static var readOnly = ["hx_aget_i_slow" => true, "hx_aget_f_slow" => true, "hx_aget_l_slow" => true, "rt_write_barrier" => true];

	var f:MFunc;
	var repl:Array<Int>;
	var ver:Array<Int>; // per load: the version of its memory class

	public function new(f:MFunc) {
		this.f = f;
	}

	public function run() {
		simplifyCfg();
		var order = rpo();
		if (order.length == 0) return;
		repl = [for (i in 0...f.vals.length) i];
		// copies are their operand
		for (bb in f.blocks)
			for (i in bb.ins)
				if (i.op == Copy && !i.dead) {
					repl[i.id] = i.a;
					i.dead = true;
				}
		ver = [for (_ in 0...f.vals.length) 0];
		// (not across setjmp: what a second return finds is in memory)
		var twice = false;
		for (b in order)
			for (i in b.ins)
				if (i.op == Call && i.returnsTwice) twice = true;
		if (!twice) {
			versions(order);
			canonicalize();
			gvn(order);
		}
		rewrite();
		dce();
	}

	// ---- control flow

	// Jump threading of the blocks that only test a phi of booleans (what
	// `a && b` and `a || b` become): [phi x, (const 0), c = cmp eq|ne x 0,
	// br c], nothing of it used elsewhere. A predecessor whose value is a
	// constant, or known from its own branch on the edge, jumps straight to
	// the target; one that jumps here unconditionally branches on its value.
	// Then a block that jumps to a block with no other predecessor absorbs it.
	function simplifyCfg() {
		var uses = [for (_ in f.vals) 0];
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.a >= 0) uses[i.a]++;
				if (i.b >= 0) uses[i.b]++;
				if (i.c >= 0) uses[i.c]++;
				if (i.args != null)
					for (x in i.args)
						uses[x]++;
			}
		var vals = f.vals;
		for (b in f.blocks.copy()) {
			if (b == f.entry || b.handler) continue;
			var ins = b.ins;
			var n = ins.length;
			if (n < 3 || n > 4) continue;
			var phi = ins[0], c = ins[n - 2], br = ins[n - 1];
			if (phi.op != Phi || br.op != Br || c.op != Cmp || br.a != c.id || uses[c.id] != 1 || uses[phi.id] != 1) continue;
			if (c.imm != CEq && c.imm != CNe || c.a != phi.id) continue;
			var z = vals[c.b];
			if (z.op != Const || z.sym != null || z.imm != 0 || z.imm2 != 0) continue;
			if (n == 4 && (ins[1] != z || uses[z.id] != 1)) continue;
			// targets when x is zero / not zero
			var onZero = c.imm == CEq ? br.targets[0] : br.targets[1];
			var onSet = c.imm == CEq ? br.targets[1] : br.targets[0];
			if (onZero == b || onSet == b || onZero == onSet || hasPhi(onZero) || hasPhi(onSet)) continue;
			var k = 0;
			while (k < b.preds.length) {
				var p = b.preds[k];
				var v = phi.args[k];
				var t = p.term();
				var known = -1; // 0: zero, 1: set
				var x = vals[v];
				if (x.op == Const && x.sym == null) known = x.imm == 0 && x.imm2 == 0 ? 0 : 1;
				else if (t != null && t.op == Br && t.a == v && t.targets[0] != t.targets[1]) known = t.targets[1] == b ? 0 : 1;
				if (known >= 0) {
					retarget(p, b, known == 0 ? onZero : onSet);
				} else if (t != null && t.op == Jmp && p.succs.length == 1) {
					// branch on the value here
					t.op = Br;
					t.a = v;
					t.targets = [onSet, onZero];
					p.succs = [onSet, onZero];
					onSet.preds.push(p);
					onZero.preds.push(p);
					uses[v]++;
				} else {
					k++;
					continue;
				}
				// drop the edge into b
				b.preds.splice(k, 1);
				phi.args.splice(k, 1);
			}
		}
		pruneBlocks();
		// merge a block into its only predecessor that jumps to it
		var changed = true;
		while (changed) {
			changed = false;
			for (b in f.blocks) {
				var t = b.term();
				if (t == null || t.op != Jmp) continue;
				var s = t.targets[0];
				if (s == b || s == f.entry || s.preds.length != 1 || s.handler || s.cold != b.cold) continue;
				// phis of a single predecessor are their operand
				var rest = [];
				for (i in s.ins)
					if (i.op == Phi) {
						i.op = Copy;
						i.a = i.args[0];
						i.args = null;
						i.block = b;
						rest.push(i);
					} else {
						i.block = b;
						rest.push(i);
					}
				b.ins.pop();
				for (i in rest)
					b.ins.push(i);
				b.succs = s.succs;
				for (x in s.succs)
					for (q in 0...x.preds.length)
						if (x.preds[q] == s) x.preds[q] = b;
				s.ins = [];
				s.preds = [];
				s.succs = [];
				f.blocks.remove(s);
				changed = true;
				break;
			}
		}
	}

	static inline function hasPhi(b:MBlock):Bool
		return b.ins.length > 0 && b.ins[0].op == Phi;

	// p's edge to `from` goes to `to` (no phis there) instead
	function retarget(p:MBlock, from:MBlock, to:MBlock) {
		var t = p.term();
		for (q in 0...t.targets.length)
			if (t.targets[q] == from) t.targets[q] = to;
		for (q in 0...p.succs.length)
			if (p.succs[q] == from) p.succs[q] = to;
		to.preds.push(p);
		// a branch with both edges to one block is a jump
		if (t.op == Br && t.targets[0] == t.targets[1]) {
			t.op = Jmp;
			t.a = -1;
			t.targets = [to];
			p.succs = [to];
			to.preds.remove(p);
		}
	}

	function pruneBlocks() {
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
				while (k >= 0) {
					s.preds.splice(k, 1);
					for (i in s.ins)
						if (i.op == Phi) i.args.splice(k, 1);
					k = s.preds.indexOf(b);
				}
			}
		}
		f.blocks = [for (b in f.blocks) if (reach.exists(b.id)) b];
	}

	function rpo():Array<MBlock> {
		var seen = new Map<Int, Bool>();
		var post = [];
		var stack:Array<MBlock> = [f.entry];
		var idx:Array<Int> = [0];
		seen.set(f.entry.id, true);
		while (stack.length > 0) {
			var top = stack.length - 1;
			var b = stack[top];
			var k = idx[top];
			if (k < b.succs.length) {
				idx[top] = k + 1;
				var s = b.succs[k];
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
		return post;
	}

	inline function res(x:Int):Int {
		if (x < 0) return x;
		while (repl[x] != x)
			x = repl[x];
		return x;
	}

	static inline function pure(op:Op):Bool
		return switch op {
			case Add | Sub | Mul | And | Or | Xor | Shl | Sar | Shr | Neg | Not | FAdd | FSub | FMul | FDiv | FNeg | FSqrt | FAbs | Cmp | SExt | ZExt | Trunc | I2F | F2I | BitsToF | FToBits | Select:
				true;
			case _: false;
		};

	// the classes an instruction writes, as a bit set (0: none)
	static function killMask(i:MIns):Int {
		return switch i.op {
			case Store:
				switch i.mem {
					case MInit: 0;
					case MOther: ((1 << NCLS) - 1) & ~(1 << MConst) & ~(1 << MCallOnly) & ~(1 << MTls);
					case c: (1 << c) | (1 << MOther);
				}
			case TlsStore: 1 << MTls;
			case Call if (i.returnsTwice || i.sym == null || !readOnly.exists(i.sym)): ((1 << NCLS) - 1) & ~(1 << MConst);
			case _: 0;
		};
	}

	var next = 1; // the next fresh version

	// the memory versions: per block in reverse postorder, from its
	// predecessors' (a loop header: new versions of what the loop writes),
	// through its instructions; recorded per load
	function versions(order:Array<MBlock>) {
		var n = order.length;
		var pos = new Map<Int, Int>();
		for (k in 0...n)
			pos.set(order[k].id, k);
		// per block: the classes it writes
		var kill = [for (b in order) {
			var m = 0;
			for (i in b.ins)
				if (!i.dead) m |= killMask(i);
			m;
		}];
		var outs:Array<Array<Int>> = [for (_ in 0...n) null];
		for (k in 0...n) {
			var b = order[k];
			var v:Array<Int> = null;
			var latch = -1;
			var mixed = 0; // classes the forward predecessors disagree on
			for (p in b.preds) {
				var pk = pos.get(p.id);
				if (pk == null) continue;
				if (pk >= k) {
					if (pk > latch) latch = pk;
					continue;
				}
				var o = outs[pk];
				if (v == null) v = o.copy() else
					for (c in 0...NCLS)
						if (v[c] != o[c]) mixed |= 1 << c;
			}
			if (v == null || b.handler) {
				v = [for (_ in 0...NCLS) next++];
			} else {
				if (latch >= 0)
					for (q in k...latch + 1)
						mixed |= kill[q];
				for (c in 0...NCLS)
					if (mixed & (1 << c) != 0) v[c] = next++;
			}
			for (i in b.ins) {
				if (i.dead) continue;
				if (i.op == Load) ver[i.id] = v[i.mem] else if (i.op == TlsLoad) ver[i.id] = v[MTls];
				var m = killMask(i);
				if (m != 0)
					for (c in 0...NCLS)
						if (m & (1 << c) != 0) v[c] = next++;
			}
			outs[k] = v;
		}
	}

	// operands compared as values: constants and addresses of the same thing are equal
	var canon:Array<Int>;

	inline function cres(x:Int):Int
		return x < 0 ? x : canon[res(x)];

	function canonicalize() {
		canon = [for (i in 0...f.vals.length) i];
		var first = new Map<String, Int>();
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.dead) continue;
				var k = switch i.op {
					case Const: "c" + (i.ty : Int) + ":" + i.imm + ":" + i.imm2 + ":" + i.sym;
					case SymAddr: "s" + i.sym + ":" + i.imm;
					case StackAddr: "a" + i.imm;
					case _: null;
				};
				if (k == null) continue;
				var j = first.get(k);
				if (j == null) first.set(k, i.id) else canon[i.id] = j;
			}
	}

	function same(x:MIns, y:MIns):Bool
		return x.op == y.op && x.ty == y.ty && cres(x.a) == cres(y.a) && cres(x.b) == cres(y.b) && cres(x.c) == cres(y.c) && x.imm == y.imm && x.imm2 == y.imm2
			&& x.size == y.size && x.signed == y.signed && x.sym == y.sym && x.mem == y.mem && ver[x.id] == ver[y.id];

	inline function hash(i:MIns):Int {
		var h = (i.op : Int) * 31 + cres(i.a);
		h = h * 31 + cres(i.b);
		h = h * 31 + cres(i.c);
		h = h * 31 + i.imm;
		h = h * 31 + i.imm2;
		return h * 31 + ver[i.id];
	}

	// value numbering in a preorder walk of the dominator tree, with a
	// scoped table (entries made in a subtree are undone after it)
	function gvn(order:Array<MBlock>) {
		var n = order.length;
		var pos = new Map<Int, Int>();
		for (k in 0...n)
			pos.set(order[k].id, k);
		// immediate dominators (Cooper, Harvey and Kennedy), as rpo indices
		var idom = [for (_ in 0...n) -1];
		idom[0] = 0;
		var preds = [for (b in order) [for (p in b.preds) if (pos.exists(p.id)) pos.get(p.id)]];
		var changed = true;
		while (changed) {
			changed = false;
			for (k in 1...n) {
				var d = -1;
				for (p in preds[k]) {
					if (idom[p] < 0) continue;
					if (d < 0) d = p else {
						var x = p, y = d;
						while (x != y) {
							while (x > y)
								x = idom[x];
							while (y > x)
								y = idom[y];
						}
						d = x;
					}
				}
				if (d >= 0 && idom[k] != d) {
					idom[k] = d;
					changed = true;
				}
			}
		}
		// children lists
		var childHead = [for (_ in 0...n) -1], childNext = [for (_ in 0...n) -1];
		var k = n - 1;
		while (k >= 1) {
			var d = idom[k];
			childNext[k] = childHead[d];
			childHead[d] = k;
			k--;
		}
		var table = new Map<Int, Array<Int>>();
		var log:Array<Int> = []; // hashes added, in order
		var vals = f.vals;
		// iterative preorder: a block is entered, its children walked, then left
		var stack = [0], mark = [0];
		var marks:Array<Int> = [];
		while (stack.length > 0) {
			var top = stack.length - 1;
			var bk = stack[top];
			if (mark[top] == 0) {
				mark[top] = 1;
				marks.push(log.length);
				for (i in order[bk].ins) {
					if (i.dead) continue;
					var op = i.op;
					// (comparisons are recomputed: they fuse with their branch)
					if (!(pure(op) || op == Load || op == TlsLoad) || op == Cmp) continue;
					var h = hash(i);
					var l = table.get(h);
					var hit = -1;
					if (l != null) {
						var q = l.length;
						while (q-- > 0)
							if (same(i, vals[l[q]])) {
								hit = l[q];
								break;
							}
					} else {
						l = [];
						table.set(h, l);
					}
					if (hit >= 0) {
						repl[i.id] = hit;
						i.dead = true;
					} else {
						l.push(i.id);
						log.push(h);
					}
				}
				var c = childHead[bk];
				// push children (reverse order does not matter)
				while (c >= 0) {
					stack.push(c);
					mark.push(0);
					c = childNext[c];
				}
			} else {
				stack.pop();
				mark.pop();
				var m = marks.pop();
				while (log.length > m) {
					var h = log.pop();
					table.get(h).pop();
				}
			}
		}
	}

	function rewrite() {
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.dead) continue;
				if (i.a >= 0) i.a = res(i.a);
				if (i.b >= 0) i.b = res(i.b);
				if (i.c >= 0) i.c = res(i.c);
				if (i.args != null)
					for (k in 0...i.args.length)
						i.args[k] = res(i.args[k]);
			}
	}

	// removes pure operations and loads without uses (to a fixed point)
	function dce() {
		var uses = [for (_ in f.vals) 0];
		for (b in f.blocks)
			for (i in b.ins)
				if (!i.dead) {
					if (i.a >= 0) uses[i.a]++;
					if (i.b >= 0) uses[i.b]++;
					if (i.c >= 0) uses[i.c]++;
					if (i.args != null)
						for (x in i.args)
							uses[x]++;
				}
		var work = [];
		for (b in f.blocks)
			for (i in b.ins)
				if (!i.dead && uses[i.id] == 0 && removable(i)) work.push(i);
		while (work.length > 0) {
			var i = work.pop();
			if (i.dead) continue;
			i.dead = true;
			for (x in [i.a, i.b, i.c])
				if (x >= 0 && --uses[x] == 0 && removable(f.vals[x])) work.push(f.vals[x]);
			if (i.args != null)
				for (x in i.args)
					if (--uses[x] == 0 && removable(f.vals[x])) work.push(f.vals[x]);
		}
		for (b in f.blocks)
			b.ins = [for (i in b.ins) if (!i.dead) i];
	}

	static inline function removable(i:MIns):Bool
		return pure(i.op) || i.op == Load || i.op == TlsLoad || i.op == Const || i.op == ConstF || i.op == SymAddr || i.op == StackAddr || i.op == Copy;
}
