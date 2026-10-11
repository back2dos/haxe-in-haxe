package core.ds;

import sys.thread.Mutex;

class ThreadSafeHashtbl<Key, Value> {
	final h:OcamlHashtbl<Key, Value>;
	final mutex:Mutex = new Mutex();

	public function new(size:Int) {
		h = new OcamlHashtbl<Key, Value>(polymorphicHash, function(a, b) return a == b, size);
	}

	// port: OCaml's polymorphic `Hashtbl.hash`, for the key types the port uses.
	static function polymorphicHash<Key>(key:Key):Int {
		var k:Dynamic = key;
		if (Std.isOfType(k, String)) return OcamlHash.hashString(k);
		if (Std.isOfType(k, Int)) return OcamlHashtbl.hashInt(k);
		throw new Failure("ThreadSafeHashtbl: no polymorphic hash for " + Std.string(k));
	}

	// port: `Mutex.protect`: the mutex is released when `f` raises.
	inline function protect<Result>(f:Void->Result):Result {
		mutex.acquire();
		var r = try f() catch (e:haxe.Exception) {
			mutex.release();
			throw e;
		}
		mutex.release();
		return r;
	}

	public function add(k:Key, v:Value):Void {
		protect(function() {
			h.add(k, v);
			return null;
		});
	}

	public function replace(k:Key, v:Value):Void {
		protect(function() {
			h.replace(k, v);
			return null;
		});
	}

	public function find(k:Key):Value {
		return protect(function() return h.find(k));
	}

	public function findOrAdd(k:Key, f:Void->Value):Value {
		mutex.acquire();
		try {
			var r = h.find(k);
			mutex.release();
			return r;
		} catch (_:NotFound) {
			// port: like upstream, the mutex stays locked if `f` raises
			var r = f();
			h.add(k, r);
			mutex.release();
			return r;
		}
	}

	public function mem(k:Key):Bool {
		return protect(function() return h.mem(k));
	}

	public function remove(k:Key):Void {
		protect(function() {
			h.remove(k);
			return null;
		});
	}

	public function fold<Acc>(f:Key->Value->Acc->Acc, acc:Acc):Acc {
		return protect(function() return h.fold(f, acc));
	}
}
