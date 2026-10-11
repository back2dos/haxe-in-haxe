package libs.extc;

import haxe.io.Bytes;
import libs.extlib.IO;
import libs.extlib.IO.Output;

// port: the deflate half of haxe/libs/extc/extc.ml (zlib_deflate_init, zlib_op,
// zip, output_zip), over the zlib translation in Zlib.hx. Inflate (unzip,
// input_zip) is not ported: nothing on the HXB/SWF output path reads
// compressed data.
typedef ZResult = {
	var z_finish:Bool;
	var z_read:Int;
	var z_wrote:Int;
}

class Extc {
	// port: zlib_deflate_init2 of extc_stubs.c.
	public static function zlibDeflateInit2(level:Int, windowBits:Int):Zlib return Zlib.deflateInit2(level, windowBits);

	// port: zlib_deflate of extc_stubs.c, with its error messages.
	public static function zlibDeflate(z:Zlib, src:Bytes, spos:Int, slen:Int, dst:Bytes, dpos:Int, dlen:Int, flush:Int):ZResult {
		var r = z.deflate(src, spos, slen, dst, dpos, dlen, flush);
		if (r == Zlib.Z_OK || r == Zlib.Z_STREAM_END) {
			return {
				z_finish: r == Zlib.Z_STREAM_END,
				z_read: slen - z.getAvailIn(),
				z_wrote: dlen - z.getAvailOut()
			};
		}
		throw new core.ds.Failure(switch r {
			case Zlib.Z_STREAM_ERROR: "Error in `zlib_deflate` (extc_stubs.c): call to `deflate` failed: Z_STREAM_ERROR";
			case Zlib.Z_BUF_ERROR: "Error in `zlib_deflate` (extc_stubs.c): call to `deflate` failed: Z_BUF_ERROR";
			case _: "Error in `zlib_deflate` (extc_stubs.c): unknown return code from `deflate`";
		});
	}

	public static function zlibDeflateEnd(z:Zlib):Void {
		if (z.deflateEnd() != 0) throw new core.ds.Failure("zlib_deflate_end");
	}

	/* support for backward compatibility */
	public static function zlibDeflateInit(lvl:Int):Zlib return zlibDeflateInit2(lvl, 15);

	// port: zlib_op specialised to deflate.
	static function zlibOp(z:Zlib, str:Bytes):Bytes {
		var bufsize = 1 << 14;
		var tmp = Bytes.alloc(bufsize);
		var total = 0;
		var acc = [];
		var pos = 0;
		var len = str.length;
		while (true) {
			var r = zlibDeflate(z, str, pos, len, tmp, 0, bufsize, if (len == 0) Zlib.Z_FINISH else Zlib.Z_SYNC_FLUSH);
			total += r.z_wrote;
			acc.push(tmp.sub(0, r.z_wrote));
			if (r.z_finish) break;
			pos += r.z_read;
			len -= r.z_read;
		}
		var big = Bytes.alloc(total);
		var p = 0;
		for (s in acc) {
			big.blit(p, s, 0, s.length);
			p += s.length;
		}
		return big;
	}

	public static function zip(str:Bytes):Bytes {
		var z = zlibDeflateInit(9);
		var s = zlibOp(z, str);
		zlibDeflateEnd(z);
		return s;
	}

	public static function outputZip(?bufsize:Int = 65536, ?level:Int = 9, ch:Output):Output {
		var z = zlibDeflateInit(level);
		var out = Bytes.alloc(bufsize);
		var tmp_out = Bytes.alloc(bufsize);
		var p = 0;
		function flush(finish:Bool):Void {
			var r = zlibDeflate(z, out, 0, p, tmp_out, 0, bufsize, if (finish) Zlib.Z_FINISH else Zlib.Z_SYNC_FLUSH);
			IO.reallyOutput(ch, tmp_out, 0, r.z_wrote);
			var remain = p - r.z_read;
			// port: an overlapping move (Bytes.blit upstream), copied forwards.
			for (i in 0...remain) out.set(i, out.get(r.z_read + i));
			p = remain;
			if (finish && !r.z_finish) flush(true);
		}
		function write(c:Int):Void {
			if (p == bufsize) flush(false);
			out.set(p, c);
			p++;
		}
		function output(str:Bytes, pos:Int, len:Int):Int {
			var b = bufsize - p;
			if (len <= b) {
				out.blit(p, str, pos, len);
				p = p + len;
				return len;
			} else {
				out.blit(p, str, pos, b);
				p = p + b;
				flush(false);
				return b + output(str, pos + b, len - b);
			}
		}
		function close():Dynamic {
			flush(true);
			zlibDeflateEnd(z);
			return null;
		}
		return IO.createOut(write, output, () -> {
			flush(false);
			ch.outFlush();
		}, close);
	}
}
