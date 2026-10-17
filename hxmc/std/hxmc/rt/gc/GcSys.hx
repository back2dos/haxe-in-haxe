package hxmc.rt.gc;

// -D hxmc.wasm-gc: the system functions (hxmc.NativeSys: WasiSys's API), over
// the host (hxmc/bootstrap/wasmgc.mjs, node's): what a browser or node has,
// the rest an error that says so
@:keep @:hxmc.wasmgc
class GcSys {
	static function unsupported(what:String):Dynamic
		throw what + ": not supported by -D hxmc.wasm-gc";

	// the host's strings joined by "\x00"
	static function list(s:String):Array<String>
		return s == null ? [] : s == "" ? [] : s.split("\x00");

	public static function print(s:String):Void
		W.write(1, s);

	public static function printErr(s:String):Void
		W.write(2, s);

	public static function args():Array<String>
		return list(W.sysStr(4, null, null));

	public static function argv0():String
		return W.sysStr(6, null, null);

	public static function getEnv(s:String):String
		return W.sysStr(0, s, null);

	public static function putEnv(s:String, v:String):Void
		W.sysNum(11, s, v, 0);

	public static function environ():Array<String>
		return list(W.sysStr(5, null, null));

	public static function sleep(seconds:Float):Void
		W.sysNum(10, null, null, seconds);

	public static function getCwd():String
		return W.sysStr(1, null, null);

	public static function setCwd(s:String):Bool
		return W.sysNum(6, s, null, 0) != 0;

	public static function systemName():String
		return W.sysStr(8, null, null);

	public static function hostSystem():String
		return W.sysStr(8, null, null);

	public static function command(cmd:String):Int
		return unsupported("Sys.command");

	public static function commandArgs(cmd:String, args:Array<String>):Int
		return unsupported("Sys.command");

	public static function exit(code:Int):Void
		W.sysNum(7, null, null, code);

	public static function time():Float
		return W.sysNum(8, null, null, 0);

	public static function cpuTime():Float
		return W.sysNum(9, null, null, 0);

	public static function programPath():String
		return W.sysStr(6, null, null);

	public static function getChar(echo:Bool):Int
		return unsupported("Sys.getChar");

	public static function fileOpen(path:String, mode:Int):Int
		return unsupported("sys.io.File streams");

	public static function fileRead(fd:Int, b:Dynamic, pos:Int, len:Int):Int
		return unsupported("sys.io.File streams");

	public static function fileWrite(fd:Int, b:Dynamic, pos:Int, len:Int):Int
		return unsupported("sys.io.File streams");

	public static function fileFlush(fd:Int):Void
		unsupported("sys.io.File streams");

	public static function fileClose(fd:Int):Void
		unsupported("sys.io.File streams");

	public static function fileSeek(fd:Int, p:Int, whence:Int):Void
		unsupported("sys.io.File streams");

	public static function fileTell(fd:Int):Int
		return unsupported("sys.io.File streams");

	public static function fileContent(path:String):Dynamic
		return W.readFile(path);

	public static function fileSave(path:String, b:Dynamic, append:Bool):Bool
		return W.writeFile(path, b, append);

	public static function exists(path:String):Bool
		return W.sysNum(0, path, null, 0) != 0;

	public static function isDirectory(path:String):Bool
		return W.sysNum(1, path, null, 0) != 0;

	public static function createDirectory(path:String):Bool
		return W.sysNum(2, path, null, 0) != 0;

	public static function deleteFile(path:String):Bool
		return W.sysNum(3, path, null, 0) != 0;

	public static function deleteDirectory(path:String):Bool
		return W.sysNum(4, path, null, 0) != 0;

	public static function rename(path:String, newPath:String):Bool
		return W.sysNum(5, path, newPath, 0) != 0;

	public static function readDirectory(path:String):Array<String> {
		var s = W.sysStr(3, path, null);
		return s == null ? null : list(s);
	}

	public static function fullPath(path:String):String
		return W.sysStr(2, path, null);

	public static function realPath(path:String):String
		return W.sysStr(2, path, null);

	// gid, uid, atime, mtime, ctime, size, dev, ino, nlink, rdev, mode (sys.FileStat's order, as WasiSys)
	public static function stat(path:String):Array<Float> {
		var s = W.sysStr(7, path, null);
		return s == null ? null : [for (x in list(s)) Std.parseFloat(x)];
	}

	public static function processRun(cmd:String, args:Array<String>, fds:Array<Int>):Int
		return unsupported("sys.io.Process");

	public static function processWait(pid:Int, block:Bool):Int
		return unsupported("sys.io.Process");

	public static function processKill(pid:Int):Void
		unsupported("sys.io.Process");
}
