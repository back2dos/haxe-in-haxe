/*
 *  Extc : C common OCaml bindings
 *  Copyright (c)2004 Nicolas Cannasse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
 */

package libs.extc;

import haxe.io.Bytes;
import libs.extlib.IO;
import libs.extlib.IO.Output;
import libs.extlib.IO.Input;
import libs.extlib.IO.NoMoreInput;

// port: haxe/libs/extc/extc.ml. Deflate is the zlib translation in Zlib.hx; inflate
// is haxe.zip.InflateImpl (see Inflater).
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

	public static function zlibDeflateBound(z:Zlib, len:Int):Int return z.deflateBound(len);

	public static function zlibInflateInit2(windowBits:Int):Inflater return new Inflater(windowBits);

	public static function zlibInflateInit():Inflater return zlibInflateInit2(15);

	public static function zlibInflate(z:Inflater, src:Bytes, spos:Int, slen:Int, dst:Bytes, dpos:Int, dlen:Int, flush:Int):ZResult {
		return z.inflate(src, spos, slen, dst, dpos, dlen);
	}

	public static function zlibInflateEnd(z:Inflater):Void z.end();

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

	// port: an extlib IO.input seen as a haxe.io.Input, for InflateImpl.
	static function hostInput(ch:Input):haxe.io.Input return new ExtcHostInput(ch);

	static function inflater(i:haxe.io.Input):haxe.zip.InflateImpl {
		return try new haxe.zip.InflateImpl(i, true, true) catch (_:Dynamic) throw new core.ds.Failure("zlib_inflate");
	}

	public static function unzip(str:Bytes):Bytes {
		var z = inflater(new haxe.io.BytesInput(str));
		var buf = new haxe.io.BytesBuffer();
		var tmp = Bytes.alloc(1 << 14);
		try {
			while (true) {
				var n = z.readBytes(tmp, 0, tmp.length);
				buf.addBytes(tmp, 0, n);
				if (n < tmp.length) break;
			}
		} catch (e:core.ds.Failure) {
			throw e;
		} catch (_:Dynamic) {
			throw new core.ds.Failure("zlib_inflate");
		}
		return buf.getBytes();
	}

	// port: input_zip inflates lazily from `ch` like upstream's 64KB refills.
	public static function inputZip(?bufsize:Int = 65536, ch:Input):Input {
		var z:Null<haxe.zip.InflateImpl> = null;
		function get():haxe.zip.InflateImpl {
			if (z == null) z = inflater(hostInput(ch));
			return z;
		}
		function input(s:Bytes, p:Int, l:Int):Int {
			var n = try get().readBytes(s, p, l) catch (e:core.ds.Failure) throw e catch (e:NoMoreInput) throw e catch (_:Dynamic) throw new core.ds.Failure("zlib_inflate");
			if (n == 0) throw new NoMoreInput();
			return n;
		}
		var one = Bytes.alloc(1);
		function read():Int {
			input(one, 0, 1);
			return one.get(0);
		}
		return IO.createIn(read, input, () -> {});
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

private class ExtcHostInput extends haxe.io.Input {
	final ch:Input;

	public function new(ch:Input) {
		this.ch = ch;
	}

	override public function readByte():Int {
		return try IO.read(ch) catch (_:NoMoreInput) throw new haxe.io.Eof();
	}

	override public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		return try IO.input(ch, s, pos, len) catch (_:NoMoreInput) throw new haxe.io.Eof();
	}
}

// port: a zlib inflate stream over haxe.zip.InflateImpl, which reads a whole stream
// from a haxe.io.Input and cannot be suspended. The input is buffered until it
// holds the complete stream, which is then inflated at once and its output
// handed out as `dst` allows: zlib writes partial output for a partial stream,
// this writes none until the stream is complete. The flush mode makes no
// difference to the output. The gzip wrapper (windowBits > 15) is not supported.
class Inflater {
	final header:Bool;
	var input:haxe.io.BytesBuffer = new haxe.io.BytesBuffer();
	var output:Null<Bytes> = null;
	var outPos = 0;

	public function new(windowBits:Int) {
		if (windowBits > 15 || windowBits < -15 || (windowBits > -8 && windowBits < 8 && windowBits != 0))
			throw new core.ds.Failure("zlib_inflate_init");
		header = windowBits >= 0;
	}

	public function inflate(src:Bytes, spos:Int, slen:Int, dst:Bytes, dpos:Int, dlen:Int):ZResult {
		var read = 0;
		if (output == null) {
			input.addBytes(src, spos, slen);
			read = slen;
			var data = input.getBytes();
			input = new haxe.io.BytesBuffer();
			input.add(data);
			var bi = new haxe.io.BytesInput(data);
			var out = new haxe.io.BytesBuffer();
			try {
				var z = new haxe.zip.InflateImpl(bi, header, header);
				// port: InflateImpl's window overflows when a stored block is read more than
				// 32KB at a time
				var tmp = Bytes.alloc(1 << 15);
				while (true) {
					var n = z.readBytes(tmp, 0, tmp.length);
					out.addBytes(tmp, 0, n);
					if (n < tmp.length) break;
				}
			} catch (_:haxe.io.Eof) {
				if (slen == 0) throw new core.ds.Failure("zlib_inflate");
				return {z_finish: false, z_read: read, z_wrote: 0};
			} catch (_:Dynamic) {
				throw new core.ds.Failure("zlib_inflate");
			}
			// bytes after the end of the stream are not consumed
			var unused = data.length - bi.position;
			read -= unused < read ? unused : read;
			input = null;
			output = out.getBytes();
		}
		var n = output.length - outPos;
		if (n > dlen) n = dlen;
		dst.blit(dpos, output, outPos, n);
		outPos += n;
		return {z_finish: outPos == output.length, z_read: read, z_wrote: n};
	}

	public function end():Void {
		input = null;
		output = null;
	}
}
