package unit.moduleload;

class LocalStatics {
	public static function run():Int {
		static var count = 1;
		static final increment = 2;
		return count + increment;
	}
}
