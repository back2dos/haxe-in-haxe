// A struct value is never boxed: not into Dynamic (trace), a type parameter or Null<T>.
// expect: the struct Point converted to or from a reference
// expect: StructBoxed.hx:14)
@:hxmc.struct @:publicFields class Point {
	var x:Int;
	var y:Int;

	function new() {}
}

class StructBoxed {
	static function main() {
		var p = new Point();
		trace(p);
	}
}
