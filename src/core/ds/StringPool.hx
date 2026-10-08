package core.ds;

// Port of haxe/src/core/ds/stringPool.ml.
class StringPool {
	var indices:Map<String, Int> = new Map();
	var items:StringDynArray = new StringDynArray(16);
	var closed:Bool = false;

	public function new() {}

	// Deviation: HashLink's StringMap truncates keys at the first NUL ("\x00"
	// and "" collide), so on HL keys containing NUL (or starting with the
	// escape character) are escaped injectively into a NUL-free form.
	static inline function key(value:String):String {
		#if hl
		return value.indexOf("\x00") < 0 && value.charCodeAt(0) != 1 ? value : "\x01" + value.split("\x01").join("\x01\x01").split("\x00").join("\x01\x02");
		#else
		return value;
		#end
	}

	public function add(value:String):Int {
		if (closed) throw "String pool is finalized";
		var index = items.length;
		indices.set(key(value), index);
		items.add(value);
		return index;
	}

	public function get(value:String):Int {
		var k = key(value);
		if (!indices.exists(k)) throw "Not_found";
		return indices.get(k);
	}

	public function getOrAdd(value:String):Int {
		var i = indices.get(key(value));
		return i != null ? i : add(value);
	}

	public function finalize():StringDynArray {
		if (closed) throw "String pool is finalized";
		closed = true;
		return items;
	}
}
