package unit.moduleload;

class TryCatch {
	static function main():Void {
		try {
			throw "failure";
		} catch (error:String) {
			trace(error);
		} catch (error:Dynamic) {
			trace(error);
		}
	}
}
