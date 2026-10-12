package shim;

// port: tink.core.Error (tink_core), the error type of haxeshim and lix:
// an HTTP-like status code, also the exit code of the command line tools

enum abstract ErrorCode(Int) from Int to Int {
	var BadRequest = 400;
	var Unauthorized = 401;
	var NotFound = 404;
	var UnprocessableEntity = 422;
	var InternalError = 500;
	var NotImplemented = 501;
}

class Error extends haxe.Exception {
	public final code:Int;
	public var data(default, null):Dynamic;

	public function new(?code:ErrorCode = InternalError, message:String, ?previous:haxe.Exception) {
		super(message, previous);
		this.code = code;
	}

	static public function withData(?code:ErrorCode = InternalError, message:String, data:Dynamic):Error {
		var e = new Error(code, message);
		e.data = data;
		return e;
	}

	/** `e` as an `Error`, if it is not one already (code 500). **/
	static public function of(e:Dynamic):Error
		return switch Std.downcast(e, Error) {
			case null:
				var ex = Std.downcast(e, haxe.Exception);
				new Error(InternalError, ex != null ? ex.message : Std.string(e));
			case v: v;
		}
}
