package hxmc.android;

import haxe.io.Bytes;
import hxmc.android.Axml.el;

// An Android app without the SDK (-D hxmc.target=android-arm64 or
// android-x86_64 and an output ending in .apk): the program's shared
// library (LinkDyn) as lib/<abi>/libmain.so, which NativeActivity loads
// (the activity of the framework: hasCode="false", no classes.dex; with
// Java's listeners Glue's classes.dex, and with views its org.hxmc.Activity,
// a NativeActivity whose window draws views, in the system's DayNight
// theme), and an
// AndroidManifest.xml in binary XML (Axml) naming it; no resources.arsc
// (the label is a plain string, the theme a framework resource). The zip
// stores everything uncompressed, the library aligned to 16 KB (loaded in
// place: extractNativeLibs="false"; Android 15's 16 KB pages) and the rest
// to 4 bytes, as zipalign -P 16 does; then the APK Signature Scheme v2
// block before the central directory, signed with ECDSA P-256 and SHA-256
// (P256) by a debug key made on first use and kept in the user's cache
// directory (<cache>/android/debug-key: the private scalar and its
// self-signed certificate), so that reinstalls keep the signature;
// HXMC_ANDROID_KEY (or -D hxmc.android-key=<file>) names another such
// file. Options (Options.android): -D hxmc.android-package=<id> (default
// org.hxmc.<the output's name>), -D hxmc.android-label=<text> (the output's
// name), -D hxmc.android-version=<code> (1), -D hxmc.android-version-name
// (1.0), -D hxmc.android-min-sdk (29: Bionic's ELF TLS), -D
// hxmc.android-target-sdk (35), -D hxmc.android-permissions=<names>
// (uses-permission, android.permission.<name> unless it has a dot: none by
// default; hxmc dev's APK asks for INTERNET, its dev server's socket).
class Apk {
	static inline var LIB = "main";
	static inline var PAGE = 16384;
	// the v2 signature scheme's block id, the algorithm (ECDSA with SHA2-256)
	static inline var V2_ID = 0x7109871a;
	static inline var ECDSA_SHA256 = 0x0201;

	// the library's name in the APK (lib<name>.so; NativeActivity's default)
	public static function libName(out:String):String
		return LIB;

