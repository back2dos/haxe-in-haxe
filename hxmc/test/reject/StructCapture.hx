// A struct local lives in its function's frame: a closure cannot capture it.
// expect: a closure cannot capture the struct local p
// expect: StructCapture.hx:15)
@:hxmc.struct @:publicFields class Point {
	var x:Int;
	var y:Int;

	function new() {}
}

class StructCapture {
	static function main() {
		var p = new Point();
		p.x = 1;
		var f = () -> p.x;
		trace(f());
	}
}
