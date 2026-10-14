// hxmc: haxe/std/sys/thread/Mutex.hx: a re-entrant mutex (rt_thread.c: a
// pthread mutex with OS threads, a queue of parked threads with green
// threads). A thread blocked on it is in a safe region, so a collection never
// waits for it.

package sys.thread;

import hxmc.NativeThread;

/**
	Creates a mutex, which can be used to acquire a temporary lock
	to access some resource. The main difference with a lock is
	that a mutex must always be released by the owner thread.

	On targets that don't support threads this class is a stub.
**/
class Mutex {
	final handle:Dynamic = NativeThread.mutexNew();

	/**
		Creates a mutex.
	**/
	public function new():Void {}

	/**
		The current thread acquire the mutex or wait if not available.
		The same thread can acquire several times the same mutex but
		must release it as many times it has been acquired.
	**/
	public function acquire():Void {
		NativeThread.mutexAcquire(handle);
	}

	/**
		Try to acquire the mutex, returns true if acquire or false
		if it's already locked by another thread.
	**/
	public function tryAcquire():Bool {
		return NativeThread.mutexTryAcquire(handle);
	}

	/**
		Release a mutex that has been acquired by the current thread.
		The behavior is undefined if the current thread does not own
		the mutex.
	**/
	public function release():Void {
		NativeThread.mutexRelease(handle);
	}
}
