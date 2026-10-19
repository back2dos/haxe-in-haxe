package hxmc;

import haxe.ds.Vector;
import hxmc.Mir;

// Escape analysis with scalar replacement (after inlining, before Sroa and
// Opt): an allocation that never leaves its function is replaced by its
// fields in SSA values, and is not made at all.
//
// The allocations are MirBuild's: the inline bump allocation of an object
// (a phi of the fast path's address and the slow path's stub call,
// MirBuild.alloc: class instances, anonymous objects, enum values,
// closures, the boxes of captured variables) and the runtime's boxing of an
// Int, Float or Int64 into a Dynamic (hx_box_int, hx_box_float,
// hx_box_i64). An allocation's aliases are its value, its copies, phis of
// aliases only, and what is read back from a shadow-stack slot (or a cold
// site's spill area: "cells", tracked as variables whose stores reach their
// loads, a collection moving nothing the transformation keeps) it was stored
// into. Allocations that meet at a phi form a group, replaced together when
// their layouts agree: the group's fields are one set of variables, which
// is right only when every use of an alias is a use of the group's latest
// instance (checked: the alias's instance is the group's reaching
// allocation at the use). An alias may be read and written at constant
// offsets (fields, the header's type index), compared with null, given to
// the write barrier (which a new object never needs), stored into a cell
// and, for a box, unboxed; anything else (a call, a return, a store into
// the heap or a global, a phi with another value, an identity comparison)
// is an escape, and the group stays as it was.
//
// Before that, the type index of any alias (escaping or not) is known: the
// inline caches' and enum switches' tests on it fold, so their slow paths
// (which take the object) go first.
class Escape {
	static inline var EMPTY = -1; // lattice: no allocation seen (yet)
	static inline var TOP = -2; // lattice: anything else, or several groups
	static inline var UNDEF = -2; // abstract value: no store reaches (the variable's entry)
	static inline var NONE = -3; // no definition in the block

	public static var on = Sys.getEnv("HXMC_ESCAPE") != "0";

	// the enum constructors by the symbol of their type index: the enum's
	// number and the tag (Driver sets it before compiling; read only)
	public static var ctorTags:Null<Map<String, {en:Int, tag:Int}>>;

	var f:MFunc;

	public var removed = 0; // allocation sites replaced
	public var folds = 0; // tests folded on known type indices

	var sites:Array<Site> = [];
	var siteAt:Map<Int, Int> = new Map(); // value of a site -> its index
	var uses:Array<Null<Array<MIns>>> = [];
	var vbase = 0; // abstract values: Mir values below, virtual phis from here
	var vpBlock:Array<MBlock> = [];
	var vpArgs:Array<Array<Int>> = [];
	// cells: shadow-stack slots and spill areas at constant offsets
	var cellOf:Vector<Int>; // load or store -> its cell (-1: none)
	var cellTracked:Array<Bool> = [];
	var cellLoads:Array<Array<MIns>> = [];
	var cellStores:Array<Array<MIns>> = [];
	var cellDone:Array<Bool> = [];
	var cellVps:Array<Array<Int>> = [];
	var reach:Map<Int, Int> = new Map(); // cell load -> the abstract value stored
	// the alias lattice (by abstract value)
	var src:Array<Int> = []; // (by abstract value: vbase + virtual phis long)
	var inClosure:Vector<Bool>; // (Mir values; virtual phis: vpIn)
	var vpIn:Array<Bool> = [];
	var closure:Array<Int> = [];
	var parent:Array<Int> = []; // union-find of sites
	var escaped:Array<Bool> = [];
	var repl:Map<Int, Int> = new Map(); // trivial phis -> their value

	public function new(f:MFunc)
		this.f = f;

	public function run() {
		for (b in f.blocks)
			for (i in b.ins)
				if (i.op == Call && i.returnsTwice) return;
		for (round in 0...3) {
			findSites();
			if (sites.length == 0) return;
			if (round == 0) deadPhis();
			analyze();
			if (round == 2 || !foldKnown()) break;
		}
		var groups = check();
		var any = false;
		for (g in groups)
			if (replace(g)) any = true else escape(g.root, "fields overlap");
		if (log) report(groups);
		if (!any) return;
		sweep();
		prune();
		trivialPhis();
	}

	// ---- allocation sites

