// hxmc: haxe/upstream/std/sys/thread/Lock.hx: a counting semaphore starting at 0
// (rt_thread.c), each release lets exactly one wait through

package sys.thread;

import hxmc.NativeThread;

/**
	A Lock allows blocking execution until it has been unlocked. It keeps track
	of how often `release` has been called, and blocks exactly as many `wait`
	calls.

	The order of the `release` and `wait` calls is irrelevant. That is, a Lock
	can be released before anyone waits for it. In that case, the `wait` call
	will execute immediately.

	Usage example:

	```haxe
	var lock = new Lock();
	var elements = [1, 2, 3];
	for (element in elements) {
		// Create one thread per element
		new Thread(function() {
			trace(element);
			Sys.sleep(1);
			// Release once per thread = 3 times
			lock.release();
		});
	}
	for (_ in elements) {
		// Wait 3 times
		lock.wait();
	}
	trace("All threads finished");
	```
**/
class Lock {
	final sem:Dynamic = NativeThread.semNew(0);

	/**
		Creates a new Lock which is initially locked.
	**/
	public function new():Void {}

	/**
		Waits for the lock to be released, or `timeout` (in seconds)
		to expire. Returns `true` if the lock is released and `false`
		if a time-out occurs.
	**/
	public function wait(?timeout:Float):Bool {
		return NativeThread.semAcquire(sem, timeout == null ? -1 : (timeout > 0 ? timeout : 0));
	}

	/**
		Releases the lock once.

		The thread does not need to own the lock in order to release
		it. Each call to `release` allows exactly one call to `wait`
		to execute.
	**/
	public function release():Void {
		NativeThread.semRelease(sem);
	}
}
