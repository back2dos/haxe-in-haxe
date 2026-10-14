package hxmc;

import hxmc.rt.PosixNet;
import hxmc.rt.WinNet;
import hxmc.unsafe.Mem;

// BSD sockets behind the Eval natives of `eval.vm.NativeSocket` and
// `sys.net.Host` (src/macros/eval/EvalStdLibB.hx StdSocket, EvalStdLibA.hx
// StdHost), standing for OCaml's Unix module: POSIX (hxmc.rt.PosixNet) or
// Winsock (hxmc.rt.WinNet), chosen by the target. Sockets are file
// descriptors. Functions returning Int give -1 on failure with the C errno in
// `errno()`; `strerror` is OCaml's `Unix.error_message`.
class NativeNet {
	public static inline function errno():Int
		return Mem.os() == 2 ? WinNet.getErrno() : PosixNet.getErrno();

	public static inline function strerror(err:Int):String
		return Mem.os() == 2 ? WinNet.strerror(err) : PosixNet.strerror(err);

	// PF_INET, SOCK_STREAM
	public static inline function socket():Int
		return Mem.os() == 2 ? WinNet.socket() : PosixNet.socket();

	public static inline function close(fd:Int):Int
		return Mem.os() == 2 ? WinNet.close(fd) : PosixNet.close(fd);

	public static inline function accept(fd:Int):Int
		return Mem.os() == 2 ? WinNet.accept(fd) : PosixNet.accept(fd);

	// ip: host-order IPv4
	public static inline function bind(fd:Int, ip:Int, port:Int):Int
		return Mem.os() == 2 ? WinNet.bind(fd, ip, port) : PosixNet.bind(fd, ip, port);

	public static inline function connect(fd:Int, ip:Int, port:Int):Int
		return Mem.os() == 2 ? WinNet.connect(fd, ip, port) : PosixNet.connect(fd, ip, port);

	public static inline function listen(fd:Int, backlog:Int):Int
		return Mem.os() == 2 ? WinNet.listen(fd, backlog) : PosixNet.listen(fd, backlog);

	// getsockname (peer false) or getpeername: [ip, port], null on failure;
	// [0, -1] when the address is not ADDR_INET
	public static inline function sockName(fd:Int, peer:Bool):Null<Array<Int>>
		return Mem.os() == 2 ? WinNet.sockName(fd, peer) : PosixNet.sockName(fd, peer);

	public static inline function recv(fd:Int, b:haxe.io.Bytes, pos:Int, len:Int):Int
		return Mem.os() == 2 ? WinNet.recv(fd, b, pos, len) : PosixNet.recv(fd, b, pos, len);

	public static inline function send(fd:Int, b:haxe.io.Bytes, pos:Int, len:Int):Int
		return Mem.os() == 2 ? WinNet.send(fd, b, pos, len) : PosixNet.send(fd, b, pos, len);

	// Unix.select: sets the entries of descriptors that are not ready to -1
	public static inline function select(read:Array<Int>, write:Array<Int>, others:Array<Int>, timeout:Float):Int
		return Mem.os() == 2 ? WinNet.select(read, write, others, timeout) : PosixNet.select(read, write, others, timeout);

	public static inline function setNoDelay(fd:Int, b:Bool):Int
		return Mem.os() == 2 ? WinNet.setNoDelay(fd, b) : PosixNet.setNoDelay(fd, b);

	public static inline function setBroadcast(fd:Int, b:Bool):Int
		return Mem.os() == 2 ? WinNet.setBroadcast(fd, b) : PosixNet.setBroadcast(fd, b);

	// SO_REUSEADDR (sys.net.Socket.bind)
	public static inline function setReuseAddr(fd:Int, b:Bool):Int
		return Mem.os() == 2 ? WinNet.setReuseAddr(fd, b) : PosixNet.setReuseAddr(fd, b);

	// SO_RCVTIMEO then SO_SNDTIMEO
	public static inline function setTimeout(fd:Int, seconds:Float):Int
		return Mem.os() == 2 ? WinNet.setTimeout(fd, seconds) : PosixNet.setTimeout(fd, seconds);

	// 0 receive, 1 send, 2 all
	public static inline function shutdown(fd:Int, mode:Int):Int
		return Mem.os() == 2 ? WinNet.shutdown(fd, mode) : PosixNet.shutdown(fd, mode);

	// O_NONBLOCK (sys.net.Socket only)
	public static inline function setBlocking(fd:Int, b:Bool):Int
		return Mem.os() == 2 ? WinNet.setBlocking(fd, b) : PosixNet.setBlocking(fd, b);

	// the last failure was EAGAIN/EWOULDBLOCK
	public static inline function blocked():Bool
		return Mem.os() == 2 ? WinNet.blocked() : PosixNet.blocked();

	// host names: null when the name is unknown (errno 0) or on failure
	public static inline function gethostname():Null<String>
		return Mem.os() == 2 ? WinNet.gethostname() : PosixNet.gethostname();

	// [host-order IPv4 of h_addr_list[0]]
	public static inline function resolve(name:String):Null<Array<Int>>
		return Mem.os() == 2 ? WinNet.resolve(name) : PosixNet.resolve(name);

	public static inline function reverse(ip:Int):Null<String>
		return Mem.os() == 2 ? WinNet.reverse(ip) : PosixNet.reverse(ip);
}
