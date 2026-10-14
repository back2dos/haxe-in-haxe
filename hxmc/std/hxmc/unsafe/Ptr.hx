package hxmc.unsafe;

import hxmc.I64;

// A raw machine address (hxmc/README.md, "Runtime in Haxe"): an int64_t the
// collector neither traces nor moves. The address of a heap object
// (Mem.addr) is valid only until the next GC point: code that keeps one
// across calls is in a function declared @:hxmc.noGc, which the compiler
// checks never reaches a GC point. Internal to the runtime's std.
abstract Ptr(I64) {
	public static inline function nil():Ptr
		return new Ptr(0);

	public inline function new(v:I64)
		this = v;

	public static inline function ofI64(v:I64):Ptr
		return new Ptr(v);

	public inline function toI64():I64
		return this;

	public inline function isNull():Bool
		return this == 0;

	// the address `bytes` further (a signed 32-bit offset)
	public inline function add(bytes:Int):Ptr
		return new Ptr(this + (bytes : I64));

	public inline function addL(bytes:I64):Ptr
		return new Ptr(this + bytes);

	// the byte distance from `p` to this address
	public inline function diff(p:Ptr):I64
		return this - p.toI64();

	@:op(a == b) static inline function eq(a:Ptr, b:Ptr):Bool
		return a.toI64() == b.toI64();

	@:op(a != b) static inline function ne(a:Ptr, b:Ptr):Bool
		return !(a.toI64() == b.toI64());

	// unsigned comparisons (addresses)
	public inline function ult(p:Ptr):Bool
		return Mem.ult(this, p.toI64());

	public inline function uge(p:Ptr):Bool
		return !Mem.ult(this, p.toI64());
}
