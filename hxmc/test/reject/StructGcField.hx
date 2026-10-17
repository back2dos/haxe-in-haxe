// A struct holds C scalars and other structs: no GC references (the collector does not scan struct memory).
// expect: name has no C type
@:hxmc.struct @:publicFields class Named {
	var id:Int;
	var name:String;

	function new() {}
}

class StructGcField {
	static function main() {
		var n = new Named();
		trace(n.id);
	}
}
