// hxmc: haxe/upstream/std/sys/thread/Semaphore.hx, a counting semaphore (rt_thread.c)

package sys.thread;

import hxmc.NativeThread;

class Semaphore {
	final sem:Dynamic;

	/**
		Creates a new semaphore with an initial value.
	**/
	public function new(value:Int):Void {
		sem = NativeThread.semNew(value);
	}

	/**
		Locks the semaphore.
		If the value of the semaphore is zero, then the thread will block until it is able to lock the semaphore.
		If the value is non-zero, it is decreased by one.
	**/
	public function acquire():Void {
		NativeThread.semAcquire(sem, -1);
	}

	/**
		Try to lock the semaphore.
		If the value of the semaphore is zero, `false` is returned, else the value is increased.

		If `timeout` is specified, this function will block until the thread is able to acquire the semaphore, or the timeout expires.
		`timeout` is in seconds.
	**/
	// hxmc: a null or 0 timeout just tries, < 0 waits forever
	public function tryAcquire(?timeout:Float):Bool {
		return NativeThread.semAcquire(sem, timeout == null ? 0 : timeout);
	}

	/**
		Release the semaphore.
		The value of the semaphore is increased by one.
	**/
	public function release():Void {
		NativeThread.semRelease(sem);
	}
}
