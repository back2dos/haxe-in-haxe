package unit.moduleload;

class Accessors {
	public var message(get, never):String;

	function get_message():String return "message";

	public static function read(value:Null<Accessors>):String return value.message;
}
