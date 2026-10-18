import Harness.*;
import haxe.io.Bytes;
import hxmc.ios.Plist;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The iOS apps hxmc writes (hxmc/src/hxmc/ios/Bundle.hx; make ios-check),
// checked without a Mac:
//   bin/hxmc/hxmc -cp hxmc/test -cp haxe/test -cp hxmc/src --run IosCheck <app or ipa>...
// - the bundle: <name>.app with its executable, Info.plist and
//   _CodeSignature/CodeResources and nothing else (an .ipa: the same under
//   Payload/, stored, the executable with mode 0755);
// - Info.plist read back: the executable, the bundle id, UILaunchScreen,
//   the platform (iPhoneOS or iPhoneSimulator) and the minimum version;
// - the executable: a 64-bit arm64 MH_EXECUTE, PIE, dyld, LC_MAIN, the
//   build version's platform (iOS or the simulator: the plist's) and
//   minimum (the plist's), the dylibs only the system's (libSystem first,
//   and no AppKit), thread-local descriptors flagged when there,
//   LC_CODE_SIGNATURE at the end of the file and of __LINKEDIT;
// - the code signature: the SuperBlob, the CodeDirectory (ad hoc,
//   identified by the bundle id, the page hashes recomputed, the code limit
//   at the signature, the executable segment __TEXT's), its special slots
//   equal to the hashes of the Info.plist, of the requirements blob and of
//   CodeResources; CodeResources' own hash of the Info.plist;
// - llvm-objdump's view of the load commands and binds, when there; on a
//   Mac, codesign --verify and plutil -lint.
// Exits non-zero on a failure; a missing tool is skipped.
class IosCheck {
	static var failures:Array<String> = [];

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println(pad(what, 56) + " " + (ok ? "ok" : "FAIL") + (detail != "" ? "  " + detail : ""));
		if (!ok) failures.push(what);
	}

	static function has(tool:String):Bool
		return !windows && exec(["sh", "-c", "command -v " + tool]).code == 0;

	static function main() {
		for (a in Sys.args())
			checkBundle(a);
		if (failures.length > 0) {
			Sys.println("IosCheck: " + failures.length + " failed");
			Sys.exit(1);
		}
		Sys.println("IosCheck: all passed");
	}

	static function checkBundle(path:String) {
		Sys.println("IosCheck: " + path);
		var files = new Map<String, Bytes>();
		var ipa = path.endsWith(".ipa");
		var exec755 = new Map<String, Bool>();
		if (ipa) {
			var b = File.getBytes(path);
			var eocd = b.length - 22;
			check("zip: end of central directory", b.getInt32(eocd) == 0x06054b50);
			var n = b.getUInt16(eocd + 10), at = b.getInt32(eocd + 16);
			var app:Null<String> = null;
			for (_ in 0...n) {
				if (b.getInt32(at) != 0x02014b50) break;
				var method = b.getUInt16(at + 10), size = b.getInt32(at + 20), nl = b.getUInt16(at + 28), xl = b.getUInt16(at + 30),
					cl = b.getUInt16(at + 32), attrs = b.getInt32(at + 38), local = b.getInt32(at + 42);
				var name = b.getString(at + 46, nl);
				var dataAt = local + 30 + b.getUInt16(local + 26) + b.getUInt16(local + 28);
				check('zip: $name stored', method == 0);
				var m = ~/^Payload\/([^\/]+\.app)\/(.+)$/;
				check('zip: $name under Payload/<name>.app/', m.match(name));
				if (m.matched(1) != null) app = m.matched(1);
				var inner = m.matched(2);
				files.set(inner, b.sub(dataAt, size));
				exec755.set(inner, (attrs >>> 16) & 0x1ff == 0x1ed);
				at += 46 + nl + xl + cl;
			}
		} else {
			for (rel in walk(path))
				files.set(rel, File.getBytes(path + "/" + rel));
		}
		var info = files.get("Info.plist");
		check("bundle: Info.plist", info != null);
		if (info == null) return;
		var plist = try Plist.parse(info.toString()) catch (e:Dynamic) null;
		check("Info.plist: an XML property list", plist != null);
		if (plist == null) return;
		var d = switch plist {
			case PDict(d): d;
			case _: new Map();
		}
		inline function str(k:String):Null<String>
			return switch d.get(k) {
				case PString(s): s;
				case _: null;
			}
		var exe = str("CFBundleExecutable"), id = str("CFBundleIdentifier"), min = str("MinimumOSVersion");
		check("Info.plist: CFBundleExecutable, CFBundleIdentifier, MinimumOSVersion", exe != null && id != null && min != null, '$exe $id $min');
		check("Info.plist: CFBundlePackageType APPL", str("CFBundlePackageType") == "APPL");
		check("Info.plist: UILaunchScreen (no storyboard)", d.get("UILaunchScreen") != null && d.get("UILaunchStoryboardName") == null);
		var sim = switch d.get("CFBundleSupportedPlatforms") {
			case PArray([PString(p)]): p == "iPhoneSimulator";
			case _: false;
		}
		check("Info.plist: DTPlatformName matches the platform", str("DTPlatformName") == (sim ? "iphonesimulator" : "iphoneos"));
		var names = [for (k in files.keys()) k];
		names.sort(compare);
		var want = ["Info.plist", exe, "_CodeSignature/CodeResources"];
		want.sort(compare);
		check("bundle: the executable, Info.plist, _CodeSignature/CodeResources", names.join(",") == want.join(","), names.join(" "));
		if (ipa) check("ipa: the executable's mode 0755", exec755.get(exe) == true);
		var bin = files.get(exe), res = files.get("_CodeSignature/CodeResources");
		if (bin == null || res == null) return;
		// CodeResources
		var cr = try Plist.parse(res.toString()) catch (e:Dynamic) null;
		var hashed = switch cr {
			case PDict(c): switch c.get("files") {
					case PDict(f): switch f.get("Info.plist") {
							case PData(h): h.toHex() == haxe.crypto.Sha1.make(info).toHex();
							case _: false;
						}
					case _: false;
				}
			case _: false;
		}
		check("CodeResources: Info.plist's SHA-1", hashed);
		macho(bin, id, sim, min, info, res);
		if (!ipa && Sys.systemName() == "Mac") {
			var r = exec(["codesign", "--verify", "--verbose=2", path], {merge: true});
			check("codesign --verify", r.code == 0, r.out.trim().split("\n").join("; "));
			var r = exec(["plutil", "-lint", path + "/Info.plist"], {merge: true});
			check("plutil -lint Info.plist", r.code == 0, r.out.trim());
		}
		if (!ipa && has("llvm-objdump")) {
			var r = exec(["llvm-objdump", "--macho", "--private-headers", path + "/" + exe], {merge: true});
			check("llvm-objdump: the load commands", r.code == 0 && r.out.indexOf("platform " + (sim ? "iossimulator" : "ios")) >= 0, r.code == 0 ? "" : r.out.trim());
			var r = exec(["llvm-objdump", "--macho", "--bind", path + "/" + exe], {merge: true});
			check("llvm-objdump: the binds", r.code == 0 && r.out.indexOf("libSystem") >= 0, r.code == 0 ? "" : r.out.trim());
		}
	}

	static function be32(b:Bytes, at:Int):Int
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);

	static function cstr(b:Bytes, at:Int, max:Int):String {
		var e = at;
		while (e < at + max && b.get(e) != 0)
			e++;
		return b.getString(at, e - at);
	}

	static function macho(b:Bytes, id:String, sim:Bool, min:String, info:Bytes, res:Bytes) {
		check("Mach-O: 64-bit, arm64, MH_EXECUTE", b.getInt32(0) == 0xfeedfacf && b.getInt32(4) == 0x0100000c && b.getInt32(12) == 2);
		var flags = b.getInt32(24);
		check("Mach-O: PIE, two-level, dyld", flags & 0x200000 != 0 && flags & 0x80 != 0 && flags & 0x4 != 0);
		var ncmds = b.getInt32(16), at = 32;
		var platform = -1, minos = -1, main = false, dyld = "", libs = [], sigOff = -1, sigSize = 0, tlv = false;
		var textFileSize = 0, leEnd = 0;
		for (_ in 0...ncmds) {
			var cmd = b.getInt32(at), size = b.getInt32(at + 4);
			switch cmd {
				case 0x32:
					platform = b.getInt32(at + 8);
					minos = b.getInt32(at + 12);
				case 0x80000028: main = true;
				case 0xe: dyld = cstr(b, at + b.getInt32(at + 8), size);
				case 0xc: libs.push(cstr(b, at + b.getInt32(at + 8), size));
				case 0x1d:
					sigOff = b.getInt32(at + 8);
					sigSize = b.getInt32(at + 12);
				case 0x19:
					var name = cstr(b, at + 8, 16);
					var fileoff = b.getInt32(at + 40), filesize = b.getInt32(at + 48);
					if (name == "__TEXT") textFileSize = filesize;
					if (name == "__LINKEDIT") leEnd = fileoff + filesize;
					var nsects = b.getInt32(at + 64);
					for (k in 0...nsects)
						if (cstr(b, at + 72 + 80 * k, 16) == "__thread_vars" && b.getInt32(at + 72 + 80 * k + 40) > 0) tlv = true;
				case _:
			}
			at += size;
		}
		var p = min.split(".");
		var want = (Std.parseInt(p[0]) << 16) | (Std.parseInt(p[1]) << 8);
		check("Mach-O: the build version's platform: " + (sim ? "iOS simulator (7)" : "iOS (2)"), platform == (sim ? 7 : 2), "" + platform);
		check("Mach-O: the build version's minimum is MinimumOSVersion", minos == want, StringTools.hex(minos));
		check("Mach-O: LC_MAIN, /usr/lib/dyld", main && dyld == "/usr/lib/dyld");
		check("Mach-O: libSystem first, only the system's dylibs, no AppKit", libs[0] == "/usr/lib/libSystem.B.dylib"
			&& Lambda.foreach(libs, l -> l.startsWith("/usr/lib/") || l.startsWith("/System/Library/Frameworks/")) && !Lambda.exists(libs, l -> l.indexOf("AppKit") >= 0),
			libs.map(l -> haxe.io.Path.withoutDirectory(l)).join(" "));
		check("Mach-O: thread-local descriptors flagged", !tlv || flags & 0x800000 != 0);
		check("Mach-O: the signature ends the file and __LINKEDIT", sigOff > 0 && sigOff + sigSize == b.length && leEnd == b.length);
		if (sigOff <= 0) return;
		// the signature
		check("signature: a SuperBlob", be32(b, sigOff) == 0xfade0cc0);
		var count = be32(b, sigOff + 8);
		var blobs = new Map<Int, Int>();
		for (k in 0...count)
			blobs.set(be32(b, sigOff + 12 + 8 * k), sigOff + be32(b, sigOff + 16 + 8 * k));
		var cd = blobs.get(0), req = blobs.get(2);
		check("signature: a CodeDirectory and requirements", cd != null && req != null && be32(b, cd) == 0xfade0c02 && be32(b, req) == 0xfade0c01);
		if (cd == null || req == null) return;
		var cdFlags = be32(b, cd + 12), hashOff = be32(b, cd + 16), identOff = be32(b, cd + 20), nSpecial = be32(b, cd + 24), nCode = be32(b, cd + 28),
			codeLimit = be32(b, cd + 32), hashSize = b.get(cd + 36), hashType = b.get(cd + 37), pageLog = b.get(cd + 39);
		check("CodeDirectory: ad hoc, not linker-signed", cdFlags & 0x2 != 0 && cdFlags & 0x20000 == 0, StringTools.hex(cdFlags));
		check("CodeDirectory: identified by the bundle id", cstr(b, cd + identOff, 256) == id, cstr(b, cd + identOff, 256));
		check("CodeDirectory: SHA-256 of 4 KB pages up to the signature", hashSize == 32 && hashType == 2 && pageLog == 12 && codeLimit == sigOff
			&& nCode == (codeLimit + 4095) >> 12);
		// (execSegBase, execSegLimit, execSegFlags: 64-bit words at 64, 72, 80)
		check("CodeDirectory: the executable segment is __TEXT, the main binary's", be32(b, cd + 64) == 0 && be32(b, cd + 68) == 0 && be32(b, cd + 72) == 0
			&& be32(b, cd + 76) == textFileSize && be32(b, cd + 84) & 1 == 1);
		var bad = 0;
		for (k in 0...nCode) {
			var off = k << 12, n = codeLimit - off < 4096 ? codeLimit - off : 4096;
			if (haxe.crypto.Sha256.make(b.sub(off, n)).toHex() != b.sub(cd + hashOff + 32 * k, 32).toHex()) bad++;
		}
		check("CodeDirectory: the page hashes", bad == 0, bad + " of " + nCode + " differ");
		function slot(k:Int):String
			return k > nSpecial ? "" : b.sub(cd + hashOff - 32 * k, 32).toHex();
		check("CodeDirectory: slot 1 is the Info.plist's hash", slot(1) == haxe.crypto.Sha256.make(info).toHex());
		check("CodeDirectory: slot 2 is the requirements' hash", slot(2) == haxe.crypto.Sha256.make(b.sub(req, be32(b, req + 4))).toHex());
		check("CodeDirectory: slot 3 is CodeResources' hash", slot(3) == haxe.crypto.Sha256.make(res).toHex());
		var ent = blobs.get(5);
		if (ent != null) check("CodeDirectory: slot 5 is the entitlements' hash", slot(5) == haxe.crypto.Sha256.make(b.sub(ent, be32(b, ent + 4))).toHex());
	}
}
