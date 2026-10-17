package hxmc.rt;

import hxmc.I64;
import hxmc.rt.C;
import hxmc.rt.Types.*;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The Array natives (formerly in rt_std.c): generic natives over arrays of
// any element kind (rt.h: slot 0 the length and the element kind, slot 1
// the data, null while empty; Int and Bool elements take 4 bytes, others 8). The
// element access, growth and kind conversion themselves stay in rt.c with
// the collector (hx_arr_*); here they are the language's own array
// operations on Array<Dynamic>, which go through them.
@:keep @:allow(hxmc.rt)
class Arr {
	static inline function len(a:Dynamic):Int
		return Mem.getI32(Mem.addr(a), 0);

	static inline function setLen(a:Dynamic, n:Int)
		Mem.setI32(Mem.addr(a), 0, n);

	static inline function kindOf(a:Dynamic):Int
		return Mem.getI32(Mem.addr(a), 4);

	static inline function data(a:Dynamic):Ptr
		return Mem.getPtr(Mem.addr(a), 8);

	static inline function elemSize(a:Dynamic):Int
		return ak4(kindOf(a)) ? 4 : 8;

	// a new array of this kind and length (elements zero)
	static function make(kind:Int, n:Int):Dynamic {
		if (n == 0) {
			// `[]`: the data is allocated by the first store
			var a = Mem.alloc(2, T_ARRAY, K_OBJ);
			Mem.setI32(Mem.addr(a), 4, kind);
			return a;
		}
		return Rt.hx_arr_new_n(kind, n);
	}

	// the data of a fresh reference array was written without the barrier
	static inline function barrierAll(a:Dynamic, n:Int) {
		if (kindOf(a) == AK_PTR && n > 0) Leaf.rt_barrier_range(Mem.obj(data(a)), data(a), n);
	}

	@:hxmc.host("Array_copy") static function copy(a:Dynamic):Dynamic {
		var n = len(a);
		var r = make(kindOf(a), n);
		if (n > 0) LibC.memcpy(data(r), data(a), (elemSize(a) * n : I64));
		barrierAll(r, n);
		return r;
	}

	@:hxmc.host("Array_concat") static function concat(a:Dynamic, b:Dynamic):Dynamic {
		if (kindOf(a) == kindOf(b)) {
			// same element kind: one allocation, two copies
			var na = len(a), nb = len(b);
			var r = make(kindOf(a), na + nb);
			if (na + nb > 0) {
				var es = elemSize(a);
				if (na > 0) LibC.memcpy(data(r), data(a), (es * na : I64));
				if (nb > 0) LibC.memcpy(data(r).add(es * na), data(b), (es * nb : I64));
				barrierAll(r, na + nb);
			}
			return r;
		}
		var r:Array<Dynamic> = copy(a);
		var bb:Array<Dynamic> = b;
		var i = 0;
		while (i < bb.length) {
			r.push(bb[i]);
			i++;
		}
		return r;
	}

	static function indexFrom(a:Dynamic, x:Dynamic, from:Int):Int {
		var n = len(a);
		if (from < 0) {
			from += n;
			if (from < 0) from = 0;
		}
		switch kindOf(a) {
			case AK_I32:
				if (Str.isNull(x)) return -1;
				if (tindex(x) == T_BOXFLOAT) {
					var f = Mem.getF64(Mem.addr(x), 0);
					if (f != Math.ffloor(f)) return -1;
				}
				var v:Int = x;
				var d = data(a);
				for (i in from...n)
					if (Mem.getI32At(d, 0, i) == v) return i;
				return -1;
			case AK_BOOL:
				if (Str.isNull(x) || tindex(x) != T_BOXBOOL) return -1;
				var v = Mem.getI32(Mem.addr(x), 0);
				var d = data(a);
				for (i in from...n)
					if (Mem.getI32At(d, 0, i) == v) return i;
				return -1;
			case AK_F64:
				if (Str.isNull(x)) return -1;
				var v:Float = x;
				var d = data(a);
				for (i in from...n)
					if (Mem.getF64At(d, 0, i) == v) return i;
				return -1;
			case _:
				for (i in from...n) {
					var e = Mem.getRefAt(data(a), 0, i);
					if (Mem.addr(e) == Mem.addr(x) || Dyn.dynEq(e, x)) return i;
				}
				return -1;
		}
	}

	@:hxmc.host("Array_indexOf") static function indexOf(a:Dynamic, x:Dynamic, from:Null<Int>):Int
		return indexFrom(a, x, from == null ? 0 : from);

