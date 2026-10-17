package hxmc.rt.gc;

// -D hxmc.wasm-gc: a growing string (StringBuf, the runtime's joins)
@:keep @:hxmc.wasmgc
class GcBuf {
	public var chars:String;
	public var len = 0;
	var cap = 16;

	public function new()
		chars = W.strNew(16);

	function grow(n:Int) {
		var c = cap * 2;
		if (c < len + n) c = len + n;
		var r = W.strNew(c);
		W.strCopy(r, 0, chars, 0, len);
		chars = r;
		cap = c;
	}

	public function add(s:String) {
		var n = W.strLen(s);
		if (len + n > cap) grow(n);
		W.strCopy(chars, len, s, 0, n);
		len += n;
	}

	public inline function addChar(c:Int) {
		if (c >= 0x10000) addPair(c) else {
			if (len == cap) grow(1);
			W.strSet(chars, len++, c);
		}
	}

	function addPair(c:Int)
		add(String.fromCharCode(c));
}
