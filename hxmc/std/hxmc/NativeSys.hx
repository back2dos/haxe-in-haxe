package hxmc;

import hxmc.rt.PosixSys;
import hxmc.rt.WinSys;
import hxmc.unsafe.Mem;

// Operating-system primitives, the base of the std's Sys, sys.io.* and
// sys.FileSystem: POSIX (hxmc.rt.PosixSys) or Windows (hxmc.rt.WinSys), chosen
// by the target (Mem.os folds while lowering: only one is reached).
class NativeSys {
	public static inline function print(s:String):Void {
		if (Mem.os() == 2) WinSys.print(s) else PosixSys.print(s);
	}

	public static inline function printErr(s:String):Void {
		if (Mem.os() == 2) WinSys.printErr(s) else PosixSys.printErr(s);
	}

	public static inline function args():Array<String>
		return Mem.os() == 2 ? WinSys.args() : PosixSys.args();

	// the program name as invoked (argv[0])
	public static inline function argv0():Null<String>
		return Mem.os() == 2 ? WinSys.argv0() : PosixSys.argv0();

	public static inline function getEnv(s:String):Null<String>
		return Mem.os() == 2 ? WinSys.getEnv(s) : PosixSys.getEnv(s);

	public static inline function putEnv(s:String, v:Null<String>):Void {
		if (Mem.os() == 2) WinSys.putEnv(s, v) else PosixSys.putEnv(s, v);
	}

	// "name=value"
	public static inline function environ():Array<String>
		return Mem.os() == 2 ? WinSys.environ() : PosixSys.environ();

	public static inline function sleep(seconds:Float):Void {
		if (Mem.os() == 2) WinSys.sleep(seconds) else PosixSys.sleep(seconds);
	}

	public static inline function getCwd():String
		return Mem.os() == 2 ? WinSys.getCwd() : PosixSys.getCwd();

	public static inline function setCwd(s:String):Bool
		return Mem.os() == 2 ? WinSys.setCwd(s) : PosixSys.setCwd(s);

	public static inline function systemName():String
		return Mem.os() == 2 ? WinSys.systemName() : PosixSys.systemName();

	// also under Cosmopolitan (whose systemName is "Linux")
	public static inline function hostSystem():String
		return Mem.os() == 2 ? WinSys.hostSystem() : PosixSys.hostSystem();

	// through the shell
	public static inline function command(cmd:String):Int
		return Mem.os() == 2 ? WinSys.command(cmd) : PosixSys.command(cmd);

	// Windows: without a shell; -2 elsewhere
	public static inline function commandArgs(cmd:String, args:Array<String>):Int
		return Mem.os() == 2 ? WinSys.commandArgs(cmd, args) : PosixSys.commandArgs(cmd, args);

	public static inline function exit(code:Int):Void {
		if (Mem.os() == 2) WinSys.exit(code) else PosixSys.exit(code);
	}

	public static inline function time():Float
		return Mem.os() == 2 ? WinSys.time() : PosixSys.time();

	public static inline function cpuTime():Float
		return Mem.os() == 2 ? WinSys.cpuTime() : PosixSys.cpuTime();

	public static inline function programPath():String
		return Mem.os() == 2 ? WinSys.programPath() : PosixSys.programPath();

	public static inline function getChar(echo:Bool):Int
		return Mem.os() == 2 ? WinSys.getChar(echo) : PosixSys.getChar(echo);

	// files: descriptors
	// 0 read, 1 write, 2 append, 3 update; -1 on error
	public static inline function fileOpen(path:String, mode:Int):Int
		return Mem.os() == 2 ? WinSys.fileOpen(path, mode) : PosixSys.fileOpen(path, mode);

	// 0 at end, -1 on error
	public static inline function fileRead(fd:Int, b:haxe.io.Bytes, pos:Int, len:Int):Int
		return Mem.os() == 2 ? WinSys.fileRead(fd, b, pos, len) : PosixSys.fileRead(fd, b, pos, len);

	public static inline function fileWrite(fd:Int, b:haxe.io.Bytes, pos:Int, len:Int):Int
		return Mem.os() == 2 ? WinSys.fileWrite(fd, b, pos, len) : PosixSys.fileWrite(fd, b, pos, len);

	public static inline function fileClose(fd:Int):Void {
		if (Mem.os() == 2) WinSys.fileClose(fd) else PosixSys.fileClose(fd);
	}

	public static inline function fileSeek(fd:Int, p:Int, whence:Int):Void {
		if (Mem.os() == 2) WinSys.fileSeek(fd, p, whence) else PosixSys.fileSeek(fd, p, whence);
	}

	public static inline function fileTell(fd:Int):Int
		return Mem.os() == 2 ? WinSys.fileTell(fd) : PosixSys.fileTell(fd);

	public static inline function fileContent(path:String):Null<haxe.io.Bytes>
		return Mem.os() == 2 ? WinSys.fileContent(path) : PosixSys.fileContent(path);

	public static inline function fileSave(path:String, b:haxe.io.Bytes, append:Bool):Bool
		return Mem.os() == 2 ? WinSys.fileSave(path, b, append) : PosixSys.fileSave(path, b, append);

	public static inline function exists(path:String):Bool
		return Mem.os() == 2 ? WinSys.exists(path) : PosixSys.exists(path);

	public static inline function isDirectory(path:String):Bool
		return Mem.os() == 2 ? WinSys.isDirectory(path) : PosixSys.isDirectory(path);

	public static inline function createDirectory(path:String):Bool
		return Mem.os() == 2 ? WinSys.createDirectory(path) : PosixSys.createDirectory(path);

	public static inline function deleteFile(path:String):Bool
		return Mem.os() == 2 ? WinSys.deleteFile(path) : PosixSys.deleteFile(path);

	public static inline function deleteDirectory(path:String):Bool
		return Mem.os() == 2 ? WinSys.deleteDirectory(path) : PosixSys.deleteDirectory(path);

	public static inline function rename(path:String, newPath:String):Bool
		return Mem.os() == 2 ? WinSys.rename(path, newPath) : PosixSys.rename(path, newPath);

	public static inline function readDirectory(path:String):Null<Array<String>>
		return Mem.os() == 2 ? WinSys.readDirectory(path) : PosixSys.readDirectory(path);

	// realpath; Windows: GetFullPathName (Extc.get_full_path)
	public static inline function fullPath(path:String):Null<String>
		return Mem.os() == 2 ? WinSys.fullPath(path) : PosixSys.fullPath(path);

	// Extc.get_real_path: Windows' spelling of an existing path; fullPath elsewhere
	public static inline function realPath(path:String):Null<String>
		return Mem.os() == 2 ? WinSys.realPath(path) : PosixSys.realPath(path);

	// gid uid atime mtime ctime dev ino nlink rdev size mode
	public static inline function stat(path:String):Null<Array<Float>>
		return Mem.os() == 2 ? WinSys.stat(path) : PosixSys.stat(path);

	// processes
	// pid, fds: stdin, stdout, stderr
	public static inline function processRun(cmd:String, args:Null<Array<String>>, fds:Array<Int>):Int
		return Mem.os() == 2 ? WinSys.processRun(cmd, args, fds) : PosixSys.processRun(cmd, args, fds);

	// exit code, -1 while running
	public static inline function processWait(pid:Int, block:Bool):Int
		return Mem.os() == 2 ? WinSys.processWait(pid, block) : PosixSys.processWait(pid, block);

	public static inline function processKill(pid:Int):Void {
		if (Mem.os() == 2) WinSys.processKill(pid) else PosixSys.processKill(pid);
	}
}