	function findSites() {
		sites = [];
		siteAt = new Map();
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.dead) continue;
				var s:Null<Site> = null;
				if (i.op == Phi) s = objectSite(i);
				else if (i.op == Call && i.sym != null && i.args != null && i.args.length == 1) {
					var k = switch i.sym {
						case "hx_box_int": 1;
						case "hx_box_float": 2;
						case "hx_box_i64": 3;
						case _: 0;
					};
					if (k > 0) {
						s = new Site(i, i.block);
						s.defAt = i;
						s.box = k;
						s.key = "box" + k;
					}
				}
				if (s != null) {
					siteAt.set(i.id, sites.length);
					sites.push(s);
				}
			}
	}

	inline function constOf(v:Int):Null<MIns> {
		var c = f.vals[v];
		while (c.op == Copy)
			c = f.vals[c.a];
		return c.op == Const ? c : null;
	}

	function isConst(v:Int, k:Int):Bool {
		var c = constOf(v);
		return c != null && c.sym == null && c.imm == k && c.imm2 == (k < 0 ? -1 : 0);
	}

	// MirBuild.alloc's shape: head: ptr = young_ptr ... br (enough room) fast, slow;
	// fast: young_ptr = ptr + bytes, the header's two words, ptr + 8; join: phi(ptr + 8, stub())
	function objectSite(p:MIns):Null<Site> {
		if (p.ty != I64 || p.args == null || p.args.length != 2) return null;
		var j = p.block;
		if (j.preds.length != 2) return null;
		for (k in 0...2) {
			var o = f.vals[p.args[k]], r = f.vals[p.args[1 - k]];
			if (o.op != Add || r.op != Call || r.sym == null || !StringTools.startsWith(r.sym, MirBuild.ALLOC_STUB)) continue;
			var fast = o.block;
			if (j.preds[k] != fast || fast.preds.length != 1 || fast.succs.length != 1) continue;
			var ptr = f.vals[o.a];
			if (ptr.op != TlsLoad || ptr.sym != "rt_young_ptr" || !isConst(o.b, 8)) continue;
			var head = fast.preds[0];
			var br = head.term();
			if (ptr.block != head || br == null || br.op != Br || br.targets[0] != fast || br.targets[1] == fast) continue;
			var tls:MIns = null, hdr:MIns = null, ty:MIns = null, bytes = -1;
			var ok = true;
			for (i in fast.ins) {
				if (i.dead) continue;
				switch i.op {
					case Const | Jmp:
					case Add if (i.a == ptr.id):
					case TlsStore if (i.sym == "rt_young_ptr" && tls == null):
						var a = f.vals[i.a];
						var c = a.op == Add && a.a == ptr.id ? constOf(a.b) : null;
						if (c == null || c.sym != null) ok = false else {
							tls = i;
							bytes = c.imm;
						}
					case Store if (i.a == ptr.id && i.b < 0 && i.size == 4 && i.imm == 0 && hdr == null):
						hdr = i;
					case Store if (i.a == ptr.id && i.b < 0 && i.size == 4 && i.imm == 4 && ty == null):
						ty = i;
					case _:
						ok = false;
				}
			}
			if (!ok || tls == null || hdr == null || ty == null || bytes < 16 || bytes & 7 != 0) continue;
			var hc = constOf(hdr.c), tc = constOf(ty.c);
			if (hc == null || tc == null || hc.sym != null) continue;
			var s = new Site(p, j);
			// (its values are defined where it is first used: what the block
			// computes before, its constructor's arguments, may read the
			// previous instance of its group)
			s.defAt = j.term();
			for (i in j.ins) {
				if (i.dead || i.op == Phi) continue;
				if (i.a == p.id || i.b == p.id || i.c == p.id || i.args != null && i.args.indexOf(p.id) >= 0) {
					s.defAt = i;
					break;
				}
			}
			if (s.defAt == null) return null;
			s.head = head;
			s.fast = fast;
			s.tls = tls;
			s.hdr = hdr;
			s.ty = ty;
			s.nslots = (bytes >> 3) - 1;
			s.key = "o" + hc.imm + ":" + (tc.sym == null ? "" : tc.sym) + ":" + tc.imm;
			return s;
		}
		return null;
	}

	// ---- analysis

	// phis and copies nothing (but such) uses go first: MirBuild leaves
	// unused phis, which would merge aliases with other values
	function deadPhis() {
		var live = new Vector<Bool>(f.vals.length);
		var work:Array<Int> = [];
		inline function mark(v:Int) {
			if (v >= 0 && !live[v]) {
				live[v] = true;
				var i = f.vals[v];
				if (i.op == Phi || i.op == Copy) work.push(v);
			}
		}
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.dead || i.op == Phi || i.op == Copy) continue;
				mark(i.a);
				mark(i.b);
				mark(i.c);
				if (i.args != null)
					for (x in i.args)
						mark(x);
			}
		while (work.length > 0) {
			var i = f.vals[work.pop()];
			mark(i.a);
			if (i.args != null)
				for (x in i.args)
					mark(x);
		}
		for (b in f.blocks) {
			var ins = b.ins, k = 0;
			for (i in ins) {
				if ((i.op == Phi || i.op == Copy) && !live[i.id]) i.dead = true;
				if (!i.dead) ins[k++] = i;
			}
			if (k < ins.length) ins.resize(k);
		}
	}

	function buildUses() {
		uses = [];
		uses.resize(f.vals.length);
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.dead) continue;
				inline function use(v:Int) {
					var u = uses[v];
					if (u == null) uses[v] = [i] else if (u[u.length - 1] != i) u.push(i);
				}
				if (i.a >= 0) use(i.a);
				if (i.b >= 0) use(i.b);
				if (i.c >= 0) use(i.c);
				if (i.args != null)
					for (x in i.args)
						use(x);
			}
	}

	function analyze() {
		buildUses();
		vbase = f.vals.length;
		vpBlock = [];
		vpArgs = [];
		reach = new Map();
		repl = new Map();
		findCells();
		parent = [for (k in 0...sites.length) k];
		escaped = [for (_ in sites) false];
		whys = [for (_ in sites) null];
		// the closure: what may be an alias
		inClosure = new Vector(vbase);
		closure = [];
		src = [for (_ in 0...vbase) EMPTY];
		vpIn = [];
		inline function add(x:Int) {
			if (!isIn(x)) {
				if (x >= vbase) vpIn[x - vbase] = true else inClosure[x] = true;
				closure.push(x);
			}
		}
		for (s in sites)
			add(s.v.id);
		var k = 0;
		while (k < closure.length) {
			var x = closure[k++];
			if (x >= vbase) continue;
			var us = uses[x];
			if (us == null) continue;
			for (u in us)
				switch u.op {
					case Copy | Phi:
						add(u.id);
					case Store if (u.c == x && u.a != x):
						var c = cellOf[u.id];
						if (c >= 0 && cellTracked[c]) {
							cellReach(c);
							for (l in cellLoads[c])
								add(l.id);
							for (v in cellVps[c])
								add(v);
						}
					case _:
				}
		}
		// the lattice, from below
		var changed = true;
		while (changed) {
			changed = false;
			for (x in closure) {
				var n = compute(x);
				var o = src[x];
				if (o >= 0) o = find(o);
				if (n != o) {
					src[x] = n;
					changed = true;
				}
			}
		}
		for (x in closure) {
			var s = src[x];
			if (s >= 0) src[x] = find(s);
		}
		// the layouts of a group agree; (boxes) one per block
		var boxAt = new Map<Int, Int>();
		for (k in 0...sites.length) {
			var r = find(k);
			if (sites[r].key != sites[k].key) escape(r, "layouts differ");
			if (sites[k].box > 0) {
				var o = boxAt.get(sites[k].block.id);
				if (o != null && find(o) == r) escape(r, "two boxes in a block");
				boxAt.set(sites[k].block.id, k);
			}
		}
		// trivial phis (of the closure) are their value
		var phis = [];
		for (x in closure)
			if (x >= vbase || f.vals[x].op == Phi) phis.push(x);
		collapse(phis);
	}

	function find(k:Int):Int {
		while (parent[k] != k) {
			parent[k] = parent[parent[k]];
			k = parent[k];
		}
		return k;
	}

	function escape(s:Int, ?why:String) {
		var r = find(s);
		escaped[r] = true;
		if (log && whys[r] == null) whys[r] = why == null ? "?" : why;
	}

	// (HXMC_ESCAPE_LOG=1) why a group stays, per site
	static var log = Sys.getEnv("HXMC_ESCAPE_LOG") == "1";
	var whys:Array<Null<String>> = [];
	var lastFail:Null<MIns>;

	function report(groups:Array<Group>) {
		var lines = [];
		for (k in 0...sites.length) {
			var r = find(k);
			var s = sites[k];
			var what = s.box > 0 ? "box" + s.box : s.key.substr(s.key.indexOf(":") + 1);
			var w = escaped[r] ? (whys[r] == null ? "?" : whys[r]) : "replaced";
			lines.push('escape: ${f.name}: $what: $w');
		}
		Sys.println(lines.join("\n"));
	}

	function failWhy(u:Null<MIns>):String {
		if (u == null) return "use";
		var s = MFunc.opName(u.op);
		if (u.op == Call) s += " " + (u.sym == null ? "(indirect)" : u.sym);
		if (u.op == Store) s += u.c >= 0 && f.vals[u.c] != null && isIn(u.c) ? " (as a value)" : "";
		return s;
	}

	// the lattice's join: two groups meeting become one; a group meeting
	// anything else escapes
	function merge(a:Int, b:Int):Int {
		if (a == EMPTY) return b;
		if (b == EMPTY) return a;
		if (a == TOP || b == TOP) {
			if (a >= 0) escape(a, "merge");
			if (b >= 0) escape(b, "merge");
			return TOP;
		}
		var ra = find(a), rb = find(b);
		if (ra == rb) return ra;
		// (the smaller index the root: deterministic)
		var e = escaped[ra] || escaped[rb];
		var w = whys[ra] != null ? whys[ra] : whys[rb];
		if (ra < rb) {
			parent[rb] = ra;
			escaped[ra] = e;
			whys[ra] = w;
			return ra;
		}
		parent[ra] = rb;
		escaped[rb] = e;
		whys[rb] = w;
		return rb;
	}

	inline function absSrc(x:Int):Int {
		if (x < 0) return TOP;
		if (!isIn(x)) return TOP;
		var s = src[x];
		return s >= 0 ? find(s) : s;
	}

	function compute(x:Int):Int {
		if (x >= vbase) {
			var r = EMPTY;
			for (a in vpArgs[x - vbase])
				r = merge(r, absSrc(a));
			return r;
		}
		var s = siteAt.get(x);
		if (s != null) return find(s);
		var i = f.vals[x];
		return switch i.op {
			case Copy: absSrc(i.a);
			case Phi:
				var r = EMPTY;
				for (a in i.args)
					r = merge(r, a == x ? EMPTY : absSrc(a));
				r;
			case Load if (reach.exists(x)): absSrc(reach.get(x));
			case _: TOP;
		};
	}

	// phis whose operands are one value (or the phi) are that value
	function collapse(phis:Array<Int>) {
		var changed = true;
		while (changed) {
			changed = false;
			for (p in phis) {
				if (repl.exists(p)) continue;
				var args = p >= vbase ? vpArgs[p - vbase] : f.vals[p].args;
				var same = NONE, trivial = true;
				for (a in args) {
					var x = resolve(a);
					if (x == p || x == same) continue;
					if (same != NONE) {
						trivial = false;
						break;
					}
					same = x;
				}
				if (trivial && same != NONE) {
					repl.set(p, same);
					changed = true;
				}
			}
		}
	}

	// the value behind copies, trivial phis and cell loads
	function resolve(x:Int):Int {
		var n = 0;
		while (x >= 0 && n++ < 100000) {
			var r = repl.get(x);
			if (r != null) {
				x = r;
				continue;
			}
			if (x >= vbase) break;
			var i = f.vals[x];
			if (i.op == Copy) {
				x = i.a;
				continue;
			}
			if (i.op == Load) {
				var c = reach.get(x);
				if (c != null) {
					x = c;
					continue;
				}
			}
			break;
		}
		return x;
	}

	// ---- cells

	function findCells() {
		cellOf = MFunc.ints(f.vals.length, -1);
		cellTracked = [];
		cellLoads = [];
		cellStores = [];
		cellDone = [];
		cellVps = [];
		for (b in f.blocks)
			for (i in b.ins)
				if (!i.dead && i.op == TlsLoad && i.sym == "rt_sp") cellRoot(i);
	}

	// the accesses of one shadow-stack frame or spill area (an rt_sp value),
	// at constant offsets; an address that leaves (but as a call's argument:
	// the runtime's slot handles) keeps the whole area untracked
	function cellRoot(r:MIns) {
		var acc:Array<MIns> = [], accOff:Array<Int> = [];
		var all = false;
		var untrack = new Map<Int, Bool>();
		var work = [r.id], workOff = [0];
		var seen = new Map<Int, Bool>();
		while (work.length > 0 && !all) {
			var v = work.pop(), off = workOff.pop();
			if (seen.exists(v)) continue;
			seen.set(v, true);
			var us = uses[v];
			if (us == null) continue;
			for (u in us) {
				switch u.op {
					case Load if (u.a == v && u.b < 0 && u.size == 8):
						acc.push(u);
						accOff.push(off + u.imm);
					case Store if (u.a == v && u.b < 0 && u.c != v && u.size == 8):
						acc.push(u);
						accOff.push(off + u.imm);
					case Add if (u.a == v && u.b != v):
						var c = constOf(u.b);
						if (c == null || c.sym != null || c.imm2 != (c.imm < 0 ? -1 : 0)) all = true else {
							work.push(u.id);
							workOff.push(off + c.imm);
						}
					case Copy:
						work.push(u.id);
						workOff.push(off);
					case TlsStore if ((u.sym == "rt_sp" || u.sym == "rt_sp_hw") && u.a == v):
					case Cmp:
					case Call if (u.a != v):
						untrack.set(off, true);
					case _:
						all = true;
				}
				if (all) break;
			}
		}
		var at = new Map<Int, Int>();
		for (k in 0...acc.length) {
			var c = at.get(accOff[k]);
			if (c == null) {
				c = cellTracked.length;
				at.set(accOff[k], c);
				cellTracked.push(!all && !untrack.exists(accOff[k]));
				cellLoads.push([]);
				cellStores.push([]);
				cellDone.push(false);
				cellVps.push([]);
			}
			cellOf[acc[k].id] = c;
			if (acc[k].op == Load) cellLoads[c].push(acc[k]) else cellStores[c].push(acc[k]);
		}
	}

	static var noUses:Array<MIns> = [];

	inline function usesOf(v:Int):Array<MIns> {
		var u = uses[v];
		return u == null ? noUses : u;
	}

	inline function isIn(x:Int):Bool
		return x >= vbase ? vpIn[x - vbase] == true : x >= 0 && inClosure[x];

	// the source of an alias (a group's root), EMPTY or TOP
	inline function srcOf(x:Int):Int
		return isIn(x) ? src[x] : TOP;

	function newVp(b:MBlock):Int {
		vpBlock.push(b);
		vpArgs.push([]);
		src.push(EMPTY);
		vpIn.push(false);
		return vbase + vpBlock.length - 1;
	}

	// the store reaching each load of cell c (virtual phis where they meet)
	function cellReach(c:Int) {
		if (cellDone[c]) return;
		cellDone[c] = true;
		var blocks:Array<MBlock> = [];
		var seen = new Map<Int, Bool>();
		for (l in [cellLoads[c], cellStores[c]])
			for (i in l)
				if (!seen.exists(i.block.id)) {
					seen.set(i.block.id, true);
					blocks.push(i.block);
				}
		var last = new Map<Int, Int>();
		var early:Array<MIns> = [];
		for (b in blocks) {
			var cur = NONE;
			for (i in b.ins) {
				if (i.dead || cellOf[i.id] != c) continue;
				if (i.op == Store) cur = i.c else if (cur != NONE) reach.set(i.id, cur) else early.push(i);
			}
			if (cur != NONE) last.set(b.id, cur);
		}
		var first = vpBlock.length;
		var rd = new Reader(f.entry, UNDEF, b -> {
			var d = last.get(b.id);
			d == null ? NONE : d;
		}, newVp, (v, args) -> vpArgs[v - vbase] = args);
		for (l in early)
			reach.set(l.id, rd.readEntry(l.block));
		rd.finish();
		for (k in first...vpBlock.length)
			cellVps[c].push(vbase + k);
	}

	// ---- folding on known type indices

	// the type index of an alias is its group's; an alias is not null; then
	// comparisons of equal constants, and branches and switches on constants
	function foldKnown():Bool {
		var n = 0;
		for (x in closure) {
			if (x >= vbase) continue;
			var s = src[x];
			if (s < 0 || !sameKeys(s)) continue;
			var site = sites[s];
			for (u in usesOf(x)) {
				if (u.dead) continue;
				switch u.op {
					case Load if (site.box == 0 && u.a == x && u.b < 0 && u.imm == Abi.HDR_TINDEX && u.size == 2):
						var tc = constOf(site.ty.c);
						u.op = Const;
						u.a = -1;
						u.sym = tc.sym;
						u.imm = tc.imm;
						u.imm2 = tc.imm2;
						u.size = 0;
						u.mem = 0;
						n++;
					case Cmp if ((u.imm == CEq || u.imm == CNe) && (u.a == x && isConst(u.b, 0) || u.b == x && isConst(u.a, 0))):
						toConst(u, u.imm == CEq ? 0 : 1);
						n++;
					case _:
				}
			}
		}
		if (n == 0) return false;
		folds += n;
		constFold();
		prune();
		return true;
	}

	// whether the group of site s has one layout
	function sameKeys(s:Int):Bool {
		var r = find(s);
		for (k in 0...sites.length)
			if (find(k) == r && sites[k].key != sites[r].key) return false;
		return true;
	}

	function toConst(i:MIns, v:Int) {
		i.op = Const;
		i.a = -1;
		i.b = -1;
		i.c = -1;
		i.sym = null;
		i.imm = v;
		i.imm2 = v < 0 && i.ty == I64 ? -1 : 0;
		i.size = 0;
		i.mem = 0;
	}

	function constFold() {
		for (b in f.blocks)
			for (i in b.ins) {
				if (i.dead) continue;
				switch i.op {
					case Cmp if (i.imm == CEq || i.imm == CNe):
						var x = constOf(i.a), y = constOf(i.b);
						if (x == null || y == null || x.ty != y.ty) continue;
						var eq = if (x.sym == y.sym && x.imm == y.imm && x.imm2 == y.imm2) 1 else if (x.sym == null && y.sym == null) 0 else if (x.sym != null
							&& y.sym != null && x.imm == 0 && y.imm == 0 && x.imm2 == 0 && y.imm2 == 0 && StringTools.startsWith(x.sym, "TY_")
							&& StringTools.startsWith(y.sym, "TY_")) 0 else -1;
						if (eq >= 0) toConst(i, i.imm == CEq ? eq : 1 - eq);
					case Sub if (i.ty == I32):
						var x = constOf(i.a), y = constOf(i.b);
						if (x == null || y == null || x.sym == null || y.sym == null || x.imm2 != 0 || y.imm2 != 0) continue;
						if (x.sym == y.sym) toConst(i, x.imm - y.imm) else {
							// (constructors of one enum: their type indices less their tags are the same)
							var tx = ctorTags == null ? null : ctorTags.get(x.sym), ty = ctorTags == null ? null : ctorTags.get(y.sym);
							if (tx != null && ty != null && tx.en == ty.en) toConst(i, tx.tag + x.imm - ty.tag - y.imm);
						}
					case Br:
						var c = constOf(i.a);
						if (c == null || c.sym != null) continue;
						jumpTo(b, i, c.imm != 0 || c.imm2 != 0 ? i.targets[0] : i.targets[1]);
					case Switch:
						var c = constOf(i.a);
						if (c == null || c.sym != null) continue;
						var to = i.targets[i.targets.length - 1];
						for (k in 0...i.cases.length)
							if (i.cases[k] == c.imm) {
								to = i.targets[k];
								break;
							}
						jumpTo(b, i, to);
					case _:
				}
			}
	}

	// b's terminator t becomes a jump to `to` (the edges to its other successors go)
	function jumpTo(b:MBlock, t:MIns, to:MBlock) {
		for (s in b.succs) {
			var keep = s == to;
			var k = 0;
			while (k < s.preds.length) {
				if (s.preds[k] == b) {
					if (keep) keep = false else {
						s.preds.splice(k, 1);
						for (i in s.ins)
							if (i.op == Phi && !i.dead) i.args.splice(k, 1);
						continue;
					}
				}
				k++;
			}
		}
		t.op = Jmp;
		t.a = -1;
		t.cases = null;
		t.targets = [to];
		b.succs = [to];
	}

	function prune() {
		var reachable = f.newMark();
		var stack = [f.entry];
		f.entry.mark = reachable;
		while (stack.length > 0) {
			var b = stack.pop();
			for (s in b.succs)
				if (s.mark != reachable) {
					s.mark = reachable;
					stack.push(s);
				}
		}
		var all = true;
		for (b in f.blocks) {
			if (b.mark == reachable) continue;
			all = false;
			for (s in b.succs) {
				var k = s.preds.indexOf(b);
				while (k >= 0) {
					s.preds.splice(k, 1);
					for (i in s.ins)
						if (i.op == Phi && !i.dead) i.args.splice(k, 1);
					k = s.preds.indexOf(b);
				}
			}
			for (i in b.ins)
				i.dead = true;
		}
		if (!all) f.blocks = [for (b in f.blocks) if (b.mark == reachable) b];
	}

	// ---- the uses of the aliases

	// the groups that do not escape, with their accesses
	function check():Array<Group> {
		var acc:Array<Null<Group>> = [for (_ in sites) null];
		inline function group(s:Int):Group {
			var r = find(s);
			if (acc[r] == null) acc[r] = new Group(r);
			return acc[r];
		}
		for (x in closure) {
			if (x >= vbase) continue;
			var s = src[x];
			if (s < 0 || escaped[s]) continue;
			var g = group(s);
			g.aliases.push(x);
			lastFail = null;
			if (!uses1(g, x, x, 0)) escape(s, failWhy(lastFail));
		}
		// the instance used is the group's latest
		for (g in acc) {
			if (g == null || escaped[g.root]) continue;
			for (k in 0...g.accesses.length)
				if (!latest(g, g.bases[k], g.accesses[k])) {
					escape(g.root, "not the latest instance");
					break;
				}
		}
		var r = [];
		for (k in 0...acc.length)
			if (acc[k] != null && !escaped[k]) {
				var g = acc[k];
				for (j in 0...sites.length)
					if (find(j) == k) g.sites.push(sites[j]);
				r.push(g);
			}
		return r;
	}

	// the uses of v, an alias x or an address off bytes into it (false: an escape)
	function uses1(g:Group, x:Int, v:Int, off:Int):Bool {
		var us = uses[v];
		if (us == null) return true;
		var box = sites[g.root].box;
		for (u in us) {
			if (u.dead) continue;
			lastFail = u;
			switch u.op {
				case Copy:
					if (v != x) {
						g.derived.push(u);
						if (!uses1(g, x, u.id, off)) return false;
					}
				case Phi:
					if (v != x) return false;
					var s = srcOf(u.id);
					if (s < 0 || find(s) != g.root) return false;
				case Load if (u.a == v && u.b != v && u.b < 0 && box == 0):
					g.access(u, x, off + u.imm);
				case Store if (u.a == v && u.b != v && u.b < 0 && u.c != v && box == 0):
					var c = srcOf(u.c);
					if (c >= 0) escape(c, "stored into an object"); // (phase 1 keeps it)
					g.access(u, x, off + u.imm);
				case Store if (u.c == v && v == x && u.a != v && u.b != v && cellOf[u.id] >= 0 && cellTracked[cellOf[u.id]]):
					g.cellStores.push(u);
				case Add if (u.a == v && u.b != v && box == 0):
					var c = constOf(u.b);
					if (c == null || c.sym != null || c.imm2 != (c.imm < 0 ? -1 : 0)) return false;
					g.derived.push(u);
					if (!uses1(g, x, u.id, off + c.imm)) return false;
				case Sub if (u.a == v && v == x && youngStart(u.b) && box == 0):
					// the write barrier's test: the object is young
					for (w in usesOf(u.id))
						if (!w.dead && (w.op != Cmp || w.imm != CULt || w.a != u.id)) return false;
					g.derived.push(u);
					for (w in usesOf(u.id))
						if (!w.dead) g.young.push(w);
				case Cmp if ((u.imm == CEq || u.imm == CNe) && v == x && (u.a == v && isConst(u.b, 0) || u.b == v && isConst(u.a, 0))):
					g.nulls.push(u);
				case Call if (u.sym == "hxmc_barrier_slow" && box == 0 && u.args.length == 4 && u.args[2] != v && u.args[3] != v):
					g.barriers.push(u);
				case Call if (box > 0 && v == x && u.sym != null && u.args != null && u.args.length == 1 && unboxOk(box, u.sym)):
					g.access(u, x, 0);
				case _:
					return false;
			}
		}
		return true;
	}

	static function unboxOk(box:Int, sym:String):Bool
		return switch sym {
			case "hx_unbox_int": box == 1;
			case "hx_unbox_float": box == 1 || box == 2;
			case "hx_unbox_i64": box == 3;
			case _: false;
		};

	function youngStart(v:Int):Bool {
		var l = f.vals[v];
		if (l.op != Load || l.b >= 0 || l.imm != 0) return false;
		var a = f.vals[l.a];
		return a.op == SymAddr && a.sym == "rt_young_start" && a.imm == 0;
	}

	// ---- the latest instance

	var curReaders:Map<Int, Reader> = new Map();
	var curDefs:Map<Int, Map<Int, Int>> = new Map();

	// where u uses alias x: the group's reaching allocation is x's instance
	function latest(g:Group, x:Int, u:MIns):Bool {
		var defs = curDefs.get(g.root);
		var rd = curReaders.get(g.root);
		if (defs == null) {
			defs = new Map();
			for (k in 0...sites.length)
				if (find(k) == g.root) defs.set(sites[k].block.id, sites[k].v.id);
			var d = defs;
			rd = new Reader(f.entry, UNDEF, b -> {
				var v = d.get(b.id);
				v == null ? NONE : v;
			}, newVp, (v, args) -> vpArgs[v - vbase] = args);
			curDefs.set(g.root, defs);
			curReaders.set(g.root, rd);
		}
		var b = u.block;
		var cur = NONE;
		var d = defs.get(b.id);
		if (d != null) {
			// (the allocation is made in the block: before u?)
			var at = f.vals[d].op == Phi ? sites[siteAt.get(d)].defAt : f.vals[d];
			for (i in b.ins) {
				if (i == at) cur = d;
				if (i == u) break;
			}
		}
		if (cur == NONE) {
			var first = vpBlock.length;
			cur = rd.readEntry(b);
			rd.finish();
			if (vpBlock.length > first) collapse([for (k in first...vpBlock.length) vbase + k]);
		}
		return same(x, cur);
	}

	// x and y are the same value: phis of one block with the same operands
	// (coinductively)
	function same(x:Int, y:Int):Bool {
		var wx = [x], wy = [y];
		var assumed = new Map<String, Bool>();
		while (wx.length > 0) {
			var a = resolve(wx.pop()), b = resolve(wy.pop());
			if (a == b) continue;
			if (a < 0 || b < 0) return false;
			var ba = phiBlock(a), bb = phiBlock(b);
			if (ba == null || ba != bb) return false;
			var key = a + ":" + b;
			if (assumed.exists(key)) continue;
			assumed.set(key, true);
			var xa = phiArgs(a), xb = phiArgs(b);
			if (xa.length != xb.length) return false;
			for (k in 0...xa.length) {
				wx.push(xa[k]);
				wy.push(xb[k]);
			}
		}
		return true;
	}

	inline function phiBlock(v:Int):Null<MBlock>
		return v >= vbase ? vpBlock[v - vbase] : f.vals[v].op == Phi ? f.vals[v].block : null;

	inline function phiArgs(v:Int):Array<Int>
		return v >= vbase ? vpArgs[v - vbase] : f.vals[v].args;

	// ---- scalar replacement

	var pending:Array<{b:MBlock, at:Null<MIns>, i:MIns}> = [];
	var newPhis:Array<MIns> = [];
	var zeros:Map<Int, Int> = new Map();

	function newIns(op:Op, ty:MTy, b:MBlock, before:Null<MIns>):MIns {
		var x = new MIns(op, ty);
		x.id = f.vals.length;
		f.vals.push(x);
		x.block = b;
		x.pos = before != null ? before.pos : 0;
		pending.push({b: b, at: before, i: x});
		return x;
	}

	function zero(t:MTy):Int {
		var z = zeros.get(t);
		if (z != null) return z;
		var e = f.entry;
		var at:Null<MIns> = null;
		for (i in e.ins)
			if (i.op != Phi && i.op != Param) {
				at = i;
				break;
			}
		var x = newIns(t == F64 ? ConstF : Const, t, e, at);
		zeros.set(t, x.id);
		return x.id;
	}

	// replaces group g by variables (false: its accesses do not fit)
	function replace(g:Group):Bool {
		var box = sites[g.root].box;
		// the variables: the accessed ranges, identical or disjoint (narrower
		// loads at a range's start read its low bytes; stores of zero define
		// the ranges they cover)
		var vars:Array<Var> = [];
		if (box == 0) {
			vars.push(new Var(-8, 4, I32));
			vars.push(new Var(Abi.HDR_TINDEX, 4, I32));
		} else
			vars.push(box == 1 ? new Var(0, 4, I32) : box == 2 ? new Var(0, 8, F64) : new Var(0, 8, I64));
		var nslots = sites[g.root].nslots;
		var order = [for (k in 0...g.accesses.length) k];
		// (wider first: a narrower load then finds its range)
		order.sort((a, b) -> {
			var sa = accSize(g.accesses[a]), sb = accSize(g.accesses[b]);
			sa != sb ? sb - sa : a - b;
		});
		var varOf = new Map<Int, Int>(); // access -> variable
		var zeroStores:Array<MIns> = [];
		for (k in order) {
			var u = g.accesses[k], off = g.offs[k];
			if (u.op == Call) {
				varOf.set(u.id, 0);
				continue;
			}
			var size = u.size;
			var t = u.op == Load ? u.ty : f.vals[u.c].ty;
			if (off < -8 || off + size > 8 * nslots) return false;
			if (u.op == Store && isConst(u.c, 0)) {
				zeroStores.push(u);
				continue;
			}
			if (size != 1 && size != 2 && size != 4 && size != 8 || size == 8 && t == I32 || size < 8 && t != I32) return false;
			var v = -1;
			for (j in 0...vars.length) {
				var r = vars[j];
				if (r.off == off) {
					if (r.size == size) {
						v = j;
						if (r.ty != t) {
							if (size != 8) return false;
							r.ty = I64; // (doubles and words: words)
						}
					} else if (u.op == Load && size < r.size && r.ty != F64) v = j else return false;
				} else if (off < r.off + r.size && r.off < off + size) return false;
			}
			if (v < 0) {
				if (u.op == Load && size < 4) return false; // (a narrow load of nothing wider)
				v = vars.length;
				vars.push(new Var(off, size, t));
			}
			varOf.set(u.id, v);
		}
		// stores of zero: every range they cover
		var zeroVars = new Map<Int, Array<Int>>();
		for (u in zeroStores) {
			var vs = [];
			for (j in 0...vars.length) {
				var r = vars[j];
				if (r.off >= u.imm + offDelta(g, u) && r.off + r.size <= u.imm + offDelta(g, u) + u.size) vs.push(j);
				else if (r.off < u.imm + offDelta(g, u) + u.size && u.imm + offDelta(g, u) < r.off + r.size) return false;
			}
			zeroVars.set(u.id, vs);
		}
		// the definitions: each site (zeros, the header; the boxed value) and the stores
		var siteDef = new Map<Int, Site>(); // the instruction a site's values are defined before -> site
		for (s in g.sites)
			siteDef.set(s.defAt.id, s);
		var nv = vars.length;
		// the blocks with a definition or a read, in order
		var blocks:Array<MBlock> = [];
		var seen = new Map<Int, Bool>();
		inline function touch(b:MBlock)
			if (!seen.exists(b.id)) {
				seen.set(b.id, true);
				blocks.push(b);
			}
		for (s in g.sites)
			touch(s.block);
		for (u in g.accesses)
			touch(u.block);
		var stored = new Map<Int, Int>(); // store -> the value it gives its variable
		function storedValue(st:MIns, v:Int):Int {
			var r = stored.get(st.id);
			if (r != null) return r;
			var c = st.c;
			if (vars[v].ty == I64 && f.vals[c].ty == F64) {
				var x = newIns(FToBits, I64, st.block, st);
				x.a = c;
				c = x.id;
			}
			stored.set(st.id, c);
			return c;
		}
		function siteValue(s:Site, v:Int):Int {
			var r = vars[v];
			if (s.box > 0) return s.v.args[0];
			if (r.off == -8) return s.hdr.c;
			if (r.off == Abi.HDR_TINDEX) return s.ty.c;
			return zero(r.ty);
		}
		// the definitions of the block, in order: (instruction, variable, value)
		var lastDef = new Map<Int, Vector<Int>>();
		for (b in blocks) {
			var cur:Null<Vector<Int>> = null;
			for (i in b.ins) {
				if (i.dead) continue;
				var s = siteDef.get(i.id);
				if (s != null) {
					if (cur == null) cur = MFunc.ints(nv, NONE);
					for (v in 0...nv)
						cur[v] = siteValue(s, v);
				}
				if (i.op != Store) continue;
				var zv = zeroVars.get(i.id);
				if (zv != null) {
					if (cur == null) cur = MFunc.ints(nv, NONE);
					for (v in zv)
						cur[v] = zero(vars[v].ty);
					continue;
				}
				var v = varOf.get(i.id);
				if (v == null) continue;
				if (cur == null) cur = MFunc.ints(nv, NONE);
				cur[v] = storedValue(i, v);
			}
			if (cur != null) lastDef.set(b.id, cur);
		}
		var readers = [
			for (v in 0...nv) {
				var vv = v;
				new Reader(f.entry, NONE, b -> {
					var d = lastDef.get(b.id);
					d == null ? NONE : d[vv];
				}, b -> {
					var phi = new MIns(Phi, vars[vv].ty);
					phi.id = f.vals.length;
					f.vals.push(phi);
					phi.block = b;
					phi.args = [];
					var k = 0;
					while (k < b.ins.length && b.ins[k].op == Phi)
						k++;
					b.ins.insert(k, phi);
					newPhis.push(phi);
					phi.id;
				}, (p, args) -> f.vals[p].args = args);
			}
		];
		// the reads
		for (b in blocks) {
			var cur = MFunc.ints(nv, NONE);
			for (i in b.ins.copy()) {
				if (i.dead) continue;
				var s = siteDef.get(i.id);
				if (s != null)
					for (v in 0...nv)
						cur[v] = siteValue(s, v);
				if (i.op == Store) {
					var zv = zeroVars.get(i.id);
					if (zv != null)
						for (v in zv)
							cur[v] = zero(vars[v].ty);
					else {
						var v = varOf.get(i.id);
						if (v != null) cur[v] = storedValue(i, v);
					}
					continue;
				}
				var v = varOf.get(i.id);
				if (v == null || i.op != Load && i.op != Call) continue;
				var x = cur[v] != NONE ? cur[v] : readers[v].readEntry(b);
				if (x == NONE) x = zero(vars[v].ty);
				read(i, x, vars[v]);
			}
		}
		for (r in readers)
			r.finish();
		// (an entry read nothing defines: zero; never on a path from a site)
		for (p in newPhis)
			for (k in 0...p.args.length)
				if (p.args[k] == NONE) p.args[k] = zero(p.ty);
		// the stores go; the cells keep null; the barrier and the tests know the object is young and not null
		for (u in g.accesses)
			if (u.op == Store) u.dead = true;
		var z64 = g.cellStores.length > 0 ? zero(I64) : -1;
		for (u in g.cellStores)
			u.c = z64;
		for (u in g.barriers)
			u.dead = true;
		for (u in g.young)
			toConst(u, 1);
		for (u in g.nulls)
			toConst(u, u.imm == CEq ? 0 : 1);
		for (u in g.derived)
			u.dead = true;
		for (x in g.aliases)
			f.vals[x].dead = true;
		// the allocations go
		for (s in g.sites) {
			if (s.box > 0) {
				s.v.dead = true;
				continue;
			}
			s.tls.dead = true;
			s.hdr.dead = true;
			s.ty.dead = true;
			jumpTo(s.head, s.head.term(), s.fast);
		}
		removed += g.sites.length;
		return true;
	}

	// the displacement of an access through a derived address (zero stores: their offset from the object)
	function offDelta(g:Group, u:MIns):Int {
		var k = g.accesses.indexOf(u);
		return g.offs[k] - u.imm;
	}

	static inline function accSize(u:MIns):Int
		return u.op == Call ? 8 : u.size;

	// load or unbox i reads x, the value of variable r
	function read(i:MIns, x:Int, r:Var) {
		var b = i.block;
		if (i.op == Call) {
			var conv = i.sym == "hx_unbox_float" && r.ty == I32;
			i.op = conv ? I2F : Copy;
			i.a = x;
			i.sym = null;
			i.args = null;
			i.argTys = null;
			i.cSizes = null;
			i.cGroups = null;
			i.cRet = null;
			i.keepsFrame = false;
			i.noReturn = false;
			return;
		}
		var size = i.size, signed = i.signed, ty = i.ty;
		i.b = -1;
		i.c = -1;
		i.imm = 0;
		i.imm2 = 0;
		i.size = 0;
		i.signed = false;
		i.mem = 0;
		if (r.off == Abi.HDR_TINDEX) {
			// (the 16-bit type index: the whole constant, as every comparison takes it)
			i.op = Copy;
			i.a = x;
			return;
		}
		if (ty == F64 && r.ty == I64) {
			i.op = BitsToF;
			i.a = x;
		} else if (ty == I64 && r.ty == F64) {
			i.op = FToBits;
			i.a = x;
		} else if (ty == I32 && r.ty == I64) {
			if (size == 4) {
				i.op = Trunc;
				i.a = x;
			} else {
				var t = newIns(Trunc, I32, b, i);
				t.a = x;
				narrow(i, t.id, size, signed);
			}
		} else if (size < 4 && r.size == 4)
			narrow(i, x, size, signed)
		else {
			i.op = Copy;
			i.a = x;
		}
	}

	// i: the low size bytes of the 32-bit x
	function narrow(i:MIns, x:Int, size:Int, signed:Bool) {
		var b = i.block;
		var k = newIns(Const, I32, b, i);
		if (signed) {
			var bits = 32 - 8 * size;
			k.imm = bits;
			var sh = newIns(Shl, I32, b, i);
			sh.a = x;
			sh.b = k.id;
			i.op = Sar;
			i.a = sh.id;
			i.b = k.id;
		} else {
			k.imm = size == 1 ? 0xFF : 0xFFFF;
			i.op = And;
			i.a = x;
			i.b = k.id;
		}
	}

	// the new instructions in place, the dead ones out
	function sweep() {
		for (p in pending) {
			var ins = p.b.ins;
			var k = p.at == null ? -1 : ins.indexOf(p.at);
			if (k < 0) {
				k = ins.length;
				if (k > 0 && ins[k - 1].isTerm()) k--;
			}
			ins.insert(k, p.i);
		}
		pending = [];
		for (b in f.blocks) {
			var ins = b.ins, k = 0;
			for (i in ins)
				if (!i.dead) ins[k++] = i;
			if (k < ins.length) ins.resize(k);
		}
	}

	// the phis made whose operands are one value (or the phi) are copies of it
	function trivialPhis() {
		var changed = true;
		while (changed) {
			changed = false;
			for (p in newPhis) {
				if (p.op != Phi || p.dead) continue;
				var same = -1, trivial = true;
				for (a in p.args) {
					var x = a;
					while (f.vals[x].op == Copy && f.vals[x].a >= 0)
						x = f.vals[x].a;
					if (x == p.id || x == same) continue;
					if (same >= 0) {
						trivial = false;
						break;
					}
					same = x;
				}
				if (trivial && same >= 0) {
					p.op = Copy;
					p.a = same;
					p.args = null;
					changed = true;
				}
			}
		}
	}
}

