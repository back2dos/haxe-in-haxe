// hxc: haxe/std/eval/_std/haxe/io/Bytes.hx (an extern), a byte buffer in the
// runtime (rt_std.c). Members involving Int64 are inline Haxe so the runtime
// never builds Haxe objects.

package haxe.io;

extern class Bytes {
	var length(get, never):Int;
	private function get_length():Int;
	function get(pos:Int):Int;
	function set(pos:Int, v:Int):Void;
	function blit(pos:Int, src:Bytes, srcpos:Int, len:Int):Void;
	function fill(pos:Int, len:Int, value:Int):Void;
	function sub(pos:Int, len:Int):Bytes;
	function compare(other:Bytes):Int;
	function getDouble(pos:Int):Float;
	function getFloat(pos:Int):Float;
	function setDouble(pos:Int, v:Float):Void;
	function setFloat(pos:Int, v:Float):Void;
	function getUInt16(pos:Int):Int;
	function setUInt16(pos:Int, v:Int):Void;
	function getInt32(pos:Int):Int;
	function setInt32(pos:Int, v:Int):Void;
	inline function getInt64(pos:Int):haxe.Int64
		return haxe.Int64.make(getInt32(pos + 4), getInt32(pos));
	inline function setInt64(pos:Int, v:haxe.Int64):Void {
		setInt32(pos, v.low);
		setInt32(pos + 4, v.high);
	}
	function getString(pos:Int, len:Int, ?encoding:Encoding):String;
	inline function readString(pos:Int, len:Int):String
		return getString(pos, len);
	function toString():String;
	function toHex():String;
	inline function getData():BytesData
		return this;
	static function alloc(length:Int):Bytes;
	static function ofString(s:String, ?encoding:Encoding):Bytes;
	static inline function ofData(b:BytesData):Bytes
		return b;
	static function ofHex(s:String):Bytes;
	static inline function fastGet(b:BytesData, pos:Int):Int
		return b[pos];
}
