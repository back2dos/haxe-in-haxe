class H {
	public static function out(s:String):Void {
		#if js
		js.Syntax.code("console.log({0})", s);
		#elseif flash
		trace(s);
		#else
		Sys.println(s);
		#end
	}
	public static function ix(i:Int, len:Int):Int {
		if (len <= 0)
			return 0;
		var r = i % len;
		return r < 0 ? r + len : r;
	}
	public static function at<T>(a:Array<T>, i:Int, d:T):T
		return a.length == 0 ? d : a[ix(i, a.length)];
	public static function exn(e:Dynamic):String {
		if (Std.isOfType(e, Fuel))
			return "fuel";
		if (Std.isOfType(e, String) || Std.isOfType(e, Int) || Std.isOfType(e, Bool))
			return Std.string(e);
		if (Std.isOfType(e, Err))
			return "Err" + (e : Err).errCode;
		return "other";
	}
}

class Fuel {
	public function new() {}
}

class Err extends haxe.Exception {
	public var errCode:Int;

	public function new(code:Int) {
		super("err" + code);
		this.errCode = code;
	}
}
