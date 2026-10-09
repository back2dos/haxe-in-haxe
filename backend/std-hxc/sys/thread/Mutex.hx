package sys.thread;

import hxc.NativeThread;

// hxc target (backend/): a re-entrant mutex over green threads (rt_thread.c).
// Only one thread runs at a time, so the state needs no atomics; a release
// hands the mutex to the longest waiting thread.
class Mutex {
	var owner = 0; // thread id, 0: free
	var depth = 0;
	var waiters:Null<Array<Int>>;

	public function new():Void {}

	public function acquire():Void {
		var cur = NativeThread.current();
		if (owner == 0) {
			owner = cur;
			depth = 1;
		} else if (owner == cur) {
			depth++;
		} else {
			if (waiters == null) waiters = [];
			waiters.push(cur);
			while (owner != cur) NativeThread.park(-1);
		}
	}

	public function tryAcquire():Bool {
		var cur = NativeThread.current();
		if (owner == 0) {
			owner = cur;
			depth = 1;
			return true;
		}
		if (owner == cur) {
			depth++;
			return true;
		}
		return false;
	}

	public function release():Void {
		if (owner == 0) return;
		if (depth > 1) {
			depth--;
			return;
		}
		if (waiters != null && waiters.length > 0) {
			owner = waiters.shift();
			depth = 1;
			NativeThread.unpark(owner);
		} else {
			owner = 0;
			depth = 0;
		}
	}
}
