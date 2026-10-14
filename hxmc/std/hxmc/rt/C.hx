package hxmc.rt;

import hxmc.I64;
import hxmc.unsafe.Ptr;

// The runtime's remaining C functions (hxmc/rt) that its Haxe code calls,
// by their symbols. Rt's may collect (GC points, as generated code's calls
// of the runtime); Leaf's never do (hxmc/README.md, "Runtime in Haxe").
@:hxmc.rt extern class Rt {
	static function hx_std_string(v:Dynamic):String;
	static function hx_is(v:Dynamic, t:Dynamic):Bool;
	static function hx_throw_str(msg:Ptr):Void;
}

@:hxmc.c extern class Leaf {
	// shortest round-trip formatting of a double, as JavaScript does (rt_str.c: printf and strtod)
	static function hx_format_float(v:Float, out:Ptr):Void;
}
