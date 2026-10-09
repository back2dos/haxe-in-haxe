package sys.thread;

import hxc.NativeThread;

// hxc target (backend/): a re-entrant mutex over green threads (rt_thread.c).
// Only one thread runs at a time, so the state needs no atomics, but a thread
// can be switched out at an allocation (rt_alloc_slow), so waits check their
// condition again after queueing. A release hands the mutex to the longest
// waiting thread.
class Mutex {
	var owner = 0; // thread id, 0: free
	var depth = 0;
	// allocated with the mutex: a lazy `if (waiters == null) waiters = []` could
	// lose a waiter (two threads allocating, switched at the allocation)
	final waiters:Array<Int> = [];

	public function new():Void {}

	public function acquire():Void {
		var cur = NativeThread.current();
		if (owner == 0) {
			owner = cur;
			depth = 1;
		} else if (owner == cur) {
			depth++;
		} else {
			waiters.push(cur);
			while (owner != cur) {
				// released while push was growing the array (an allocation may
				// switch threads): nobody was waiting, take it
				if (owner == 0) {
					waiters.remove(cur);
					owner = cur;
					depth = 1;
					return;
				}
				NativeThread.park(-1);
			}
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
		if (waiters.length > 0) {
			owner = waiters.shift();
			depth = 1;
			NativeThread.unpark(owner);
		} else {
			owner = 0;
			depth = 0;
		}
	}
}
