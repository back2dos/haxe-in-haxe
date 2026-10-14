// hxmc: haxe/std/haxe/ds/ObjectMap.hx as a compact insertion-ordered hash table (as
// in Python and JS): entries are appended to parallel arrays, an
// open-addressing index (0 empty, -1 removed, else entry + 1) finds them.
// Iteration follows insertion order. IntMap, StringMap and ObjectMap are the
// same code but for the key type, hash and equality.

package haxe.ds;

/**
	ObjectMap allows mapping of object keys to arbitrary values.

	On static targets, the keys are considered to be strong references. Refer
	to `haxe.ds.WeakMap` for a weak reference version.

	See `Map` for documentation details.

	@see https://haxe.org/manual/std-Map.html
**/
class ObjectMap<K:{}, T> implements haxe.Constraints.IMap<K, T> {
	var index:Array<Int>;
	var hashes:Array<Int>;
	var ks:Array<K>;
	var vs:Array<T>;
	var dead:Array<Bool>;
	var live:Int;
	var mask:Int;

	/**
		Creates a new ObjectMap.
	**/
	public function new()
		reset(0); // the index is allocated by the first set

	function reset(cap:Int) {
		index = [];
		if (cap > 0) index.resize(cap);
		hashes = [];
		ks = [];
		vs = [];
		dead = [];
		live = 0;
		mask = cap - 1;
	}

	inline function hashOf(k:K):Int {
		return hxmc.Native.objHash(k);
	}

	inline function find(k:K, h:Int):Int {
		if (live == 0) return -1;
		var i = h & mask;
		var r = -1;
		while (true) {
			var e = index[i];
			if (e == 0) break;
			if (e > 0 && hashes[e - 1] == h && hxmc.Native.refEq(ks[e - 1], k)) {
				r = e - 1;
				break;
			}
			i = (i + 1) & mask;
		}
		return r;
	}

	/**
		See `Map.get`
	**/
	public function get(k:K):Null<T> {
		var e = find(k, hashOf(k));
		return e < 0 ? null : vs[e];
	}

	/**
		See `Map.exists`
	**/
	public function exists(k:K):Bool
		return find(k, hashOf(k)) >= 0;

	/**
		See `Map.set`
	**/
	public function set(k:K, v:T):Void {
		var h = hashOf(k);
		var e = find(k, h);
		if (e >= 0) {
			vs[e] = v;
			return;
		}
		if ((ks.length + 1) * 4 > (mask + 1) * 3) grow();
		var n = ks.length;
		hashes.push(h);
		ks.push(k);
		vs.push(v);
		dead.push(false);
		live++;
		var i = h & mask;
		while (index[i] > 0)
			i = (i + 1) & mask;
		index[i] = n + 1;
	}

	/**
		See `Map.remove`
	**/
	public function remove(k:K):Bool {
		if (live == 0) return false;
		var h = hashOf(k);
		var i = h & mask;
		while (true) {
			var e = index[i];
			if (e == 0) return false;
			if (e > 0 && hashes[e - 1] == h && {var k2 = ks[e - 1]; hxmc.Native.refEq(k2, k);}) {
				index[i] = -1;
				dead[e - 1] = true;
				ks[e - 1] = cast null;
				vs[e - 1] = cast null;
				live--;
				return true;
			}
			i = (i + 1) & mask;
		}
	}

	// rebuild with removed entries dropped and room for twice the live ones
	function grow() {
		var oh = hashes, ok = ks, ov = vs, od = dead;
		var cap = 8;
		while (cap * 3 < (live + 1) * 8)
			cap *= 2;
		reset(cap);
		for (j in 0...ok.length)
			if (!od[j]) {
				var n = ks.length;
				hashes.push(oh[j]);
				ks.push(ok[j]);
				vs.push(ov[j]);
				dead.push(false);
				live++;
				var i = oh[j] & mask;
				while (index[i] > 0)
					i = (i + 1) & mask;
				index[i] = n + 1;
			}
	}

	/**
		See `Map.keys`

		(java) Implementation detail: Do not `set()` any new value while
		iterating, as it may cause a resize, which will break iteration.
	**/
	public function keys():Iterator<K>
		return new ObjectMapIterator(this, true);

	/**
		See `Map.iterator`

		(java) Implementation detail: Do not `set()` any new value while
		iterating, as it may cause a resize, which will break iteration.
	**/
	public function iterator():Iterator<T>
		return cast new ObjectMapIterator(this, false);

	/**
		See `Map.keyValueIterator`
	**/
	@:runtime public inline function keyValueIterator():KeyValueIterator<K, T>
		return new haxe.iterators.MapKeyValueIterator(this);

	/**
		See `Map.copy`
	**/
	public function copy():ObjectMap<K, T> {
		var m = new ObjectMap<K, T>();
		for (j in 0...ks.length)
			if (!dead[j]) m.set(ks[j], vs[j]);
		return m;
	}

	/**
		See `Map.toString`
	**/
	public function toString():String {
		var b = new StringBuf();
		b.add("[");
		var first = true;
		for (j in 0...ks.length)
			if (!dead[j]) {
				if (!first) b.add(", ");
				first = false;
				b.add(Std.string(ks[j]));
				b.add(" => ");
				b.add(Std.string(vs[j]));
			}
		b.add("]");
		return b.toString();
	}

	/**
		See `Map.clear`
	**/
	public function clear():Void
		reset(0);

	public function size():Int
		return live;
}

@:access(haxe.ds.ObjectMap)
private class ObjectMapIterator<K:{}, T> {
	var m:ObjectMap<K, T>;
	var i:Int;
	var keys:Bool;

	public function new(m, keys) {
		this.m = m;
		this.keys = keys;
		i = 0;
		skip();
	}

	inline function skip() {
		while (i < m.ks.length && m.dead[i])
			i++;
	}

	public function hasNext():Bool
		return i < m.ks.length;

	public function next():Dynamic {
		var r:Dynamic = keys ? m.ks[i] : m.vs[i];
		i++;
		skip();
		return r;
	}
}
