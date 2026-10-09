package compiler;

import haxe.io.Bytes;
import haxe.io.Input;
import compiler.io.CompilerIo;

/**
	Port of haxe/src/compiler/pipeThings.ml: IO piping between the compilation
	server and its clients.

	Host differences: Haxe inputs cannot be polled with `Unix.select`, so the
	stdin forwarders below cannot be interrupted while blocked in a read.
	`run_command` polls the server-side stdin when it is a `ForwardedInput`
	(the client stdin forwarded by `Server`); the client's own stdin forwarder
	(`poll`) is left running instead of being joined, and ends with the process.
**/
class PipeThings {
	/** Reads all available data from [channel] in 1024-byte chunks,
		passing each chunk to [f]. Stops on EOF or Unix error. */
	public static function readContent(channel:Input, buf:Bytes, f:String->Void):Void {
		while (true) {
			var i = try channel.readBytes(buf, 0, 1024) catch (_:Dynamic) 0;
			if (i > 0) f(buf.sub(0, i).toString()) else break;
		}
	}

	/** Runs a shell command in server mode, forwarding stdin from the client
		and capturing stdout/stderr through the socket protocol. */
	public static function runCommand(io:CompilerIoData, cmd:String):Int {
		var writeOut = function(s) CompilerIo.writeOut(io, s);
		var writeErr = function(s) CompilerIo.writeErr(io, s);
		var proc = new sys.io.Process(cmd);
		var pout = proc.stdout;
		var pin = proc.stdin;
		var perr = proc.stderr;
		var bout = Bytes.alloc(1024);
		var berr = Bytes.alloc(1024);
		/* Use a flag to signal the stdin-forwarding thread to stop. */
		var stopStdin = false;
		var tin = switch CompilerIo.getStdin(io) {
			case stdinPipe if (Std.isOfType(stdinPipe, ForwardedInput)):
				var stdinPipe:ForwardedInput = cast stdinPipe;
				var done = new sys.thread.Lock();
				sys.thread.Thread.create(function() {
					try {
						while (!stopStdin) {
							var chunk = stdinPipe.poll(0.05);
							if (chunk != null) {
								if (chunk.length == 0) throw new haxe.io.Eof();
								pin.write(chunk);
								pin.flush();
							}
						}
					} catch (_:Dynamic) {}
					try pin.close() catch (_:Dynamic) {}
					done.release();
				});
				done;
			case _:
				try pin.close() catch (_:Dynamic) {}
				null;
		}
		var toutDone = new sys.thread.Lock(), terrDone = new sys.thread.Lock();
		sys.thread.Thread.create(function() {
			readContent(pout, bout, writeOut);
			toutDone.release();
		});
		sys.thread.Thread.create(function() {
			readContent(perr, berr, writeErr);
			terrDone.release();
		});
		/* Join stdout/stderr threads first — they complete when the child closes
			its output fds (typically on exit). Then reap the child process, signal
			the stdin thread to stop, and join it. */
		toutDone.wait();
		terrDone.wait();
		var code = proc.exitCode();
		stopStdin = true;
		if (tin != null) tin.wait();
		proc.close();
		return code;
	}

	public static function ssend(sock:sys.net.Socket, str:Bytes):Void {
		sock.output.writeFullBytes(str, 0, str.length);
		sock.output.flush();
	}

	public static function poll(sock:sys.net.Socket, print:String->Void):Void {
		var responseBuf = new haxe.io.BytesBuffer();
		function lines(s:String):Array<String> {
			var lines = s.split("\n");
			if (lines.length > 0 && lines[lines.length - 1] == "") lines.pop();
			return lines;
		}
		/* Process all complete lines (up to the last newline) in the buffer,
			keeping any partial unflushed line for the next read. */
		function flushCompleteLines() {
			var bytes = responseBuf.getBytes();
			var lastNl = -1;
			for (i in 0...bytes.length) if (bytes.get(i) == "\n".code) lastNl = i;
			responseBuf = new haxe.io.BytesBuffer();
			if (lastNl < 0) {
				responseBuf.add(bytes);
				return;
			}
			var complete = bytes.getString(0, lastNl + 1);
			for (line in lines(complete)) print(line);
			if (lastNl + 1 < bytes.length) responseBuf.addBytes(bytes, lastNl + 1, bytes.length - lastNl - 1);
		}
		/* Forward stdin to the server socket in a background thread. */
		sys.thread.Thread.create(function() {
			var stdinBuf = Bytes.alloc(1024);
			var stdin = Sys.stdin();
			try {
				while (true) {
					var n = try stdin.readBytes(stdinBuf, 0, 1024) catch (_:haxe.io.Eof) 0;
					if (n == 0) {
						try sock.shutdown(false, true) catch (_:Dynamic) {}
						break;
					}
					ssend(sock, stdinBuf.sub(0, n));
				}
			} catch (_:Dynamic) {}
		});
		/* Read server output until the connection closes, printing lines immediately
			as they arrive rather than waiting for the server to disconnect. */
		var sockBuf = Bytes.alloc(1024);
		var sockOpen = true;
		while (sockOpen) {
			var b = try sock.input.readBytes(sockBuf, 0, 1024) catch (_:Dynamic) 0;
			if (b <= 0)
				sockOpen = false
			else {
				responseBuf.addBytes(sockBuf, 0, b);
				flushCompleteLines();
			}
		}
		/* Flush any remaining partial line after the server closes the connection */
		var s = responseBuf.getBytes().toString();
		if (s != "") {
			for (line in lines(s)) print(line);
		}
	}
}

/**
	Server-side stdin of a request: bytes the client sends after its
	null-terminated arguments, fed by a forwarding thread. Upstream uses a Unix
	pipe (`SocketRequest.setup_client_stdin_forward`); here a queue of chunks,
	with an empty chunk marking end of input.
**/
class ForwardedInput extends Input {
	final queue = new sys.thread.Deque<Bytes>();
	var current:Null<Bytes> = null;
	var pos = 0;
	var eof = false;

	public function new() {}

	public function push(chunk:Bytes):Void {
		queue.add(chunk);
	}

	public function finish():Void {
		queue.add(Bytes.alloc(0));
	}

	/** Returns the next chunk, an empty chunk at end of input, or null after [timeout] seconds. **/
	public function poll(timeout:Float):Null<Bytes> {
		if (current != null && pos < current.length) {
			var chunk = current.sub(pos, current.length - pos);
			current = null;
			return chunk;
		}
		if (eof) return Bytes.alloc(0);
		var chunk = queue.pop(false);
		if (chunk == null) {
			Sys.sleep(timeout);
			chunk = queue.pop(false);
		}
		if (chunk != null && chunk.length == 0) eof = true;
		return chunk;
	}

	override public function readByte():Int {
		while (current == null || pos >= current.length) {
			if (eof) throw new haxe.io.Eof();
			current = queue.pop(true);
			pos = 0;
			if (current.length == 0) {
				eof = true;
				current = null;
				throw new haxe.io.Eof();
			}
		}
		return current.get(pos++);
	}

	override public function readBytes(s:Bytes, p:Int, len:Int):Int {
		if (len == 0) return 0;
		var first = readByte();
		s.set(p, first);
		var n = 1;
		while (n < len && current != null && pos < current.length) {
			s.set(p + n, current.get(pos++));
			n++;
		}
		return n;
	}
}
