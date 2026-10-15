// hxmc: haxe/upstream/std/eval/_std/haxe/io/BytesBuffer.hx (an extern), a growable byte
// buffer in the runtime (rt_std.c)

package haxe.io;

extern class BytesBuffer {
	var length(get, never):Int;
	function new():Void;
	private function get_length():Int;
	function addByte(byte:Int):Void;
	function add(src:Bytes):Void;
	function addString(v:String, ?encoding:Encoding):Void;
	function addInt32(v:Int):Void;
	inline function addInt64(v:haxe.Int64):Void {
		addInt32(v.low);
		addInt32(v.high);
	}
	function addFloat(v:Float):Void;
	function addDouble(v:Float):Void;
	function addBytes(src:Bytes, pos:Int, len:Int):Void;
	function getBytes():Bytes;
}
