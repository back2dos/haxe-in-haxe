package hxmc;

import backend.Ir;
import hxmc.Lir.Bits;

// Which reference locals live in shadow-stack slots, as EmitC.Roots decides
// for C (the same backward liveness over the structured statements: a
// reference live across a GC point is rooted; at a cold site the references
// live across its slow path are spilled there instead), with bit sets over
// local ids instead of maps, and without sharing slots between locals (a
// slot per rooted local). Also which locals may be read before they are set
// (EmitC.Roots.maybeUnset: their slots start as null).
class Roots {
	var n:Int;
	var refs:Bits; // locals of reference type
	public var rooted:Bits;
	public var spills = new Map<Int, Array<Local>>(); // SCold id -> references live across its slow path
	public var slots:Array<Int>; // local id -> slot, -1
	public var nslots = 0;
	var byId:Array<Null<Local>>;
	var brk:Array<Bits> = [];
	var cont:Array<Bits> = [];

	function new() {}

	public static function analyze(f:FuncInfo):Roots {
		var r = new Roots();
		var all = f.args.concat(f.locals);
		var n = 0;
		for (l in all)
			if (l.id >= n) n = l.id + 1;
		r.n = n;
		r.byId = [for (_ in 0...n) null];
		r.refs = new Bits(n);
		for (l in all) {
			r.byId[l.id] = l;
			if (Ir.isRef(l.ty)) r.refs.set(l.id);
		}
		r.rooted = new Bits(n);
		r.seq(f.body, new Bits(n));
		// try functions: a reference assigned inside a try body lives in its
		// slot, so that a second return of setjmp finds its latest value
		if (f.hasTry)
			for (id in MirBuild.assignedInTry(f).keys())
				if (r.refs.get(id)) r.rooted.set(id);
		r.slots = hxmc.Lir.Arrays.filled(n, -1);
		for (l in all)
			if (r.rooted.get(l.id)) r.slots[l.id] = r.nslots++;
		return r;
	}

	inline function copy(b:Bits):Bits
		return b.copy();

	function union(a:Bits, b:Bits):Bits {
		var r = a.copy();
		r.union(b);
		return r;
	}

	function across(live:Bits) {
		var w = live.w, rw = refs.w, ro = rooted.w;
		for (k in 0...w.length)
			ro[k] |= w[k] & rw[k];
	}

	function uses(e:Ex, acc:Bits) {
		switch e {
			case ELocal(l): acc.set(l.id);
			case _: backend.EmitC.iterEx(x -> uses(x, acc), e);
		}
	}

	function seq(ss:Array<Stmt>, out:Bits):Bits {
		var live = out;
		var i = ss.length;
		while (i-- > 0)
			live = stmt(ss[i], live);
		return live;
	}

	static function gcPoint(e:Ex):Int
		return backend.EmitC.Roots.gcPoint(e);

	static function nestedGc(e:Ex):Bool
		return backend.EmitC.Roots.nestedGc(e);

	function expr(e:Ex, after:Bits, def:Null<Local>):Bits {
		var rest = copy(after);
		if (def != null) rest.clear(def.id);
		var g = gcPoint(e);
		if (nestedGc(e)) g = 2;
		if (g == 1) across(rest);
		uses(e, rest);
		if (g == 2) across(rest);
		return rest;
	}

	function cold(id:Int, s:Stmt, out:Bits):Bits {
		var live = copy(out);
		switch s {
			case SSet(l, e):
				live.clear(l.id);
				uses(e, live);
			case SArrSet(_, a, i, v):
				live.set(a.id);
				uses(i, live);
				uses(v, live);
			case SArrPush(_, a, v):
				live.set(a.id);
				uses(v, live);
			case _:
				throw "cold statement";
		}
		// inside a try body the references a slow path reloads are assigned
		// there: they live in their slots (see analyze)
		if (extras.length > 0) {
			for (k in 0...n)
				if (live.get(k) && refs.get(k)) rooted.set(k);
		}
		var list = spills.get(id);
		if (list == null) spills.set(id, list = []);
		for (k in 0...n)
			if (live.get(k) && refs.get(k) && byId[k] != null && list.indexOf(byId[k]) < 0) list.push(byId[k]);
		list.sort((x, y) -> x.id - y.id);
		return live;
	}

	// per enclosing try body: what its handlers need (live wherever it may throw)
	var extras:Array<Bits> = [];

	function stmt(s:Stmt, out:Bits):Bits {
		var r = stmt0(s, out);
		if (extras.length > 0) r = union(r, extras[extras.length - 1]);
		return r;
	}

