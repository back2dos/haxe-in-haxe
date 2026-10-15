package hxmc.rt;

import hxmc.I64;
import hxmc.rt.C;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The slow paths of allocation and reference stores that generated code
// calls (once hxmc/c/rthxmc.c; WebAssembly's are in wasm/Gc.hx): one call
// sequence each, so that every allocation or reference store site has a
// short slow path.
@:hxmc.native @:keep
class GcPaths {
	// rt_alloc_slow with the header assembled here (the type index is a
	// link-time constant: it cannot be shifted into place by the linker)
	@:hxmc.export("hxmc_alloc_slow") @:hxmc.collects static function allocSlow(lo:Int, tindex:Int, bytes:Int):Ptr
		return Rt.rt_alloc_slow(((tindex : I64) << 32) | ((lo : I64) & 0xFFFFFFFF), bytes);

	@:hxmc.noGc static inline function young(p:Ptr):Bool
		return !p.ult(Mem.getPtr(Mem.sym("rt_young_start"), 0)) && p.ult(Mem.getPtr(Mem.sym("rt_young_end"), 0));

	// the rest of the barrier once obj is known not to be young
	@:hxmc.export("hxmc_barrier_slow") @:hxmc.noGc static function barrierSlow(obj:Ptr, slot:Ptr, v:Ptr, prev:Ptr):Void {
		if (young(v) && !young(prev)) Leaf.rt_write_barrier(obj, slot, v);
	}
}