	@:hxmc.host("Array_lastIndexOf") static function lastIndexOf(a:Dynamic, x:Dynamic, from:Null<Int>):Int {
		var n = len(a);
		var f:Int = from == null ? n - 1 : from;
		if (f < 0) f += n;
		if (f >= n) f = n - 1;
		var i = f;
		while (i >= 0) {
			if (kindOf(a) == AK_PTR) {
				var e = Mem.getRefAt(data(a), 0, i);
				if (Mem.addr(e) == Mem.addr(x) || Dyn.dynEq(e, x)) return i;
			} else if (kindOf(a) == AK_BOOL) {
				if (!Str.isNull(x) && tindex(x) == T_BOXBOOL && Mem.getI32At(data(a), 0, i) == Mem.getI32(Mem.addr(x), 0)) return i;
			} else if (!Str.isNull(x)) {
				var v:Float = x;
				var e = kindOf(a) == AK_I32 ? (Mem.getI32At(data(a), 0, i) : Float) : kindOf(a) == AK_F64 ? Mem.getF64At(data(a), 0, i) : {
					var l:Float = cast Mem.getI64At(data(a), 0, i);
					l;
				};
				if (e == v) return i;
			}
			i--;
		}
		return -1;
	}

	@:hxmc.host("Array_contains") static function contains(a:Dynamic, x:Dynamic):Bool
		return indexFrom(a, x, 0) >= 0;

	// removes element i, shifting the rest down
	static function removeAt(a:Dynamic, i:Int) {
		var n = len(a), es = elemSize(a);
		var d = data(a);
		LibC.memmove(d.add(es * i), d.add(es * (i + 1)), (es * (n - i - 1) : I64));
		LibC.memset(d.add(es * (n - 1)), 0, es);
		if (kindOf(a) == AK_PTR && n - i - 1 > 0) Leaf.rt_barrier_range(Mem.obj(d), d.add(8 * i), n - i - 1);
		setLen(a, n - 1);
	}

	@:hxmc.host("Array_remove") static function remove(a:Dynamic, x:Dynamic):Bool {
		var i = indexFrom(a, x, 0);
		if (i < 0) return false;
		removeAt(a, i);
		return true;
	}

	@:hxmc.host("Array_pop") static function pop(a:Dynamic):Dynamic {
		var n = len(a);
		if (n == 0) return null;
		var v = (a : Array<Dynamic>)[n - 1];
		LibC.memset(data(a).add(elemSize(a) * (n - 1)), 0, elemSize(a));
		setLen(a, n - 1);
		return v;
	}

	@:hxmc.host("Array_shift") static function shift(a:Dynamic):Dynamic {
		if (len(a) == 0) return null;
		var v = (a : Array<Dynamic>)[0];
		removeAt(a, 0);
		return v;
	}

	@:hxmc.host("Array_insert") static function insert(a:Dynamic, pos:Int, x:Dynamic):Void {
		var n = len(a);
		if (pos < 0) {
			pos += n;
			if (pos < 0) pos = 0;
		}
		// grows (and converts the kind if needed); the length may have changed
		// meanwhile (another thread at the allocation)
		var arr:Array<Dynamic> = a;
		arr.push(x);
		n = len(a) - 1;
		if (pos > n) pos = n;
		var es = elemSize(a);
		var d = data(a);
		var tmp = es == 4 ? (Mem.getI32(d, 4 * n) : I64) : Mem.getI64(d, 8 * n);
		LibC.memmove(d.add(es * (pos + 1)), d.add(es * pos), (es * (n - pos) : I64));
		if (es == 4) Mem.setI32(d, 4 * pos, tmp.toInt()) else Mem.setI64(d, 8 * pos, tmp);
		if (kindOf(a) == AK_PTR) Leaf.rt_barrier_range(Mem.obj(d), d.add(8 * pos), n - pos + 1);
	}

	@:hxmc.host("Array_unshift") static function unshift(a:Dynamic, x:Dynamic):Void
		insert(a, 0, x);

	@:hxmc.host("Array_resize") @:access(hxmc.rt.Boxes) static function resize(a:Dynamic, n:Int):Void {
		var m = len(a);
		if (n < m) {
			LibC.memset(data(a).add(elemSize(a) * n), 0, (elemSize(a) * (m - n) : I64));
			setLen(a, n);
			return;
		}
		if (n == m) return;
		// past the capacity (haxe.ds.Vector's constructor: from empty), the data
		// allocated at the new length, the elements copied once (the new ones
		// zero, the kind kept), unless another thread changed the array meanwhile
		var kind = kindOf(a);
		if (n > Boxes.arrCap(a)) {
			var d0 = data(a);
			var nd:Dynamic = Boxes.dataAlloc(kind, n);
			var k = len(a);
			if (data(a) == d0 && kindOf(a) == kind && k <= n) {
				if (k > 0) {
					LibC.memcpy(Mem.addr(nd), data(a), (elemSize(a) * k : I64));
					if (kind == AK_PTR && !Boxes.inYoungObj(nd)) Boxes.Gc_barrierRange(nd, k);
				}
				Mem.setRefBarrier(a, 8, nd);
				setLen(a, n);
				return;
			}
		}
		// a store past the end grows the array (zeros in between, the kind kept)
		var arr:Array<Dynamic> = a;
		arr[n - 1] = null;
	}