	function stmt0(s:Stmt, out:Bits):Bits {
		return switch s {
			case SCold(id, x): cold(id, x, out);
			case SSet(l, e): expr(e, out, l);
			case SExpr(e): expr(e, out, null);
			case SSetGlobal(_, v):
				var u = copy(out);
				uses(v, u);
				if (nestedGc(v) || gcPoint(v) > 0) across(u);
				u;
			case SSetField(_, _, o, v) | SBoxSet(_, o, v):
				var u = copy(out);
				uses(o, u);
				uses(v, u);
				if (nestedGc(o) || nestedGc(v) || gcPoint(v) > 0 || gcPoint(o) > 0) across(u);
				u;
			case SAnonSet(_, _, o, v):
				var u = copy(out);
				uses(o, u);
				uses(v, u);
				across(u);
				u;
			case SArrSet(_, a, i, v):
				rooted.set(a.id);
				var u = copy(out);
				u.set(a.id);
				uses(i, u);
				uses(v, u);
				across(u);
				u;
			case SArrPush(_, a, v):
				rooted.set(a.id);
				var u = copy(out);
				u.set(a.id);
				uses(v, u);
				across(u);
				u;
			case SIf(c, x, y):
				var u = union(seq(x, out), seq(y, out));
				uses(c, u);
				if (nestedGc(c) || gcPoint(c) > 0) across(u);
				u;
			case SLoop(body):
				var entry = new Bits(n);
				while (true) {
					brk.push(out);
					cont.push(entry);
					var nb = seq(body, entry);
					brk.pop();
					cont.pop();
					var u = union(entry, nb);
					if (same(u, entry)) break;
					entry = u;
				}
				entry;
			case SBreak: brk[brk.length - 1];
			case SContinue: cont[cont.length - 1];
			case SSwitch(e, cases, def):
				var u = seq(def, out);
				for (c in cases)
					u = union(u, seq(c.body, out));
				uses(e, u);
				u;
			case SReturn(e):
				var u = new Bits(n);
				if (e != null) uses(e, u);
				u;
			case SThrow(e):
				var u = new Bits(n);
				uses(e, u);
				u;
			case STry(body, catches):
				// a handler may run after any point of the body (or the code after
				// the try, when no catch matches)
				var h = copy(out);
				for (c in catches) {
					// the catch variable is set before the tests, which may collect
					// (haxe.Exception.caught), and read after them
					if (refs.get(c.l.id)) rooted.set(c.l.id);
					var u = seq(c.body, out);
					u.clear(c.l.id);
					h = union(h, u);
				}
				if (extras.length > 0) h = union(h, extras[extras.length - 1]);
				extras.push(h);
				var b = seq(body, union(out, h));
				extras.pop();
				union(b, h);
		}
	}

	static function same(a:Bits, b:Bits):Bool {
		for (k in 0...a.w.length)
			if (a.w[k] != b.w[k]) return false;
		return true;
	}

	// ---- locals that may be read before any assignment (the arguments are set)

	public static function maybeUnset(f:FuncInfo):Bits {
		var n = 0;
		for (l in f.args.concat(f.locals))
			if (l.id >= n) n = l.id + 1;
		var bad = new Bits(n);
		function reads(e:Ex, set:Bits) {
			switch e {
				case ELocal(l):
					if (!set.get(l.id)) bad.set(l.id);
				case _:
					backend.EmitC.iterEx(x -> reads(x, set), e);
			}
		}
		function inter(a:Bits, b:Bits):Bits {
			var r = a.copy();
			for (k in 0...r.w.length)
				r.w[k] &= b.w[k];
			return r;
		}
		var step:(Stmt, Bits) -> Bits = null;
		function seq(ss:Array<Stmt>, set:Bits):Bits {
			for (st in ss)
				set = step(st, set);
			return set;
		}
		step = function(st:Stmt, set:Bits):Bits {
			switch st {
				case SSet(l, e):
					reads(e, set);
					var r = set.copy();
					r.set(l.id);
					return r;
				case SExpr(e) | SThrow(e) | SSetGlobal(_, e):
					reads(e, set);
				case SReturn(e):
					if (e != null) reads(e, set);
				case SSetField(_, _, o, v) | SBoxSet(_, o, v) | SAnonSet(_, _, o, v):
					reads(o, set);
					reads(v, set);
				case SArrSet(_, a, i, v):
					if (!set.get(a.id)) bad.set(a.id);
					reads(i, set);
					reads(v, set);
				case SArrPush(_, a, v):
					if (!set.get(a.id)) bad.set(a.id);
					reads(v, set);
				case SIf(c, x, y):
					reads(c, set);
					return inter(seq(x, set.copy()), seq(y, set.copy()));
				case SLoop(body):
					seq(body, set.copy());
				case SSwitch(e, cases, def):
					reads(e, set);
					var r = seq(def, set.copy());
					for (c in cases)
						r = inter(r, seq(c.body, set.copy()));
					return r;
				case SCold(_, x):
					return step(x, set);
				case SBreak | SContinue:
				case STry(_, _):
					throw "try in a function without hasTry";
			}
			return set;
		};
		var entry = new Bits(n);
		for (a in f.args)
			entry.set(a.id);
		seq(f.body, entry);
		return bad;
	}
}
