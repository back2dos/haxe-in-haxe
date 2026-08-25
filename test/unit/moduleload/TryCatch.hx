package unit.moduleload;

class TryCatch {
	static function main():Void {
		try {
			throw "failure";
		} catch (error:String) {
			trace(isString(error));
		} catch (error:Dynamic) {
			trace(error);
		}
	}

	static function isString(value:Dynamic):Bool return value is String;
}
