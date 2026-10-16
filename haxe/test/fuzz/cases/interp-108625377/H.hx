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
}
