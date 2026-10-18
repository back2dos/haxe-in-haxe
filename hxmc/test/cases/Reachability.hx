// What hxmc.ir.Reach keeps (docs/hxmc.md, "Reachability"): methods
// dispatched on instantiated classes, reached by structural and Dynamic
// access, by Reflect with literal names, getProperty's "get_" + name, names
// from the runtime's tables, @:keep; static initializers of the statics live
// code uses.
interface Shape {
	function area():Float;
}

class Square implements Shape {
	public var side:Float;

	public function new(s:Float)
		side = s;

	public function area():Float
		return side * side;

	public function perimeter():Float
		return 4 * side;

	public function toString():String
		return "Square(" + side + ")";
}

class Circle implements Shape {
	public var r:Float;

	public function new(r:Float)
		this.r = r;

	public function area():Float
		return 3 * r * r;
}

class Base {
	public function new() {}

	public function name():String
		return "base";

	public function byReflection():String
		return "found by Reflect.field";

	public function get_answer():Int
		return 42;

	public function hidden():String
		return "never called";

	@:keep public function kept():String
		return "kept";
}

class Derived extends Base {
	override public function name():String
		return "derived";
}

class Registry {
	public static var entries:Array<String> = {
		var a = ["first"];
		a.push("second");
		a;
	};
}

class Reachability {
	static function shapes():Array<Shape>
		return [new Square(2), new Circle(1)];

	static function main() {
		for (s in shapes())
			Sys.println(s.area());
		var b:Base = Sys.args().length > 100 ? new Base() : new Derived();
		Sys.println(b.name());
		var d:Dynamic = b;
		Sys.println(Reflect.field(d, "byReflection")());
		Sys.println(Reflect.getProperty(d, "answer"));
		var fields = Type.getInstanceFields(Base);
		fields.sort(Reflect.compare);
		Sys.println(fields.join(","));
		for (f in fields)
			Sys.println(f + " " + Reflect.isFunction(Reflect.field(d, f)));
		// (structurally)
		var p:{function perimeter():Float;} = cast new Square(3);
		Sys.println(p.perimeter());
		Sys.println(Std.string(new Square(5)));
		Sys.println(Registry.entries.join(" "));
		var e:Derived = Type.createEmptyInstance(Derived);
		Sys.println(e.name());
	}
}
