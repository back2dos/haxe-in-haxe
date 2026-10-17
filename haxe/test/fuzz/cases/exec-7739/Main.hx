import H;
import p.M1;
using p.Ext;
using StringTools;

abstract class C25 {
	public static var f26:Int = 215;
}

class Main {
	public static function fn34(a35:Float, a36:Int, a37:String = "d"):Int {
		H.tick();
		H.out("o129 " + Std.string(C25.f26));
		return a36;
	}
	public static function section1():Void {
		C25.f26 = H.w(C25.f26 << (("").ext49() & 7));
	}
	public static function section2():Void {
		Ext.ext52(91, 178);
	}
	public static function main():Void {
		H.out("start");
		try section1() catch (e:Dynamic) H.out("section1 threw " + H.exn(e));
		try section2() catch (e:Dynamic) H.out("section2 threw " + H.exn(e));
	}
}
