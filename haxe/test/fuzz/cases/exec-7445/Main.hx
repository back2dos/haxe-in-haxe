import H;
import p.M1;
import p.q.M2;

class Main {
	public static function section1():Void {
		C27.m33(0.0, 0);
		var v303:Null<Int> = C18.m22(new Box<Int>(0), 85);
	}
	public static function main():Void {
		H.out("start");
		try section1() catch (e:Dynamic) H.out("section1 threw " + H.exn(e));
	}
}
