package hxc;

// hxc target (backend/): BSD sockets (rt_net.c) behind the Eval natives of
// `eval.vm.NativeSocket` and `sys.net.Host` (src/macros/eval/EvalStdLibB.hx
// StdSocket, EvalStdLibA.hx StdHost), standing for OCaml's Unix module.
// Sockets are file descriptors. Functions returning Int give -1 on failure
// with the C errno in `errno()`; `strerror` is OCaml's `Unix.error_message`.
extern class NativeNet {
	static function errno():Int;
	static function strerror(err:Int):String;
	static function socket():Int; // PF_INET, SOCK_STREAM
	static function close(fd:Int):Int;
	static function accept(fd:Int):Int;
	static function bind(fd:Int, ip:Int, port:Int):Int; // ip: host-order IPv4
	static function connect(fd:Int, ip:Int, port:Int):Int;
	static function listen(fd:Int, backlog:Int):Int;
	// getsockname (peer false) or getpeername: [ip, port], null on failure;
	// [0, -1] when the address is not ADDR_INET
	static function sockName(fd:Int, peer:Bool):Null<Array<Int>>;
	static function recv(fd:Int, b:haxe.io.Bytes, pos:Int, len:Int):Int;
	static function send(fd:Int, b:haxe.io.Bytes, pos:Int, len:Int):Int;
	// Unix.select: sets the entries of descriptors that are not ready to -1
	static function select(read:Array<Int>, write:Array<Int>, others:Array<Int>, timeout:Float):Int;
	static function setNoDelay(fd:Int, b:Bool):Int;
	static function setBroadcast(fd:Int, b:Bool):Int;
	static function setTimeout(fd:Int, seconds:Float):Int; // SO_RCVTIMEO then SO_SNDTIMEO
	static function shutdown(fd:Int, mode:Int):Int; // 0 receive, 1 send, 2 all
	// host names: null when the name is unknown (errno 0) or on failure
	static function gethostname():Null<String>;
	static function resolve(name:String):Null<Array<Int>>; // [host-order IPv4 of h_addr_list[0]]
	static function reverse(ip:Int):Null<String>;
}
