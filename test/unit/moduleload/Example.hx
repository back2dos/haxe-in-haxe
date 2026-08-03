package unit.moduleload;

import haxe.ds.StringMap;

class Example {
	public static var value:Int = 1;
	public var choice:Choice;
	private final var alias:Alias;
	public function select(value:Choice):Alias { return null; }
}

enum Choice {
	One;
	Many(value:Example, ?count:Int);
}

typedef Alias = String;

abstract Count(Int) {}
