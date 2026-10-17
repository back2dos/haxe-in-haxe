package hxmc.rt.gc;

import haxe.io.Bytes;

// -D hxmc.wasm-gc: haxe.io.Bytes is an array of bytes (W.bytes*); its
// accessors are instructions (hxmc.wasmgc.FuncGen), the rest here
@:keep @:hxmc.wasmgc
class GcBytes {
	@:hxmc.host("haxe_io_Bytes_blit") static function blit(b:Bytes, pos:Int, src:Bytes, srcpos:Int, len:Int):Void
		W.bytesCopy(b, pos, src, srcpos, len);

	@:hxmc.host("haxe_io_Bytes_fill") static function fill(b:Bytes, pos:Int, len:Int, value:Int):Void
		W.bytesFill(b, pos, value, len);

	@:hxmc.host("haxe_io_Bytes_sub") static function sub(b:Bytes, pos:Int, len:Int):Bytes {
		var r = W.bytesNew(len);
		W.bytesCopy(r, 0, b, pos, len);
		return r;
	}

	@:hxmc.host("haxe_io_Bytes_compare") static function compare(b:Bytes, other:Bytes):Int {
		var na = W.bytesLen(b), nb = W.bytesLen(other);
		for (i in 0...(na < nb ? na : nb)) {
			var x = W.bytesGet(b, i), y = W.bytesGet(other, i);
			if (x != y) return x - y;
		}
		return na - nb;
	}

	@:hxmc.host("haxe_io_Bytes_getUInt16") static function getUInt16(b:Bytes, pos:Int):Int
		return W.bytesGet(b, pos) | (W.bytesGet(b, pos + 1) << 8);

	@:hxmc.host("haxe_io_Bytes_setUInt16") static function setUInt16(b:Bytes, pos:Int, v:Int):Void {
		W.bytesSet(b, pos, v);
		W.bytesSet(b, pos + 1, v >> 8);
	}

	// UTF-8 to UTF-16 (invalid sequences as U+FFFD)
	// UTF-8 to UTF-16: the length counted, then the string written
	@:hxmc.host("haxe_io_Bytes_getString") static function getString(b:Bytes, pos:Int, len:Int, encoding:Dynamic):String {
		var s = W.strNew(utf16(b, pos, pos + len, null));
		utf16(b, pos, pos + len, s);
		return s;
	}

	// the UTF-16 units of the bytes [i, end), written to s unless null
	static function utf16(b:Bytes, i:Int, end:Int, s:Null<String>):Int {
		var o = 0;
		while (i < end) {
			var c = W.bytesGet(b, i++);
			if (c >= 0x80) {
				var n = c >= 0xF0 ? 3 : c >= 0xE0 ? 2 : c >= 0xC0 ? 1 : 0;
				if (n == 0 || i + n > end) c = 0xFFFD else {
					c &= 0x3F >> n;
					for (_ in 0...n)
						c = (c << 6) | (W.bytesGet(b, i++) & 0x3F);
					if (c >= 0x10000) {
						if (s != null) {
							W.strSet(s, o, 0xD800 | ((c - 0x10000) >> 10));
							W.strSet(s, o + 1, 0xDC00 | ((c - 0x10000) & 0x3FF));
						}
						o += 2;
						continue;
					}
				}
			}
			if (s != null) W.strSet(s, o, c);
			o++;
		}
		return o;
	}

	@:hxmc.host("haxe_io_Bytes_toString") static function toString(b:Bytes):String
		return getString(b, 0, W.bytesLen(b), null);

	@:hxmc.host("haxe_io_Bytes_toHex") static function toHex(b:Bytes):String {
		var n = W.bytesLen(b), r = W.strNew(2 * n);
		for (i in 0...n) {
			var x = W.bytesGet(b, i);
			W.strSet(r, 2 * i, hex(x >> 4));
			W.strSet(r, 2 * i + 1, hex(x & 15));
		}
		return r;
	}

	static inline function hex(d:Int):Int
		return d < 10 ? 48 + d : 87 + d;

