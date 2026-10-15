// hxmc: haxe/upstream/std/sys/thread/Deque.hx: an array guarded by a mutex, with a
// condition for blocking pops (rt_thread.c)

package sys.thread;

import hxmc.NativeThread;

/**
	A Deque is an output-restricted double-ended queue with a `pop` method that can
	block until an element is available. It is commonly used to synchronize threads.
 */
class Deque<T> {
	final mutex:Dynamic = NativeThread.mutexNew();
	final cond:Dynamic = NativeThread.condNew();
	var items:Array<T> = [];

	/**
		Create a new Deque instance which is initially empty.
	**/
	public function new():Void {}

	/**
		Adds an element at the end of `this` Deque.

		(Java,Jvm): throws `java.lang.NullPointerException` if `i` is `null`.
	**/
	public function add(i:T):Void {
		NativeThread.mutexAcquire(mutex);
		items.push(i);
		NativeThread.condSignal(cond);
		NativeThread.mutexRelease(mutex);
	}

	/**
		Adds an element at the front of `this` Deque.

		(Java,Jvm): throws `java.lang.NullPointerException` if `i` is `null`.
	**/
	public function push(i:T):Void {
		NativeThread.mutexAcquire(mutex);
		items.unshift(i);
		NativeThread.condSignal(cond);
		NativeThread.mutexRelease(mutex);
	}

	/**
		Tries to retrieve an element from the front of `this` Deque.

		If an element is available, it is removed from the queue and returned.

		If no element is available and `block` is `false`, `null` is returned.

		Otherwise, execution blocks until an element is available and returns it.
	**/
	public function pop(block:Bool):Null<T> {
		NativeThread.mutexAcquire(mutex);
		while (items.length == 0) {
			if (!block) {
				NativeThread.mutexRelease(mutex);
				return null;
			}
			NativeThread.condWait(cond, mutex, -1);
		}
		var v = items.shift();
		NativeThread.mutexRelease(mutex);
		return v;
	}
}
