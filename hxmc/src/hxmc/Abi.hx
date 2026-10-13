package hxmc;

// Facts about the runtime (hxc/rt) and the target's C library that the
// generated code depends on. The struct layouts are the same on every
// 64-bit target; the jmp_buf of rt_handler is not (hxmc/tools/probe.c
// prints them all).
class Abi {
	// rt_type
	public static inline var TYPE_SIZE = 112;
	public static inline var TYPE_TAG = 80;
	// rt_icache: uint32 t, int32 slot, char kind, void *fn, int32 sig
	public static inline var IC_SIZE = 32;
	public static inline var IC_SLOT = 4;
	public static inline var IC_KIND = 8;
	public static inline var IC_FN = 16;
	public static inline var IC_SIG = 24;
	// object header (rt.h): the type index is bits 32..47, i.e. the 16-bit
	// word at payload - 4; the kind bits 28..31 of the word at payload - 8
	public static inline var HDR_TINDEX = -4;
	public static inline var T_FIRST = 32;
	public static inline var T_ARRAY = 5;
	public static inline var T_REFBOX_P = 11;
	public static inline var T_REFBOX_I = 12;
	public static inline var T_REFBOX_F = 13;
	public static inline var K_OBJ = 0;
	public static inline var K_PARR = 1;
	public static inline var K_RAW = 2;
	public static inline var AK_PTR = 0;
	public static inline var AK_I32 = 1;
	public static inline var AK_F64 = 2;
	public static inline var AK_I64 = 3;

	public var name:String; // linux-x86_64, ...
	public var arm:Bool;
	public var os:String; // linux, macos, windows
	public var handlerSize:Int;
	public var handlerPrev:Int;
	public var handlerSp:Int;
	public var handlerAlign:Int;
	public var setjmp:String; // the C library's setjmp without the signal mask
	public var symPrefix:String; // "_" on macOS

	function new(name, arm, os, size, prev, sp, align, setjmp, prefix) {
		this.name = name;
		this.arm = arm;
		this.os = os;
		handlerSize = size;
		handlerPrev = prev;
		handlerSp = sp;
		handlerAlign = align;
		this.setjmp = setjmp;
		symPrefix = prefix;
	}

	public static function get(target:String):Abi
		return switch target {
			case "linux-x86_64": new Abi(target, false, "linux", 216, 200, 208, 8, "_setjmp", "");
			case "linux-arm64": new Abi(target, true, "linux", 328, 312, 320, 8, "_setjmp", "");
			case "macos-arm64": new Abi(target, true, "macos", 208, 192, 200, 8, "_setjmp", "_");
			case "macos-x86_64": new Abi(target, false, "macos", 168, 152, 160, 8, "_setjmp", "_");
			case "windows-x86_64": new Abi(target, false, "windows", 272, 256, 264, 16, "_setjmp", "");
			case "windows-arm64": new Abi(target, true, "windows", 208, 192, 200, 8, "__mingw_setjmp", "");
			case _: throw "hxmc: unknown target " + target + " (linux-x86_64, linux-arm64, macos-arm64, macos-x86_64, windows-x86_64, windows-arm64)";
		}
}
