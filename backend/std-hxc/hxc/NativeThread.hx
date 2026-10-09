package hxc;

// hxc target (backend/): green threads (rt_thread.c), the base of the hxc
// sys.thread package. All threads run on one OS thread and switch only when
// the running one parks, sleeps, yields or waits for a descriptor (blocking
// socket, pipe and terminal I/O of hxc.NativeNet/NativeSys), so the
// sys.thread primitives are plain Haxe over park/unpark. Threads are ids;
// the main thread is 1.
extern class NativeThread {
	static function spawn(job:() -> Void):Int; // a new runnable thread (it runs when the current one gives way)
	static function current():Int;
	static function count():Int; // live threads
	// blocks until unpark (true) or until `timeout` seconds pass (false); timeout < 0: no timeout
	static function park(timeout:Float):Bool;
	// wakes a thread blocked in park, else makes its next park return at once
	// (a thread may be switched out at an allocation between queueing itself
	// and parking); park can return early, so callers check their condition again
	static function unpark(id:Int):Void;
	static function yield():Void;
}
