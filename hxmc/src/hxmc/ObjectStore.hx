package hxmc;

import sys.FileSystem;
import sys.io.File;

// The compiled objects in the module cache's store (Driver.hx; ModuleCache.hx
// for the typed modules): per tool build, <cache>/modules/<tool>/o/<key>-<module>.o,
// <key> the hash of the module's lowered IR with the tool and the target
// (Fingerprint), so every output and project that compiles the same code
// for the same target shares the object. Per output (by its absolute path)
// <out-hash>.objs names the objects its last build used (what the trim keeps:
// an object goes with the last .objs naming it, one none names after an
// hour; the .objs files go with their last use, as the indexes do) and <out-hash>.key is UpToDate's record. Not
// used under WASI, nor where the cache directory cannot be written: then the
// objects are kept next to the output, in <out>.hxmc/, as before.
class ObjectStore {
	public final dir:String;
	final outKey:String;

	function new(dir:String, out:String) {
		this.dir = dir;
		outKey = Fingerprint.hash("hxmc-out|" + (try FileSystem.absolutePath(out) catch (_:Dynamic) out));
	}

	// the store for an output (null: none, the objects go next to it)
	public static function open(out:String):Null<ObjectStore> {
		if (Sys.systemName() == "Wasi") return null;
		var root = CacheDir.root();
		if (root == null) return null;
		var dir = root + "modules/" + CacheDir.toolStamp() + "/";
		try {
			if (!FileSystem.exists(dir + "o")) FileSystem.createDirectory(dir + "o");
		} catch (_:Dynamic) {
			return null;
		}
		if (!FileSystem.exists(dir + "o")) return null;
		if (!FileSystem.exists(dir + "used") || CacheDir.now() - CacheDir.mtime(dir + "used") > CacheDir.USED_REFRESH) CacheDir.touch(dir + "used");
		CacheDir.trim(root + "modules/", dir);
		return new ObjectStore(dir, out);
	}

	public function objectPath(key:String, moduleFile:String):String
		return dir + "o/" + key + "-" + moduleFile + ".o";

	public function keyFile():String
		return dir + outKey + ".key";

	// an object written beside and renamed into place
	public function save(path:String, b:haxe.io.Bytes) {
		if (FileSystem.exists(path)) return;
		var tmp = path + "." + CacheDir.nonce() + ".tmp";
		try {
			File.saveBytes(tmp, b);
			if (CacheDir.replace(tmp, path)) CacheDir.wrote(b.length);
		} catch (_:Dynamic) {
			try FileSystem.deleteFile(tmp) catch (_:Dynamic) {}
		}
	}

	// the objects the output's build used (rewritten when they change, else
	// its last use refreshed)
	public function record(names:Array<String>) {
		var p = dir + outKey + ".objs";
		var text = names.join("\n");
		var old = try File.getContent(p) catch (_:Dynamic) null;
		if (old == text) {
			CacheDir.used(p);
			return;
		}
		var tmp = p + "." + CacheDir.nonce() + ".tmp";
		try {
			File.saveContent(tmp, text);
			if (CacheDir.replace(tmp, p)) CacheDir.wrote(text.length - (old == null ? 0 : old.length));
		} catch (_:Dynamic) {
			try FileSystem.deleteFile(tmp) catch (_:Dynamic) {}
		}
	}

	// the objects an object list names (CacheDir.trim: removed with the last
	// list naming them)
	public static function objectsOf(file:String):Array<String>
		return [for (l in File.getContent(file).split("\n")) if (l != "") "o/" + l];
}
