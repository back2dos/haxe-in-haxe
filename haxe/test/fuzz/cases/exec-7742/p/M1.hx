package p;

import Main;
import H;
import p.M1;
using p.Ext;
using StringTools;

class M1 {}

abstract A0(Int) from Int to Int {
	public inline function new(i:Int)
		this = i;

	public function get():Int
		return this;

	public var twice(get, never):Int;

	function get_twice():Int
		return H.w(this * 2);

	@:op(A + B) public static function add(a:A0, b:A0):A0
		return new A0(H.w(a.get() + b.get()));

	@:op(A * B) public static function mul(a:A0, b:A0):A0
		return new A0(H.w(a.get() * b.get()));

	@:op(-A) public static function neg(a:A0):A0
		return new A0(-a.get());
}

class C10 {
	public static var f12:Int = 143;
	public final f13:Int;
	public function new() {
		this.f13 = 0;
	}
	public function m18(a19:A0):Int {
		++C10.f12;
		return 0;
	}
}

class C20 {
	public function new(a22:Int, a23:Float) {}
	public function m26(a27:Float):String {
		H.out("o104 " + Std.string(C10.f12));
		return ("" + (new C10()).m18(new A0(0)));
	}
	public function m28(a29:String):Map<String, C2> {
		C10.f12 = H.w(C10.f12 - (([] : Array<Int>)).ext58(0));
		(new C2()).m5("");
		return new Map<String, C2>();
	}
	public function m30():String {
		var v110 = 0;
		return (new C20(52, 7.0)).m26(v110);
	}
}
