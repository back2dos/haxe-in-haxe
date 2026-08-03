package core.ds;

// Port of haxe/src/core/ds/stringPool.ml.
class StringPool {
	var indices:Map<String, Int> = new Map();
	var items:StringDynArray = new StringDynArray(16);
	var closed:Bool = false;

	public function new() {}

	public function add(value:String):Int {
		if (closed) throw "String pool is finalized";
		var index = items.length;
		indices.set(value, index);
		items.add(value);
		return index;
	}

	public function get(value:String):Int {
		if (!indices.exists(value)) throw "Not_found";
		return indices.get(value);
	}

	public function getOrAdd(value:String):Int {
		return indices.exists(value) ? indices.get(value) : add(value);
	}

	public function finalize():StringDynArray {
		if (closed) throw "String pool is finalized";
		closed = true;
		return items;
	}
}