	@:hxmc.host("Array_reverse") @:hxmc.noGc static function reverse(a:Dynamic):Void {
		var n = len(a);
		if (n < 2) return;
		var d = data(a);
		var i = 0, j = n - 1;
		if (elemSize(a) == 4)
			while (i < j) {
				var t = Mem.getI32At(d, 0, i);
				Mem.setI32At(d, 0, i, Mem.getI32At(d, 0, j));
				Mem.setI32At(d, 0, j, t);
				i++;
				j--;
			}
		else
			while (i < j) {
				var t = Mem.getI64At(d, 0, i);
				Mem.setI64At(d, 0, i, Mem.getI64At(d, 0, j));
				Mem.setI64At(d, 0, j, t);
				i++;
				j--;
			}
		if (kindOf(a) == AK_PTR) Leaf.rt_barrier_range(Mem.obj(d), d, n);
	}

	@:hxmc.host("Array_slice") static function slice(a:Dynamic, pos:Int, endp:Null<Int>):Dynamic {
		var n = len(a);
		var end:Int = endp == null ? n : endp;
		if (pos < 0) {
			pos += n;
			if (pos < 0) pos = 0;
		}
		if (end < 0) end += n;
		if (end > n) end = n;
		var l = end > pos ? end - pos : 0;
		var r = make(kindOf(a), l);
		if (l > 0) LibC.memcpy(data(r), data(a).add(elemSize(a) * pos), (elemSize(a) * l : I64));
		barrierAll(r, l);
		return r;
	}

	@:hxmc.host("Array_splice") static function splice(a:Dynamic, pos:Int, l:Int):Dynamic {
		var n = len(a);
		if (pos < 0) {
			pos += n;
			if (pos < 0) pos = 0;
		}
		if (pos > n) pos = n;
		if (l < 0) l = 0;
		if (pos + l > n) l = n - pos;
		var r = make(kindOf(a), l);
		var es = elemSize(a);
		var d = data(a);
		if (l > 0) LibC.memcpy(data(r), d.add(es * pos), (es * l : I64));
		if (n > 0) {
			LibC.memmove(d.add(es * pos), d.add(es * (pos + l)), (es * (n - pos - l) : I64));
			LibC.memset(d.add(es * (n - l)), 0, (es * l : I64));
		}
		setLen(a, n - l);
		if (kindOf(a) == AK_PTR) {
			barrierAll(r, l);
			if (n - pos - l > 0) Leaf.rt_barrier_range(Mem.obj(d), d.add(8 * pos), n - pos - l);
		}
		return r;
	}

	@:hxmc.host("Array_join") static function join(a:Dynamic, sep:String):String {
		var arr:Array<Dynamic> = a;
		var b = new StringBuf();
		var i = 0;
		while (i < arr.length) {
			if (i > 0) b.add(sep);
			b.add(arr[i]);
			i++;
		}
		return b.toString();
	}

	@:hxmc.host("Array_toString") static function toString(a:Dynamic):String
		return Dyn.stdString(a);

	// a stable merge sort over boxed copies (the comparator may allocate);
	// the result written back through the array's own stores (its kind kept)
	@:hxmc.host("Array_sort") static function sort(a:Dynamic, f:Dynamic->Dynamic->Int):Void {
		var arr:Array<Dynamic> = a;
		var n = arr.length;
		if (n < 2) return;
		var src:Array<Dynamic> = [];
		src.resize(n);
		for (i in 0...n)
			src[i] = arr[i];
		var dst:Array<Dynamic> = [];
		dst.resize(n);
		var width = 1;
		while (width < n) {
			var lo = 0;
			while (lo < n) {
				var mid = lo + width < n ? lo + width : n;
				var hi = lo + 2 * width < n ? lo + 2 * width : n;
				var i = lo, j = mid, k = lo;
				while (i < mid && j < hi) {
					if (f(src[j], src[i]) < 0) dst[k++] = src[j++] else dst[k++] = src[i++];
				}
				while (i < mid)
					dst[k++] = src[i++];
				while (j < hi)
					dst[k++] = src[j++];
				lo += 2 * width;
			}
			var t = src;
			src = dst;
			dst = t;
			width *= 2;
		}
		for (i in 0...n)
			arr[i] = src[i];
	}

	@:hxmc.host("Array_filter") static function filter(a:Dynamic, f:Dynamic->Bool):Dynamic {
		var arr:Array<Dynamic> = a;
		var r:Array<Dynamic> = make(kindOf(a), 0);
		var i = 0;
		while (i < arr.length) {
			var v = arr[i];
			if (f(v)) r.push(v);
			i++;
		}
		return r;
	}

	@:hxmc.host("Array_map") static function map(a:Dynamic, f:Dynamic->Dynamic):Dynamic {
		var arr:Array<Dynamic> = a;
		var r:Array<Dynamic> = [];
		var i = 0;
		while (i < arr.length) {
			r.push(f(arr[i]));
			i++;
		}
		return r;
	}
}
