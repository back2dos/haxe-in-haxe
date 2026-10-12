package hxc;

// DEFLATE (RFC 1951) decompression in C (rt_std.c), for programs that inflate
// whole buffers (the compiler's ZIP reader): haxe.zip.InflateImpl, in Haxe,
// is several times slower.
extern class NativeZip {
	// inflates the raw DEFLATE stream in src[srcPos, srcPos + srcLen) into
	// dst[dstPos, dstPos + dstLen): the number of bytes written, or -1 when the
	// stream is invalid, truncated or does not fit
	static function inflateRaw(src:haxe.io.Bytes, srcPos:Int, srcLen:Int, dst:haxe.io.Bytes, dstPos:Int, dstLen:Int):Int;
}
