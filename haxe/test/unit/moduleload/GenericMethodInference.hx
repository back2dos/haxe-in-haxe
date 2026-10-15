package unit.moduleload;

class GenericMethodInference {
	public static function main():Void {
		var value = null;
		combine(1, value);
	}

	static function combine<T, R:T>(value:R, nullable:Null<T>):Void {}
}
