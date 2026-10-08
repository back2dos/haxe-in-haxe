class Fib {
	static function fib(n:Int):Int return n < 2 ? n : fib(n - 1) + fib(n - 2);
	static function main() Sys.println(fib(30));
}
