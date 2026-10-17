// Bool values kept in containers stay Bool when viewed dynamically: an
// Array<Bool> (its element kind is Bool, stored as 4 bytes like Int, not
// Int) printed, read as Dynamic, through Type.typeof, Std.isOfType, Json,
// Reflect and Array<Dynamic> casts; the arrays the natives make from one
// (copy, concat, slice, splice, filter, map, reversed, inserted, popped);
// an Array<Bool> through generic code; Bool and Int arrays mixed by
// Dynamic stores; Vector<Bool>, maps' values, enum arguments, anonymous and
// class fields, Null<Bool>, closures' captured Bools; the Int arrays next
// to them, which stay Int; and conditionals of Bools the optimizer turns
// into `&&` and `||` typed Dynamic.
import haxe.ds.Vector;
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.ds.ObjectMap;
import haxe.Json;

enum E {
	A(b:Bool);
	B(b:Bool, i:Int, a:Array<Bool>);
}

class C {
	public var b:Bool;
	public var bs:Array<Bool>;
	public var nb:Null<Bool>;

	public function new() {
		b = true;
		bs = [false, true];
		nb = false;
	}
}

class BoolValues {
	static function show(label:String, v:Dynamic) {
		Sys.println(label + ": " + Std.string(v) + " " + Type.typeof(v) + " bool=" + Std.isOfType(v, Bool) + " int=" + Std.isOfType(v, Int)
			+ " ==true:" + (v == true) + " ==1:" + (v == 1));
	}

	static function first<T>(a:Array<T>):T
		return a[0];

	static function pushGeneric<T>(a:Array<T>, v:T) {
		a.push(v);
		return a;
	}

	static function generic<T>(a:Array<T>):String {
		var r = [];
		for (x in a)
			r.push(Std.string(x) + ":" + Type.typeof(x));
		return r.join(",");
	}

	static function dynArr(a:Array<Dynamic>):String
		return Std.string(a) + " " + Type.typeof(a[0]) + " " + Std.isOfType(a[0], Bool) + " " + (a[0] == true);

