class H {
	public static var fuel:Int = 20000;
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
}

class Fuel {
	public function new() {}
}
