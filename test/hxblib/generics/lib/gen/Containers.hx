package gen;

import haxe.ds.Option;

@:generic
class Stack<T> {
	var items:Array<T> = [];

	public var length(get, never):Int;

	public function new() {}

	function get_length()
		return items.length;

	public function push(v:T):Stack<T> {
		items.push(v);
		return this;
	}

	public function pop():Option<T> {
		return items.length == 0 ? None : Some(items.pop());
	}

	public function iterator():Iterator<T>
		return items.iterator();
}

class Pair<A, B = String> {
	public final first:A;
	public final second:B;

	public function new(first:A, second:B) {
		this.first = first;
		this.second = second;
	}

	public function swap():Pair<B, A>
		return new Pair(second, first);

	public function toString()
		return '($first, $second)';
}

interface Visitor<R> {
	function visitNum(n:Float):R;
	function visitAdd(a:Expr, b:Expr):R;
}

enum Expr {
	Num(n:Float);
	Add(a:Expr, b:Expr);
	Neg(e:Expr);
}

class Eval implements Visitor<Float> {
	public function new() {}

	public function visitNum(n:Float)
		return n;

	public function visitAdd(a:Expr, b:Expr)
		return Tools.accept(a, this) + Tools.accept(b, this);
}

class Tools {
	public static function accept<R>(e:Expr, v:Visitor<R>):R {
		return switch e {
			case Num(n): v.visitNum(n);
			case Add(a, b): v.visitAdd(a, b);
			case Neg(e): v.visitAdd(Num(0), Neg(e));
		}
	}

	public static function sum<T:Float>(a:Array<T>):Float {
		var s = 0.0;
		for (x in a)
			s += x;
		return s;
	}

	public static inline function mapOpt<T, S>(o:Option<T>, f:T->S):Option<S> {
		return switch o {
			case Some(v): Some(f(v));
			case None: None;
		}
	}

	public static function describe<T:{name:String, ?age:Int}>(o:T):String
		return o.name + (o.age == null ? "" : " " + o.age);

	public static function counter():Void->Int {
		var n = 0;
		return () -> ++n;
	}
}

typedef Named<T> = {
	var name:String;
	var value:T;
	@:optional var tags:Array<String>;
}

abstract Vec2(Array<Float>) {
	public var x(get, set):Float;
	public var y(get, set):Float;

	public inline function new(x:Float, y:Float)
		this = [x, y];

	inline function get_x()
		return this[0];

	inline function set_x(v:Float)
		return this[0] = v;

	inline function get_y()
		return this[1];

	inline function set_y(v:Float)
		return this[1] = v;

	@:op(A * B) static function scale(a:Vec2, f:Float):Vec2
		return new Vec2(a.x * f, a.y * f);

	@:op(-A) function neg():Vec2
		return new Vec2(-x, -y);

	@:arrayAccess function get(i:Int):Float
		return this[i];

	@:from static function fromPair(p:Pair<Float, Float>):Vec2
		return new Vec2(p.first, p.second);

	@:to public function toString():String
		return 'Vec2($x, $y)';
}

enum abstract Dir(String) {
	var North = "N";
	var South = "S";

	public function flip():Dir
		return if (this == "N") South else North;
}

class StringExt {
	public static function shout(s:String):String
		return s.toUpperCase() + "!";

	public static function times(s:String, n:Int):String
		return [for (_ in 0...n) s].join("");
}

class Statics {
	public static var initialized:Array<String> = [];
	public static dynamic function hook(s:String):String
		return "default " + s;

	static function __init__() {
		initialized = ["init"];
	}
}

private class Hidden {
	public static function secret()
		return 7;
}

class UsesHidden {
	public static function value()
		return Hidden.secret() * 6;
}
