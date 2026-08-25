package unit.moduleload;

class Expressions {
	public static var initial = 1 + 2;
	public function run():Dynamic {
		var value = 1;
		return helper(value + 2);
	}
	function helper(value:Dynamic):Dynamic { return value; }
	function unchecked(value:Dynamic):Dynamic return untyped value.missing();
	function typeTest(value:Dynamic):Bool return value is String;
	function conditions(value:Int):Void {
		while (value > 0) value--;
		if (value == 0) value++;
	}
	function guarded(value:Dynamic):Dynamic try {
		return value.missing();
	} catch (error:Dynamic) {
		return error;
	}
}
