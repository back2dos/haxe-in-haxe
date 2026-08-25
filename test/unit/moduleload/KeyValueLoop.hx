package unit.moduleload;

class KeyValueLoop {
	public static function visit(values:Array<String>):Void {
		for (index => value in values) {
			index;
			value;
		}
	}
}
