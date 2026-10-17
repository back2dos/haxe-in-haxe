import H;
using p.Ext;
using StringTools;

interface I6 {}

class C12 {}

class C16 implements I6 {
	public function new(a18:String, a19:Int) {}
	public function m7(a8:Int):Void {}
}

abstract class C28 extends C12 implements I6 {
	public static var f30:Int = 227;
	abstract public function m9(a10:Int, a11:Int):Int;
	public function m33():String {
		this.m9(0, 267);
		return "";
	}
}

abstract class C42 extends C16 implements I6 {
	override public function m7(a8:Int):Void {}
}

class C50 implements I6 {
	public function new(a51:Int, a52:Bool) {}
	public function m7(a8:Int):Void {}
	public function m56(a57:String):String {
		return ((Std.isOfType(null, C28) ? null : null)).m25(C28.f30, 0);
	}
	public static function m61(a62:Int = 7):Void {
		(new C16("", 0)).m7(102);
	}
}

class Main {
	public static function section1():Void {
		C50.m61(0);
	}
	public static function section2():Void {
		(new C50(85, true)).m7(175);
	}
	public static function main():Void {
		H.out("start");
		try section1() catch (e:Dynamic) H.out("section1 threw " + H.exn(e));
		try section2() catch (e:Dynamic) H.out("section2 threw " + H.exn(e));
	}
}
