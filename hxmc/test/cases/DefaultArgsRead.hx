// Default values reading the function's arguments or `this` (Haxe 5,
// upstream's unit test TestDefaultArgs): a call passes the default values of
// numbers and Bools itself, the forwarders of closures and dynamic calls fill
// them in, each with the arguments and receiver of that call
// (FnLower.defaultValue).
class Counter {
	public static var count = 0;

	public static function next():Int
		return ++count;
}

class Base {
	public var scale:Int;

	public function new(scale:Int, offset:Int = scale + 1) {
		this.scale = scale * 100 + offset;
	}

	public function apply(x:Int, y:Int = x * 2):String
		return "base " + x + " " + y;

	public function own(z:Int = this.scale):Int
		return z;
}

class Sub extends Base {
	public function new() {
		super(3);
	}

	override public function apply(x:Int, y:Int = x + this.scale):String
		return "sub " + x + " " + y;
}

abstract Meters(Int) from Int to Int {
	public function plus(a:Int, by:Int = a * 2):Int
		return this + a + by;
}

class DefaultArgsRead {
	var field = 10;

	static function sibling(a:Int, b:Int = a):Int
		return a + b;

	static function chain(a:Int = 1, b:Int = a, c:Int = b):String
		return '$a,$b,$c';

	static function floats(x:Float, y:Float = x / 2, flag:Bool = y > 1):String
		return x + " " + y + " " + flag;

	static function strings(s:String, t:String = s + "!"):String
		return s + t;

	// a call of itself leaves b out: its a there, not this call's
	static function down(a:Int, b:Int = a * 10):String
		return a == 0 ? "" + b : b + " " + down(a - 1);

	// the arguments are read before the default's effects
	static function order(a:Int, b:Int = Counter.next()):String
		return a + " " + b;

	function method(x:Int = this.field):Int
		return x;

	static function main() {
		Sys.println(sibling(5) + " " + sibling(5, 3));
		Sys.println(chain() + " " + chain(2) + " " + chain(2, 3) + " " + chain(2, 3, 4));
		Sys.println(floats(5) + " / " + floats(1));
		Sys.println(strings("hi"));
		Sys.println(down(3));
		Counter.count = 40;
		Sys.println(order(Counter.count) + " " + order(Counter.next()));
		var o = new DefaultArgsRead();
		var other = new DefaultArgsRead();
		other.field = 77;
		Sys.println(o.method() + " " + other.method() + " " + o.method(3));
		// through closures
		var f = sibling;
		var g = sibling.bind(_, _);
		var m = other.method;
		Sys.println(f(6) + " " + f(6, 1) + " " + g(7) + " " + m());
		// through Dynamic
		var d:Dynamic = other;
		Sys.println(d.method() + " " + Reflect.callMethod(other, Reflect.field(other, "method"), []));
		// a null passed for the argument: its default
		var n:Null<Int> = null;
		Sys.println(sibling(4, n));
		// dispatched: the receiver's own default, its arguments and this
		var objs:Array<Base> = [new Base(2), new Sub()];
		for (b in objs)
			Sys.println(b.scale + " " + b.apply(5) + " " + b.apply(5, 1) + " " + b.own());
		var ap = objs[1].apply;
		Sys.println(ap(6));
		var meters:Meters = 21;
		Sys.println(meters.plus(1) + " " + meters.plus(1, 0));
	}

	function new() {}
}
