package unit.moduleload;

class ValueSwitch {
	static inline final expected = 1;

	public static function select(value:Int):String return switch (value) {
		case expected: "yes";
		case _: "no";
	}

	public static function numeric(value:Int):String return switch value {
		case 1, 2: "yes";
		default: "no";
	}
}
