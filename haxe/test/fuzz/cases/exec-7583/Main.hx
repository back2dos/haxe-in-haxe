import H;
import p.M1;
import p.q.M2;
using p.Ext;
using StringTools;

class Main {
	public static function section1():Void {
		H.out("o402 " + (new C26(120, true)).m30(0, 23));
	}
	public static function main():Void {
		H.out("start");
		try section1() catch (e:Dynamic) H.out("section1 threw " + H.exn(e));
	}
}
