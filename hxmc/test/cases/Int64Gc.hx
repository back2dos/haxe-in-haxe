// haxe.Int64 under collections: Int64 values in arrays, Vectors, fields,
// Null<Int64>, Dynamic boxes, closures, maps and anonymous structures kept
// across minor collections, and SHA-512 (Vector<Int64> state, blocks padded
// with Bytes.alloc's zeros, as the crypto library's haxe.crypto.Sha512
// does) with known digests, also after the nursery has been reused: hxmc's
// Bytes.alloc once left the bytes of dead objects in a reused nursery
import haxe.Int64;
import haxe.ds.Vector;
import haxe.io.Bytes;

class Acc {
	public var lo:Int64;
	public var hi:Null<Int64>;
	public var any:Dynamic;

	public function new(v:Int64) {
		lo = v;
		hi = v * 3;
		any = v + 1;
	}
}

class Sha512 {
	static var K:Vector<Int64> = Vector.fromArrayCopy([
		Int64.make(0x428A2F98, 0xD728AE22), Int64.make(0x71374491, 0x23EF65CD), Int64.make(0xB5C0FBCF, 0xEC4D3B2F), Int64.make(0xE9B5DBA5, 0x8189DBBC),
		Int64.make(0x3956C25B, 0xF348B538), Int64.make(0x59F111F1, 0xB605D019), Int64.make(0x923F82A4, 0xAF194F9B), Int64.make(0xAB1C5ED5, 0xDA6D8118),
		Int64.make(0xD807AA98, 0xA3030242), Int64.make(0x12835B01, 0x45706FBE), Int64.make(0x243185BE, 0x4EE4B28C), Int64.make(0x550C7DC3, 0xD5FFB4E2),
		Int64.make(0x72BE5D74, 0xF27B896F), Int64.make(0x80DEB1FE, 0x3B1696B1), Int64.make(0x9BDC06A7, 0x25C71235), Int64.make(0xC19BF174, 0xCF692694),
		Int64.make(0xE49B69C1, 0x9EF14AD2), Int64.make(0xEFBE4786, 0x384F25E3), Int64.make(0x0FC19DC6, 0x8B8CD5B5), Int64.make(0x240CA1CC, 0x77AC9C65),
		Int64.make(0x2DE92C6F, 0x592B0275), Int64.make(0x4A7484AA, 0x6EA6E483), Int64.make(0x5CB0A9DC, 0xBD41FBD4), Int64.make(0x76F988DA, 0x831153B5),
		Int64.make(0x983E5152, 0xEE66DFAB), Int64.make(0xA831C66D, 0x2DB43210), Int64.make(0xB00327C8, 0x98FB213F), Int64.make(0xBF597FC7, 0xBEEF0EE4),
		Int64.make(0xC6E00BF3, 0x3DA88FC2), Int64.make(0xD5A79147, 0x930AA725), Int64.make(0x06CA6351, 0xE003826F), Int64.make(0x14292967, 0x0A0E6E70),
		Int64.make(0x27B70A85, 0x46D22FFC), Int64.make(0x2E1B2138, 0x5C26C926), Int64.make(0x4D2C6DFC, 0x5AC42AED), Int64.make(0x53380D13, 0x9D95B3DF),
		Int64.make(0x650A7354, 0x8BAF63DE), Int64.make(0x766A0ABB, 0x3C77B2A8), Int64.make(0x81C2C92E, 0x47EDAEE6), Int64.make(0x92722C85, 0x1482353B),
		Int64.make(0xA2BFE8A1, 0x4CF10364), Int64.make(0xA81A664B, 0xBC423001), Int64.make(0xC24B8B70, 0xD0F89791), Int64.make(0xC76C51A3, 0x0654BE30),
		Int64.make(0xD192E819, 0xD6EF5218), Int64.make(0xD6990624, 0x5565A910), Int64.make(0xF40E3585, 0x5771202A), Int64.make(0x106AA070, 0x32BBD1B8),
		Int64.make(0x19A4C116, 0xB8D2D0C8), Int64.make(0x1E376C08, 0x5141AB53), Int64.make(0x2748774C, 0xDF8EEB99), Int64.make(0x34B0BCB5, 0xE19B48A8),
		Int64.make(0x391C0CB3, 0xC5C95A63), Int64.make(0x4ED8AA4A, 0xE3418ACB), Int64.make(0x5B9CCA4F, 0x7763E373), Int64.make(0x682E6FF3, 0xD6B2B8A3),
		Int64.make(0x748F82EE, 0x5DEFB2FC), Int64.make(0x78A5636F, 0x43172F60), Int64.make(0x84C87814, 0xA1F0AB72), Int64.make(0x8CC70208, 0x1A6439EC),
		Int64.make(0x90BEFFFA, 0x23631E28), Int64.make(0xA4506CEB, 0xDE82BDE9), Int64.make(0xBEF9A3F7, 0xB2C67915), Int64.make(0xC67178F2, 0xE372532B),
		Int64.make(0xCA273ECE, 0xEA26619C), Int64.make(0xD186B8C7, 0x21C0C207), Int64.make(0xEADA7DD6, 0xCDE0EB1E), Int64.make(0xF57D4F7F, 0xEE6ED178),
		Int64.make(0x06F067AA, 0x72176FBA), Int64.make(0x0A637DC5, 0xA2C898A6), Int64.make(0x113F9804, 0xBEF90DAE), Int64.make(0x1B710B35, 0x131C471B),
		Int64.make(0x28DB77F5, 0x23047D84), Int64.make(0x32CAAB7B, 0x40C72493), Int64.make(0x3C9EBE0A, 0x15C9BEBC), Int64.make(0x431D67C4, 0x9C100D4C),
		Int64.make(0x4CC5D4BE, 0xCB3E42B6), Int64.make(0x597F299C, 0xFC657E2A), Int64.make(0x5FCB6FAB, 0x3AD6FAEC), Int64.make(0x6C44198C, 0x4A475817)
	]);

