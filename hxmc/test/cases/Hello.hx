class Hello {
	static function fib(n:Int):Int
		return n < 2 ? n : fib(n - 1) + fib(n - 2);

	static function main() {
		var s = 0;
		for (i in 0...10)
			s += i * i;
		trace("hello " + s + " " + fib(20));
		var a = [3, 1, 2];
		a.sort((x, y) -> x - y);
		trace(a);
	}
}
