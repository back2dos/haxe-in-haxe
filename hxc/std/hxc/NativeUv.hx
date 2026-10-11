package hxc;

import haxe.io.Bytes;

// libuv (rt_uv.c) behind the Eval natives of eval.luv.*
// (src/macros/eval/EvalLuv.hx), standing for the OCaml luv library.
//
// Loops, handles, requests, directories and synchronization objects are
// integer ids. Functions returning Int give a negative libuv error code on
// failure unless noted; functions returning an object give null on failure
// with the code in `lastError()`. 64-bit results are read with i64Hi/i64Lo.
// Callbacks only run inside `loopRun`, through its dispatcher:
// dispatcher(id, event, int, value), events as in rt_uv.c (EV_*).
// Socket addresses are Bytes of `sockaddrSize()` bytes (sockaddr_storage).
extern class NativeUv {
	static function available():Bool;
	static function lastError():Int;
	static function i64Hi():Int;
	static function i64Lo():Int;
	// errors: luv's Error.t index (evalLuv.ml encode_uv_error) <-> libuv code
	static function errIndex(code:Int):Int;
	static function errCode(index:Int):Int;
	static function strerror(code:Int):String;
	static function errName(code:Int):String;
	static function translateSysError(sysError:Int):Int;
	static function constant(group:Int, index:Int):Int;
	static function versionString():String;
	static function versionSuffix():String;
	// loops
	static function loopDefault():Int;
	static function loopInit():Int;
	static function loopRun(loop:Int, mode:Int, dispatcher:(id:Int, event:Int, a:Int, b:Dynamic) -> Void):Bool;
	static function loopStop(loop:Int):Void;
	static function loopClose(loop:Int):Int;
	static function loopAlive(loop:Int):Bool;
	static function loopNow(loop:Int):Void; // i64
	static function loopUpdateTime(loop:Int):Void;
	static function libraryShutdown():Void;
	static function metricsIdleTime(loop:Int):Void; // i64
	// handles (kinds: idle prepare check timer async tcp udp pipe tty signal process fsEvent fsPoll)
	static function handleInit(kind:Int, loop:Int, arg:Int, arg2:Int):Int;
	static function handleClose(handle:Int):Bool; // false: already closing
	static function handleIsActive(handle:Int):Bool;
	static function handleIsClosing(handle:Int):Bool;
	static function handleRef(handle:Int):Void;
	static function handleUnref(handle:Int):Void;
	static function handleHasRef(handle:Int):Bool;
	static function bufferSize(handle:Int, send:Bool, size:Int):Int; // size 0: get
	static function watcherStart(handle:Int):Int;
	static function watcherStop(handle:Int):Int;
	static function timerStart(handle:Int, timeout:Int, repeat:Int):Int;
	static function timerStop(handle:Int):Int;
	static function timerAgain(handle:Int):Int;
	static function timerSetRepeat(handle:Int, repeat:Int):Void;
	static function timerGetRepeat(handle:Int):Int;
	static function timerGetDueIn(handle:Int):Int;
	static function asyncSend(handle:Int):Int;
	static function signalStart(handle:Int, signum:Int, oneshot:Bool):Int;
	static function signalStop(handle:Int):Int;
	static function signalSignum(handle:Int):Int;
	// requests
	static function reqNew():Int;
	static function reqFree(req:Int):Void;
	static function reqCancel(req:Int):Int;
	static function reqCopyOut(req:Int, b:Bytes, pos:Int, src:Int, len:Int):Void;
	// socket addresses
	static function sockaddrSize():Int;
	static function sockaddrIp(host:String, port:Int, v6:Bool, out:Bytes):Int;
	static function sockaddrPort(sa:Bytes):Int; // -1: none
	static function sockaddrToString(sa:Bytes):Null<String>;
	// tcp
	static function tcpNoDelay(handle:Int, b:Bool):Int;
	static function tcpKeepAlive(handle:Int, enable:Bool, delay:Int):Int;
	static function tcpSimultaneousAccepts(handle:Int, b:Bool):Int;
	static function tcpBind(handle:Int, sa:Bytes, ipv6only:Bool):Int;
	static function sockName(handle:Int, peer:Bool, out:Bytes):Int; // tcp, udp
	static function tcpConnect(handle:Int, sa:Bytes, req:Int):Int;
	static function tcpCloseReset(handle:Int, req:Int):Int;
	// streams
	static function allocSize(n:Int):Void; // answer to an allocation event
	static function streamShutdown(handle:Int, req:Int):Int;
	static function streamListen(handle:Int, backlog:Int):Int;
	static function streamAccept(server:Int, client:Int):Int;
	static function readStart(handle:Int):Int;
	static function readStop(handle:Int):Int;
	static function streamWrite(handle:Int, req:Int, data:Bytes, sizes:Array<Int>, sendHandle:Int):Int;
	static function streamTryWrite(handle:Int, data:Bytes, sizes:Array<Int>):Int;
	static function streamWriteQueueSize(handle:Int):Int;
	static function streamIsReadable(handle:Int):Bool;
	static function streamIsWritable(handle:Int):Bool;
	static function streamSetBlocking(handle:Int, b:Bool):Int;
	// pipes, ttys
	static function pipeBind(handle:Int, name:Bytes):Int;
	static function pipeConnect(handle:Int, name:Bytes, req:Int):Void;
	static function pipeName(handle:Int, peer:Bool):Null<Bytes>;
	static function pipePendingInstances(handle:Int, n:Int):Void;
	static function pipePendingType(handle:Int):Int; // 0 none, 1 tcp, 2 pipe
	static function pipeChmod(handle:Int, mode:Int):Int;
	static function ttySetMode(handle:Int, mode:Int):Int;
	static function ttyResetMode():Int;
	static function ttyGetWinSize(handle:Int):Null<Array<Int>>;
	static function ttySetVTermState(state:Int):Void;
	static function ttyGetVTermState():Int;
	// udp
	static function udpBind(handle:Int, sa:Bytes, flags:Int):Int;
	static function udpConnect(handle:Int, sa:Null<Bytes>):Int;
	static function udpSetMembership(handle:Int, group:String, iface:String, source:Null<String>, join:Bool):Int;
	static function udpSetOption(handle:Int, option:Int, value:Int):Int;
	static function udpSetMulticastInterface(handle:Int, iface:String):Int;
	static function udpSend(handle:Int, req:Int, data:Bytes, sizes:Array<Int>, sa:Null<Bytes>):Int;
	static function udpTrySend(handle:Int, data:Bytes, sizes:Array<Int>, sa:Null<Bytes>):Int;
	static function udpRecvStart(handle:Int):Int;
	static function udpRecvStop(handle:Int):Int;
	static function udpSendQueue(handle:Int, count:Bool):Int;
	// processes; redirect: (child fd, kind, pipe flags, fd or stream handle) per redirection
	static function processSpawn(loop:Int, cmd:Bytes, args:Array<Bytes>, env:Null<Array<Bytes>>, cwd:Null<Bytes>, flags:Int, uid:Int, gid:Int,
		redirect:Array<Int>, onExit:Bool):Int;
	static function disableStdioInheritance():Void;
	static function killPid(pid:Int, signum:Int):Int;
	static function processPid(handle:Int):Int;
	// dns
	static function getAddrInfo(loop:Int, req:Int, node:Null<String>, service:Null<String>, family:Int, socktype:Int, protocol:Int, flags:Int,
		hasHints:Bool):Int;
	static function addrInfoResult(req:Int):Array<Dynamic>;
	static function getNameInfo(loop:Int, req:Int, sa:Bytes, flags:Int):Int;
	static function nameInfoResult(req:Int):Array<String>;
	// files: loop -1 runs synchronously
	static function fs(op:Int, loop:Int, req:Int, p1:Null<Bytes>, p2:Null<Bytes>, i1:Int, i2:Int, i3:Int, f1:Float, f2:Float, data:Null<Bytes>,
		sizes:Null<Array<Int>>):Int;
	static function fsResult(req:Int):Int;
	static function fsCleanup(req:Int):Void;
	static function fsPath(req:Int):Null<Bytes>;
	static function fsPtrString(req:Int):Null<Bytes>;
	static function fsStat(req:Int, out:Bytes):Void; // 160 bytes
	static function fsStatfs(req:Int, out:Bytes):Void; // 88 bytes
	static function fsDir(req:Int):Int;
	static function fsDirents(req:Int):Array<Dynamic>;
	static function fsScandirNext(req:Int):Null<Array<Dynamic>>;
	static function fsEventStart(handle:Int, path:Bytes, flags:Int):Int;
	static function fsEventStop(handle:Int):Int;
	static function fsPollStart(handle:Int, path:Bytes, interval:Int):Int;
	static function fsPollStop(handle:Int):Int;
	// random: loop -1 runs synchronously; the bytes are copied out with reqCopyOut
	static function random(loop:Int, req:Int, len:Int):Int;
	// environment, time, paths, system
	static function getEnv(name:String):Null<Bytes>;
	static function setEnv(name:String, value:Null<Bytes>):Int; // null: unset
	static function environ():Null<Array<Dynamic>>;
	static function getTimeOfDay():Int; // usec; sec in i64
	static function hrTime():Void; // i64
	static function sleep(ms:Int):Void;
	static function path(which:Int):Null<Bytes>;
	static function chdir(dir:Bytes):Int;
	static function interfaceAddresses():Null<Array<Dynamic>>;
	static function netName(which:Int, index:Int):Null<String>;
	static function uptime():Float; // lastError
	static function loadAvg():Array<Float>;
	static function memory(which:Int):Void; // i64 (resident set: lastError)
	static function getPriority(pid:Int):Int; // lastError
	static function setPriority(pid:Int, priority:Int):Int;
	static function getRUsage(out:Bytes):Int; // 144 bytes
	static function cpuInfo():Null<Array<Dynamic>>;
	static function uname():Null<Array<String>>;
	static function getPid():Int;
	static function getPPid():Int;
	static function getPasswd():Null<Array<Dynamic>>;
}
