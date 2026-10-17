package p;

import Main;
import H;
import p.M1;
import p.q.M2;

class M1 {}

class C7 {}

abstract class C9 extends C7 {
	public static var f10:Int = 30;
}

class C18 extends C9 {
	public static function m22(a23:Box<Int>, ?a24:Null<Int>):Int {
		var v117 = 0;
		C9.f10 = H.w(C9.f10 - 189);
		final v121:Int = (K6.K6C : Int);
		function lf122(n123:Int):Int {
			H.tick();
			return n123 <= 0 ? C9.f10 : H.w(lf122(n123 - 1) + v117);
		}
		H.out("lf122 " + lf122(2));
		return v121;
	}
}
