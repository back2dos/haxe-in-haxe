package p.q;

import Main;
import H;
import p.M1;
import p.q.M2;
using p.Ext;
using StringTools;

class M2 {}

enum E0 {
	E0A;
}

class C10 extends C4 {
	public function new(a12:String) {
		super(0, a12);
	}
	public function m17(a18:Int = 4):String {
		return "";
	}
}

class C34 extends C10 {
	public function new(a35:E0, a36:Int) {
		super("");
	}
	override public function m17(a18:Int = 7):String {
		var v227:Int = 267;
		H.out("o229 " + Std.string(H.at([0, a18, v227], 124, 0)));
		return "";
	}
}