	static inline function ror(x:Int64, n:Int):Int64
		return (x >>> n) | (x << (64 - n));

	public static function encode(s:String):String {
		var msg = Bytes.ofString(s);
		var state:Vector<Int64> = Vector.fromArrayCopy([
			Int64.make(0x6A09E667, 0xF3BCC908), Int64.make(0xBB67AE85, 0x84CAA73B), Int64.make(0x3C6EF372, 0xFE94F82B), Int64.make(0xA54FF53A, 0x5F1D36F1),
			Int64.make(0x510E527F, 0xADE682D1), Int64.make(0x9B05688C, 0x2B3E6C1F), Int64.make(0x1F83D9AB, 0xFB41BD6B), Int64.make(0x5BE0CD19, 0x137E2179)
		]);
		var off = Math.floor(msg.length / 128) * 128;
		compress(state, msg, off);
		// padding: what Bytes.alloc returns is relied on to be zero
		var block = Bytes.alloc(128);
		block.blit(0, msg, off, msg.length - off);
		off = msg.length % 128;
		block.set(off, 0x80);
		off++;
		if (off + 16 > 128) {
			compress(state, block, 128);
			block.fill(0, 128, 0);
		}
		var len = msg.length << 3;
		for (i in 0...4)
			block.set(127 - i, len >>> (i * 8));
		compress(state, block, 128);
		var out = Bytes.alloc(64);
		for (i in 0...64)
			out.set(i, (state[i >>> 3] >>> ((7 - i % 8) * 8)).low);
		return out.toHex();
	}

	static function compress(state:Vector<Int64>, blocks:Bytes, len:Int) {
		var i = 0;
		while (i < len) {
			var w:Vector<Int64> = Vector.fromArrayCopy([for (k in 0...80) Int64.make(0, 0)]);
			for (j in 0...128)
				w[j >>> 3] |= Int64.ofInt(blocks.get(i + j) & 0xFF) << ((7 - j % 8) * 8);
			for (j in 16...80)
				w[j] = w[j - 16] + w[j - 7] + (ror(w[j - 15], 1) ^ ror(w[j - 15], 8) ^ (w[j - 15] >>> 7))
					+ (ror(w[j - 2], 19) ^ ror(w[j - 2], 61) ^ (w[j - 2] >>> 6));
			var a = state[0], b = state[1], c = state[2], d = state[3];
			var e = state[4], f = state[5], g = state[6], h = state[7];
			for (j in 0...80) {
				var t1 = h + (ror(e, 14) ^ ror(e, 18) ^ ror(e, 41)) + (g ^ (e & (f ^ g))) + K[j] + w[j];
				var t2 = (ror(a, 28) ^ ror(a, 34) ^ ror(a, 39)) + ((a & (b | c)) | (b & c));
				h = g;
				g = f;
				f = e;
				e = d + t1;
				d = c;
				c = b;
				b = a;
				a = t1 + t2;
			}
			state[0] += a;
			state[1] += b;
			state[2] += c;
			state[3] += d;
			state[4] += e;
			state[5] += f;
			state[6] += g;
			state[7] += h;
			i += 128;
		}
	}
}

