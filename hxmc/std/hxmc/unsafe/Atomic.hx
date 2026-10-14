package hxmc.unsafe;

import hxmc.I64;

// Atomic memory operations, sequentially consistent, expanded inline
// (x86-64: mov/xchg/lock xadd/lock cmpxchg/mfence; arm64: ldar/stlr and
// ldaxr/stlxr loops, dmb ish: no LSE needed). The read-modify-write
// operations return the previous value. Internal to the runtime's std.
extern class Atomic {
	static function load32(p:Ptr):Int;
	static function load64(p:Ptr):I64;
	static function store32(p:Ptr, v:Int):Void;
	static function store64(p:Ptr, v:I64):Void;
	static function add32(p:Ptr, v:Int):Int;
	static function add64(p:Ptr, v:I64):I64;
	static function exchange32(p:Ptr, v:Int):Int;
	static function exchange64(p:Ptr, v:I64):I64;
	static function cas32(p:Ptr, expected:Int, replacement:Int):Int;
	static function cas64(p:Ptr, expected:I64, replacement:I64):I64;
	static function fence():Void;
}
