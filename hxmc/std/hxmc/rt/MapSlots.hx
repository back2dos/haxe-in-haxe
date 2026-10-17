package hxmc.rt;

// The storage of haxe.ds.IntMap, StringMap and ObjectMap: fixed-size arrays
// of zeros, false or nulls, read and written without the test of the index
// (the maps keep theirs in bounds). A NativeArray (one allocation, Int and
// Bool elements packed); an Array under WasmGC, which has no NativeArray.
// The element type must be a concrete one (Int, Bool, Dynamic): made for an
// erased type parameter, a NativeArray is a wrapper (rt/NArray).
abstract MapSlots<T>(#if hxmc.wasm_gc Array<T> #else hxmc.NativeArray<T> #end) {
	public inline function new(n:Int) {
		#if hxmc.wasm_gc
		this = [];
		this.resize(n);
		#else
		this = new hxmc.NativeArray<T>(n);
		#end
	}

	@:op([]) inline function get(i:Int):T
		return #if hxmc.wasm_gc this[i] #else this.unsafeGet(i) #end;

	@:op([]) inline function set(i:Int, v:T):T {
		#if hxmc.wasm_gc
		this[i] = v;
		#else
		this.unsafeSet(i, v);
		#end
		return v;
	}
}
