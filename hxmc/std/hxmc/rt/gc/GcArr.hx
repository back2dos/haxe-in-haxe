package hxmc.rt.gc;

// -D hxmc.wasm-gc: Array's methods over arrays of any element kind (W.arr*:
// elements boxed in and out), as hxmc.rt.Arr's
@:keep @:hxmc.wasmgc
class GcArr {
	@:hxmc.host("Array_copy") static function copy(a:Dynamic):Dynamic {
		var n = W.arrLen(a), r = W.arrNew(W.arrKind(a), n);
		W.arrBlit(r, 0, a, 0, n);
		return r;
	}

	@:hxmc.host("Array_concat") static function concat(a:Dynamic, b:Dynamic):Dynamic {
		var na = W.arrLen(a), nb = W.arrLen(b), r = W.arrNew(W.arrKind(a), na + nb);
		W.arrBlit(r, 0, a, 0, na);
		if (W.arrKind(b) == W.arrKind(a)) W.arrBlit(r, na, b, 0, nb) else for (i in 0...nb)
			W.arrSet(r, na + i, W.arrGet(b, i));
		return r;
	}

	@:hxmc.host("Array_indexOf") static function indexOf(a:Dynamic, x:Dynamic, from:Null<Int>):Int {
		var n = W.arrLen(a), i = from == null ? 0 : from;
		if (i < 0) {
			i += n;
			if (i < 0) i = 0;
		}
		while (i < n) {
			if (GcDyn.eq(W.arrGet(a, i), x)) return i;
			i++;
		}
		return -1;
	}

	@:hxmc.host("Array_lastIndexOf") static function lastIndexOf(a:Dynamic, x:Dynamic, from:Null<Int>):Int {
		var n = W.arrLen(a), i = from == null ? n - 1 : from;
		if (i >= n) i = n - 1;
		if (i < 0) i += n;
		while (i >= 0) {
			if (GcDyn.eq(W.arrGet(a, i), x)) return i;
			i--;
		}
		return -1;
	}

	@:hxmc.host("Array_contains") static function contains(a:Dynamic, x:Dynamic):Bool
		return indexOf(a, x, 0) >= 0;

	@:hxmc.host("Array_remove") static function remove(a:Dynamic, x:Dynamic):Bool {
		var i = indexOf(a, x, 0);
		if (i < 0) return false;
		splice(a, i, 1);
		return true;
	}

	@:hxmc.host("Array_pop") static function pop(a:Dynamic):Dynamic {
		var n = W.arrLen(a);
		if (n == 0) return null;
		var v = W.arrGet(a, n - 1);
		W.arrSetLen(a, n - 1);
		return v;
	}

	@:hxmc.host("Array_shift") static function shift(a:Dynamic):Dynamic {
		var n = W.arrLen(a);
		if (n == 0) return null;
		var v = W.arrGet(a, 0);
		W.arrBlit(a, 0, a, 1, n - 1);
		W.arrSetLen(a, n - 1);
		return v;
	}

	@:hxmc.host("Array_insert") static function insert(a:Dynamic, pos:Int, x:Dynamic):Void {
		var n = W.arrLen(a);
		if (pos < 0) {
			pos += n + 1;
			if (pos < 0) pos = 0;
		} else if (pos > n) pos = n;
		W.arrSetLen(a, n + 1);
		W.arrBlit(a, pos + 1, a, pos, n - pos);
		W.arrSet(a, pos, x);
	}

	@:hxmc.host("Array_unshift") static function unshift(a:Dynamic, x:Dynamic):Void
		insert(a, 0, x);

	@:hxmc.host("Array_resize") static function resize(a:Dynamic, n:Int):Void
		W.arrSetLen(a, n);

	@:hxmc.host("Array_reverse") @:hxmc.noGc static function reverse(a:Dynamic):Void {
		var i = 0, j = W.arrLen(a) - 1;
		while (i < j) {
			var t = W.arrGet(a, i);
			W.arrSet(a, i, W.arrGet(a, j));
			W.arrSet(a, j, t);
			i++;
			j--;
		}
	}

	@:hxmc.host("Array_slice") static function slice(a:Dynamic, pos:Int, endp:Null<Int>):Dynamic {
		var n = W.arrLen(a), end = endp == null ? n : endp;
		if (pos < 0) {
			pos += n;
			if (pos < 0) pos = 0;
		}
		if (end < 0) end += n;
		if (end > n) end = n;
		var len = end - pos;
		if (len < 0) len = 0;
		var r = W.arrNew(W.arrKind(a), len);
		if (len > 0) W.arrBlit(r, 0, a, pos, len);
		return r;
	}

	@:hxmc.host("Array_splice") static function splice(a:Dynamic, pos:Int, l:Int):Dynamic {
		var n = W.arrLen(a);
		if (l < 0 || pos > n) return W.arrNew(W.arrKind(a), 0);
		if (pos < 0) {
			pos += n;
			if (pos < 0) pos = 0;
		}
		if (pos + l > n) l = n - pos;
		var r = W.arrNew(W.arrKind(a), l);
		W.arrBlit(r, 0, a, pos, l);
		W.arrBlit(a, pos, a, pos + l, n - pos - l);
		W.arrSetLen(a, n - l);
		return r;
	}

	@:hxmc.host("Array_join") static function join(a:Dynamic, sep:String):String {
		var b = new GcBuf();
		for (i in 0...W.arrLen(a)) {
			if (i > 0) b.add(sep);
			b.add(GcDyn.string(W.arrGet(a, i)));
		}
		return GcStr.sub(b.chars, 0, b.len);
	}

	@:hxmc.host("Array_toString") static function toString(a:Dynamic):String
		return "[" + join(a, ",") + "]";

	@:hxmc.host("Array_sort") static function sort(a:Dynamic, f:Dynamic->Dynamic->Int):Void {
		// (a stable merge sort over the boxed elements)
		var n = W.arrLen(a);
		if (n < 2) return;
		var xs:Array<Dynamic> = [for (i in 0...n) W.arrGet(a, i)];
		var tmp:Array<Dynamic> = [for (i in 0...n) null];
		var width = 1;
		while (width < n) {
			var lo = 0;
			while (lo < n) {
				var mid = lo + width < n ? lo + width : n, hi = lo + 2 * width < n ? lo + 2 * width : n;
				var i = lo, j = mid, k = lo;
				while (i < mid && j < hi)
					tmp[k++] = f(xs[j], xs[i]) < 0 ? xs[j++] : xs[i++];
				while (i < mid)
					tmp[k++] = xs[i++];
				while (j < hi)
					tmp[k++] = xs[j++];
				lo += 2 * width;
			}
			var t = xs;
			xs = tmp;
			tmp = t;
			width *= 2;
		}
		for (i in 0...n)
			W.arrSet(a, i, xs[i]);
	}

	@:hxmc.host("Array_filter") static function filter(a:Dynamic, f:Dynamic->Bool):Dynamic {
		var r = W.arrNew(W.arrKind(a), 0), k = 0;
		for (i in 0...W.arrLen(a)) {
			var x = W.arrGet(a, i);
			if (f(x)) W.arrSet(r, k++, x);
		}
		return r;
	}

	@:hxmc.host("Array_map") static function map(a:Dynamic, f:Dynamic->Dynamic):Dynamic {
		var r:Array<Dynamic> = [];
		for (i in 0...W.arrLen(a))
			r.push(f(W.arrGet(a, i)));
		return r;
	}
}
