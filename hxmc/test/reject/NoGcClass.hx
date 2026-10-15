// @:hxmc.noGc on a class covers its functions; throwing, closures and dynamic calls are GC points.
// expect: NoGcClass.thrower is declared @:hxmc.noGc but reaches a GC point: it throws
// expect: NoGcClass.closure is declared @:hxmc.noGc but reaches a GC point: it allocates a closure
// expect: NoGcClass.dyncall is declared @:hxmc.noGc but reaches a GC point: it calls through a closure or structural field
@:hxmc.noGc class NoGcClass {
	static function thrower(n:Int):Int {
		if (n < 0) throw "negative";
		return n;
	}

	static function closure(n:Int):Void->Int
		return () -> n;

	static function dyncall(f:Int->Int):Int
		return f(1);

	static function ok(n:Int):Int
		return n * 2;

	static function main() {
		trace(thrower(1) + closure(2)() + dyncall(x -> x) + ok(3));
	}
}
