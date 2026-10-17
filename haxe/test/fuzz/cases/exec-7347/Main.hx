import H;
using p.Ext;
using StringTools;

enum E4 {
	E4A;
	E4B(a5:Float);
}

interface I16 {}

class C21 implements I16 {
	public function new() {}
	public function m20():Bool {
		switch (E4A) {
			case E4A: {
				switch (E4.E4A) {
					case _: {
						H.out("o87 " + "ab");
					};
				}
			};
			case E4B(c88): {};
		}
		return false;
	}
}

class C32 implements I16 {
	public function new(a33:Float) {}
	public function m34():String {
		var v146 = 0;
		return Std.string(Main.fn62(v146, C35.f37));
	}
}

class C35 {
	public static var f37:Int = 72;
	public function new() {}
	public function m40():Int {
		for (i155 in 0...3) {
			H.tick();
			C35.f37 = H.w(i155);
		}
		return (Std.string(10)).length;
	}
}

class Main {
	public static inline function fn62(a63:Float, a64:Int):Int {
		C35.f37 = H.w(C35.f37 & (new C35()).m40());
		switch (C35.f37) {
			case 0: {
				H.out("o244 " + Std.string(false));
			};
			case 2 | 6: {
				H.tick();
				(new C21()).m20();
			};
		}
		return C35.f37;
	}
	public static function section0():Void {
		H.out("o283 " + (new C32(2.5e-3)).m34());
	}
	public static function main():Void {
		H.out("start");
		try section0() catch (e:Dynamic) H.out("section0 threw " + H.exn(e));
	}
}
