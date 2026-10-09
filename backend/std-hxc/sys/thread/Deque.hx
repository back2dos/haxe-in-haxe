package sys.thread;

import hxc.NativeThread;

// hxc target (backend/): over green threads (rt_thread.c).
class Deque<T> {
	var items:Array<T> = [];
	var waiters:Array<Int> = [];

	public function new():Void {}

	public function add(i:T):Void {
		items.push(i);
		wakeOne();
	}

	public function push(i:T):Void {
		items.unshift(i);
		wakeOne();
	}

	public function pop(block:Bool):Null<T> {
		while (items.length == 0) {
			if (!block) return null;
			var cur = NativeThread.current();
			waiters.push(cur);
			// items.length: an add while push was growing the array found no waiter
			while (waiters.indexOf(cur) >= 0 && items.length == 0) NativeThread.park(-1);
			waiters.remove(cur);
		}
		return items.shift();
	}

	inline function wakeOne() {
		if (waiters.length > 0) NativeThread.unpark(waiters.shift());
	}
}
