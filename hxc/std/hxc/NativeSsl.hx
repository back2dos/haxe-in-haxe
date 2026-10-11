package hxc;

// mbedtls (rt_ssl.c) behind the Eval natives of mbedtls.* and sys.ssl.*
// (src/macros/eval/EvalSsl.hx), mirroring the OCaml bindings
// haxe/libs/mbedtls/mbedtls.ml. Contexts are opaque runtime handles.
extern class NativeSsl {
	static function strerror(code:Int):String;
	static function ctrDrbgInit():Dynamic;
	static function ctrDrbgRandom(ctx:Dynamic, output:haxe.io.Bytes, len:Int):Int;
	static function ctrDrbgSeed(ctx:Dynamic, entropy:Dynamic):Int;
	static function entropyInit():Dynamic;
	static function x509CrtInit():Dynamic;
	static function x509Next(crt:Dynamic):Dynamic; // null: none
	static function x509CrtParse(crt:Dynamic, b:haxe.io.Bytes):Int;
	static function x509CrtParseFile(crt:Dynamic, path:String):Int;
	static function x509CrtParsePath(crt:Dynamic, path:String):Int;
	static function certAltNames(crt:Dynamic):Array<String>;
	static function certIssuer(crt:Dynamic, field:String):Null<String>;
	static function certSubject(crt:Dynamic, field:String):Null<String>;
	static function certNotAfter(crt:Dynamic):Float;
	static function certNotBefore(crt:Dynamic):Float;
	static function certLoadDefaults(crt:Dynamic):Int;
	static function configInit():Dynamic;
	static function confAuthmode(conf:Dynamic, authmode:Int):Void;
	static function confCaChain(conf:Dynamic, crt:Dynamic):Void;
	static function configDefaults(conf:Dynamic, endpoint:Int, transport:Int, preset:Int):Int;
	static function confRng(conf:Dynamic, ctrDrbg:Dynamic):Void;
	static function pkInit():Dynamic;
	static function pkParseKey(pk:Dynamic, key:haxe.io.Bytes, password:Null<String>, rng:Dynamic):Int;
	static function pkParseKeyfile(pk:Dynamic, path:String, password:Null<String>, rng:Dynamic):Int;
	static function pkParsePublicKey(pk:Dynamic, key:haxe.io.Bytes):Int;
	static function pkParsePublicKeyfile(pk:Dynamic, path:String):Int;
	static function sslInit():Dynamic;
	static function sslGetPeerCert(ssl:Dynamic):Dynamic; // null: none
	static function sslHandshake(ssl:Dynamic):Int;
	static function sslRead(ssl:Dynamic, buf:haxe.io.Bytes, pos:Int, len:Int):Int;
	static function sslWrite(ssl:Dynamic, buf:haxe.io.Bytes, pos:Int, len:Int):Int;
	static function sslSetBio(ssl:Dynamic, fd:Int):Void; // send/recv on the socket
	static function sslSetHostname(ssl:Dynamic, hostname:String):Int;
	static function sslSetup(ssl:Dynamic, conf:Dynamic):Int;
	// errno of the BIO's failed send/recv during the last handshake/read/write (0: none)
	static function bioError(ssl:Dynamic):Int;
	static function bioErrorSend(ssl:Dynamic):Bool;
}
