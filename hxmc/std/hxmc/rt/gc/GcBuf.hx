package hxmc.rt.gc;

// -D hxmc.wasm-gc: a growing string (StringBuf, the runtime's joins)
@:keep @:hxmc.wasmgc
class GcBuf {
	public var chars:String;
	public var len = 0;

	public function new()
		chars = W.strNew(16);

	function room(n:Int) {
		var cap = W.strLen(chars);
		if (len + n <= cap) return;
		var c = cap * 2;
		if (c < len + n) c = len + n;
		var r = W.strNew(c);
		W.strCopy(r, 0, chars, 0, len);
		chars = r;
	}

	public function add(s:String) {
		var n = W.strLen(s);
		room(n);
		W.strCopy(chars, len, s, 0, n);
		len += n;
	}

	public function addChar(c:Int) {
		if (c >= 0x10000) {
			add(String.fromCharCode(c));
			return;
		}
		room(1);
		W.strSet(chars, len++, c);
	}
}
