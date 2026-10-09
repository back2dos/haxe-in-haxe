package sys.thread;

import hxc.NativeThread;

// hxc target (backend/): over green threads (rt_thread.c). A release with
// waiters wakes the longest waiting one and gives it the release.
class Lock {
	var count = 0;
	var waiters:Array<Int> = [];

	public function new():Void {}

	public function wait(?timeout:Float):Bool {
		if (count > 0) {
			count--;
			return true;
		}
		if (timeout != null && timeout <= 0) return false;
		var cur = NativeThread.current();
		var deadline = timeout == null ? -1 : timeout;
		if (deadline >= 0) deadline += Sys.time();
		waiters.push(cur);
		while (true) {
			if (waiters.indexOf(cur) < 0) return true; // a release took us out
			// a release while push was growing the array (an allocation may
			// switch threads) found no waiter and counted
			if (count > 0) {
				waiters.remove(cur);
				count--;
				return true;
			}
			if (!NativeThread.park(deadline < 0 ? -1 : Math.max(0, deadline - Sys.time()))) {
				if (waiters.remove(cur)) return false; // else a release took us out meanwhile
				return true;
			}
			// unparked, or an early return of park (see NativeThread.unpark): look again
		}
	}

	public function release():Void {
		if (waiters.length > 0) NativeThread.unpark(waiters.shift()) else count++;
	}
}
