// hxmc: haxe/std/eval/_std/sys/ssl/Certificate.hx over hxmc.NativeSsl (rt_ssl.c);
// as there, parse errors are ignored

package sys.ssl;

import haxe.io.Bytes;
import hxmc.NativeSsl;

@:coreApi
class Certificate {
	var native:Dynamic;

	function new(native:Dynamic) {
		this.native = native;
	}

	public static function loadFile(file:String):Certificate {
		var cert = NativeSsl.x509CrtInit();
		NativeSsl.x509CrtParseFile(cert, file);
		return new Certificate(cert);
	}

	public static function loadPath(path:String):Certificate {
		var cert = NativeSsl.x509CrtInit();
		NativeSsl.x509CrtParsePath(cert, path);
		return new Certificate(cert);
	}

	public static function fromString(str:String):Certificate {
		var cert = NativeSsl.x509CrtInit();
		NativeSsl.x509CrtParse(cert, Bytes.ofString(str));
		return new Certificate(cert);
	}

	public static function loadDefaults():Certificate {
		var cert = NativeSsl.x509CrtInit();
		Mbedtls.loadDefaultCertificates(cert);
		return new Certificate(cert);
	}

	public var commonName(get, null):Null<String>;

	public var altNames(get, null):Array<String>;

	public var notBefore(get, null):Date;

	public var notAfter(get, null):Date;

	public function subject(field:String):Null<String> {
		return NativeSsl.certSubject(native, field);
	}

	public function issuer(field:String):Null<String> {
		return NativeSsl.certIssuer(native, field);
	}

	public function next():Null<Certificate> {
		var cert = NativeSsl.x509Next(native);
		if (cert == null) {
			return null;
		}
		return new Certificate(cert);
	}

	public function add(pem:String):Void {
		NativeSsl.x509CrtParse(native, Bytes.ofString(pem));
	}

	public function addDER(der:Bytes):Void {
		NativeSsl.x509CrtParse(native, der);
	}

	private function get_commonName():Null<String> {
		return subject("CN");
	}

	private function get_altNames():Array<String> {
		return NativeSsl.certAltNames(native);
	}

	private function get_notBefore():Date {
		return Date.fromTime(NativeSsl.certNotBefore(native) * 1000.0);
	}

	private function get_notAfter():Date {
		return Date.fromTime(NativeSsl.certNotAfter(native) * 1000.0);
	}

	private inline function getNative():Dynamic {
		return native;
	}
}
