package hxmc.unsafe;

import hxmc.I64;

// Winsock (ws2_32) and the few other functions hxmc.rt.WinNet calls, with
// the C ABI as LibC's. A SOCKET is pointer-sized (I64 here).
@:hxmc.c extern class Winsock {
	static function socket(af:Int, type:Int, protocol:Int):I64;
	static function closesocket(s:I64):Int;
	static function accept(s:I64, addr:Ptr, len:Ptr):I64;
	static function bind(s:I64, addr:Ptr, len:Int):Int;
	static function connect(s:I64, addr:Ptr, len:Int):Int;
	static function listen(s:I64, backlog:Int):Int;
	static function getsockname(s:I64, addr:Ptr, len:Ptr):Int;
	static function getpeername(s:I64, addr:Ptr, len:Ptr):Int;
	static function getsockopt(s:I64, level:Int, opt:Int, v:Ptr, len:Ptr):Int;
	static function setsockopt(s:I64, level:Int, opt:Int, v:Ptr, len:Int):Int;
	static function recv(s:I64, p:Ptr, n:Int, flags:Int):Int;
	static function send(s:I64, p:Ptr, n:Int, flags:Int):Int;
	static function select(n:Int, r:Ptr, w:Ptr, e:Ptr, tv:Ptr):Int;
	static function shutdown(s:I64, how:Int):Int;
	static function ioctlsocket(s:I64, cmd:Int, arg:Ptr):Int;
	static function gethostname(buf:Ptr, n:Int):Int;
	static function gethostbyname(name:Ptr):Ptr;
	static function gethostbyaddr(addr:Ptr, len:Int, type:Int):Ptr;
	static function WSAGetLastError():Int;
	// kernel32, the UCRT
	static function SetHandleInformation(h:I64, mask:Int, flags:Int):Int;
	static function strerror(err:Int):Ptr;
	static function _strdup(s:Ptr):Ptr;
	// rt_win.c: Winsock's error as the errno OCaml's Unix library reports; WSAStartup once
	static function rt_win_sock_errno(wsa:Int):Int;
	static function rt_win_sockets_init():Void;
}
