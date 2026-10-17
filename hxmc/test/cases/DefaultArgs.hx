// Default argument values are the called function's own: an override
// declaring other values than the method it overrides (direct calls take the
// method's own, not the root declaration's; dispatched calls test the
// receiver's class where the implementations disagree; the fuzzer's exec
// lane, seed 7583); an interface method's arguments left out (the
// implementation's defaults); and calls through closures (of static
// functions, methods, dispatched and interface methods, local functions,
// function literals, dynamic methods, bind), where a left-out number or Bool
// is null and the closure fills in the default, as does a direct call
// passing null for it; and calls by name through Dynamic, Reflect and a
// structural type (the method table's entry takes them nullable).
interface I {
	function m(?x:Int):Int;
	function n(x:Int, y:Float = 2.5):Float;
}

class A implements I {
	public function new() {}

	public function m(?x:Int):Int
		return x == null ? -1 : x;

	public function n(x:Int, y:Float = 2.5):Float
		return x + y;

	public function k(x:Int = 4, s:String = "a", b:Bool = true):String
		return x + s + b;

	public dynamic function d(x:Int = 8):Int
		return x;
}

class B extends A {
	override public function n(x:Int, y:Float = 4.5):Float
		return x * y;

	override public function m(?x:Int = 3):Int
		return x * 2;

	override public function k(x:Int = 7, s:String = "b", b:Bool = false):String
		return "B" + x + s + b;
}

class C extends B {
	override public function k(x:Int = 9, s:String = "c", b:Bool = true):String
		return "C" + x + s + b;
}

class Leaf extends A {
	override public function k(x:Int = 5, s:String = "l", b:Bool = false):String
		return "L" + x + s + b;
}

class DefaultArgs {
	static function foo(x:Int = 5, y:Float = 1.5, b:Bool = true, s:String = "s"):String
		return x + " " + y + " " + b + " " + s;

	static function local() {
		function f(a:Int, b:Int = 4, ?c:Bool, d:Float = 0.5)
			return a + b + d + " " + c;
		Sys.println(f(1));
		var g = f;
		Sys.println(g(1, 2));
		var h = (x:Int = 7) -> x;
		Sys.println(h());
		Sys.println(h(1));
	}

	static function main() {
		// direct calls: the callee's own defaults
		Sys.println(new Leaf().k());
		Sys.println(new C().k(1));
		// dispatched calls: the receiver's
		var as:Array<A> = [new A(), new B(), new C(), new Leaf()];
		for (a in as)
			Sys.println(a.k() + " " + a.k(0) + " " + a.n(2));
		var b:B = new C();
		Sys.println(b.k());
		// interface calls
		var is:Array<I> = [new A(), new B()];
		for (i in is)
			Sys.println(i.m() + " " + i.n(1) + " " + i.n(1, 1.0));
		// closures
		var f = foo;
		Sys.println(f());
		Sys.println(f(1));
		Sys.println(f(1, 2.5, false));
		for (a in as) {
			var g = a.k;
			var h = a.n;
			Sys.println(g() + " " + g(3) + " " + h(1));
		}
		for (i in is) {
			var g = i.n;
			var h = i.m;
			Sys.println(g(3) + " " + h());
		}
		var leaf = new Leaf();
		var lk = leaf.k;
		Sys.println(lk());
		var dyn:Dynamic = foo;
		Sys.println(dyn());
		Sys.println(Reflect.callMethod(null, dyn, [2]));
		// dynamic methods
		var a = new A();
		Sys.println(a.d());
		var dd = a.d;
		Sys.println(dd());
		a.d = function(x:Int = 9) return x * 3;
		Sys.println(a.d());
		// bind and null for a defaulted argument
		var bound = foo.bind(_, 2.5);
		Sys.println(bound());
		Sys.println(bound(3));
		var n:Null<Int> = null;
		Sys.println(foo(n));
		Sys.println([1, 2].map(new B().n.bind(_, 0.5)));
		// by name
		for (a in as) {
			var d:Dynamic = a;
			Sys.println(d.k() + " " + d.k(2) + " " + d.n(1) + " " + Reflect.callMethod(a, Reflect.field(a, "k"), [3, "r"]));
			var s:{function n(x:Int, ?y:Float):Float;} = a;
			Sys.println(s.n(1) + " " + s.n(1, 2.0));
		}
		local();
	}
}
