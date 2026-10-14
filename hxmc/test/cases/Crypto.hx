// haxe.crypto: rotations, 16-bit split additions, Int32 arithmetic
class Crypto {
	static function rotl(x:Int, n:Int):Int
		return (x << n) | (x >>> (32 - n));

	static function main() {
		var inputs = ["", "abc", "The quick brown fox jumps over the lazy dog", [for (i in 0...300) String.fromCharCode(32 + i % 90)].join("")];
		for (s in inputs) {
			trace(haxe.crypto.Md5.encode(s));
			trace(haxe.crypto.Sha1.encode(s));
			trace(haxe.crypto.Sha224.encode(s));
			trace(haxe.crypto.Sha256.encode(s));
			trace(haxe.crypto.Crc32.make(haxe.io.Bytes.ofString(s)));
			trace(haxe.crypto.Adler32.make(haxe.io.Bytes.ofString(s)));
		}
		var x = 0x12345678;
		for (n in 1...32)
			x ^= rotl(x, n) + n;
		trace(x);
		var y = 0x9abcdef0;
		trace((y >>> 7) | (y << 25), (y << 3) | (y >>> 29), (y >> 4) | (y << 28));
	}
}
