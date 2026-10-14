package hxmc.rt.wasm;

import hxmc.rt.C;

// hxmc.NativeThread for WebAssembly, which has one thread here
// (hxmc/README.md, "WebAssembly"): creating a thread throws; mutexes count
// (they are reentrant), semaphores count, waits that nothing can end
// (no timeout, no permit, nobody to signal) throw instead of hanging, and
// waits with a timeout sleep it out; thread-local values are globals.
@:hxmc.wasm @:keep
class Threads {
	static var tls:Array<Dynamic>;
	static var tlsNext:Int;
	static var unparked:Bool;

	static function never(what:String):Void
		Rt.rt_throw(what + ": no other thread can end this wait (WebAssembly has one thread)");

	static function sleep(timeout:Float) {
		if (timeout > 0) hxmc.rt.WasiSys.sleep(timeout);
	}

	@:hxmc.export("hxmc_NativeThread_spawn") static function spawn(job:Dynamic):Int {
		Rt.rt_throw("threads are not supported on WebAssembly");
		return 0;
	}

	@:hxmc.export("hxmc_NativeThread_current") @:hxmc.noGc static function current():Int
		return 1;

	@:hxmc.export("hxmc_NativeThread_count") @:hxmc.noGc static function count():Int
		return 1;

	@:hxmc.export("hxmc_NativeThread_parallel") @:hxmc.noGc static function parallel():Bool
		return false;

	@:hxmc.export("hxmc_NativeThread_park") static function park(timeout:Float):Bool {
		if (unparked) {
			unparked = false;
			return true;
		}
		if (timeout < 0) never("Thread park");
		sleep(timeout);
		return false;
	}

	@:hxmc.export("hxmc_NativeThread_unpark") static function unpark(id:Int):Void {
		if (id == 1) unparked = true;
	}

	@:hxmc.export("hxmc_NativeThread_yield") @:hxmc.noGc static function yield():Void {}

	@:hxmc.export("hxmc_NativeThread_mutexNew") static function mutexNew():Dynamic
		return new Counter(0);

	@:hxmc.export("hxmc_NativeThread_mutexAcquire") static function mutexAcquire(m:Dynamic):Void
		(m : Counter).n++;

	@:hxmc.export("hxmc_NativeThread_mutexTryAcquire") static function mutexTryAcquire(m:Dynamic):Bool {
		(m : Counter).n++;
		return true;
	}

	@:hxmc.export("hxmc_NativeThread_mutexRelease") static function mutexRelease(m:Dynamic):Void {
		var c:Counter = m;
		if (c.n > 0) c.n--;
	}

	@:hxmc.export("hxmc_NativeThread_condNew") static function condNew():Dynamic
		return new Counter(0);

	@:hxmc.export("hxmc_NativeThread_condWait") static function condWait(c:Dynamic, m:Dynamic, timeout:Float):Bool {
		if (timeout < 0) never("Condition wait");
		sleep(timeout);
		return false;
	}

	@:hxmc.export("hxmc_NativeThread_condSignal") static function condSignal(c:Dynamic):Void {}

	@:hxmc.export("hxmc_NativeThread_condBroadcast") static function condBroadcast(c:Dynamic):Void {}

	@:hxmc.export("hxmc_NativeThread_semNew") static function semNew(value:Int):Dynamic
		return new Counter(value);

	@:hxmc.export("hxmc_NativeThread_semAcquire") static function semAcquire(s:Dynamic, timeout:Float):Bool {
		var c:Counter = s;
		if (c.n > 0) {
			c.n--;
			return true;
		}
		if (timeout < 0) never("Semaphore acquire");
		sleep(timeout);
		return false;
	}

	@:hxmc.export("hxmc_NativeThread_semRelease") static function semRelease(s:Dynamic):Void
		(s : Counter).n++;

	@:hxmc.export("hxmc_NativeThread_tlsNew") static function tlsNew():Int
		return tlsNext++;

	@:hxmc.export("hxmc_NativeThread_tlsGet") static function tlsGet(id:Int):Dynamic
		return tls == null || id < 0 || id >= tls.length ? null : tls[id];

	@:hxmc.export("hxmc_NativeThread_tlsSet") static function tlsSet(id:Int, v:Dynamic):Void {
		if (id < 0) return;
		if (tls == null) tls = [];
		tls[id] = v;
	}
}

@:hxmc.wasm @:keep
private class Counter {
	public var n:Int;

	public function new(n:Int)
		this.n = n;
}
