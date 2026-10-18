// Compound assignments (a op= b) and increments whose target holds another
// representation than its type has: a Dynamic array's element typed Float
// (upstream's unit test TestOps: `x[0] %= 100`), a generic field read as
// Int (Issue2281: `fint.val++`), a Dynamic field; the result is stored as
// the target holds it, an old value read as its type (FnLower.binop, unop).
class Box<T> {
	public var v:T;

	public function new(v:T)
		this.v = v;
}

class CompoundOps {
	static function main() {
		var b = new Box(1);
		b.v += 41;
		b.v *= 2;
		var f = new Box(1.5);
		f.v += 1;
		Sys.println(b.v + " " + f.v);
		var y:Dynamic = [7.5];
		y[0] += 1;
		y[0] = y[0] * 2;
		var x:Dynamic = [-101.5];
		x[0] %= 100;
		var s:Dynamic = ["a"];
		s[0] += "b";
		var o:Dynamic = {n: 1, m: 2.5};
		o.n += 2;
		o.m -= 1;
		Sys.println(y[0] + " " + x[0] + " " + s[0] + " " + o.n + " " + o.m);
		var r = (y[0] += 1) + (b.v += 1);
		Sys.println(r + " " + y[0] + " " + b.v);
		// increments (upstream's unit test Issue2281)
		var old = b.v++;
		var pre = ++b.v;
		var n = new Box<Null<Int>>(0);
		var oldN = n.v++;
		var d = y[0]++;
		var dpre = --y[0];
		var g = new Box(2.5);
		var gOld = g.v--;
		Sys.println(old + " " + pre + " " + b.v + " " + oldN + " " + n.v + " " + d + " " + dpre + " " + y[0] + " " + gOld + " " + g.v);
	}
}
