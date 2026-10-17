import Harness.*;
import haxe.io.Bytes;
import hxmc.android.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The APKs hxmc writes for Android (hxmc/src/hxmc/android/Apk.hx; make
// android-check), checked without a device:
//   bin/hxmc/hxmc -cp hxmc/test -cp haxe/test -cp hxmc/src --run ApkCheck <apk>...
// - P256 against RFC 6979's test vector (A.2.5: the public key and the
//   deterministic signature of "sample"), and a certificate it makes parsed
//   back;
// - the zip: AndroidManifest.xml and lib/<abi>/libmain.so stored, the
//   library's data at a multiple of 16 KB, the rest of 4 bytes (zipalign -c
//   -p 4 too, when there);
// - the manifest read back from its binary XML (Axml.dump, aapt dump
//   xmltree when there): NativeActivity, its library, no code;
// - the library (readelf): a shared object of the APK's ABI, 16 KB
//   segments, DT_NEEDED only of the system's libraries, its SONAME, the
//   export ANativeActivity_onCreate, no text relocations, the module's
//   thread-locals through TLSDESC (arm64) or the general dynamic model
//   (x86-64), Bionic's symbol versions;
// - the v2 signature: its block found, the digest of the contents recomputed
//   and equal to the signed one, the signature verified by apksigner (when
//   there: CI's Android SDK) or by openssl.
// Exits non-zero on a failure; a missing tool is skipped.
class ApkCheck {
	static var failures:Array<String> = [];

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println(pad(what, 52) + " " + (ok ? "ok" : "FAIL") + (detail != "" ? "  " + detail : ""));
		if (!ok) failures.push(what);
	}

	static function has(tool:String):Bool
		return !windows && exec(["sh", "-c", "command -v " + tool]).code == 0;

	static function main() {
		vectors();
		for (apk in Sys.args())
			checkApk(apk);
		if (failures.length > 0) {
			Sys.println("ApkCheck: " + failures.length + " failed");
			Sys.exit(1);
		}
		Sys.println("ApkCheck: all passed");
	}

	static function vectors() {
		var d = Bytes.ofHex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721");
		var q = P256.publicKey(d).toHex();
		check("P-256: RFC 6979's public key", q == "0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299");
		var sig = P256.sign(d, Bytes.ofString("sample")).toHex();
		check("P-256: RFC 6979's signature of \"sample\"",
			sig == "3046022100efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716022100f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8");
		if (has("openssl")) {
			var dir = "bin/hxmc-apk";
			mkdirs(dir);
			var cert = Apk.certificate(d, Bytes.ofHex("0102030405060708"), new Date(2026, 0, 1, 0, 0, 0), 30);
			File.saveBytes('$dir/cert.der', cert);
			var r = exec(["openssl", "x509", "-inform", "DER", "-in", '$dir/cert.der', "-noout", "-subject", "-dates"]);
			check("certificate: openssl reads it", r.code == 0 && r.out.indexOf("CN = Android Debug") >= 0, r.out.trim().split("\n").join("; "));
		}
	}

	static function le32(b:Bytes, at:Int):Int
		return b.getInt32(at);

	static function checkApk(apk:String) {
		Sys.println("ApkCheck: " + apk);
		var b = File.getBytes(apk);
		// the end of central directory, the directory
		var eocd = b.length - 22;
		check("zip: end of central directory", le32(b, eocd) == 0x06054b50);
		var n = b.getUInt16(eocd + 10), cdSize = le32(b, eocd + 12), cdAt = le32(b, eocd + 16);
		var entries = new Map<String, {data:Bytes, at:Int}>();
		var at = cdAt;
		for (_ in 0...n) {
			if (le32(b, at) != 0x02014b50) break;
			var method = b.getUInt16(at + 10), size = le32(b, at + 20), nl = b.getUInt16(at + 28), xl = b.getUInt16(at + 30),
				cl = b.getUInt16(at + 32), local = le32(b, at + 42);
			var name = b.getString(at + 46, nl);
			var dataAt = local + 30 + b.getUInt16(local + 26) + b.getUInt16(local + 28);
			check('zip: $name stored', method == 0);
			var align = name.endsWith(".so") ? 16384 : 4;
			check('zip: $name aligned to $align', dataAt % align == 0, "at " + dataAt);
			entries.set(name, {data: b.sub(dataAt, size), at: dataAt});
			at += 46 + nl + xl + cl;
		}
		if (has("zipalign")) check("zipalign -c -p 4", exec(["zipalign", "-c", "-p", "4", apk]).code == 0);
		var lib = [for (k in entries.keys()) if (k.startsWith("lib/")) k];
		check("zip: AndroidManifest.xml and one library", entries.exists("AndroidManifest.xml") && lib.length == 1, lib.join(" "));
		if (lib.length != 1 || !entries.exists("AndroidManifest.xml")) return;
		var abi = lib[0].split("/")[1];
		check("zip: the library is lib/<abi>/libmain.so", lib[0] == 'lib/$abi/libmain.so' && (abi == "arm64-v8a" || abi == "x86_64"), lib[0]);
		// the manifest
		var xml = Axml.dump(entries.get("AndroidManifest.xml").data);
		check("manifest: NativeActivity", xml.indexOf('android:name(0x01010003)="android.app.NativeActivity"') >= 0);
		check("manifest: android.app.lib_name main", xml.indexOf('"android.app.lib_name"') >= 0 && xml.indexOf('android:value(0x01010024)="main"') >= 0);
		check("manifest: hasCode false, extractNativeLibs false", xml.indexOf("android:hasCode(0x0101000c)=false") >= 0
			&& xml.indexOf("android:extractNativeLibs(0x010104ea)=false") >= 0, [for (l in xml.split("\n")) if (l.indexOf("<application") >= 0) l.trim()].join(""));
		check("manifest: the launcher's intent filter", xml.indexOf('"android.intent.action.MAIN"') >= 0 && xml.indexOf('"android.intent.category.LAUNCHER"') >= 0);
		if (has("aapt")) {
			var r = exec(["aapt", "dump", "badging", apk]);
			check("aapt dump badging", r.code == 0 && r.out.indexOf("launchable-activity: name='android.app.NativeActivity'") >= 0, r.out.split("\n")[0]);
		}
		// the library
		var dir = "bin/hxmc-apk";
		mkdirs(dir);
		var so = '$dir/libmain-$abi.so';
		File.saveBytes(so, entries.get(lib[0]).data);
		if (has("readelf")) elf(so, abi);
		// the signature
		signature(b, cdAt, eocd);
		if (has("apksigner")) {
			var r = exec(["apksigner", "verify", "--verbose", apk], {merge: true});
			check("apksigner verify (v2)", r.code == 0 && r.out.indexOf("Verified using v2 scheme (APK Signature Scheme v2): true") >= 0,
				r.code == 0 ? "" : r.out.trim().split("\n").pop());
		}
	}

	static function readelf(args:Array<String>, file:String):String
		return exec(["readelf", "-W"].concat(args).concat([file])).out;

	static function elf(so:String, abi:String) {
		var h = readelf(["-h"], so);
		check("library: a shared object", h.indexOf("DYN (Shared object file)") >= 0);
		check("library: the ABI's machine", h.indexOf(abi == "x86_64" ? "X86-64" : "AArch64") >= 0);
		var l = readelf(["-l"], so);
		var load = ~/^\s*LOAD\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+0x[0-9a-f]+\s+0x[0-9a-f]+\s+0x[0-9a-f]+\s+.{3}\s+0x([0-9a-f]+)/;
		var segs = 0, aligned = true;
		for (line in l.split("\n"))
			if (load.match(line)) {
				segs++;
				var off = Std.parseInt("0x" + load.matched(1)), va = Std.parseInt("0x" + load.matched(2)), al = Std.parseInt("0x" + load.matched(3));
				if (al != 0x4000 || off % 0x4000 != va % 0x4000) aligned = false;
			}
		check("library: 16 KB segments", segs >= 3 && aligned, segs + " loadable");
		check("library: no program interpreter", l.indexOf("INTERP") < 0);
		var d = readelf(["-d"], so);
		check("library: no text relocations", d.indexOf("TEXTREL") < 0);
		check("library: SONAME libmain.so", d.indexOf("Library soname: [libmain.so]") >= 0);
		var allowed = ["libc.so", "libm.so", "libdl.so", "liblog.so", "libandroid.so", "libEGL.so", "libGLESv3.so", "libGLESv2.so"];
		var needed = ~/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/, s = d, libs = [];
		while (needed.match(s)) {
			libs.push(needed.matched(1));
			s = needed.matchedRight();
		}
		check("library: DT_NEEDED the system's libraries only", libs.indexOf("libc.so") >= 0 && Lambda.foreach(libs, x -> allowed.indexOf(x) >= 0), libs.join(" "));
		var syms = readelf(["--dyn-syms"], so);
		check("library: exports ANativeActivity_onCreate", ~/FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+ANativeActivity_onCreate/.match(syms));
		var vers = ~/@(\w+)/g, bad = [];
		var t = syms;
		while (vers.match(t)) {
			var v = vers.matched(1);
			if (!v.startsWith("LIBC") && bad.indexOf(v) < 0) bad.push(v);
			t = vers.matchedRight();
		}
		check("library: Bionic's symbol versions (LIBC*)", bad.length == 0, bad.join(" "));
		var r = readelf(["-r"], so);
		var tls = abi == "x86_64" ? r.indexOf("R_X86_64_DTPMOD64") >= 0 && r.indexOf("__tls_get_addr") >= 0 : r.indexOf("R_AARCH64_TLSDESC") >= 0;
		check("library: thread-locals " + (abi == "x86_64" ? "general dynamic" : "through TLSDESC"), tls);
		check("library: no initial-exec or local-exec TLS", r.indexOf("R_X86_64_TPOFF") < 0 && r.indexOf("TLS_TPREL") < 0);
	}

	// the APK Signing Block before the central directory, its v2 signer
	static function signature(b:Bytes, cdAt:Int, eocdAt:Int) {
		var magic = b.getString(cdAt - 16, 16);
		check("signature: the APK Signing Block", magic == "APK Sig Block 42");
		if (magic != "APK Sig Block 42") return;
		var size = b.getInt32(cdAt - 24);
		var blockAt = cdAt - size - 8;
		check("signature: the block's sizes agree", b.getInt32(blockAt) == size);
		// the pairs
		var at = blockAt + 8, v2 = null;
		while (at < cdAt - 24) {
			var len = b.getInt32(at), id = b.getInt32(at + 8);
			if (id == 0x7109871a) v2 = b.sub(at + 12, len - 4);
			at += 8 + len;
		}
		check("signature: a v2 block", v2 != null);
		if (v2 == null) return;
		// signers > signer > signed data > digests > digest
		var signer = v2.sub(8, v2.getInt32(4));
		var sd = signer.sub(4, signer.getInt32(0));
		var digests = sd.sub(4, sd.getInt32(0));
		var digest = digests.sub(4, digests.getInt32(0));
		var alg = digest.getInt32(0);
		var signedDigest = digest.sub(8, digest.getInt32(4));
		check("signature: ECDSA with SHA-256", alg == 0x0201);
		// (the digest sees the end of directory with the block's offset)
		var eocd = b.sub(eocdAt, b.length - eocdAt);
		eocd.setInt32(16, blockAt);
		var computed = Apk.contentDigest([b.sub(0, blockAt), b.sub(cdAt, eocdAt - cdAt), eocd]);
		check("signature: the contents' digest", computed.toHex() == signedDigest.toHex());
		// the signature over the signed data, by openssl
		var rest = signer.sub(4 + sd.length, signer.length - 4 - sd.length);
		var sigs = rest.sub(4, rest.getInt32(0));
		var sig1 = sigs.sub(4, sigs.getInt32(0));
		var sig = sig1.sub(8, sig1.getInt32(4));
		var keyAt = 4 + rest.getInt32(0);
		var spki = rest.sub(keyAt + 4, rest.getInt32(keyAt));
		if (has("openssl")) {
			var dir = "bin/hxmc-apk";
			File.saveBytes('$dir/signed-data', sd);
			File.saveBytes('$dir/sig', sig);
			File.saveBytes('$dir/key.der', spki);
			var k = exec(["openssl", "pkey", "-pubin", "-inform", "DER", "-in", '$dir/key.der', "-out", '$dir/key.pem']);
			var r = exec(["openssl", "dgst", "-sha256", "-verify", '$dir/key.pem', "-signature", '$dir/sig', '$dir/signed-data'], {merge: true});
			check("signature: openssl verifies it", k.code == 0 && r.code == 0, r.out.trim());
		}
	}
}
