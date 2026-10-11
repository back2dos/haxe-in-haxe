package fuzz;

import fuzz.Ast;

/**
	Test-case reduction on the generated program tree.

	Passes, repeated until nothing changes or the test budget is spent:
	1. remove chunks of block elements (statements, members, declarations),
	   halving the chunk size down to single elements (ddmin-style), then
	   replace statements by the contents of their blocks;
	2. replace each expression with the default value of its type;
	3. replace each expression with a sub-expression of the same type.

	Candidates are kept when `interesting` still reports the same failure. A
	candidate the reference rejects is never interesting, so the reduced
	program stays valid Haxe.
**/
class Reduce {
	var program:Program;
	var interesting:Program->Bool;
	var budget:Int;

	public var tests(default, null) = 0;

	function new(p, f, budget) {
		program = p;
		interesting = f;
		this.budget = budget;
	}

	public static function run(p:Program, interesting:Program->Bool, budget:Int):Int {
		var r = new Reduce(p, interesting, budget);
		r.loop();
		return r.tests;
	}

	function test():Bool {
		tests++;
		return interesting(program);
	}

	inline function exhausted():Bool
		return tests >= budget;

	function loop() {
		var changed = true;
		while (changed && !exhausted()) {
			changed = false;
			if (blocksPass())
				changed = true;
			if (exprPass())
				changed = true;
		}
	}

	function allBlocks():Array<Block> {
		var res = [];
		function node(n:Node) {
			for (p in n.parts)
				switch p {
					case N(c): node(c);
					case B(b):
						res.push(b);
						for (i in b.items)
							node(i);
					case S(_):
				}
		}
		for (m in program.modules) {
			res.push(m.body);
			for (i in m.body.items)
				node(i);
		}
		return res;
	}

	function blocksPass():Bool {
		var changed = false;
		// blocks found before an edit stay valid: removing items only detaches subtrees
		for (b in allBlocks()) {
			if (exhausted())
				break;
			var chunk = b.items.length;
			while (chunk >= 1 && !exhausted()) {
				var i = 0;
				while (i < b.items.length && !exhausted()) {
					var removable = [];
					var j = i;
					while (j < b.items.length && j < i + chunk) {
						if (!b.items[j].pinned)
							removable.push(j);
						j++;
					}
					if (removable.length == 0) {
						i += chunk;
						continue;
					}
					var saved = b.items.copy();
					var kept = [for (k in 0...b.items.length) if (!removable.contains(k)) b.items[k]];
					b.items = kept;
					if (test()) {
						changed = true;
						// stay at i: the next chunk moved here
					} else {
						b.items = saved;
						i += chunk;
					}
				}
				chunk = chunk >> 1;
			}
			// replace a statement by the contents of one of its blocks (unwraps if, loops, try)
			var i = 0;
			while (i < b.items.length && !exhausted()) {
				var it = b.items[i];
				var spliced = false;
				if (!it.pinned && it.ty == null)
					for (p in it.parts)
						switch p {
							case B(inner) if (!spliced && inner.braces):
								var saved = b.items.copy();
								b.items = b.items.slice(0, i).concat(inner.items).concat(b.items.slice(i + 1));
								if (test()) {
									changed = true;
									spliced = true;
								} else
									b.items = saved;
							default:
						}
				if (!spliced)
					i++;
			}
		}
		return changed;
	}

	function exprPass():Bool {
		var changed = false;
		function visit(n:Node) {
			if (exhausted())
				return;
			if (n.ty != null && !n.pinned && n.ty != TVoid) {
				var replacement = Gen.defaultSrc(n.ty);
				var simple = n.parts.length == 1 && switch n.parts[0] {
					case S(s): s == replacement || s.indexOf("(") < 0 && s.indexOf(" ") < 0;
					default: false;
				};
				if (!simple) {
					var saved = n.parts;
					n.parts = [S(replacement)];
					if (test()) {
						changed = true;
						return;
					}
					n.parts = saved;
					// hoist a same-typed sub-expression
					for (c in children(n))
						if (c.ty != null && Types.eq(c.ty, n.ty)) {
							n.parts = c.parts;
							if (test()) {
								changed = true;
								visit(n);
								return;
							}
							n.parts = saved;
						}
				}
			}
			for (p in n.parts)
				switch p {
					case N(c): visit(c);
					case B(b):
						for (i in b.items)
							visit(i);
					case S(_):
				}
		}
		for (m in program.modules)
			for (i in m.body.items)
				visit(i);
		return changed;
	}

	/** Expression nodes directly below `n` (through nested statement nodes, not blocks). **/
	static function children(n:Node):Array<Node> {
		var res = [];
		for (p in n.parts)
			switch p {
				case N(c):
					if (c.ty != null)
						res.push(c);
					else
						for (x in children(c))
							res.push(x);
				default:
			}
		return res;
	}
}
