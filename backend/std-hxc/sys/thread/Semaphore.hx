package sys.thread;

import hxc.NativeThread;

// hxc target (backend/): over green threads (rt_thread.c). A release with
// waiters hands the unit to the longest waiting thread.
class Semaphore {
	var count:Int;
	var waiters:Array<Int> = [];

	public function new(value:Int):Void {
		count = value;
	}

	public function acquire():Void {
		tryAcquire(-1);
	}

	public function tryAcquire(?timeout:Float):Bool {
		if (count > 0) {
			count--;
			return true;
		}
		if (timeout == null || timeout == 0) return false;
		var cur = NativeThread.current();
		waiters.push(cur);
		while (true) {
			var woken = NativeThread.park(timeout < 0 ? -1 : timeout);
			if (waiters.indexOf(cur) < 0) return true; // a release took us out
			if (!woken) {
				waiters.remove(cur);
				return false;
			}
		}
	}

	public function release():Void {
		if (waiters.length > 0) NativeThread.unpark(waiters.shift()) else count++;
	}
}
