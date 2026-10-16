// @:hxmc.threadLocal statics: a copy per thread, zero in a new thread.
class ThreadLocal {
	@:hxmc.threadLocal static var counter:Int;
	@:hxmc.threadLocal static var f:Float;
	static function main() {
		counter = 5;
		f = 1.25;
		var lock = new sys.thread.Lock();
		// (Array is not thread-safe: the threads push under a mutex)
		var mutex = new sys.thread.Mutex();
		var seen = [];
		for (i in 0...3)
			sys.thread.Thread.create(() -> {
				var before = counter;
				for (k in 0...1000) counter++;
				f += i;
				var s = before + ":" + counter + ":" + f;
				mutex.acquire();
				seen.push(s);
				mutex.release();
				lock.release();
			});
		for (i in 0...3) lock.wait();
		seen.sort(Reflect.compare);
		trace(counter, f, seen);
	}
}
