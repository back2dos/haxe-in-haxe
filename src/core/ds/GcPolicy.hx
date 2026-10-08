package core.ds;

/**
	HashLink only: libhl starts a full (non-generational) mark after
	allocating 20% of the heap, so a heap full of typed modules is marked
	over and over. Like OCaml's space_overhead, collect instead when the
	allocation since the last major exceeds `factor` times the heap size seen
	after it. Elsewhere `tick` is a no-op.
**/
class GcPolicy {
	#if hl
	static var counter = 0;
	static var enabled = false;
	static var allocatedAtMajor = 0.;
	static var heapAtMajor = 0.;
	static var factor = 0.5;

	public static function init():Void {
		var v = Sys.getEnv("HAXE_IN_HAXE_GC_FACTOR");
		if (v != null) factor = Std.parseFloat(v);
		if (factor <= 0) return; // 0 keeps libhl's own policy
		enabled = true;
		hl.Gc.enable(false);
		var s = hl.Gc.stats();
		allocatedAtMajor = s.totalAllocated;
		heapAtMajor = Math.max(s.currentMemory, 64 * 1024 * 1024);
	}

	public static inline function tick():Void {
		if (++counter & 0xFFF == 0 && enabled) check();
	}

	static function check():Void {
		var s = hl.Gc.stats();
		if (s.totalAllocated - allocatedAtMajor > factor * heapAtMajor) {
			hl.Gc.major();
			s = hl.Gc.stats();
			allocatedAtMajor = s.totalAllocated;
			heapAtMajor = Math.max(s.currentMemory, 64 * 1024 * 1024);
		}
	}
	#else
	public static inline function init():Void {}
	public static inline function tick():Void {}
	#end
}
