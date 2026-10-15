// C structs are reached through pointers only (no struct values yet), and only C types cross a C call.
// expect: local r has the C type Point by value: structs are reached through a Ptr only
import hxmc.unsafe.*;

@:hxmc.struct @:publicFields class Point {
	var x:Int32;
	var y:Int32;
}

class StructValue {
	static function main() {
		Arena.scoped(a -> {
			var p = a.make(Point);
			var r = p.value;
			trace(r.x);
		});
	}
}
