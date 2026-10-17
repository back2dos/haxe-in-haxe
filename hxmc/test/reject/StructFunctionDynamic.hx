// A function taking or returning a struct value is called with addresses: it cannot become Dynamic.
// expect: a function taking or returning a struct value cannot become Dynamic
@:hxmc.struct @:publicFields class Point {
	var x:Int;
	var y:Int;

	function new() {}
}

class StructFunctionDynamic {
	static function call(f:Dynamic):Dynamic
		return f(null);

	static function main() {
		trace(call((p:Point) -> p.x));
	}
}
