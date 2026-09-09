package examples;

class Fibonacci {
	static function fibonacci(n:Int):Int {
		var previous = 0;
		var current = 1;
		var remaining = n;
		while (remaining > 0) {
			var next = previous + current;
			previous = current;
			current = next;
			remaining--;
		}
		return previous;
	}

	static function main():Void {
		for (index in 0...11) {
			trace('fibonacci($index) = ${fibonacci(index)}');
		}
	}
}