	// UTF-16 to UTF-8
	@:hxmc.host("haxe_io_Bytes_ofString") static function ofString(s:String, encoding:Dynamic):Bytes {
		var n = W.strLen(s), size = 0, i = 0;
		while (i < n) {
			var c = codePoint(s, i, n);
			size += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
			i += c >= 0x10000 ? 2 : 1;
		}
		var b:Bytes = W.bytesNew(size), o = 0;
		i = 0;
		while (i < n) {
			var c = codePoint(s, i, n);
			i += c >= 0x10000 ? 2 : 1;
			if (c < 0x80) W.bytesSet(b, o++, c) else if (c < 0x800) {
				W.bytesSet(b, o++, 0xC0 | (c >> 6));
				W.bytesSet(b, o++, 0x80 | (c & 0x3F));
			} else if (c < 0x10000) {
				W.bytesSet(b, o++, 0xE0 | (c >> 12));
				W.bytesSet(b, o++, 0x80 | ((c >> 6) & 0x3F));
				W.bytesSet(b, o++, 0x80 | (c & 0x3F));
			} else {
				W.bytesSet(b, o++, 0xF0 | (c >> 18));
				W.bytesSet(b, o++, 0x80 | ((c >> 12) & 0x3F));
				W.bytesSet(b, o++, 0x80 | ((c >> 6) & 0x3F));
				W.bytesSet(b, o++, 0x80 | (c & 0x3F));
			}
		}
		return b;
	}

	static function codePoint(s:String, i:Int, n:Int):Int {
		var c = W.strGet(s, i);
		if (c >= 0xD800 && c < 0xDC00 && i + 1 < n) {
			var d = W.strGet(s, i + 1);
			if (d >= 0xDC00 && d < 0xE000) return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
		}
		return c;
	}

	@:hxmc.host("haxe_io_Bytes_ofHex") static function ofHex(s:String):Bytes {
		var n = W.strLen(s) >> 1, b:Bytes = W.bytesNew(n);
		for (i in 0...n)
			W.bytesSet(b, i, (unhex(W.strGet(s, 2 * i)) << 4) | unhex(W.strGet(s, 2 * i + 1)));
		return b;
	}

	static inline function unhex(c:Int):Int
		return c <= 57 ? c - 48 : (c | 32) - 87;
}

// haxe.io.BytesBuffer: its bytes, doubled when short (hxmc.rt.Bytes' natives)
@:keep @:hxmc.wasmgc
class GcBytesBuffer {
	var data = Bytes.alloc(64);
	var len = 0;

	function new() {}

	// room for n more bytes
	function reserve(n:Int) {
		if (len + n <= data.length) return;
		var cap = data.length * 2;
		if (cap < len + n) cap = len + n;
		var d = Bytes.alloc(cap);
		d.blit(0, data, 0, len);
		data = d;
	}

	@:hxmc.host("haxe_io_BytesBuffer_new") static function bbNew():Dynamic
		return new GcBytesBuffer();

	@:hxmc.host("haxe_io_BytesBuffer_get_length") @:hxmc.noGc static function bbGetLength(bb:GcBytesBuffer):Int
		return bb.len;

	@:hxmc.host("haxe_io_BytesBuffer_addByte") static function addByte(bb:GcBytesBuffer, v:Int):Void {
		bb.reserve(1);
		bb.data.set(bb.len++, v);
	}

	@:hxmc.host("haxe_io_BytesBuffer_addBytes") static function addBytes(bb:GcBytesBuffer, b:Bytes, pos:Int, n:Int):Void {
		if (pos < 0 || n < 0 || pos + n > b.length) throw haxe.io.Error.OutsideBounds;
		bb.reserve(n);
		bb.data.blit(bb.len, b, pos, n);
		bb.len += n;
	}

	@:hxmc.host("haxe_io_BytesBuffer_add") static function add(bb:GcBytesBuffer, b:Bytes):Void
		addBytes(bb, b, 0, b.length);

	@:hxmc.host("haxe_io_BytesBuffer_addString") static function addString(bb:GcBytesBuffer, s:String, encoding:Dynamic):Void
		add(bb, Bytes.ofString(s));

	@:hxmc.host("haxe_io_BytesBuffer_addInt32") static function addInt32(bb:GcBytesBuffer, v:Int):Void {
		bb.reserve(4);
		bb.data.setInt32(bb.len, v);
		bb.len += 4;
	}

	@:hxmc.host("haxe_io_BytesBuffer_addFloat") static function addFloat(bb:GcBytesBuffer, v:Float):Void {
		bb.reserve(4);
		bb.data.setFloat(bb.len, v);
		bb.len += 4;
	}

	@:hxmc.host("haxe_io_BytesBuffer_addDouble") static function addDouble(bb:GcBytesBuffer, v:Float):Void {
		bb.reserve(8);
		bb.data.setDouble(bb.len, v);
		bb.len += 8;
	}

	@:hxmc.host("haxe_io_BytesBuffer_getBytes") static function getBytes(bb:GcBytesBuffer):Bytes
		return bb.data.sub(0, bb.len);
}
