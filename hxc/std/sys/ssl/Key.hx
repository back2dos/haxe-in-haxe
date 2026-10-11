// hxc: haxe/std/eval/_std/sys/ssl/Key.hx over hxc.NativeSsl (rt_ssl.c)

package sys.ssl;

import haxe.io.Bytes;
import hxc.NativeSsl;

@:coreApi
class Key {
	var native:Dynamic;

	function new() {
		native = NativeSsl.pkInit();
	}

	static public function loadFile(file:String, ?isPublic:Bool, ?pass:String):Key {
		var key = new Key();
		var code = if (isPublic) {
			NativeSsl.pkParsePublicKeyfile(key.native, file);
		} else {
			NativeSsl.pkParseKeyfile(key.native, file, pass, Mbedtls.getDefaultCtrDrbg());
		}
		if (code != 0) {
			throw(NativeSsl.strerror(code));
		}
		return key;
	}

	static function parse(data:Bytes, isPublic:Bool, ?pass:String):Key {
		var key = new Key();
		var code = if (isPublic) {
			NativeSsl.pkParsePublicKey(key.native, data);
		} else {
			NativeSsl.pkParseKey(key.native, data, null, Mbedtls.getDefaultCtrDrbg());
		}
		if (code != 0) {
			throw(NativeSsl.strerror(code));
		}
		return key;
	}

	static public function readPEM(data:String, isPublic:Bool, ?pass:String):Key {
		return parse(Bytes.ofString(data), isPublic, pass);
	}

	static public function readDER(data:haxe.io.Bytes, isPublic:Bool):Key {
		return parse(data, isPublic);
	}
}
