package sys.thread;

import hxc.NativeThread;

// hxc target (backend/): values keyed by green thread id (rt_thread.c).
// Setting null removes the entry (sys.thread.Thread does it when a thread ends).
class Tls<T> {
	public var value(get, set):Null<T>;

	final values = new haxe.ds.IntMap<T>();

	public function new():Void {}

	function get_value():Null<T> {
		return values.get(NativeThread.current());
	}

	function set_value(v:Null<T>):Null<T> {
		if (v == null) values.remove(NativeThread.current()) else values.set(NativeThread.current(), v);
		return v;
	}
}
