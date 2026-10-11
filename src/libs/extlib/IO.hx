package libs.extlib;

import haxe.io.Bytes;

// port: the subset of OCaml extlib's IO module (opam extlib 1.8.0, src/IO.ml)
// that swflib, png and genswf read and write with: `IO.input` and `'a IO.output`
// are the records of closures below, and the little-endian/big-endian/bits
// readers and writers keep extlib's checks (64-bit build: read_i32 is read_i31).
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

class Input {
	public var inRead:Void->Int;
	public var inInput:Bytes->Int->Int->Int;
	public var inClose:Void->Void;

	public function new(read, input, close) {
		this.inRead = read;
		this.inInput = input;
		this.inClose = close;
	}
}

class NoMoreInput extends haxe.Exception {
	public function new() super("No_more_input");
}

class InputClosed extends haxe.Exception {
	public function new() super("Input_closed");
}

class Overflow extends haxe.Exception {}
class BitsError extends haxe.Exception {}
class OutputClosed extends haxe.Exception {}

// port: the bits reader state (`input bc`).
class InBits {
	public final ch:Input;
	public var nbits:Int;
	public var bits:Int;

	public function new(ch:Input) {
		this.ch = ch;
		nbits = 0;
		bits = 0;
	}
}

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
	public static function createIn(read:Void->Int, input:Bytes->Int->Int->Int, close:Void->Void):Input return new Input(read, input, close);

	// port: `read` returns the char as its code (0..255).
	public static inline function read(i:Input):Int return i.inRead();

	public static function nread(i:Input, n:Int):Bytes {
		if (n < 0) throw new core.ds.InvalidArgument("IO.nread");
		if (n == 0) return Bytes.alloc(0);
		var s = Bytes.alloc(n);
		var l = n;
		var p = 0;
		try {
			while (l > 0) {
				var r = i.inInput(s, p, l);
				if (r == 0) throw new NoMoreInput();
				p += r;
				l -= r;
			}
			return s;
		} catch (e:NoMoreInput) {
			if (p == 0) throw e;
			return s.sub(0, p);
		}
	}

	// port: OCaml strings are bytes; the port decodes the bytes read (as UTF-8).
	public static function nreadString(i:Input, n:Int):String return nread(i, n).toString();

	public static function input(i:Input, s:Bytes, p:Int, l:Int):Int {
		var sl = s.length;
		if (p + l > sl || p < 0 || l < 0) throw new core.ds.InvalidArgument("IO.input");
		if (l == 0) return 0 else return i.inInput(s, p, l);
	}

	public static function reallyInput(i:Input, s:Bytes, p:Int, l2:Int):Int {
		var sl = s.length;
		if (p + l2 > sl || p < 0 || l2 < 0) throw new core.ds.InvalidArgument("IO.really_input");
		var l = l2;
		while (l > 0) {
			var r = i.inInput(s, p, l);
			if (r == 0) throw new haxe.Exception("Sys_blocked_io");
			p += r;
			l -= r;
		}
		return l2;
	}

	public static function reallyNread(i:Input, n:Int):Bytes {
		if (n < 0) throw new core.ds.InvalidArgument("IO.really_nread");
		if (n == 0) return Bytes.alloc(0);
		var s = Bytes.alloc(n);
		reallyInput(i, s, 0, n);
		return s;
	}

	public static function closeIn(i:Input):Void {
		i.inClose();
		i.inRead = () -> throw new InputClosed();
		i.inInput = (_, _, _) -> throw new InputClosed();
		i.inClose = () -> throw new InputClosed();
	}

	public static function inputBytes(s:Bytes):Input {
		var pos = 0;
		var len = s.length;
		return createIn(() -> {
			if (pos >= len) throw new NoMoreInput();
			var c = s.get(pos);
			pos++;
			c;
		}, (sout, p, l) -> {
			if (pos >= len) throw new NoMoreInput();
			var n = (if (pos + l > len) len - pos else l);
			sout.blit(p, s, pos, n);
			pos += n;
			n;
		}, () -> {});
	}

	public static inline function inputString(s:Bytes):Input return inputBytes(s);

	// port: Stdlib in_channel over a host input; End_of_file is haxe.io.Eof.
	public static function inputChannel(ch:haxe.io.Input):Input {
		return createIn(() -> {
			try ch.readByte() catch (_:haxe.io.Eof) throw new NoMoreInput();
		}, (s, p, l) -> {
			var n = try ch.readBytes(s, p, l) catch (_:haxe.io.Eof) 0;
			if (n == 0) throw new NoMoreInput();
			n;
		}, () -> ch.close());
	}

	public static function posIn(i:Input):{ch:Input, pos:Void->Int} {
		var p = 0;
		var ch = createIn(() -> {
			var c = i.inRead();
			p++;
			c;
		}, (s, sp, l) -> {
			var n = i.inInput(s, sp, l);
			p += n;
			n;
		}, i.inClose);
		return {ch: ch, pos: () -> p};
	}

	public static inline function readByte(i:Input):Int return i.inRead();

	public static function readSignedByte(i:Input):Int {
		var c = i.inRead();
		return if (c & 128 != 0) c - 256 else c;
	}

	// port: read_string returns the bytes up to the NUL, decoded as UTF-8.
	public static function readBytesNul(i:Input):Bytes {
		var b = new haxe.io.BytesBuffer();
		while (true) {
			var c = i.inRead();
			if (c == 0) break;
			b.addByte(c);
		}
		return b.getBytes();
	}

	public static function readString(i:Input):String return readBytesNul(i).toString();

	public static function readUi16(i:Input):Int {
		var ch1 = readByte(i);
		var ch2 = readByte(i);
		return ch1 | (ch2 << 8);
	}

	public static function readI16(i:Input):Int {
		var ch1 = readByte(i);
		var ch2 = readByte(i);
		var n = ch1 | (ch2 << 8);
		return if (ch2 & 128 != 0) n - 65536 else n;
	}

	// port: read_32 ~i31; the sign-extended value fits the port's 32-bit Int.
	static function read32(i31:Bool, ch:Input):Int {
		var ch1 = readByte(ch);
		var ch2 = readByte(ch);
		var ch3 = readByte(ch);
		var ch4 = readByte(ch);
		if (ch4 & 128 != 0) {
			if (i31 && ch4 & 64 == 0) throw new Overflow("read_i31");
		} else {
			if (i31 && ch4 & 64 != 0) throw new Overflow("read_i31");
		}
		return ch1 | (ch2 << 8) | (ch3 << 16) | (ch4 << 24);
	}

	public static function readI31(ch:Input):Int return read32(true, ch);

	public static function readI32AsInt(ch:Input):Int return read32(false, ch);

	public static function readI32(ch:Input):Int return read32(true, ch);

	public static function readRealI32(ch:Input):Int {
		var ch1 = readByte(ch);
		var ch2 = readByte(ch);
		var ch3 = readByte(ch);
		var base = ch1 | (ch2 << 8) | (ch3 << 16);
		var big = readByte(ch) << 24;
		return base | big;
	}

	public static function readDouble(ch:Input):Float {
		var low = readRealI32(ch);
		var high = readRealI32(ch);
		return haxe.io.FPHelper.i64ToDouble(low, high);
	}

	// port: IO.BigEndian.read_i32 (read_i31).
	public static function beReadI32(ch:Input):Int {
		var ch4 = readByte(ch);
		var ch3 = readByte(ch);
		var ch2 = readByte(ch);
		var ch1 = readByte(ch);
		if (ch4 & 128 != 0) {
			if (ch4 & 64 == 0) throw new Overflow("read_i31");
		} else {
			if (ch4 & 64 != 0) throw new Overflow("read_i31");
		}
		return ch1 | (ch2 << 8) | (ch3 << 16) | (ch4 << 24);
	}

	public static function beReadRealI32(ch:Input):Int {
		var big = readByte(ch) << 24;
		var ch3 = readByte(ch);
		var ch2 = readByte(ch);
		var ch1 = readByte(ch);
		var base = ch1 | (ch2 << 8) | (ch3 << 16);
		return base | big;
	}

	public static function inputBits(ch:Input):InBits return new InBits(ch);

	public static function readBits(b:InBits, n:Int):Int {
		if (b.nbits >= n) {
			var c = b.nbits - n;
			// port: (1 lsl n) - 1 for n <= 31 on a 32-bit Int.
			var k = (b.bits >> c) & (n >= 32 ? -1 : (1 << n) - 1);
			b.nbits = c;
			return k;
		} else {
			var k = readByte(b.ch);
			if (b.nbits >= 24) {
				if (n > 31) throw new BitsError("Bits_error");
				var c = 8 + b.nbits - n;
				var d = b.bits & ((1 << b.nbits) - 1);
				var d = (d << (8 - c)) | (k >> c);
				b.bits = k;
				b.nbits = c;
				return d;
			} else {
				b.bits = (b.bits << 8) | k;
				b.nbits = b.nbits + 8;
				return readBits(b, n);
			}
		}
	}

	public static function dropBits(b:InBits):Void {
		b.nbits = 0;
	}

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

	public static function writeI16(ch:Output, n:Int):Void {
		if (n < -0x8000 || n > 0x7FFF) throw new Overflow("write_i16");
		if (n < 0) writeUi16(ch, 65536 + n) else writeUi16(ch, n);
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
