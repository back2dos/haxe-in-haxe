// Static functions called through their @:overload signatures (upstream's
// unit test Issue6674): a non-extern class implements each with the
// function itself, the arguments and result converted from the overload's
// types (FnLower.overloadImpl).
class Overloads {
	static var hits:Array<Null<String>> = [];

	@:overload(function(cb:haxe.DynamicAccess<String>->Void):Void {})
	public static function load(cb:String->Void) {
		cb("x");
	}

	@:overload(function(cb:Int->String):String {})
	public static function apply(cb:Float->String):String
		return cb(2);

	static function main() {
		load(function(response) hits.push(response["foo"]));
		load((s:String) -> hits.push(s));
		Sys.println(hits);
		Sys.println(apply((f:Float) -> "float " + f * 1.5) + ", " + apply((i:Int) -> "int " + (i + 1)));
	}
}
