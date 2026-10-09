package sys.thread;

import hxc.NativeThread;

// hxc target (backend/): over green threads (rt_thread.c) and the hxc Mutex.
class Condition {
	final mutex = new Mutex();
	var waiters:Array<Int> = [];

	public function new():Void {}

	public function acquire():Void {
		mutex.acquire();
	}

	public function tryAcquire():Bool {
		return mutex.tryAcquire();
	}

	public function release():Void {
		mutex.release();
	}

	public function wait():Void {
		var cur = NativeThread.current();
		waiters.push(cur);
		// release the mutex fully, then take it back at the same depth
		var depth = @:privateAccess mutex.depth;
		@:privateAccess mutex.depth = 1;
		mutex.release();
		while (waiters.indexOf(cur) >= 0) NativeThread.park(-1);
		mutex.acquire();
		@:privateAccess mutex.depth = depth;
	}

	public function signal():Void {
		if (waiters.length > 0) NativeThread.unpark(waiters.shift());
	}

	public function broadcast():Void {
		var all = waiters;
		waiters = [];
		for (id in all) NativeThread.unpark(id);
	}
}
