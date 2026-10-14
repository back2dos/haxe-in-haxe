package hxmc.unsafe;

import hxmc.I64;

// POSIX functions of the C library (musl on Linux, libSystem on macOS) the
// runtime's Haxe code calls (hxmc.rt.Sys, hxmc.rt.Net), with the C ABI as
// LibC's. Structures are read at their offsets per target (the callers);
// macOS x86-64 names the 64-bit-inode stat and directory functions with a
// suffix (stat$INODE64), as its headers do. Variadic functions
// (@:hxmc.varargs) pass their variadic arguments as the platform requires
// (on the stack on Apple arm64).
@:hxmc.c extern class Posix {
	static function write(fd:Int, p:Ptr, n:I64):I64;
	static function read(fd:Int, p:Ptr, n:I64):I64;
	@:hxmc.varargs(2) static function open(path:Ptr, flags:Int, mode:Int):Int;
	static function close(fd:Int):Int;
	static function lseek(fd:Int, off:I64, whence:Int):I64;
	@:hxmc.varargs(2) static function fcntl(fd:Int, cmd:Int, arg:Int):Int;
	static function pipe(fds:Ptr):Int;
	static function dup2(a:Int, b:Int):Int;
	static function isatty(fd:Int):Int;
	static function tcgetattr(fd:Int, t:Ptr):Int;
	static function tcsetattr(fd:Int, act:Int, t:Ptr):Int;
	static function getenv(name:Ptr):Ptr;
	static function setenv(name:Ptr, value:Ptr, overwrite:Int):Int;
	static function unsetenv(name:Ptr):Int;
	static function getcwd(buf:Ptr, n:I64):Ptr;
	static function chdir(path:Ptr):Int;
	static function nanosleep(req:Ptr, rem:Ptr):Int;
	static function gettimeofday(tv:Ptr, tz:Ptr):Int;
	static function clock():I64;
	static function readlink(path:Ptr, buf:Ptr, n:I64):I64;
	static function realpath(path:Ptr, buf:Ptr):Ptr;
	static function system(cmd:Ptr):Int;
	static function fork():Int;
	static function execvp(file:Ptr, argv:Ptr):Int;
	static function _exit(code:Int):Void;
	static function exit(code:Int):Void;
	static function fflush(f:Ptr):Int;
	static function waitpid(pid:Int, status:Ptr, options:Int):Int;
	static function kill(pid:Int, sig:Int):Int;
	static function mkdir(path:Ptr, mode:Int):Int;
	static function unlink(path:Ptr):Int;
	static function rmdir(path:Ptr):Int;
	static function rename(a:Ptr, b:Ptr):Int;
	static function stat(path:Ptr, st:Ptr):Int;
	static function fstat(fd:Int, st:Ptr):Int;
	static function opendir(path:Ptr):Ptr;
	static function readdir(d:Ptr):Ptr;
	static function closedir(d:Ptr):Int;
	@:native("stat$INODE64") static function statInode64(path:Ptr, st:Ptr):Int;
	@:native("fstat$INODE64") static function fstatInode64(fd:Int, st:Ptr):Int;
	@:native("opendir$INODE64") static function opendirInode64(path:Ptr):Ptr;
	@:native("readdir$INODE64") static function readdirInode64(d:Ptr):Ptr;
	// errno: musl's location, libSystem's
	static function __errno_location():Ptr;
	static function __error():Ptr;
	static function _NSGetEnviron():Ptr;
	static function realloc(p:Ptr, n:I64):Ptr;
}
