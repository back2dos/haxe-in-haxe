// hxmc: haxe/upstream/std/sys/thread/Tls.hx: per-thread values (rt_thread.c keeps them
// with each thread; they go when the thread ends)

package sys.thread;

import hxmc.NativeThread;

/**
	A thread-local storage to store per-thread values.
**/
class Tls<T> {
	public var value(get, set):Null<T>;

	final id:Int = NativeThread.tlsNew();

	/**
		Creates thread local storage. This is placeholder that can store
		a value that will be different depending on the local thread.

		It is good practice to set the value to `null` when the thread exits.
		Otherwise, it might not be garbage-collected on some targets.
	**/
	public function new():Void {}

	function get_value():Null<T> {
		return NativeThread.tlsGet(id);
	}

	function set_value(v:Null<T>):Null<T> {
		NativeThread.tlsSet(id, v);
		return v;
	}
}
