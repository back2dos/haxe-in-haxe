package hxmc;

// DEFLATE (RFC 1951) decompression and CRC-32 over raw memory (hxmc.rt.Zip),
// for programs that inflate whole buffers (the compiler's ZIP reader):
// haxe.zip.InflateImpl and haxe.crypto.Crc32 are several times slower.
extern class NativeZip {
	// inflates the raw DEFLATE stream in src[srcPos, srcPos + srcLen) into
	// dst[dstPos, dstPos + dstLen): the number of bytes written, or -1 when the
	// stream is invalid, truncated or does not fit
	static function inflateRaw(src:haxe.io.Bytes, srcPos:Int, srcLen:Int, dst:haxe.io.Bytes, dstPos:Int, dstLen:Int):Int;
	// the CRC-32 (ISO-HDLC, as zlib's crc32) of b[pos, pos + len)
	static function crc32(b:haxe.io.Bytes, pos:Int, len:Int):Int;
}