	static function baseName(out:String):String
		return haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(out));

	// (keyFile: the debug key's, made when missing)
	// (dex: Glue's classes.dex, when the program has listeners; views: org.hxmc.Activity)
	public static function write(out:String, so:Bytes, dex:Null<Bytes>, views:Bool, abi:Abi, opts:Map<String, String>, keyFile:String) {
		var abiDir = abi.arm ? "arm64-v8a" : "x86_64";
		var name = baseName(out);
		var pkg = opts.get("package") ?? "org.hxmc." + ~/[^a-z0-9_]/g.replace(name.toLowerCase(), "_");
		if (!~/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/.match(pkg)) throw "hxmc: APK: the package " + pkg + " is not an application id (a.b.c)";
		var manifest = manifest(pkg, opts.get("label") ?? name, Std.parseInt(opts.get("version") ?? "1"), opts.get("version_name") ?? "1.0",
			Std.parseInt(opts.get("min_sdk") ?? "29"), Std.parseInt(opts.get("target_sdk") ?? "35"), dex != null, views,
			opts.get("permissions") == null ? [] : [for (p in opts.get("permissions").split(",")) if (StringTools.trim(p) != "") StringTools.trim(p)]);
		var entries:Array<Zip.ZipEntry> = [{name: "AndroidManifest.xml", data: manifest, align: 4}];
		if (dex != null) entries.push({name: "classes.dex", data: dex, align: 4});
		entries.push({name: "lib/" + abiDir + "/lib" + LIB + ".so", data: so, align: PAGE});
		var zip = Zip.stored(entries);
		var key = debugKey(keyFile);
		sys.io.File.saveBytes(out, sign(zip, key.d, key.cert));
	}

	// ---- the manifest

	public static function manifest(pkg:String, label:String, versionCode:Int, versionName:String, minSdk:Int, targetSdk:Int, code = false, views = false,
			?permissions:Array<String>):Bytes {
		inline function s(n:String, v:String):Axml.Attr
			return {android: true, name: n, type: Axml.STRING, string: v};
		inline function i(n:String, v:Int, hex = false):Axml.Attr
			return {android: true, name: n, type: hex ? Axml.INT_HEX : Axml.INT_DEC, value: v};
		inline function b(n:String, v:Bool):Axml.Attr
			return {android: true, name: n, type: Axml.BOOLEAN, value: v ? -1 : 0};
		// orientation, screenSize, screenLayout, smallestScreenSize, keyboard,
		// keyboardHidden, navigation, uiMode, density, layoutDirection: the
		// activity stays (the program's thread keeps its window)
		var configChanges = 0x80 | 0x400 | 0x100 | 0x800 | 0x10 | 0x20 | 0x40 | 0x200 | 0x1000 | 0x2000;
		var uses = [];
		if (permissions != null)
			for (n in permissions)
				uses.push(el("uses-permission", [s("name", n.indexOf(".") < 0 ? "android.permission." + n : n)]));
		var root = el("manifest", [
			{android: false, name: "package", type: Axml.STRING, string: pkg},
			i("versionCode", versionCode),
			s("versionName", versionName)
		], [
			el("uses-sdk", [i("minSdkVersion", minSdk), i("targetSdkVersion", targetSdk)]),
		].concat(uses).concat([
			el("uses-feature", [i("glEsVersion", 0x30000, true), b("required", true)]),
			el("application", [s("label", label), b("hasCode", code), b("debuggable", true), b("extractNativeLibs", false)], [
				el("activity", [
					s("name", views ? Glue.ACTIVITY : "android.app.NativeActivity"),
					s("label", label),
					b("exported", true),
					i("configChanges", configChanges, true),
					// @android:style/Theme.NoTitleBar.Fullscreen; with views
					// Theme.DeviceDefault.DayNight (API 29: the system's look, light or dark)
					{android: true, name: "theme", type: Axml.REFERENCE, value: views ? 0x010302e3 : 0x01030007}
				], [
					el("meta-data", [s("name", "android.app.lib_name"), s("value", LIB)]),
					el("intent-filter", [], [
						el("action", [s("name", "android.intent.action.MAIN")]),
						el("category", [s("name", "android.intent.category.LAUNCHER")])
					])
				])
			])
		]));
		return Axml.encode(root);
	}

	// ---- the signature (APK Signature Scheme v2)

	// a length-prefixed (uint32 little-endian) blob
	static function lp(b:Bytes):Bytes {
		var o = new Buf(b.length + 4);
		o.u32(b.length);
		o.bytes(b);
		return o.toBytes();
	}

	static function cat(parts:Array<Bytes>):Bytes {
		var b = new haxe.io.BytesBuffer();
		for (p in parts)
			b.add(p);
		return b.getBytes();
	}

	// the digest of the v2 scheme over sections of the file: each split into
	// 1 MB chunks, SHA-256(0xa5, length, chunk) per chunk, then
	// SHA-256(0x5a, count, the chunks' digests)
	public static function contentDigest(sections:Array<Bytes>):Bytes {
		var digests = new haxe.io.BytesBuffer(), count = 0;
		for (s in sections) {
			var at = 0;
			while (at < s.length) {
				var n = s.length - at < 1 << 20 ? s.length - at : 1 << 20;
				var c = Bytes.alloc(5 + n);
				c.set(0, 0xa5);
				c.setInt32(1, n);
				c.blit(5, s, at, n);
				digests.add(haxe.crypto.Sha256.make(c));
				count++;
				at += n;
			}
		}
		var d = digests.getBytes();
		var top = Bytes.alloc(5 + d.length);
		top.set(0, 0x5a);
		top.setInt32(1, count);
		top.blit(5, d, 0, d.length);
		return haxe.crypto.Sha256.make(top);
	}

	// the key's SubjectPublicKeyInfo (id-ecPublicKey, prime256v1)
	public static function publicKeyInfo(d:Bytes):Bytes
		return Der.seq([Der.seq([Der.oid("1.2.840.10045.2.1"), Der.oid("1.2.840.10045.3.1.7")]), Der.bitString(P256.publicKey(d))]);

	// a self-signed X.509 v3 certificate of the key (CN=Android Debug, O=Android, C=US, as the SDK's debug key)
	public static function certificate(d:Bytes, serial:Bytes, from:Date, years:Int):Bytes {
		var name = Der.seq([
			Der.set([Der.seq([Der.oid("2.5.4.6"), Der.printable("US")])]),
			Der.set([Der.seq([Der.oid("2.5.4.10"), Der.utf8("Android")])]),
			Der.set([Der.seq([Der.oid("2.5.4.3"), Der.utf8("Android Debug")])])
		]);
		var alg = Der.seq([Der.oid("1.2.840.10045.4.3.2")]); // ecdsa-with-SHA256
		var until = new Date(from.getFullYear() + years, from.getMonth(), from.getDate(), from.getHours(), from.getMinutes(), from.getSeconds());
		var tbs = Der.seq([
			Der.explicit(0, Der.small(2)), Der.integer(serial), alg, name, Der.seq([Der.time(from), Der.time(until)]), name, publicKeyInfo(d)
		]);
		return Der.seq([tbs, alg, Der.bitString(P256.sign(d, tbs))]);
	}

	// the zip with its v2 signing block before the central directory
	public static function sign(zip:Bytes, d:Bytes, cert:Bytes):Bytes {
		// the end of central directory (no comment: the last 22 bytes) and the directory's offset
		var eocdAt = zip.length - 22;
		if (zip.getInt32(eocdAt) != 0x06054b50) throw "hxmc: APK: no end of central directory";
		var cdAt = zip.getInt32(eocdAt + 16);
		var contents = zip.sub(0, cdAt), cd = zip.sub(cdAt, eocdAt - cdAt), eocd = zip.sub(eocdAt, 22);
		// (the digest sees the directory's offset as the block's: the unsigned zip's)
		var digest = contentDigest([contents, cd, eocd]);
		var spki = publicKeyInfo(d);
		var digests = lp(lp(cat([int(ECDSA_SHA256), lp(digest)])));
		var signedData = cat([digests, lp(lp(cert)), lp(Bytes.alloc(0))]);
		var signatures = lp(lp(cat([int(ECDSA_SHA256), lp(P256.sign(d, signedData))])));
		var signer = cat([lp(signedData), signatures, lp(spki)]);
		var value = lp(lp(signer));
		// the block: size, pairs (length, id, value), size, magic
		var pair = new Buf(value.length + 12);
		pair.u64(value.length + 4, 0);
		pair.u32(V2_ID);
		pair.bytes(value);
		var size = pair.len + 8 + 16;
		var block = new Buf(size + 8);
		block.u64(size, 0);
		block.buf(pair);
		block.u64(size, 0);
		block.str("APK Sig Block 42");
		var out = new Buf(zip.length + block.len);
		out.bytes(contents);
		out.buf(block);
		out.bytes(cd);
		var e = eocd.sub(0, 22);
		e.setInt32(16, cdAt + block.len);
		out.bytes(e);
		return out.toBytes();
	}

	static function int(v:Int):Bytes {
		var b = Bytes.alloc(4);
		b.setInt32(0, v);
		return b;
	}

	// ---- the debug key

	// the key file (made when missing): "hxmc-android-debug-key 1", the
	// private scalar in hex, the certificate in base64
	// the debug key's file: -D hxmc.android-key, HXMC_ANDROID_KEY, else in the user's cache directory (cacheRoot)
	public static function keyFile(opts:Map<String, String>, cacheRoot:Null<String>):String {
		var path = opts.get("key");
		if (path == null) path = Sys.getEnv("HXMC_ANDROID_KEY");
		if (path == null || path == "") {
			if (cacheRoot == null) throw "hxmc: APK: no cache directory for the debug key (HXMC_ANDROID_KEY names a file)";
			path = cacheRoot + "android/debug-key";
		}
		return path;
	}

	public static function debugKey(path:String):{d:Bytes, cert:Bytes} {
		if (sys.FileSystem.exists(path)) {
			var l = StringTools.trim(sys.io.File.getContent(path)).split("\n");
			if (l.length < 3 || l[0] != "hxmc-android-debug-key 1") throw "hxmc: APK: " + path + " is not a debug key of hxmc's";
			var d = Bytes.ofHex(StringTools.trim(l[1]));
			if (!P256.validPrivate(d)) throw "hxmc: APK: " + path + ": not a P-256 private key";
			return {d: d, cert: haxe.crypto.Base64.decode(StringTools.trim(l[2]))};
		}
		var d = Bytes.alloc(32);
		do {
			var r = random(32);
			d.blit(0, r, 0, 32);
		} while (!P256.validPrivate(d));
		var serial = random(8);
		serial.set(0, serial.get(0) & 0x7f);
		var cert = certificate(d, serial, Date.now(), 30);
		sys.FileSystem.createDirectory(haxe.io.Path.directory(path));
		sys.io.File.saveContent(path, "hxmc-android-debug-key 1\n" + d.toHex() + "\n" + haxe.crypto.Base64.encode(cert) + "\n");
		return {d: d, cert: cert};
	}

	// bytes from the system's random source (/dev/urandom; elsewhere the
	// time and Math.random through SHA-256: a debug key only)
	static function random(n:Int):Bytes {
		var b = try {
			var f = sys.io.File.read("/dev/urandom", true);
			var r = f.read(n);
			f.close();
			r;
		} catch (_:Dynamic) null;
		if (b != null && b.length == n) return b;
		var out = Bytes.alloc(n), seed = Std.string(Date.now().getTime()) + Sys.time() + Math.random();
		var at = 0;
		while (at < n) {
			var h = haxe.crypto.Sha256.make(Bytes.ofString(seed + at + Math.random()));
			var k = n - at < 32 ? n - at : 32;
			out.blit(at, h, 0, k);
			at += k;
		}
		return out;
	}
}
