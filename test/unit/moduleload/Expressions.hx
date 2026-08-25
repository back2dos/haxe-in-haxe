package unit.moduleload;

class Expressions {
	public static var initial = 1 + 2;
	public function run():Dynamic {
		var value = 1;
		return helper(value + 2);
	}
	function helper(value:Dynamic):Dynamic { return value; }
	function unchecked(value:Dynamic):Dynamic return untyped value.missing();
}
