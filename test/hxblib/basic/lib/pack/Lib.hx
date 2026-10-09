package pack;

class Lib<T> {
	public var value:T;
	public static var counter = 0;

	public function new(v:T) {
		value = v;
		counter++;
	}

	public function get():T
		return value;

	public inline function twice(f:T->T):T
		return f(f(value));

	public static function greet(name:String)
		return 'Hello $name';

	public function map<S>(f:T->S):Lib<S>
		return new Lib(f(value));
}

enum Color {
	Red;
	Green;
	Rgb(r:Int, g:Int, b:Int);
}

enum abstract Level(Int) to Int {
	var Low = 1;
	var High = 10;
}

abstract Meters(Float) from Float to Float {
	public inline function new(f:Float)
		this = f;

	@:op(A + B) public function add(o:Meters):Meters
		return new Meters(this + o.toFloat());

	public function toFloat():Float
		return this;
}

typedef Point = {x:Int, y:Int, ?label:String};

interface Shape {
	function area():Float;
}

class Square implements Shape {
	var s:Float;

	public function new(s)
		this.s = s;

	public function area()
		return s * s;
}

class Base {
	public function new() {}

	public function name()
		return "base";

	overload public extern inline function over(i:Int)
		return "int " + i;

	overload public extern inline function over(s:String)
		return "string " + s;
}

class Derived extends Base {
	override public function name()
		return "derived/" + super.name();
}

function moduleLevel(x:Int)
	return x + 1;

final moduleConst = 42;
