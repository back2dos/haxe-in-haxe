// hxc: haxe/std/sys/thread/ThreadImpl.hx: a thread (rt_thread.c) is its id
// (null: not started yet, as sys.thread.Thread expects of other targets)

package sys.thread;

import hxc.NativeThread;

abstract ThreadImpl(Null<Int>) {
	public static inline function current():ThreadImpl {
		return cast NativeThread.current();
	}

	public static inline function create(job:() -> Void):ThreadImpl {
		return cast NativeThread.spawn(job);
	}

	public static function getName(t:ThreadImpl):Null<String> {
		return null;
	}

	public static function setName(t:ThreadImpl, name:String) {}
}
