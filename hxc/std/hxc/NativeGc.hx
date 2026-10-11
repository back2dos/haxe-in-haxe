package hxc;

// The GC's finalisers (rt.c), for Eval's Gc.finalise. `f` is called with `v`
// once a major collection finds `v` unreachable (`v` lives on for the call);
// values outside the heap are never collected. Also the heap measurements of
// the port's server/memory (context/Memory.hx).
extern class NativeGc {
	static function finalise(f:Dynamic->Void, v:Dynamic):Void;
	static function collect(full:Bool):Void; // a minor (false) or major (true) collection
	static function runFinalisers():Void; // the queued calls; an exception escapes
	// the bytes of the heap objects reachable from `v` (headers included),
	// without entering `exclude` or `out`; `reached()` tells whether an object
	// of `out` was reachable (OCaml's Objsize, for the port's server/memory)
	static function objsize(v:Dynamic, exclude:Array<Dynamic>, out:Array<Dynamic>):Float;
	static function reached():Bool;
	static function heapBytes():Float; // the heap spaces' size
}
