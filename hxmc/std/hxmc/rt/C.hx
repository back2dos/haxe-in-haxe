package hxmc.rt;

import hxmc.I64;
import hxmc.unsafe.Ptr;

// The runtime's remaining C functions (hxmc/rt) that its Haxe code calls,
// by their symbols. Rt's may collect (GC points, as generated code's calls
// of the runtime); Leaf's never do (hxmc/README.md, "Runtime in Haxe").
@:hxmc.rt extern class Rt {
	static function rt_throw(v:Dynamic):Void; // (does not return)
	// a field name as a String (an immortal copy outside the heap, made once: rt_dyn.c)
	static function hx_fid_str(fid:Int):String;
	// rt.c: an array of this element kind with `len` elements (zero)
	static function hx_arr_new_n(kind:Int, len:Int):Dynamic;
	// rt_thread.c: waits until fd is readable (0) or writable (1) letting
	// other threads run (1 ready, 0 timeout, -1 closed meanwhile); sleeps
	// (<= 0: gives way)
	static function rt_wait_fd(fd:Int, write:Int, timeout:Float):Int;
	static function rt_sleep(seconds:Float):Void;
}

@:hxmc.c extern class Leaf {
	// shortest round-trip formatting of a double, as JavaScript does (rt_str.c: printf and strtod)
	static function hx_format_float(v:Float, out:Ptr):Void;
	// the field-name table (rt_dyn.c): a name's id (interned), the id of a
	// name if it has one (else -1), an id's name (UTF-8)
	static function hx_fid_slow(name:String):Int;
	static function hx_fid_find(name:String):Int;
	static function hx_fid_name(fid:Int):Ptr;
	// rt.c: remembers the references [from, from + n) of an old object
	static function rt_barrier_range(obj:Dynamic, from:Ptr, n:Int):Void;
	// rt_thread.c: the running thread's id
	static function hxmc_NativeThread_current():Int;
	// rt_thread.c: a safe region (a blocking call holding no heap address:
	// a collection may run meanwhile); before close(fd): waiters fail
	static function rt_blocking_enter():Void;
	static function rt_blocking_leave():Void;
	static function rt_fd_closed(fd:Int):Void;
}
