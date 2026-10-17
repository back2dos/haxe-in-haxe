// An Array holds references and scalars: not struct values (a Ptr to memory, a class instead).
// expect: an Array's element cannot be the struct value Point
@:hxmc.struct @:publicFields class Point {
	var x:Int;
	var y:Int;

	function new() {}
}

class StructArray {
	static function main() {
		var a:Array<Point> = [];
		a.push(new Point());
		trace(a.length);
	}
}
