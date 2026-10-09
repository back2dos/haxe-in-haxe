package sys;

import hxc.NativeSys;

// hxc target (backend/): the file system through hxc.NativeSys.
class FileSystem {
	public static function exists(path:String):Bool
		return NativeSys.exists(path);

	public static function rename(path:String, newPath:String):Void
		if (!NativeSys.rename(path, newPath)) throw "Could not rename " + path + " to " + newPath;

	public static function stat(path:String):FileStat {
		var a = NativeSys.stat(path);
		if (a == null) throw "Could not stat " + path;
		return {
			gid: Std.int(a[0]),
			uid: Std.int(a[1]),
			atime: Date.fromTime(a[2] * 1000),
			mtime: Date.fromTime(a[3] * 1000),
			ctime: Date.fromTime(a[4] * 1000),
			dev: Std.int(a[5]),
			ino: Std.int(a[6]),
			nlink: Std.int(a[7]),
			rdev: Std.int(a[8]),
			size: Std.int(a[9]),
			mode: Std.int(a[10])
		};
	}

	public static function fullPath(relPath:String):String {
		var p = NativeSys.fullPath(relPath);
		if (p == null) throw "Could not resolve " + relPath;
		return p;
	}

	public static function absolutePath(relPath:String):String {
		if (haxe.io.Path.isAbsolute(relPath)) return relPath;
		return haxe.io.Path.join([Sys.getCwd(), relPath]);
	}

	public static function isDirectory(path:String):Bool
		return NativeSys.isDirectory(path);

	public static function createDirectory(path:String):Void {
		var path = haxe.io.Path.removeTrailingSlashes(path);
		if (path == "" || NativeSys.isDirectory(path)) return;
		var parent = haxe.io.Path.directory(path);
		if (parent != "" && parent != path) createDirectory(parent);
		if (!NativeSys.createDirectory(path) && !NativeSys.isDirectory(path)) throw "Could not create directory " + path;
	}

	public static function deleteFile(path:String):Void
		if (!NativeSys.deleteFile(path)) throw "Could not delete file " + path;

	public static function deleteDirectory(path:String):Void
		if (!NativeSys.deleteDirectory(path)) throw "Could not delete directory " + path;

	public static function readDirectory(path:String):Array<String> {
		var r = NativeSys.readDirectory(path);
		if (r == null) throw "Could not read directory " + path;
		return r;
	}
}