	static function main() {
		// the array itself
		var a = [true, false];
		trace(a);
		Sys.println(Std.string(a));
		Sys.println(a.toString());
		Sys.println(a.join("|"));
		Sys.println("" + a);
		Sys.println('$a ${a[1]}');
		var d:Dynamic = a;
		Sys.println(Std.string(d) + " " + d[0] + " " + Type.typeof(d[0]));
		show("a[0]", a[0]);
		show("a[1]", a[1]);
		var dd:Dynamic = a[0];
		show("dd", dd);
		show("d[1]", d[1]);
		show("first", first(a));
		Sys.println(generic(a));
		Sys.println(dynArr(cast a));
		var ad:Array<Dynamic> = cast a;
		Sys.println(ad + " " + (ad[0] == true) + " " + (ad[1] == false) + " " + Type.typeof(ad[1]));
		Sys.println(Json.stringify(a) + " " + Json.stringify({a: a}) + Json.stringify({b: true}) + Json.stringify({i: 1}));
		Sys.println(Json.parse("[true,false,1]") + " " + Type.typeof(Json.parse("[true]")[0]));
		Sys.println(Reflect.field({x: a}, "x") + " " + Type.typeof(Reflect.field({x: a}, "x")[0]));
		Sys.println(Reflect.callMethod(null, first, [a]) + " " + Type.typeof(Reflect.callMethod(null, first, [a])));
		Sys.println(a.indexOf(false) + " " + a.contains(true) + " " + a.lastIndexOf(true));
		for (x in a)
			show("iter", x);
		for (i => x in a)
			Sys.println(i + "=" + x);

		// arrays made from it
		Sys.println(a.copy() + " " + a.concat([false, false]) + " " + a.slice(1) + " " + a.filter(x -> x) + " " + a.map(x -> !x)
			+ " " + a.map(x -> x ? 1 : 0));
		var b = a.copy();
		b.reverse();
		b.insert(1, true);
		b.unshift(false);
		Sys.println(b + " " + b.splice(1, 2) + " " + b);
		Sys.println(b.pop() + " " + b.shift() + " " + b + " " + Type.typeof(b.pop()));
		var c = new Array<Bool>();
		c.push(true);
		c[1] = false;
		c[2] = true;
		Sys.println(c + " " + c.length + " " + [for (i in 0...4) i % 2 == 0] + " " + [for (x in c) !x]);
		var e:Array<Bool> = [];
		Sys.println(e + " " + e.length);
		e.resize(2);
		e[0] = true;
		e[1] = true;
		Sys.println(e);
		Sys.println(pushGeneric([true], false) + " " + pushGeneric([1], 2));
		var nested = [[true], [false, true]];
		Sys.println(nested + " " + Type.typeof(nested[1][1]));
		var nb:Array<Null<Bool>> = [true, null, false];
		Sys.println(nb + " " + Type.typeof(nb[0]) + " " + Type.typeof(nb[1]));
		var sorted = [true, false, true, false];
		sorted.sort((x, y) -> (x ? 1 : 0) - (y ? 1 : 0));
		Sys.println(sorted);

		// Int arrays stay Int; Dynamic stores of the other kind
		var ints = [1, 0];
		Sys.println(ints + " " + Type.typeof(ints[0]) + " " + Std.isOfType(ints[0], Bool) + " " + Json.stringify(ints));
		var di:Array<Dynamic> = cast ints;
		di[0] = true;
		Sys.println(ints + " " + Type.typeof(di[0]) + " " + Type.typeof(di[1]));
		var bools = [false, false];
		var db:Array<Dynamic> = cast bools;
		db[1] = 7;
		db.push("s");
		Sys.println(bools + " " + Type.typeof(db[0]) + " " + Type.typeof(db[1]));
		var mix:Array<Dynamic> = [true, 1, 1.5, null, false];
		Sys.println(mix + " " + [for (x in mix) Std.string(Type.typeof(x))].join(","));

		// other containers
		var v = new Vector<Bool>(3);
		v[0] = true;
		v[1] = false;
		v[2] = true;
		Sys.println(v.toArray() + " " + Type.typeof(v[0]) + " " + Std.string(v.toArray()[1]));
		var vd:Dynamic = v[2];
		show("vector", vd);
		var sm = new StringMap<Bool>();
		sm.set("t", true);
		sm.set("f", false);
		Sys.println(sm.get("t") + " " + Type.typeof(sm.get("f")) + " " + [for (k in ["f", "t"]) Std.string(sm.get(k))]);
		var im = new IntMap<Bool>();
		im.set(1, true);
		im.set(2, false);
		Sys.println(im.get(1) + " " + im.get(2) + " " + Type.typeof(im.get(1)) + " " + [for (k in 1...3) im.get(k)]);
		var om = new ObjectMap<C, Bool>();
		var co = new C();
		om.set(co, true);
		Sys.println(om.get(co) + " " + Type.typeof(om.get(co)));
		var m:Map<String, Bool> = ["x" => true];
		Sys.println(m.get("x") + " " + m + " " + Type.typeof(m["x"]));
		var mi:Map<Int, Bool> = [3 => false];
		Sys.println(mi + " " + mi[3]);
		var dm:Dynamic = sm;
		Sys.println(Type.typeof(dm.get("t")));
		var ea = A(true);
		var eb = B(false, 1, [true, false]);
		Sys.println(ea + " " + eb + " " + Type.enumParameters(ea) + " " + Type.enumParameters(eb) + " "
			+ Type.typeof(Type.enumParameters(eb)[0]) + " " + Type.typeof(Type.enumParameters(eb)[1]));
		switch eb {
			case B(x, _, arr):
				show("enum arg", x);
				Sys.println(arr);
			case _:
		}
		var o = {b: true, f: false, i: 1, a: [false]};
		Sys.println(o.b + " " + Type.typeof(o.b) + " " + Reflect.field(o, "f") + " " + Type.typeof(Reflect.field(o, "f")) + " " + o.a);
		var od:Dynamic = o;
		Sys.println(od.b + " " + Type.typeof(od.f) + " " + Std.isOfType(od.b, Bool) + " " + Type.typeof(od.i));
		Sys.println([for (f in ["a", "b", "f", "i"]) f + "=" + Reflect.field(o, f)].join(" "));
		Reflect.setField(od, "b", false);
		Sys.println(o.b + " " + Type.typeof(Reflect.field(o, "b")));
		Sys.println(Json.stringify(o, (k, v) -> v, null).length > 0);
		Sys.println(Reflect.field(co, "b") + " " + Type.typeof(Reflect.field(co, "b")) + " " + Reflect.field(co, "bs") + " "
			+ Type.typeof(Reflect.getProperty(co, "nb")) + " " + co.bs);
		var cd:Dynamic = co;
		Sys.println(cd.bs[1] + " " + Type.typeof(cd.bs[1]) + " " + Std.string(cd.bs));
		var t = true;
		var f = () -> t;
		show("closure", f());
		var nbv:Null<Bool> = false;
		show("null bool", nbv);
		var fb:Dynamic = (x:Bool) -> !x;
		show("dyn call", fb(false));

		// conditionals the optimizer turns into `c && x` and `c || x`, typed
		// as the conditional was (Dynamic, Null<Bool>): the Bool boxed
		var yes = Std.random(1) == 0;
		show("c && x", yes ? f() : false);
		show("!c && x", !yes ? f() : false);
		show("c || x", yes ? true : f());
		show("!c || x", !yes ? true : f());
		show("contains", yes ? ([] : Array<Int>).contains(1) : false);
		var cn:Null<Bool> = yes ? f() : false;
		show("null", cn);
		var cd:Dynamic = yes ? ints.length == 2 : false;
		show("dyn", cd);
		var ca:Array<Dynamic> = [yes ? f() : false, !yes ? f() : true];
		Sys.println(ca + " " + Type.typeof(ca[0]));

		// many Bools: growth, and the contents across collections
		var big = [];
		for (i in 0...1000)
			big.push(i % 3 == 0);
		var junk = [];
		for (i in 0...2000)
			junk.push([i]);
		var trues = 0;
		for (x in big)
			if (x) trues++;
		Sys.println(trues + " " + big.slice(0, 7) + " " + Type.typeof((big : Array<Dynamic>)[999]) + " " + junk.length);
	}
}
