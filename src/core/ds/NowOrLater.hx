package core.ds;

import sys.thread.Mutex;

class NowOrLater {
	var now:Mutex = new Mutex();
	// port: OCaml mutexes are not recursive, Haxe's are: `running` makes `try_lock` fail on
	// the thread that holds `now` too.
	var running:Bool = false;
	// port: `later`, a Saturn single-consumer queue (FIFO)
	var laterMutex:Mutex = new Mutex();
	var later:Array<Void->Void> = [];

	public function new() {}

	public function tryNow(callback:Void->Void):Void {
		if (!running && now.tryAcquire()) {
			running = true;
			callback();
			running = false;
			now.release();
		} else {
			laterMutex.acquire();
			later.push(callback);
			laterMutex.release();
		}
	}

	// port: runs `callback` now, holding the lock `tryNow` callbacks run under, for a
	// write upstream makes without it (Dce's `__define_feature__`): OCaml's Hashtbl
	// survives racing writes from other domains, the hxc runtime's maps do not.
	public function runNow(callback:Void->Void):Void {
		now.acquire();
		callback();
		now.release();
	}

	public function handleLater():Void {
		while (true) {
			laterMutex.acquire();
			var callback = later.shift();
			laterMutex.release();
			if (callback == null) return;
			callback();
		}
	}
}