private class Site {
	public var v:MIns; // the object (the phi) or the box (the call)
	public var block:MBlock;
	public var box = 0; // 1 Int, 2 Float, 3 Int64 (0: an object)
	public var key:String; // the layout: a group's sites agree
	public var head:MBlock;
	public var fast:MBlock;
	public var tls:MIns; // the bump of rt_young_ptr
	public var hdr:MIns; // the header's stores
	public var ty:MIns;
	public var nslots = 1;
	public var defAt:MIns; // the instruction its values are defined before

	public function new(v, block) {
		this.v = v;
		this.block = block;
	}
}

private class Group {
	public var root:Int;
	public var sites:Array<Site> = [];
	public var aliases:Array<Int> = [];
	public var accesses:Array<MIns> = []; // loads and stores (at offs), unboxings
	public var offs:Array<Int> = [];
	public var bases:Array<Int> = []; // the alias each access goes through
	public var cellStores:Array<MIns> = [];
	public var derived:Array<MIns> = []; // addresses into the object, barrier tests
	public var young:Array<MIns> = [];
	public var nulls:Array<MIns> = [];
	public var barriers:Array<MIns> = [];

	public function new(root)
		this.root = root;

	public function access(u:MIns, x:Int, off:Int) {
		accesses.push(u);
		offs.push(off);
		bases.push(x);
	}
}

