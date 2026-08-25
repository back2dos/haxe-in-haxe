package unit.moduleload;

class KeyValueLoop {
	public static function visit(values:Array<String>):Void {
		for (index => value in values) {
			index;
			value;
		}
	}

	public static function visitMap(values:Map<Int, String>):Void {
		for (value in values) value;
	}

	public static function visitArray(values:Array<String>):Void {
		for (value in values) value;
	}

	public static function visitRange(end:Int):Void {
		for (index in 0...end) index;
	}
}
