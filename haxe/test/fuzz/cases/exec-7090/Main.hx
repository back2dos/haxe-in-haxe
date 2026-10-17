import H;
using p.Ext;
using StringTools;

abstract A16(Int) from Int to Int {
	public inline function new(i:Int)
		this = i;

	public function get():Int
		return this;

	public var twice(get, never):Int;

	function get_twice():Int
		return H.w(this * 2);

	@:op(A + B) public static function add(a:A16, b:A16):A16
		return new A16(H.w(a.get() + b.get()));

	@:op(A * B) public static function mul(a:A16, b:A16):A16
		return new A16(H.w(a.get() * b.get()));

	@:op(-A) public static function neg(a:A16):A16
		return new A16(-a.get());
}

class C17 {
	public function new(a20:Array<Int>) {}
	public function m21():Float {
		C24.f26 = H.w(C24.f26 << (((202 : A16) : Int) & 7));
		return 0.0;
	}
	public static function m23():Bool {
		Main.fn68();
		return false;
	}
}

abstract class C24 extends C17 {
	public static var f26:Int = 81;
}

class C28 {
	public function new(a29:Float) {}
	public function m33():Int {
		(new C17(([] : Array<Int>))).m21();
		return 0;
	}
}

class Main {
	public static function fn68():Int {
		final v222:Float = 0;
		C24.f26 = H.w(C24.f26 << ((new C28(v222)).m33() & 7));
		return 0;
	}
	public static function section3():Void {
		C17.m23();
		H.out("o308 " + Std.string(C24.f26));
	}
	public static function main():Void {
		H.out("start");
		try section3() catch (e:Dynamic) H.out("section3 threw " + H.exn(e));
	}
}
