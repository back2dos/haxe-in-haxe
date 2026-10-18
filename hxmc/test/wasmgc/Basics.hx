// what -D hxmc.wasm-gc covers, printed: compared with the native build's output (GcCheck)
interface Shape {
	function area():Float;
	function name():String;
}

class Rect implements Shape {
	var w:Float;
	var h:Float;

	public function new(w, h) {
		this.w = w;
		this.h = h;
	}

	public function area()
		return w * h;

	public function name()
		return "rect";
}

class Square extends Rect {
	public function new(s:Float)
		super(s, s);

	override public function name()
		return "square";
}

class Circle implements Shape {
	var r:Float;

	public function new(r)
		this.r = r;

	public function area()
		return Math.PI * r * r;

	public function name()
		return "circle";
}

enum Expr {
	Num(v:Int);
	Add(a:Expr, b:Expr);
	Mul(a:Expr, b:Expr);
	Neg(e:Expr);
	Zero;
}

class MyError {
	public var code:Int;

	public function new(code)
		this.code = code;
}

class Basics {
	static function eval(e:Expr):Int
		return switch e {
			case Num(v): v;
			case Add(a, b): eval(a) + eval(b);
			case Mul(a, b): eval(a) * eval(b);
			case Neg(x): -eval(x);
			case Zero: 0;
		}

	static function counter() {
		var n = 0;
		return () -> ++n;
	}

	static function kind(s:String):String
		return switch s {
			case "apple" | "pear": "fruit";
			case "carrot": "vegetable";
			case _: "unknown";
		}

	static function main() {
		// strings
		var s = "Hello, " + "world";
		Sys.println(s + " " + s.length + " " + s.charAt(4) + " " + s.charCodeAt(0) + " " + s.indexOf("world") + " " + s.substr(7) + " " + s.substring(0, 5));
		Sys.println(s.toUpperCase() + " " + s.toLowerCase() + " " + s.split(", ").length + " " + s.lastIndexOf("o"));
		Sys.println(kind("pear") + " " + kind("carrot") + " " + kind("rock"));
		// numbers
		Sys.println(1.5 + " " + (1 / 3) + " " + 1e21 + " " + 0.000001 + " " + 1e-7 + " " + (-2.5) + " " + Math.sqrt(2) + " " + Std.int(3.99) + " " + Math.floor(-1.5) + " " + Math.round(2.5));
		// (out of range: modulo 2^32, as the native targets)
		var big = 4109205400.0, nan = Math.NaN;
		Sys.println(Std.int(big) + " " + Std.int(-big) + " " + Math.round(big) + " " + Std.int(nan) + " " + Std.int(1e20) + " " + Std.int(-2147483648.5));
		Sys.println((7 % 3) + " " + (-7 % 3) + " " + (1 << 31) + " " + (-16 >> 2) + " " + (-16 >>> 28) + " " + (5.5 % 2) + " " + Std.parseInt("42") + " " + Std.parseFloat("3.25"));
		// arrays
		var a = [3, 1, 2];
		a.push(10);
		a[6] = 7;
		var t = 0;
		for (x in a)
			t += x;
		Sys.println(a.length + " " + t + " " + a[5] + " " + a[100]);
		var names = ["b", "a"];
		names.push("c");
		Sys.println(names[0] + names[1] + names[2] + " " + names.length);
		var fs = [0.5, 1.5];
		fs.push(2.0);
		Sys.println(fs[0] + fs[1] + fs[2]);
		// classes, interfaces, overrides
		var shapes:Array<Shape> = [new Rect(2, 3), new Square(2), new Circle(1)];
		for (sh in shapes)
			Sys.println(sh.name() + " " + sh.area());
		Sys.println(Std.isOfType(shapes[1], Rect) + " " + Std.isOfType(shapes[2], Rect));
		// enums
		Sys.println(eval(Add(Num(2), Mul(Num(3), Neg(Num(4))))) + " " + eval(Zero));
		// closures
		var c = counter();
		c();
		c();
		Sys.println(c());
		var add = (x:Int, y:Int) -> x + y;
		var twice = (f:Int->Int, x:Int) -> f(f(x));
		Sys.println(add(2, 3) + " " + twice(x -> x * 3, 2));
		// exceptions
		try {
			throw new MyError(7);
		} catch (e:MyError) {
			Sys.println("caught " + e.code);
		}
		try {
			try
				throw new MyError(8)
			catch (e:String)
				Sys.println("wrong");
		} catch (e:MyError) {
			Sys.println("outer " + e.code);
		}
		// StringBuf
		var b = new StringBuf();
		for (i in 0...5)
			b.add(i);
		b.addChar(33);
		Sys.println(b.toString() + " " + b.length);
		// Dynamic
		var d:Dynamic = 5;
		var e:Dynamic = "five";
		Sys.println(Std.string(d) + " " + Std.string(e) + " " + Std.string(null) + " " + Std.string(2.25) + " " + Std.string(true));
		// Bool arrays, printed and through Dynamic
		var flags = [true, false, true];
		var df:Dynamic = flags;
		Sys.println(flags + " " + Std.string(df) + " " + (df[1] == false));
		Sys.println("done");
	}
}
