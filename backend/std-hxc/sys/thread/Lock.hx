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
		waiters.push(cur);
		while (true) {
			var woken = NativeThread.park(timeout == null ? -1 : timeout);
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
