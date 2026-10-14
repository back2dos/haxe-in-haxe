package hxmc.rt.wasm;

import haxe.io.Bytes;
import hxmc.rt.C;

// hxmc.NativeSsl and hxmc.NativeUv for WebAssembly (hxmc/README.md,
// "WebAssembly"): neither mbedtls nor libuv is there, so every call throws,
// as rt_ssl.c and rt_uv.c built with HXMC_NO_SSL / HXMC_NO_UV do
// (NativeUv.available is false; constants and the version read while
// EvalLuv's field lists are built are 0 and ""), one per extern function.
@:hxmc.wasm @:keep
class NoSslUv {
	static function noSsl():Void
		Rt.rt_throw("mbedtls is not supported on WebAssembly");

	@:hxmc.host("hxmc_NativeSsl_strerror") static function ssl_strerror(code:Int):String {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_ctrDrbgInit") static function ssl_ctrDrbgInit():Dynamic {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_ctrDrbgRandom") static function ssl_ctrDrbgRandom(ctx:Dynamic, output:haxe.io.Bytes, len:Int):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_ctrDrbgSeed") static function ssl_ctrDrbgSeed(ctx:Dynamic, entropy:Dynamic):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_entropyInit") static function ssl_entropyInit():Dynamic {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_x509CrtInit") static function ssl_x509CrtInit():Dynamic {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_x509Next") static function ssl_x509Next(crt:Dynamic):Dynamic {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_x509CrtParse") static function ssl_x509CrtParse(crt:Dynamic, b:haxe.io.Bytes):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_x509CrtParseFile") static function ssl_x509CrtParseFile(crt:Dynamic, path:String):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_x509CrtParsePath") static function ssl_x509CrtParsePath(crt:Dynamic, path:String):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_certAltNames") static function ssl_certAltNames(crt:Dynamic):Array<String> {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_certIssuer") static function ssl_certIssuer(crt:Dynamic, field:String):Null<String> {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_certSubject") static function ssl_certSubject(crt:Dynamic, field:String):Null<String> {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_certNotAfter") static function ssl_certNotAfter(crt:Dynamic):Float {
		noSsl();
		return 0.0;
	}

	@:hxmc.host("hxmc_NativeSsl_certNotBefore") static function ssl_certNotBefore(crt:Dynamic):Float {
		noSsl();
		return 0.0;
	}

	@:hxmc.host("hxmc_NativeSsl_certLoadDefaults") static function ssl_certLoadDefaults(crt:Dynamic):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_configInit") static function ssl_configInit():Dynamic {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_confAuthmode") static function ssl_confAuthmode(conf:Dynamic, authmode:Int):Void {
		noSsl();
	}

	@:hxmc.host("hxmc_NativeSsl_confCaChain") static function ssl_confCaChain(conf:Dynamic, crt:Dynamic):Void {
		noSsl();
	}

	@:hxmc.host("hxmc_NativeSsl_configDefaults") static function ssl_configDefaults(conf:Dynamic, endpoint:Int, transport:Int, preset:Int):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_confRng") static function ssl_confRng(conf:Dynamic, ctrDrbg:Dynamic):Void {
		noSsl();
	}

	@:hxmc.host("hxmc_NativeSsl_pkInit") static function ssl_pkInit():Dynamic {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_pkParseKey") static function ssl_pkParseKey(pk:Dynamic, key:haxe.io.Bytes, password:Null<String>, rng:Dynamic):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_pkParseKeyfile") static function ssl_pkParseKeyfile(pk:Dynamic, path:String, password:Null<String>, rng:Dynamic):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_pkParsePublicKey") static function ssl_pkParsePublicKey(pk:Dynamic, key:haxe.io.Bytes):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_pkParsePublicKeyfile") static function ssl_pkParsePublicKeyfile(pk:Dynamic, path:String):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_sslInit") static function ssl_sslInit():Dynamic {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_sslGetPeerCert") static function ssl_sslGetPeerCert(ssl:Dynamic):Dynamic {
		noSsl();
		return null;
	}

	@:hxmc.host("hxmc_NativeSsl_sslHandshake") static function ssl_sslHandshake(ssl:Dynamic):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_sslRead") static function ssl_sslRead(ssl:Dynamic, buf:haxe.io.Bytes, pos:Int, len:Int):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_sslWrite") static function ssl_sslWrite(ssl:Dynamic, buf:haxe.io.Bytes, pos:Int, len:Int):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_sslSetBio") static function ssl_sslSetBio(ssl:Dynamic, fd:Int):Void {
		noSsl();
	}

	@:hxmc.host("hxmc_NativeSsl_sslSetHostname") static function ssl_sslSetHostname(ssl:Dynamic, hostname:String):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_sslSetup") static function ssl_sslSetup(ssl:Dynamic, conf:Dynamic):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_bioError") static function ssl_bioError(ssl:Dynamic):Int {
		noSsl();
		return 0;
	}

	@:hxmc.host("hxmc_NativeSsl_bioErrorSend") static function ssl_bioErrorSend(ssl:Dynamic):Bool {
		noSsl();
		return false;
	}

	static function noUv():Void
		Rt.rt_throw("libuv (eval.luv) is not supported on WebAssembly");

	@:hxmc.host("hxmc_NativeUv_available") static function uv_available():Bool {
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_lastError") static function uv_lastError():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_i64Hi") static function uv_i64Hi():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_i64Lo") static function uv_i64Lo():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_errIndex") static function uv_errIndex(code:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_errCode") static function uv_errCode(index:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_strerror") static function uv_strerror(code:Int):String {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_errName") static function uv_errName(code:Int):String {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_translateSysError") static function uv_translateSysError(sysError:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_constant") static function uv_constant(group:Int, index:Int):Int {
		return 0; // (read while EvalLuv's field lists are built)
	}

	@:hxmc.host("hxmc_NativeUv_versionString") static function uv_versionString():String {
		return "";
	}

	@:hxmc.host("hxmc_NativeUv_versionSuffix") static function uv_versionSuffix():String {
		return "";
	}

	@:hxmc.host("hxmc_NativeUv_loopDefault") static function uv_loopDefault():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_loopInit") static function uv_loopInit():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_loopRun") static function uv_loopRun(loop:Int, mode:Int, dispatcher:(id:Int, event:Int, a:Int, b:Dynamic) -> Void):Bool {
		noUv();
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_loopStop") static function uv_loopStop(loop:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_loopClose") static function uv_loopClose(loop:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_loopAlive") static function uv_loopAlive(loop:Int):Bool {
		noUv();
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_loopNow") static function uv_loopNow(loop:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_loopUpdateTime") static function uv_loopUpdateTime(loop:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_libraryShutdown") static function uv_libraryShutdown():Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_metricsIdleTime") static function uv_metricsIdleTime(loop:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_handleInit") static function uv_handleInit(kind:Int, loop:Int, arg:Int, arg2:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_handleClose") static function uv_handleClose(handle:Int):Bool {
		noUv();
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_handleIsActive") static function uv_handleIsActive(handle:Int):Bool {
		noUv();
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_handleIsClosing") static function uv_handleIsClosing(handle:Int):Bool {
		noUv();
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_handleRef") static function uv_handleRef(handle:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_handleUnref") static function uv_handleUnref(handle:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_handleHasRef") static function uv_handleHasRef(handle:Int):Bool {
		noUv();
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_bufferSize") static function uv_bufferSize(handle:Int, send:Bool, size:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_watcherStart") static function uv_watcherStart(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_watcherStop") static function uv_watcherStop(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_timerStart") static function uv_timerStart(handle:Int, timeout:Int, repeat:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_timerStop") static function uv_timerStop(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_timerAgain") static function uv_timerAgain(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_timerSetRepeat") static function uv_timerSetRepeat(handle:Int, repeat:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_timerGetRepeat") static function uv_timerGetRepeat(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_timerGetDueIn") static function uv_timerGetDueIn(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_asyncSend") static function uv_asyncSend(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_signalStart") static function uv_signalStart(handle:Int, signum:Int, oneshot:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_signalStop") static function uv_signalStop(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_signalSignum") static function uv_signalSignum(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_reqNew") static function uv_reqNew():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_reqFree") static function uv_reqFree(req:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_reqCancel") static function uv_reqCancel(req:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_reqCopyOut") static function uv_reqCopyOut(req:Int, b:Bytes, pos:Int, src:Int, len:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_sockaddrSize") static function uv_sockaddrSize():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_sockaddrIp") static function uv_sockaddrIp(host:String, port:Int, v6:Bool, out:Bytes):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_sockaddrPort") static function uv_sockaddrPort(sa:Bytes):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_sockaddrToString") static function uv_sockaddrToString(sa:Bytes):Null<String> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_tcpNoDelay") static function uv_tcpNoDelay(handle:Int, b:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_tcpKeepAlive") static function uv_tcpKeepAlive(handle:Int, enable:Bool, delay:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_tcpSimultaneousAccepts") static function uv_tcpSimultaneousAccepts(handle:Int, b:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_tcpBind") static function uv_tcpBind(handle:Int, sa:Bytes, ipv6only:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_sockName") static function uv_sockName(handle:Int, peer:Bool, out:Bytes):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_tcpConnect") static function uv_tcpConnect(handle:Int, sa:Bytes, req:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_tcpCloseReset") static function uv_tcpCloseReset(handle:Int, req:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_allocSize") static function uv_allocSize(n:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_streamShutdown") static function uv_streamShutdown(handle:Int, req:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_streamListen") static function uv_streamListen(handle:Int, backlog:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_streamAccept") static function uv_streamAccept(server:Int, client:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_readStart") static function uv_readStart(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_readStop") static function uv_readStop(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_streamWrite") static function uv_streamWrite(handle:Int, req:Int, data:Bytes, sizes:Array<Int>, sendHandle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_streamTryWrite") static function uv_streamTryWrite(handle:Int, data:Bytes, sizes:Array<Int>):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_streamWriteQueueSize") static function uv_streamWriteQueueSize(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_streamIsReadable") static function uv_streamIsReadable(handle:Int):Bool {
		noUv();
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_streamIsWritable") static function uv_streamIsWritable(handle:Int):Bool {
		noUv();
		return false;
	}

	@:hxmc.host("hxmc_NativeUv_streamSetBlocking") static function uv_streamSetBlocking(handle:Int, b:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_pipeBind") static function uv_pipeBind(handle:Int, name:Bytes):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_pipeOpen") static function uv_pipeOpen(handle:Int, fd:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_pipeConnect") static function uv_pipeConnect(handle:Int, name:Bytes, req:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_pipeName") static function uv_pipeName(handle:Int, peer:Bool):Null<Bytes> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_pipePendingInstances") static function uv_pipePendingInstances(handle:Int, n:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_pipePendingType") static function uv_pipePendingType(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_pipeChmod") static function uv_pipeChmod(handle:Int, mode:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_ttySetMode") static function uv_ttySetMode(handle:Int, mode:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_ttyResetMode") static function uv_ttyResetMode():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_ttyGetWinSize") static function uv_ttyGetWinSize(handle:Int):Null<Array<Int>> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_ttySetVTermState") static function uv_ttySetVTermState(state:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_ttyGetVTermState") static function uv_ttyGetVTermState():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpBind") static function uv_udpBind(handle:Int, sa:Bytes, flags:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpConnect") static function uv_udpConnect(handle:Int, sa:Null<Bytes>):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpSetMembership") static function uv_udpSetMembership(handle:Int, group:String, iface:String, source:Null<String>, join:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpSetOption") static function uv_udpSetOption(handle:Int, option:Int, value:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpSetMulticastInterface") static function uv_udpSetMulticastInterface(handle:Int, iface:String):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpSend") static function uv_udpSend(handle:Int, req:Int, data:Bytes, sizes:Array<Int>, sa:Null<Bytes>):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpTrySend") static function uv_udpTrySend(handle:Int, data:Bytes, sizes:Array<Int>, sa:Null<Bytes>):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpRecvStart") static function uv_udpRecvStart(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpRecvStop") static function uv_udpRecvStop(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_udpSendQueue") static function uv_udpSendQueue(handle:Int, count:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_processSpawn") static function uv_processSpawn(loop:Int, cmd:Bytes, args:Array<Bytes>, env:Null<Array<Bytes>>, cwd:Null<Bytes>, flags:Int, uid:Int, gid:Int, redirect:Array<Int>, onExit:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_disableStdioInheritance") static function uv_disableStdioInheritance():Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_killPid") static function uv_killPid(pid:Int, signum:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_processPid") static function uv_processPid(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_getAddrInfo") static function uv_getAddrInfo(loop:Int, req:Int, node:Null<String>, service:Null<String>, family:Int, socktype:Int, protocol:Int, flags:Int, hasHints:Bool):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_addrInfoResult") static function uv_addrInfoResult(req:Int):Array<Dynamic> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_getNameInfo") static function uv_getNameInfo(loop:Int, req:Int, sa:Bytes, flags:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_nameInfoResult") static function uv_nameInfoResult(req:Int):Array<String> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_fs") static function uv_fs(op:Int, loop:Int, req:Int, p1:Null<Bytes>, p2:Null<Bytes>, i1:Int, i2:Int, i3:Int, f1:Float, f2:Float, data:Null<Bytes>, sizes:Null<Array<Int>>):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_fsResult") static function uv_fsResult(req:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_fsCleanup") static function uv_fsCleanup(req:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_fsPath") static function uv_fsPath(req:Int):Null<Bytes> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_fsPtrString") static function uv_fsPtrString(req:Int):Null<Bytes> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_fsStat") static function uv_fsStat(req:Int, out:Bytes):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_fsStatfs") static function uv_fsStatfs(req:Int, out:Bytes):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_fsDir") static function uv_fsDir(req:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_fsDirents") static function uv_fsDirents(req:Int):Array<Dynamic> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_fsScandirNext") static function uv_fsScandirNext(req:Int):Null<Array<Dynamic>> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_fsEventStart") static function uv_fsEventStart(handle:Int, path:Bytes, flags:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_fsEventStop") static function uv_fsEventStop(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_fsPollStart") static function uv_fsPollStart(handle:Int, path:Bytes, interval:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_fsPollStop") static function uv_fsPollStop(handle:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_random") static function uv_random(loop:Int, req:Int, len:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_getEnv") static function uv_getEnv(name:String):Null<Bytes> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_setEnv") static function uv_setEnv(name:String, value:Null<Bytes>):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_environ") static function uv_environ():Null<Array<Dynamic>> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_getTimeOfDay") static function uv_getTimeOfDay():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_hrTime") static function uv_hrTime():Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_sleep") static function uv_sleep(ms:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_path") static function uv_path(which:Int):Null<Bytes> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_chdir") static function uv_chdir(dir:Bytes):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_interfaceAddresses") static function uv_interfaceAddresses():Null<Array<Dynamic>> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_netName") static function uv_netName(which:Int, index:Int):Null<String> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_uptime") static function uv_uptime():Float {
		noUv();
		return 0.0;
	}

	@:hxmc.host("hxmc_NativeUv_loadAvg") static function uv_loadAvg():Array<Float> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_memory") static function uv_memory(which:Int):Void {
		noUv();
	}

	@:hxmc.host("hxmc_NativeUv_getPriority") static function uv_getPriority(pid:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_setPriority") static function uv_setPriority(pid:Int, priority:Int):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_getRUsage") static function uv_getRUsage(out:Bytes):Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_cpuInfo") static function uv_cpuInfo():Null<Array<Dynamic>> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_uname") static function uv_uname():Null<Array<String>> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_getPid") static function uv_getPid():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_getPPid") static function uv_getPPid():Int {
		noUv();
		return 0;
	}

	@:hxmc.host("hxmc_NativeUv_getPasswd") static function uv_getPasswd():Null<Array<Dynamic>> {
		noUv();
		return null;
	}

	@:hxmc.host("hxmc_NativeUv_guessHandle") static function uv_guessHandle(fd:Int):Int {
		noUv();
		return 0;
	}
}
