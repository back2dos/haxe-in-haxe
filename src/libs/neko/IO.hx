package libs.neko;

// port: the ExtLib `IO` output functions (extlib 1.8.0, src/IO.ml, little-endian)
// used by the Neko writers, over a `haxe.io.Output`. Strings are byte strings
// (see Nast): each character is written as one byte.
class Overflow extends haxe.Exception {
	public function new(what:String) super("IO.Overflow(\"" + what + "\")");
}

class IO {
	public static inline function writeByte(o:haxe.io.Output, n:Int):Void o.writeByte(n & 0xFF);

	public static function nwriteString(o:haxe.io.Output, s:String):Void for (i in 0...s.length) o.writeByte(StringTools.fastCodeAt(s, i) & 0xFF);

	public static function writeString(o:haxe.io.Output, s:String):Void {
		nwriteString(o, s);
		o.writeByte(0);
	}

	public static function writeUi16(o:haxe.io.Output, n:Int):Void {
		if (n < 0 || n > 0xFFFF) throw new Overflow("write_ui16");
		writeByte(o, n);
		writeByte(o, n >>> 8);
	}

	// port: OCaml ints are 63 bits; the port's values that reach here are already 32-bit,
	// so the write_i32 range check cannot fail.
	public static function writeI32(o:haxe.io.Output, n:Int):Void {
		writeByte(o, n);
		writeByte(o, n >>> 8);
		writeByte(o, n >>> 16);
		writeByte(o, n >>> 24);
	}

	public static function writeRealI32(o:haxe.io.Output, n:Int):Void {
		writeByte(o, n);
		writeByte(o, n >>> 8);
		writeByte(o, n >>> 16);
		writeByte(o, n >>> 24);
	}
}
