import H;
using p.Ext;
using StringTools;

enum E0 {
	E0A;
}

interface I8 {}

interface I12 {}

class C15 implements I8 {
	public final f16:Int;
	public function new(a18:E0) {
		this.f16 = 198;
	}
	public function m22():String {
		return "";
	}
}

class C23 extends C15 implements I12 {
	public function new(a27:Bool, a28:Float) {
		super(E0A);
	}
}

class C36 extends C23 {
	public function new() {
		super(false, 0.5);
	}
	override public function m22():String {
		H.out("o140 " + Std.string((0.1 != 100.75)));
		var v149 = "";
		return v149;
	}
}

class Main {
	public static function fn53():(Float) -> Float {
		H.out("o204 " + H.fmt(0.0));
		return (_0:Float) -> 0.0;
	}
	public static function section0():Void {
		((true ? new C36() : new C15(E0.E0A))).m22();
	}
	public static function section1():Void {
		fn53();
	}
	public static function main():Void {
		H.out("start");
		try section0() catch (e:Dynamic) H.out("section0 threw " + H.exn(e));
		try section1() catch (e:Dynamic) H.out("section1 threw " + H.exn(e));
	}
}
