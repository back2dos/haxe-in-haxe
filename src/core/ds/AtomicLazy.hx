package core.ds;

#if haxe_in_haxe_bootstrap
// HXB is a compiler cache format rather than a runnable target and exposes no
// thread primitives. The bootstrap compiler executes only after being loaded
// by a host compiler, so its lazy values need no target-level synchronization.
private class AtomicLazyMutex {
	public inline function new() {}
	public inline function acquire():Void {}
	public inline function release():Void {}
}
#else
private typedef AtomicLazyMutex = sys.thread.Mutex;
#end

// Port of haxe/src/core/ds/atomicLazy.ml.
private enum AtomicLazyState<T> {
	Unset(callback:Void->T);
	Computing;
	Set(value:T);
}

class AtomicLazy<T> {
	var state:AtomicLazyState<T>;
	var mutex:AtomicLazyMutex = new AtomicLazyMutex();

	function new(state:AtomicLazyState<T>) {
		this.state = state;
	}

	public static function fromFun<T>(callback:Void->T):AtomicLazy<T> {
		return new AtomicLazy(Unset(callback));
	}

	public static function fromVal<T>(value:T):AtomicLazy<T> {
		return new AtomicLazy(Set(value));
	}

	public function isVal():Bool {
		mutex.acquire();
		var value = switch (state) {
			case Set(_): true;
			case _: false;
		};
		mutex.release();
		return value;
	}

	public function force():T {
		while (true) {
			mutex.acquire();
			switch (state) {
				case Set(value):
					mutex.release();
					return value;
				case Computing:
					mutex.release();
					Sys.sleep(0.001);
				case Unset(callback):
					state = Computing;
					mutex.release();
					var value = callback();
					mutex.acquire();
					state = Set(value);
					mutex.release();
					return value;
			}
		}
		throw "Unreachable";
	}
}
