package shim;

// port: the parts of the ansi haxelib (https://github.com/kevinresol/ansi) that haxeshim's Logger uses
class Ansi {
	static public var available = false;

	static public inline var RED = 31;
	static public inline var GREEN = 32;
	static public inline var YELLOW = 33;
	static public inline var DEFAULT_FOREGROUND = 39;
	static public inline var OFF = 0;

	static public function set(attributes:Array<Int>):String
		return available ? '\x1B[' + attributes.join(';') + 'm' : '';

	static public function eraseLine():String
		return available ? '\x1B[2K' : '';

	static public function setX():String
		return available ? '\x1B[1G' : '';
}
