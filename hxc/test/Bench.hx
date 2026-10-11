// Allocation-heavy enum/match benchmark for the experimental backends
// (hxc/README.md): builds random expression trees, simplifies and
// evaluates them. Integer results are masked so every target agrees.
enum Expr {
	Num(v:Int);
	Var(i:Int);
	Add(a:Expr, b:Expr);
	Mul(a:Expr, b:Expr);
	Neg(e:Expr);
}

interface Shape {
	function area():Int;
}

class Rect implements Shape {
	var w:Int;
	var h:Int;

	public function new(w:Int, h:Int) {
		this.w = w;
		this.h = h;
	}

	public function area():Int
		return w * h;
}

class Square extends Rect {
	public function new(s:Int) {
		super(s, s);
	}

	override public function area():Int
		return super.area() + 1;
}

class Fail {
	public var code:Int;

	public function new(code:Int)
		this.code = code;
}

class Rng {
	var state:Int;

	public function new(seed:Int)
		state = seed;

	public function next(n:Int):Int {
		state = (state * 75 + 74) % 65537;
		return (state >> 3) % n;
	}
}

class Bench {
	static function build(rng:Rng, depth:Int):Expr {
		if (depth == 0)
			return rng.next(4) == 0 ? Var(rng.next(8)) : Num(rng.next(10));
		return switch rng.next(6) {
			case 0 | 1: Add(build(rng, depth - 1), build(rng, depth - 1));
			case 2: Mul(build(rng, depth - 1), build(rng, depth - 1));
			case 3: Neg(build(rng, depth - 1));
			case 4: Add(Num(0), build(rng, depth - 1));
			case _: Mul(build(rng, depth - 1), Num(1));
		}
	}

	static function simplify(e:Expr):Expr {
		return switch e {
			case Add(a, b):
				switch [simplify(a), simplify(b)] {
					case [Num(0), y]: y;
					case [x, Num(0)]: x;
					case [Num(x), Num(y)]: Num((x + y) & 0xFFFF);
					case [x, y]: Add(x, y);
				}
			case Mul(a, b):
				switch [simplify(a), simplify(b)] {
					case [Num(0), _] | [_, Num(0)]: Num(0);
					case [Num(1), y]: y;
					case [x, Num(1)]: x;
					case [Num(x), Num(y)]: Num((x * y) & 0xFFFF);
					case [x, y]: Mul(x, y);
				}
			case Neg(a):
				switch simplify(a) {
					case Neg(x): x;
					case Num(x): Num((-x) & 0xFFFF);
					case x: Neg(x);
				}
			case _: e;
		}
	}

	static function eval(e:Expr, env:Array<Int>):Int {
		return switch e {
			case Num(v): v;
			case Var(i): env[i];
			case Add(a, b): (eval(a, env) + eval(b, env)) & 0xFFFF;
			case Mul(a, b): (eval(a, env) * eval(b, env)) & 0xFFFF;
			case Neg(a): (-eval(a, env)) & 0xFFFF;
		}
	}

	static function size(e:Expr):Int {
		return switch e {
			case Num(_) | Var(_): 1;
			case Add(a, b) | Mul(a, b): 1 + size(a) + size(b);
			case Neg(a): 1 + size(a);
		}
	}

	static function check(v:Int):Int {
		if (v % 7 == 3)
			throw new Fail(v);
		return v;
	}

	static function map(a:Array<Int>, f:Int->Int):Array<Int> {
		var r = [];
		for (x in a)
			r.push(f(x));
		return r;
	}

	static function main() {
		var iters = 60;
		var depth = 24;
		var env = [for (i in 0...8) i * 3 + 1];
		var total = 0;
		var failures = 0;
		var shapes:Array<Shape> = [new Rect(2, 3), new Square(4), new Rect(5, 1)];
		var kept:Array<Expr> = []; // -D retain: keep every tree alive, like a compiler's typed AST
		for (i in 0...iters) {
			var rng = new Rng(i + 1);
			var e = build(rng, depth);
			var s = simplify(e);
			#if retain
			kept.push(e);
			kept.push(s);
			#end
			var k = i & 3;
			env = map(env, x -> (x * 5 + k) & 0xFF);
			var v = eval(s, env);
			#if noexc // for runtimes without exception handling (WAMR AOT)
			if (v % 7 == 3) {
				failures++;
				total = (total + v) & 0xFFFFFF;
			} else
				total = (total * 31 + v) & 0xFFFFFF;
			#else
			try {
				total = (total * 31 + check(v)) & 0xFFFFFF;
			} catch (f:Fail) {
				failures++;
				total = (total + f.code) & 0xFFFFFF;
			}
			#end
			total = (total + size(e) + size(s) + shapes[i % 3].area()) & 0xFFFFFF;
		}
		var keptSize = 0;
		for (k in kept)
			keptSize = (keptSize + size(k)) & 0xFFFFFF;
		Out.int(total);
		Out.int(failures);
		Out.int(keptSize);
	}
}

// The prototype backends compile for the cross platform, which has no Sys.
class Out {
	public static function int(v:Int):Void {
		#if cross
		Host.printInt(v);
		#elseif sys
		Sys.println(v);
		#else
		js.Syntax.code("console.log({0})", v);
		#end
	}
}

extern class Host {
	static function printInt(v:Int):Void;
}
