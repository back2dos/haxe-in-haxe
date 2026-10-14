// hxmc: haxe/std/eval/_std/sys/ssl/Socket.hx over hxmc.NativeSsl (rt_ssl.c),
// whose BIO sends and receives on the descriptor of the sys.net.Socket.
// hxmc: mbedtls's WANT_READ/WANT_WRITE results (non-blocking sockets) throw
// haxe.io.Error.Blocked (Eval tests for -1, which mbedtls never returns), and
// a failed send/recv throws its system error (as Eval's Unix_error) instead
// of Eof. With green threads TLS I/O blocks the whole process.

package sys.ssl;

import haxe.io.Bytes;
import hxmc.NativeSsl;

private class SocketInput extends haxe.io.Input {
	@:allow(sys.ssl.Socket) private var socket:Socket;

	var readBuf:Bytes;

	public function new(s:Socket) {
		this.socket = s;
		readBuf = Bytes.alloc(1);
	}

	public override function readByte() {
		readBytes(readBuf, 0, 1);
		return readBuf.get(0);
	}

	public override function readBytes(buf:haxe.io.Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || ((pos + len) : UInt) > (buf.length : UInt))
			throw haxe.io.Error.OutsideBounds;
		socket.handshake();
		var r = @:privateAccess socket.result(NativeSsl.sslRead(socket.ssl, buf, pos, len));
		if (r <= 0)
			throw new haxe.io.Eof();
		return r;
	}

	public override function close() {
		super.close();
		if (socket != null)
			socket.close();
	}
}

private class SocketOutput extends haxe.io.Output {
	@:allow(sys.ssl.Socket) private var socket:Socket;

	var writeBuf:Bytes;

	public function new(s:Socket) {
		this.socket = s;
		writeBuf = Bytes.alloc(1);
	}

	public override function writeByte(c:Int) {
		writeBuf.set(0, c);
		writeBytes(writeBuf, 0, 1);
	}

	public override function writeBytes(buf:haxe.io.Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || ((pos + len) : UInt) > (buf.length : UInt))
			throw haxe.io.Error.OutsideBounds;
		socket.handshake();
		var r = @:privateAccess socket.result(NativeSsl.sslWrite(socket.ssl, buf, pos, len));
		if (r < 0)
			throw new haxe.io.Eof();
		return r;
	}

	public override function close() {
		super.close();
		if (socket != null)
			socket.close();
	}
}

@:coreApi
class Socket extends sys.net.Socket {
	public static var DEFAULT_VERIFY_CERT:Null<Bool> = true;

	public static var DEFAULT_CA:Null<Certificate>;

	// mbedtls/ssl.h
	static inline var SSL_IS_CLIENT = 0;
	static inline var SSL_IS_SERVER = 1;
	static inline var SSL_TRANSPORT_STREAM = 0;
	static inline var SSL_PRESET_DEFAULT = 0;
	static inline var SSL_VERIFY_NONE = 0;
	static inline var SSL_VERIFY_OPTIONAL = 1;
	static inline var SSL_VERIFY_REQUIRED = 2;
	static inline var ERR_SSL_WANT_READ = -0x6900;
	static inline var ERR_SSL_WANT_WRITE = -0x6880;

	private var conf:Dynamic;
	private var ssl:Dynamic;

	public var verifyCert:Null<Bool>;

	private var caCert:Null<Certificate>;
	private var hostname:String;

	private var handshakeDone:Bool;
	private var isBlocking:Bool = true;

	override function init(fd:Int):Void {
		this.fd = fd;
		input = new SocketInput(this);
		output = new SocketOutput(this);
		if (DEFAULT_VERIFY_CERT && DEFAULT_CA == null) {
			DEFAULT_CA = Certificate.loadDefaults();
		}
		verifyCert = DEFAULT_VERIFY_CERT;
		caCert = DEFAULT_CA;
	}

	// an mbedtls result: the BIO's system error, Blocked, or the code
	function result(r:Int):Int {
		var err = NativeSsl.bioError(ssl);
		if (err != 0)
			throw haxe.io.Error.Custom(hxmc.NativeNet.strerror(err) + "(" + (NativeSsl.bioErrorSend(ssl) ? "send" : "recv") + ")");
		if (r == ERR_SSL_WANT_READ || r == ERR_SSL_WANT_WRITE)
			throw haxe.io.Error.Blocked;
		return r;
	}

	public override function connect(host:sys.net.Host, port:Int):Void {
		conf = buildConfig(false);
		ssl = NativeSsl.sslInit();
		NativeSsl.sslSetup(ssl, conf);
		NativeSsl.sslSetBio(ssl, fd);
		handshakeDone = false;
		if (hostname == null)
			hostname = host.host;
		if (hostname != null)
			NativeSsl.sslSetHostname(ssl, hostname);
		super.connect(host, port);
		if (isBlocking)
			handshake();
	}

	public function handshake():Void {
		if (!handshakeDone) {
			var r = result(NativeSsl.sslHandshake(ssl));
			if (r == 0)
				handshakeDone = true;
			else
				throw NativeSsl.strerror(r);
		}
	}

	override function setBlocking(b:Bool):Void {
		super.setBlocking(b);
		isBlocking = b;
	}

	public function setCA(cert:Certificate):Void {
		caCert = cert;
	}

	public function setHostname(name:String):Void {
		hostname = name;
	}

	public override function close():Void {
		super.close();
		var input:SocketInput = cast input;
		var output:SocketOutput = cast output;
		@:privateAccess input.socket = output.socket = null;
		input.close();
		output.close();
	}

	public override function bind(host:sys.net.Host, port:Int):Void {
		conf = buildConfig(true);
		super.bind(host, port);
	}

	public override function accept():Socket {
		var cfd = @:privateAccess sys.net.Socket.check(hxmc.NativeNet.accept(fd));
		var cssl = NativeSsl.sslInit();
		NativeSsl.sslSetup(cssl, conf);
		NativeSsl.sslSetBio(cssl, cfd);

		var s = Type.createEmptyInstance(sys.ssl.Socket);
		s.fd = cfd;
		s.ssl = cssl;
		s.input = new SocketInput(s);
		s.output = new SocketOutput(s);
		s.handshakeDone = false;
		s.isBlocking = true;

		return s;
	}

	public function addSNICertificate(cbServernameMatch:String->Bool, cert:Certificate, key:Key):Void {
		throw new haxe.exceptions.NotImplementedException();
	}

	public function peerCertificate():Certificate {
		return @:privateAccess new Certificate(NativeSsl.sslGetPeerCert(ssl));
	}

	public function setCertificate(cert:Certificate, key:Key):Void {
		throw new haxe.exceptions.NotImplementedException();
	}

	private function buildConfig(server:Bool):Dynamic {
		var conf = NativeSsl.configInit();
		NativeSsl.configDefaults(conf, server ? SSL_IS_SERVER : SSL_IS_CLIENT, SSL_TRANSPORT_STREAM, SSL_PRESET_DEFAULT);
		NativeSsl.confRng(conf, Mbedtls.getDefaultCtrDrbg());

		if (caCert != null) {
			NativeSsl.confCaChain(conf, @:privateAccess caCert.getNative());
		}
		NativeSsl.confAuthmode(conf, if (verifyCert) SSL_VERIFY_REQUIRED else if (verifyCert == null) SSL_VERIFY_OPTIONAL else SSL_VERIFY_NONE);
		return conf;
	}
}
