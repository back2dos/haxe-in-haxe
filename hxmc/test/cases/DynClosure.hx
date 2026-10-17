// Closures stored as Dynamic and called through function types whose
// representation differs from theirs (a () -> Bool called as Void->Dynamic
// returned its result unboxed: a crash), and kept as they are when it does
// not (their identity too).
class DynClosure {
	var cb:Void->Dynamic;

	function new() {}

	static function call(f:Void->Dynamic):Dynamic
		return f();

	static function get(d:Dynamic):Void->Dynamic
		return d;

	static function main() {
		var b:Dynamic = () -> true;
		var i:Dynamic = () -> 42;
		var x:Dynamic = () -> 1.5;
		Sys.println(Std.string(call(b)) + " " + (call(b) == true));
		Sys.println(Std.string(call(i)) + " " + (call(i) + 1));
		Sys.println(Std.string(call(x)));
		var inc:Dynamic = (n:Int) -> n + 1;
		var f:Dynamic->Dynamic = inc;
		Sys.println(f(41));
		var s:Dynamic = (a:String, n:Int) -> a + n;
		var g:Dynamic->Dynamic->String = s;
		Sys.println(g("x", 7));
		var v:Dynamic = (n:Float) -> {};
		var h:Int->Void = v;
		h(3);
		// the same representation: the same closure
		var same:Void->Dynamic = () -> "s";
		var d:Dynamic = same;
		var back:Void->Dynamic = d;
		Sys.println(back == same ? "identity kept" : "wrapped");
		// a field, a return, an anonymous object's field
		var o = new DynClosure();
		o.cb = b;
		Sys.println("field: " + o.cb());
		Sys.println("return: " + get(i)());
		var anon:{f:Void->Dynamic} = {f: x};
		Sys.println("anon: " + anon.f());
		var none:Dynamic = null;
		var n:Void->Dynamic = none;
		Sys.println(n == null ? "null stays null" : "not null");
	}
}
