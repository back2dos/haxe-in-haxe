package libs.extlib;

import haxe.io.Bytes;

// port: the subset of OCaml extlib's IO module (opam extlib, src/IO.ml) that
// swflib and genswf write with: `'a IO.output` is the record of closures
// below, and the little-endian/bits writers keep extlib's checks.
class Output {
	public var outWrite:Int->Void;
	public var outOutput:Bytes->Int->Int->Int;
	public var outClose:Void->Dynamic;
	public var outFlush:Void->Void;

	public function new(write, output, close, flush) {
		this.outWrite = write;
		this.outOutput = output;
		this.outClose = close;
		this.outFlush = flush;
	}
}

class Overflow extends haxe.Exception {}
class BitsError extends haxe.Exception {}
class OutputClosed extends haxe.Exception {}

// port: the bits writer state (`'a bc`).
class OutBits {
	public final ch:Output;
	public var nbits:Int;
	public var bits:Int;

	public function new(ch:Output) {
		this.ch = ch;
		nbits = 0;
		bits = 0;
	}
}

class IO {
	public static function createOut(write:Int->Void, output:Bytes->Int->Int->Int, flush:Void->Void, close:Void->Dynamic):Output
		return new Output(write, output, close, flush);

	public static inline function write(o:Output, c:Int):Void o.outWrite(c);

	public static function nwrite(o:Output, s:Bytes):Void {
		var p = 0;
		var l = s.length;
		while (l > 0) {
			var w = o.outOutput(s, p, l);
			if (w == 0) throw new haxe.Exception("Sys_blocked_io");
			p += w;
			l -= w;
		}
	}

	public static function reallyOutput(o:Output, s:Bytes, p:Int, l2:Int):Int {
		var sl = s.length;
		if (p + l2 > sl || p < 0 || l2 < 0) throw new core.ds.InvalidArgument("IO.really_output");
		var l = l2;
		while (l > 0) {
			var w = o.outOutput(s, p, l);
			if (w == 0) throw new haxe.Exception("Sys_blocked_io");
			p += w;
			l -= w;
		}
		return l2;
	}

	// port: OCaml strings are bytes; the port's strings are written as UTF-8.
	public static function nwriteString(o:Output, s:String):Void nwrite(o, Bytes.ofString(s));

	public static function closeOut(o:Output):Dynamic {
		var r = o.outClose();
		o.outWrite = _ -> throw new OutputClosed("Output_closed");
		o.outOutput = (_, _, _) -> throw new OutputClosed("Output_closed");
		o.outClose = () -> throw new OutputClosed("Output_closed");
		o.outFlush = () -> throw new OutputClosed("Output_closed");
		return r;
	}

	// port: output_strings returns the list of written strings on close; the
	// port keeps them in one buffer (Sys.max_string_length is not reached).
	public static function outputStrings():Output {
		var b = new haxe.io.BytesBuffer();
		return createOut(c -> b.addByte(c & 0xFF), (s, p, l) -> {
			b.addBytes(s, p, l);
			l;
		}, () -> {}, () -> b.getBytes());
	}

	public static function outputBytes(b:haxe.io.BytesBuffer):Output {
		return createOut(c -> b.addByte(c & 0xFF), (s, p, l) -> {
			b.addBytes(s, p, l);
			l;
		}, () -> {}, () -> null);
	}

	public static function outputChannel(f:haxe.io.Output):Output {
		return createOut(c -> f.writeByte(c & 0xFF), (s, p, l) -> {
			f.writeBytes(s, p, l);
		}, () -> f.flush(), () -> {
			f.close();
			null;
		});
	}

	public static inline function writeByte(o:Output, n:Int):Void {
		// doesn't test bounds of n in order to keep semantics of Stdlib.output_byte
		o.outWrite(n & 0xFF);
	}

	public static function writeString(o:Output, s:String):Void {
		nwriteString(o, s);
		write(o, 0);
	}

	public static function writeUi16(ch:Output, n:Int):Void {
		if (n < 0 || n > 0xFFFF) throw new Overflow("write_ui16");
		writeByte(ch, n);
		writeByte(ch, n >>> 8);
	}

	public static function write32(ch:Output, n:Int):Void {
		writeByte(ch, n);
		writeByte(ch, n >>> 8);
		writeByte(ch, n >>> 16);
		writeByte(ch, n >> 24);
	}

	// port: the 64-bit range check of write_i32 cannot fail on a 32-bit Int.
	public static function writeI32(ch:Output, n:Int):Void write32(ch, n);

	public static function writeRealI32(ch:Output, n:Int):Void {
		writeByte(ch, n);
		writeByte(ch, n >>> 8);
		writeByte(ch, n >>> 16);
		writeByte(ch, n >>> 24);
	}

	public static function writeDouble(ch:Output, f:Float):Void {
		var i = haxe.io.FPHelper.doubleToI64(f);
		writeRealI32(ch, i.low);
		writeRealI32(ch, i.high);
	}

	public static function outputBits(ch:Output):OutBits return new OutBits(ch);

	public static function writeBits(b:OutBits, nbits:Int, x:Int):Void {
		var n = nbits;
		if (n + b.nbits >= 32) {
			if (n > 31) throw new BitsError("Bits_error");
			var n2 = 32 - b.nbits - 1;
			var n3 = n - n2;
			writeBits(b, n2, x >> n3);
			writeBits(b, n3, x & ((1 << n3) - 1));
		} else {
			if (n < 0) throw new BitsError("Bits_error");
			if ((x < 0 || x > (1 << n) - 1) && n != 31) throw new BitsError("Bits_error");
			b.bits = (b.bits << n) | x;
			b.nbits = b.nbits + n;
			while (b.nbits >= 8) {
				b.nbits = b.nbits - 8;
				writeByte(b.ch, b.bits >> b.nbits);
			}
		}
	}

	public static function flushBits(b:OutBits):Void {
		if (b.nbits > 0) writeBits(b, 8 - b.nbits, 0);
	}
}
