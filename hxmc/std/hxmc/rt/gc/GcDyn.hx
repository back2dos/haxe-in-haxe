package hxmc.rt.gc;

// -D hxmc.wasm-gc: Dynamic's comparisons and printing (W.kind), as hxmc.rt.Dyn's
@:keep @:hxmc.wasmgc
class GcDyn {
	@:hxmc.host("hx_dyn_eq") @:hxmc.noGc public static function eq(a:Dynamic, b:Dynamic):Bool {
		var ka = W.kind(a), kb = W.kind(b);
		if ((ka == 1 || ka == 2) && (kb == 1 || kb == 2)) return W.unboxFloat(a) == W.unboxFloat(b);
		if (ka == 3 && kb == 3) return W.unboxBool(a) == W.unboxBool(b);
		if (ka == 4 && kb == 4) return (a : String) == (b : String);
		return same(a, b);
	}

	// the same reference (or both null)
	static inline function same(a:Dynamic, b:Dynamic):Bool
		return W.same(a, b);

	@:hxmc.host("hx_dyn_cmp") @:hxmc.noGc static function cmp(a:Dynamic, b:Dynamic):Int {
		var ka = W.kind(a), kb = W.kind(b);
		if ((ka == 1 || ka == 2) && (kb == 1 || kb == 2)) {
			var x = W.unboxFloat(a), y = W.unboxFloat(b);
			return x < y ? -1 : x > y ? 1 : 0;
		}
		if (ka == 4 && kb == 4) return GcStr.cmp(a, b);
		return eq(a, b) ? 0 : -1;
	}

	// (for the generated code's enum comparisons: hxmc.wasmgc.Meta.enumEq)
	@:hxmc.export("gc_dyn_eq") static function dynEqExport(a:Dynamic, b:Dynamic):Bool
		return eq(a, b);

	public static function string(v:Dynamic):String
		return GcStr.dynString(v);
}
