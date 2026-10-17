// Closures in structural fields. Read where a type parameter (or Dynamic)
// gives the field another signature: a (Int) -> String in {render: T -> Any}
// read inside a generic function was called with its argument boxed (the
// pointer printed as the number); read as such a field, a closure is kept
// when its signature is the wanted one, else adapted. And two objects of one
// shape (the same field names and representations): the second's closure
// was converted to the first's signature (a (String) -> String called as a
// (Float) -> Float).
class Holder<T> {
	final each:Array<T>;
	final render:T->Any;

	public function new(each:Array<T>, render:T->Any) {
		this.each = each;
		this.render = render;
	}

	public function run():String
		return [for (i in each) Std.string(render(i))].join(",");
}

interface HasFn<T> {
	var fn:T->String;
}

class IntFn implements HasFn<Int> {
	public var fn:Int->String = i -> "i" + (i + 1);

	public function new() {}
}

class AnonClosure {
	static function make<T>(props:{each:Array<T>, render:T->Any}):Holder<T>
		return new Holder(props.each, props.render);

	static function pick<T>(props:{f:T->Float}):T->Float
		return props.f;

	static function viaInterface<T>(h:HasFn<T>, x:T):String {
		var f = h.fn;
		return f(x);
	}

	static function sameShape() {
		var a = {render: (x:Float) -> x * 2};
		var b = {render: (s:String) -> s + s};
		Sys.println(a.render(1.25) + " " + b.render("q"));
		var r = b.render;
		Sys.println(r("w"));
	}

	static function main() {
		sameShape();
		Sys.println(make({each: [1, 2, 3], render: (i:Int) -> "#" + i}).run());
		Sys.println(make({each: [1.5, 2.5], render: (x:Float) -> x * 2}).run());
		Sys.println(make({each: [true, false], render: (b:Bool) -> !b}).run());
		Sys.println(make({each: ["a", "b"], render: (s:String) -> s + s}).run());
		var half = pick({f: (i:Int) -> i / 2});
		Sys.println(half(7));
		Sys.println(viaInterface(new IntFn(), 41));
		// a closure of the same signature is the same closure
		var g = (s:String) -> s.length;
		var o = {g: g};
		Sys.println(o.g == g);
		var d:{f:Dynamic->Dynamic} = {f: (n:Int) -> n * 3};
		Sys.println(d.f(14));
		var n:{f:Null<Int->Int>} = {f: null};
		Sys.println(n.f == null);
	}
}
