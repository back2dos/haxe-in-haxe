package hxc;

// hxc target (hxc/): the GC's finalisers (rt.c), for Eval's Gc.finalise.
// `f` is called with `v` once a major collection finds `v` unreachable (`v`
// lives on for the call); values outside the heap are never collected.
extern class NativeGc {
	static function finalise(f:Dynamic->Void, v:Dynamic):Void;
	static function collect(full:Bool):Void; // a minor (false) or major (true) collection
	static function runFinalisers():Void; // the queued calls; an exception escapes
}
