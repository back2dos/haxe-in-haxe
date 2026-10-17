import H;
import p.M1;
using p.Ext;
using StringTools;

class Main {
	public static function section1():Void {
		(13).ext83();
	}
	public static function main():Void {
		H.out("start");
		try section1() catch (e:Dynamic) H.out("section1 threw " + H.exn(e));
	}
}
