// haxe.Serializer and Unserializer (hxmc/std/haxe/Serializer.hx: the enum
// branch of java, python, hl and eval), and Std.isOfType against Class and
// Enum (type objects: hx_is_typeobj): basic values, strings, arrays,
// structures, class instances, enums with and without arguments, maps,
// nested, each written, read back and written again
class Item {
	public var name:String;
	public var qty:Int;

	public function new(name:String, qty:Int) {
		this.name = name;
		this.qty = qty;
	}
}

enum Shape {
	Dot;
	Rect(w:Int, h:Float);
	Group(items:Array<Shape>);
}

class Serialize {
	static function round(v:Dynamic) {
		var s = haxe.Serializer.run(v);
		var again = haxe.Serializer.run(haxe.Unserializer.run(s));
		trace(s + (again == s ? "" : " read back as " + again));
	}

	static function main() {
		round(1);
		round(-7.25);
		round(true);
		round(null);
		round("line\nbreak, ünïcode");
		round([1, 2, 3]);
		round({a: 1, b: "s"});
		round(new Item("pen", 3));
		round(Dot);
		round(Rect(2, 0.5));
		round(Group([Dot, Rect(1, 1.5)]));
		round(["k" => 1, "l" => 2]);
		round([3 => "x"]);
		round([{v: [Rect(0, 0)]}, {v: []}]);
		var item:Item = haxe.Unserializer.run(haxe.Serializer.run(new Item("cup", 2)));
		trace(item.name, item.qty, Std.isOfType(item, Item));
		var shape:Shape = haxe.Unserializer.run(haxe.Serializer.run(Group([Rect(4, 2.5)])));
		trace(Type.enumEq(shape, Group([Rect(4, 2.5)])), Type.enumConstructor(shape));
		var o:Dynamic = {};
		trace(Std.isOfType(Item, Class), Std.isOfType(Shape, Enum), Std.isOfType(Item, Enum), Std.isOfType(Shape, Class));
		trace(Std.isOfType(o, Class), Std.isOfType(o, Enum), Std.isOfType(item, Class), Std.isOfType(Dot, Enum), Std.isOfType(String, Class));
	}
}
