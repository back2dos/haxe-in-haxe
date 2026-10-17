// An Array's element is a copy (the struct is boxed in it): assigning one of its fields would change the copy only.
// expect: this struct value is a copy (of an Array element
// expect: StructArrayElement.hx:13)
@:hxmc.struct @:publicFields class Point {
	var x:Int;
	var y:Int;

	function new() {}
}

class StructArrayElement {
	static function move(a:Array<Point>) {
		a[0].x = 1;
	}

	static function main() {
		var a = [new Point()];
		move(a);
		trace(a[0].x);
	}
}
