package p;

import Main;
import H;
import p.M1;

class M1 {}

class C8 {
	public var f10:Int;
	public function new(a13:Int, a14:String) {}
	public function m15(a16:String):Bool {
		return false;
	}
	public function m17():Bool {
		if (Std.isOfType(null, C8)) throw StringTools.lpad("q", "*", -2);
		return false;
	}
	public function m18(a19:Bool, a20:Int):String {
		return "";
	}
}

class C21 extends C8 {
	override public function m18(a19:Bool, a20:Int):String {
		this.m15(StringTools.replace("q", "b", "Haxe"));
		return StringTools.trim("0");
	}
	public function m25(a26:Array<Int>, a27:String):Bool {
		if (m15("")) return (Lambda.fold(a26, (v117:Int, v118:Int) -> 38, 0) == this.f10);
		return false;
	}
}
