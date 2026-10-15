package hxmc.rt;

import hxmc.I64;
import hxmc.unsafe.Ptr;

// Runtime functions the runtime's Haxe code calls by their symbols (once
// hxmc/c's; their implementations are Haxe now: Lower binds the calls to
// them, or, for the safe region's markers, keeps the calls by symbol so that
// Facts tells the functions that enter one). Rt's may collect (GC points, as
// generated code's calls of the runtime); Leaf's never do (README.md,
// "Runtime in Haxe").
@:hxmc.rt extern class Rt {
	static function rt_throw(v:Dynamic):Void; // (does not return; Start)
	// an array of this element kind with `len` elements (zero; Boxes)
	static function hx_arr_new_n(kind:Int, len:Int):Dynamic;
	// waits until fd is readable (0) or writable (1) letting other threads
	// run (1 ready, 0 timeout, -1 closed meanwhile); sleeps (<= 0: gives way;
	// Threads)
	static function rt_wait_fd(fd:Int, write:Int, timeout:Float):Int;
	static function rt_sleep(seconds:Float):Void;
	// waits for any of n struct pollfd (revents set), letting other threads run (Threads)
	static function rt_wait_fds(pollfds:Ptr, n:Int, timeout:Float):Int;
	// a T_NATIVE object holding the C resource p (slot 0) and nrefs reference
	// slots; the collector calls free(p) (a no-GC @:hxmc.callback or a C
	// function) once it is unreachable (Gc)
	static function rt_native_new_refs(p:Ptr, free:Ptr, nrefs:Int):Dynamic;
	// the allocation slow path (the header word, the size in bytes; Gc)
	static function rt_alloc_slow(header:I64, bytes:Int):Ptr;
}

@:hxmc.c @:hxmc.fast extern class Leaf {
	// remembers the references [from, from + n) of an old object (Gc)
	static function rt_barrier_range(obj:Dynamic, from:Ptr, n:Int):Void;
	// remembers slot of the old object obj, which now holds the young v (Gc)
	static function rt_write_barrier(obj:Ptr, slot:Ptr, v:Ptr):Void;
	// the running thread's id (Threads)
	static function hxmc_NativeThread_current():Int;
	// a safe region (a blocking call holding no heap address: a collection
	// may run meanwhile); before close(fd): waiters fail (Threads)
	static function rt_blocking_enter():Void;
	static function rt_blocking_leave():Void;
	static function rt_fd_closed(fd:Int):Void;
}
