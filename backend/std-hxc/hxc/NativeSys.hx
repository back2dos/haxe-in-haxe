package hxc;

// hxc target (backend/): operating-system primitives (rt_sys.c). The std
// classes (Sys, sys.io.*, sys.FileSystem) are Haxe code over these.
extern class NativeSys {
	static function print(s:String):Void;
	static function printErr(s:String):Void;
	static function args():Array<String>;
	static function getEnv(s:String):Null<String>;
	static function putEnv(s:String, v:Null<String>):Void;
	static function environ():Array<String>; // "name=value"
	static function sleep(seconds:Float):Void;
	static function getCwd():String;
	static function setCwd(s:String):Bool;
	static function systemName():String;
	static function command(cmd:String):Int; // through the shell
	static function exit(code:Int):Void;
	static function time():Float;
	static function cpuTime():Float;
	static function programPath():String;
	static function getChar(echo:Bool):Int;
	// files: descriptors
	static function fileOpen(path:String, mode:Int):Int; // 0 read, 1 write, 2 append, 3 update; -1 on error
	static function fileRead(fd:Int, b:haxe.io.Bytes, pos:Int, len:Int):Int; // 0 at end, -1 on error
	static function fileWrite(fd:Int, b:haxe.io.Bytes, pos:Int, len:Int):Int;
	static function fileClose(fd:Int):Void;
	static function fileSeek(fd:Int, p:Int, whence:Int):Void;
	static function fileTell(fd:Int):Int;
	static function fileContent(path:String):Null<haxe.io.Bytes>;
	static function fileSave(path:String, b:haxe.io.Bytes, append:Bool):Bool;
	static function exists(path:String):Bool;
	static function isDirectory(path:String):Bool;
	static function createDirectory(path:String):Bool;
	static function deleteFile(path:String):Bool;
	static function deleteDirectory(path:String):Bool;
	static function rename(path:String, newPath:String):Bool;
	static function readDirectory(path:String):Null<Array<String>>;
	static function fullPath(path:String):Null<String>;
	static function stat(path:String):Null<Array<Float>>; // gid uid atime mtime ctime dev ino nlink rdev size mode
	// processes
	static function processRun(cmd:String, args:Null<Array<String>>, fds:Array<Int>):Int; // pid, fds: stdin, stdout, stderr
	static function processWait(pid:Int, block:Bool):Int; // exit code, -1 while running
	static function processKill(pid:Int):Void;
}