private class Var {
	public var off:Int;
	public var size:Int;
	public var ty:MTy;

	public function new(off, size, ty) {
		this.off = off;
		this.size = size;
		this.ty = ty;
	}
}

// a variable's value at block entries, on demand (Braun et al.): the
// definition at the end of a block (endDef), else a phi where predecessors
// meet (made by mkPhi, its operands set by setArgs in finish), else the
// entry's value; iterative (no recursion along long paths)
private class Reader {
	var memo = new Map<Int, Int>();
	var entry:MBlock;
	var undef:Int;
	var endDef:MBlock->Int;
	var mkPhi:MBlock->Int;
	var setArgs:(Int, Array<Int>) -> Void;
	var pendV:Array<Int> = [];
	var pendB:Array<MBlock> = [];

	static inline var NONE = -3;

	public function new(entry, undef, endDef, mkPhi, setArgs) {
		this.entry = entry;
		this.undef = undef;
		this.endDef = endDef;
		this.mkPhi = mkPhi;
		this.setArgs = setArgs;
	}

	public function readEnd(b:MBlock):Int {
		var d = endDef(b);
		return d != NONE ? d : readEntry(b);
	}

	public function readEntry(b:MBlock):Int {
		var chain:Array<MBlock> = [];
		var r = undef;
		var n = 0;
		while (true) {
			var m = memo.get(b.id);
			if (m != null) {
				r = m;
				break;
			}
			if (b == entry || b.preds.length == 0 || n++ > 1000000) {
				r = undef;
				memo.set(b.id, r);
				break;
			}
			if (b.preds.length == 1) {
				chain.push(b);
				var p = b.preds[0];
				var d = endDef(p);
				if (d != NONE) {
					r = d;
					break;
				}
				b = p;
				continue;
			}
			r = mkPhi(b);
			memo.set(b.id, r);
			pendV.push(r);
			pendB.push(b);
			break;
		}
		for (x in chain)
			memo.set(x.id, r);
		return r;
	}

	public function finish() {
		while (pendV.length > 0) {
			var v = pendV.pop(), b = pendB.pop();
			setArgs(v, [for (p in b.preds) readEnd(p)]);
		}
	}
}
