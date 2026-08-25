package unit.moduleload;

class InlineLocalFunction {
	public static function value():String {
		inline function getValue() {
			return "value";
		}
		return getValue();
	}
}
