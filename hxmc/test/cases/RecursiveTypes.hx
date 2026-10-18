// Abstracts in their own underlying types (upstream's unit test Issue8243:
// `abstract Rec(Array<Rec>)`) and typedefs in their own expansions
// (Issue12539: `typedef Recursive<F> = Recursive<F> -> F`), lowered as
// Dynamic where they occur in themselves (Lower.unfolding), through an
// Array's element, a function's result and argument, two abstracts over
// each other, a type parameter; an abstract nested in itself without
// recursion (W<W<Int>>: an Int); a class whose superclass's fields are of
// the class (TestGeneric: `MyData extends RBNode<MyData>`, one ClassInfo).
abstract Rec(Array<Rec>) from Array<Rec> to Array<Rec> {
	public var length(get, never):Int;

	inline function get_length()
		return this.length;

	@:arrayAccess inline function at(i:Int):Rec
		return this[i];

	public function depth():Int {
		var d = 0;
		for (c in this) {
			var x = c.depth();
			if (x > d) d = x;
		}
		return d + 1;
	}
}

// a function returning itself: f(1)(2)(3)...
abstract Counter(Int->Counter) from Int->Counter {
	public inline function feed(i:Int):Counter
		return this(i);
}

// a function taking itself
abstract Self((Self, Int) -> Int) from (Self, Int) -> Int {
	public inline function call(n:Int):Int
		return this(cast this, n);
}

abstract A(Array<B>) from Array<B> to Array<B> {}
abstract B(Array<A>) from Array<A> to Array<A> {}

abstract Forest<T>(Array<{value:T, children:Forest<T>}>) from Array<{value:T, children:Forest<T>}> to Array<{value:T, children:Forest<T>}> {}

abstract W<T>(T) from T to T {}

// a function taking itself, as a typedef
typedef Fix<F> = Fix<F>->F;

// through an abstract over it, called (Issue12539's Y)
@:callable abstract Y<P, R>(Fix<P->R>) from Fix<P->R> {
	public function reply():P->R
		return this(this);
}

@:generic class Node<T:Node<T>> {
	public var next:T;
}

class Item extends Node<Item> {
	public var id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

enum Shape {
	Leaf;
	Node(children:Rec);
}

class Holder {
	public var rec:Rec;
	public var nested:Null<Rec>;

	public function new(r:Rec) {
		rec = r;
		nested = r.length > 0 ? r[0] : null;
	}
}

class RecursiveTypes {
	static var empty:Null<Rec> = null;
	static var total = 0;

	static function counter(i:Int):Counter {
		total += i;
		return counter;
	}

	static function sum<T>(f:Forest<T>, value:T->Int):Int {
		var s = 0;
		for (n in (f : Array<{value:T, children:Forest<T>}>))
			s += value(n.value) + sum(n.children, value);
		return s;
	}

	static function fix<P, R>(f:(P->R)->(P->R)):P->R {
		var y:Fix<P->R> = (self:Fix<P->R>) -> (p:P) -> f(self(self))(p);
		return y(y);
	}

	static function main() {
		Sys.println(empty == null);
		var leaf:Rec = [];
		var r:Rec = [[], [[], [[]]], leaf];
		Sys.println(r.length + " " + r.depth() + " " + r[1].depth() + " " + leaf.depth());
		var arr:Array<Rec> = r;
		arr.push([leaf, leaf]);
		Sys.println(r.length + " " + (r[3] : Array<Rec>).length + " " + (r[3][0] == leaf));
		var dyn:Dynamic = r;
		var back:Rec = dyn;
		Sys.println(back.depth());
		var h = new Holder(r);
		Sys.println(h.rec.depth() + " " + h.nested.depth());
		switch Node(r) {
			case Node(c): Sys.println("node " + c.length);
			case Leaf: Sys.println("leaf");
		}
		var c:Counter = counter;
		c.feed(1).feed(2).feed(39);
		Sys.println(total);
		var fact:Self = (self:Self, n:Int) -> n <= 1 ? 1 : n * self.call(n - 1);
		Sys.println(fact.call(10));
		var a:A = [[], [[]]];
		var b:B = (a : Array<B>)[1];
		Sys.println((a : Array<B>).length + " " + (b : Array<A>).length);
		var f:Forest<Int> = [{value: 1, children: [{value: 2, children: []}]}, {value: 3, children: []}];
		Sys.println(sum(f, v -> v));
		var w:W<W<Int>> = (40 : W<Int>);
		var n:Int = (w : W<Int>);
		Sys.println(n + 2);
		var ws:Array<W<Float>> = [1.5, 2.25];
		Sys.println((ws[0] : Float) + (ws[1] : Float));
		var fib = fix((rec:Int->Int) -> (n:Int) -> n < 2 ? n : rec(n - 1) + rec(n - 2));
		Sys.println(fib(20));
		var y:Y<Int, String> = (self:Fix<Int->String>) -> (n:Int) -> "y" + n;
		Sys.println(y.reply()(7));
		var item = new Item(1);
		item.next = new Item(2);
		item.next.next = item;
		Sys.println(item.next.id + " " + item.next.next.id + " " + Std.isOfType(item, Node_Item));
	}
}