class Int64Gc {
	static var sink:Array<Dynamic> = [];
	static var globalV:Vector<Int64> = new Vector(64);

	// garbage that leaves non-zero bytes and pointers all over the nursery
	static function churn(n:Int) {
		var a:Array<Dynamic> = [];
		for (i in 0...n) {
			var b = Bytes.alloc(24 + i % 40);
			b.fill(0, b.length, 0xA5);
			a.push(b);
			a.push({k: i, s: "s" + i, v: Int64.make(i, -i)});
		}
		sink = a;
	}

	static function hex(x:Int64):String
		return StringTools.hex(x.high, 8) + StringTools.hex(x.low, 8);

	static function main() {
		// digests before the first collection and after many
		var vectors = [
			"",
			"abc",
			"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
			"The quick brown fox jumps over the lazy dog"
		];
		var first = [for (v in vectors) Sha512.encode(v)];
		for (d in first)
			Sys.println(d);
		var chain = "";
		for (round in 0...40) {
			churn(300);
			chain = Sha512.encode(chain + round);
			for (i in 0...vectors.length)
				if (Sha512.encode(vectors[i]) != first[i])
					Sys.println("digest " + i + " changed in round " + round);
		}
		Sys.println("chain " + chain);

		// Bytes.alloc after the nursery was reused
		var nonzero = 0;
		for (round in 0...50) {
			churn(100);
			for (n in [1, 7, 8, 15, 16, 100, 128, 1000]) {
				var b = Bytes.alloc(n);
				for (i in 0...n)
					if (b.get(i) != 0) nonzero++;
			}
		}
		Sys.println("non-zero bytes from Bytes.alloc: " + nonzero);

		// Int64 values held in every kind of place across collections
		var arr:Array<Int64> = [];
		var vec = new Vector<Int64>(100);
		var nul:Array<Null<Int64>> = [];
		var dyn:Array<Dynamic> = [];
		var objs:Array<Acc> = [];
		var map = new Map<Int, Int64>();
		var anons:Array<{x:Int64, s:String}> = [];
		var clos:Array<() -> Int64> = [];
		for (i in 0...100) {
			var v = Int64.make(i * 0x01010101, 0x9E3779B9 ^ i) * Int64.make(0, 0x7F4A7C15 + i);
			arr.push(v);
			vec[i] = v ^ 0x5555;
			nul.push(i % 3 == 0 ? null : v + 7);
			dyn.push(v - 1);
			objs.push(new Acc(v));
			map.set(i, v << 3);
			anons.push({x: v >>> 5, s: "a" + i});
			var captured = v;
			clos.push(() -> captured + i);
			globalV[i % 64] = v;
			if (i % 10 == 0) churn(200);
		}
		churn(500);
		var sum = Int64.make(0, 0);
		for (i in 0...100) {
			var n = nul[i];
			var d:Int64 = dyn[i];
			var o = objs[i];
			var oh:Int64 = o.hi;
			var oa:Int64 = o.any;
			sum = sum * 31 + arr[i];
			sum = sum * 31 + vec[i];
			sum = sum * 31 + (n == null ? Int64.make(0, 1) : (n : Int64));
			sum = sum * 31 + d;
			sum = sum * 31 + o.lo + oh + oa;
			sum = sum * 31 + map.get(i);
			sum = sum * 31 + anons[i].x;
			sum = sum * 31 + clos[i]();
			sum = sum * 31 + globalV[i % 64];
		}
		Sys.println("sum " + hex(sum) + " " + Int64.toStr(sum));
	}
}
