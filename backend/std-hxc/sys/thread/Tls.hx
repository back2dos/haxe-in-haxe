package sys.thread;

import hxc.NativeThread;

// hxc target (backend/): values keyed by green thread id (rt_thread.c).
// Setting null removes the entry (sys.thread.Thread does it when a thread ends).
// The map is shared by all threads, and a thread can be switched out at an
// allocation (rt_alloc_slow) in the middle of `set` (e.g. while the map
// grows), so every access holds `mutex`: an unguarded access could find the
// map half rebuilt (a missing entry, or a probe that never ends).
class Tls<T> {
	public var value(get, set):Null<T>;

	final values = new haxe.ds.IntMap<T>();
	final mutex = new Mutex();

	public function new():Void {}

	function get_value():Null<T> {
		mutex.acquire();
		var v = values.get(NativeThread.current());
		mutex.release();
		return v;
	}

	function set_value(v:Null<T>):Null<T> {
		mutex.acquire();
		if (v == null) values.remove(NativeThread.current()) else values.set(NativeThread.current(), v);
		mutex.release();
		return v;
	}
}
