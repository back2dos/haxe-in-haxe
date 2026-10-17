package hxmc.rt;

import hxmc.I64;
import hxmc.rt.Types.*;
import hxmc.unsafe.Mem;
import hxmc.unsafe.LibC;

// One allocation: length/kind in its first word, followed by packed elements.
// GC scans reference elements, excluding that word. Typed accesses are
// emitted by MirBuild; erased generics use these helpers.
@:keep
class NArray {
	@:hxmc.host("hxmc_NativeArray_copy") static function copy(a:Dynamic):Dynamic {
		var words = Mem.getI32(Mem.addr(a), -8) & 0x0FFFFFFF;
		var kind = Mem.getI32(Mem.addr(a), 4);
		var result = Mem.alloc(words, T_NATIVE_ARRAY, kind == AK_PTR ? K_PARR : K_RAW);
		LibC.memcpy(Mem.addr(result), Mem.addr(a), (words : I64) * 8);
		if (kind == AK_PTR) C.Leaf.rt_barrier_range(result, Mem.addr(result).add(8), Mem.getI32(Mem.addr(result), 0));
		return result;
	}

	@:hxmc.export("hx_narray_bad_length") static function badLength():Void
		throw "Invalid NativeArray length";

	@:hxmc.host("hx_narray_check") static function check(a:Dynamic, kind:Int):Dynamic {
		if (a != null && Mem.getI32(Mem.addr(a), 4) != kind) throw "NativeArray storage type mismatch";
		return a;
	}

	@:hxmc.host("hx_narray_get") public static function get(a:Dynamic, i:Int):Dynamic {
		return switch Mem.getI32(Mem.addr(a), 4) {
			case AK_BOOL: (Mem.getU8At(Mem.addr(a), 8, i) != 0 : Dynamic);
			case AK_I32: (Mem.getI32At(Mem.addr(a), 8, i) : Dynamic);
			case AK_F64: (Mem.getF64At(Mem.addr(a), 8, i) : Dynamic);
			case AK_I64: (Mem.getI64At(Mem.addr(a), 8, i) : Dynamic);
			case _: Mem.getRefAt(Mem.addr(a), 8, i);
		}
	}

	@:hxmc.host("hx_narray_set") public static function set(a:Dynamic, i:Int, value:Dynamic):Void {
		var kind = Mem.getI32(Mem.addr(a), 4);
		if (kind == AK_PTR) {
			Mem.setRefBarrier(a, 8 + 8 * i, value);
			return;
		}
		var t = value == null ? T_BOXINT : tindex(value);
		if (t != T_BOXINT && t != T_BOXBOOL && !(kind == AK_F64 && t == T_BOXFLOAT) && !(kind == AK_I64 && t == T_BOXI64))
			throw "NativeArray element type mismatch";
		switch kind {
			case AK_BOOL: var v:Bool = value; Mem.setU8At(Mem.addr(a), 8, i, v ? 1 : 0);
			case AK_I32: var v:Int = value; Mem.setI32At(Mem.addr(a), 8, i, v);
			case AK_F64: var v:Float = value; Mem.setF64At(Mem.addr(a), 8, i, v);
			case _: var v:I64 = value; Mem.setI64At(Mem.addr(a), 8, i, v);
		}
	}
}
