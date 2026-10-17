import H;
import p.M1;
using p.Ext;
using StringTools;

class C2 {
	public function new() {}
	public function m5(a6:String):String {
		Main.fn39("", (new C20(206, 3.0)).m30());
		return "";
	}
}

class Main {
	public static inline function fn39(a40:String, a41:String):Int {
		return 152;
	}
	public static function section2():Void {
		(new C20(0, 1.25)).m28("");
	}
	public static function main():Void {
		H.out("start");
		try section2() catch (e:Dynamic) H.out("section2 threw " + H.exn(e));
	}
}
