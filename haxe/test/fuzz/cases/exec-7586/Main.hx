import H;
import p.M1;
import p.q.M2;
using p.Ext;

abstract class C60 implements I13 {
	public static var f63:Array<Bool> = ([] : Array<Bool>);
	public function m66(a67:Bool = true):Int {
		H.tick();
		final v374:(Bool, Int) -> String = function(p375:Bool, p376:Int):String {
			H.tick();
			this.m14();
			return "\n";
		};
		return 138;
	}
	public static function m68(a69:Array<Bool>, a70:Int):Void {
		if (Std.isOfType(null, C60)) throw "";
	}
}

class Main {
	public static function section3():Void {
		var v624 = 0;
		switch (E0.E0A) {
			case E0A: {
				(new C17(v624)).m12();
			};
		}
	}
	public static function main():Void {
		H.out("start");
		try section3() catch (e:Dynamic) H.out("section3 threw " + H.exn(e));
	}
}
