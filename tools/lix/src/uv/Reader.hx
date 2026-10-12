package uv;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import uv.Uv;

/**
	Reads a libuv stream from coroutines: data is buffered as it arrives and
	`read`/`readUntil` suspend until enough of it is there.
**/
class Reader {
	public final stream:Stream;

	var buf = Bytes.alloc(0);
	var eof = false;
	var error:Null<UvError>;
	var waiting:Null<() -> Void>;

	public function new(stream:Stream) {
		this.stream = stream;
		stream.readStart(onData, e -> {
			error = e;
			wake();
		});
	}

	function onData(b:Null<Bytes>) {
		if (b == null)
			eof = true;
		else {
			var nu = Bytes.alloc(buf.length + b.length);
			nu.blit(0, buf, 0, buf.length);
			nu.blit(buf.length, b, 0, b.length);
			buf = nu;
		}
		wake();
	}

	function wake() {
		var w = waiting;
		waiting = null;
		if (w != null)
			w();
	}

	function take(n:Int, skip:Int):Bytes {
		var ret = buf.sub(0, n);
		buf = buf.sub(n + skip, buf.length - n - skip);
		return ret;
	}

	// waits for more data; throws at the end of the stream
	@:coroutine function more() {
		if (error != null)
			throw error;
		if (eof)
			throw new haxe.io.Eof();
		uv.Coro.await(done -> waiting = () -> done(null, null));
	}

	/** Exactly `n` bytes. **/
	@:coroutine public function read(n:Int):Bytes {
		while (buf.length < n)
			more();
		return take(n, 0);
	}

	/** The bytes up to the next `byte` (consumed, not returned). **/
	@:coroutine public function readUntil(byte:Int):Bytes {
		var from = 0;
		while (true) {
			for (i in from...buf.length)
				if (buf.get(i) == byte)
					return take(i, 1);
			from = buf.length;
			more();
		}
	}

	/** A 32-bit little-endian length followed by that many bytes. **/
	@:coroutine public function readFrame():Bytes {
		var len = read(4).getInt32(0);
		return read(len);
	}

	/** Bytes read but not consumed yet. **/
	public function rest():Bytes
		return take(buf.length, 0);
}
