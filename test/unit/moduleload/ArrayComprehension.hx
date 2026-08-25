package unit.moduleload;

class ArrayComprehension {
	public static function collect(values:Array<String>):Array<String>
		return [for (value in values) value];
}
