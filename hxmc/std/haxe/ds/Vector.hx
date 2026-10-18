/*
 * Copyright (C)2005-2019 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
// hxmc: haxe/upstream/std/haxe/ds/Vector.hx, its generic (Array) branch, but
// for blit: the runtime's hxmc.rt.Arr.vectorMove, one memmove of the elements
// (with the collector's barrier for references) where upstream's loop reads
// each element of a generic Vector<T> as Dynamic (a Float boxed, a call per
// element and per store).

package haxe.ds;

private typedef VectorData<T> = Array<T>;

/**
	A Vector is a storage of fixed size. It can be faster than Array on some
	targets, and is never slower.

	@see https://haxe.org/manual/std-vector.html
**/
abstract Vector<T>(VectorData<T>) {
	/**
		Creates a new Vector of length `length`.

		Initially `this` Vector contains `length` neutral elements:

		- always null on dynamic targets
		- 0, 0.0 or false for Int, Float and Bool respectively on static targets
		- null for other types on static targets

		If `length` is less than or equal to 0, the result is unspecified.
	**/
	extern overload public inline function new(length:Int) {
		this = [];
		untyped this.length = length;
	}

	/**
		Creates a new Vector of length `length` filled with `defaultValue` elements.

		Can be faster than `new Vector(length)` for iteration on some targets for non-nullable elements.

		If `length` is less than or equal to 0, the result is unspecified.
	**/
	extern overload public inline function new(length:Int, defaultValue:T):Vector<T> {
		this = [];
		untyped this.length = length;
		fill(defaultValue);
	}

	/**
		Returns the value at index `index`.

		If `index` is negative or exceeds `this.length`, the result is
		unspecified.
	**/
	@:op([]) public inline function get(index:Int):T {
		return this[index];
	}

	/**
		Sets the value at index `index` to `val`.

		If `index` is negative or exceeds `this.length`, the result is
		unspecified.
	**/
	@:op([]) public inline function set(index:Int, val:T):T {
		return this[index] = val;
	}

	/**
		Returns the length of `this` Vector.
	**/
	public var length(get, never):Int;

	inline function get_length():Int {
		return untyped this.length;
	}

	/**
		Sets all `length` elements of `this` Vector to `value`.
	**/
	public inline function fill(value:T):Void
		for (i in 0...length) this[i] = value;

	/**
		Copies `length` of elements from `src` Vector, beginning at `srcPos` to
		`dest` Vector, beginning at `destPos`

		The results are unspecified if `length` results in out-of-bounds access,
		or if `src` or `dest` are null
	**/
	public static inline function blit<T>(src:Vector<T>, srcPos:Int, dest:Vector<T>, destPos:Int, len:Int):Void {
		// hxmc: a few elements copied here, typed (cheaper than the call), as
		// upstream's loops copy them (from the end, upward within one vector);
		// otherwise moved by the runtime
		var s = src.toData(), d = dest.toData();
		if (len <= 4 && (s != d || srcPos > destPos)) {
			for (i in 0...len)
				dest[destPos + i] = src[srcPos + i];
		} else if (len <= 4 && srcPos < destPos) {
			var i = len;
			while (i > 0) {
				i--;
				dest[destPos + i] = src[srcPos + i];
			}
		} else if (!hxmc.rt.Arr.vectorMove(s, srcPos, d, destPos, len))
			hxmc.rt.Arr.vectorBlit(s, srcPos, d, destPos, len);
	}

	/**
		Creates a new Array, copy the content from the Vector to it, and returns it.
	**/
	public function toArray():Array<T> {
		var a = new Array();
		var len = length;
		for (i in 0...len)
			a[i] = get(i);
		return a;
	}

	/**
		Extracts the data of `this` Vector.

		This returns the internal representation type.
	**/
	public inline function toData():VectorData<T>
		return cast this;

	/**
		Initializes a new Vector from `data`.

		Since `data` is the internal representation of Vector, this is a no-op.

		If `data` is null, the corresponding Vector is also `null`.
	**/
	static public inline function fromData<T>(data:VectorData<T>):Vector<T>
		return cast data;

	/**
		Creates a new Vector by copying the elements of `array`.

		This always creates a copy, even on platforms where the internal
		representation is Array.

		The elements are not copied and retain their identity, so
		`a[i] == Vector.fromArrayCopy(a).get(i)` is true for any valid i.

		If `array` is null, the result is unspecified.
	**/
	static public inline function fromArrayCopy<T>(array:Array<T>):Vector<T> {
		// TODO: Optimize this for others?
		var vec = new Vector<T>(array.length);
		for (i in 0...array.length)
			vec.set(i, array[i]);
		return vec;
	}

	/**
		Returns a shallow copy of `this` Vector.

		The elements are not copied and retain their identity, so
		`a[i] == a.copy()[i]` is true for any valid `i`. However,
		`a == a.copy()` is always false.
	**/
	extern public inline function copy<T>():Vector<T> {
		var r = new Vector<T>(length);
		Vector.blit(cast this, 0, r, 0, length);
		return r;
	}

	/**
		Returns a string representation of `this` Vector, with `sep` separating
		each element.

		The result of this operation is equal to `Std.string(this[0]) + sep +
		Std.string(this[1]) + sep + ... + sep + Std.string(this[this.length-1])`

		If `this` Vector has length 0, the result is the empty String `""`.
		If `this` has exactly one element, the result is equal to a call to
		`Std.string(this[0])`.

		If `sep` is null, the result is unspecified.
	**/
	extern public inline function join<T>(sep:String):String {
		var b = new StringBuf();
		var len = length;
		for (i in 0...len) {
			b.add(Std.string(get(i)));
			if (i < len - 1) {
				b.add(sep);
			}
		}
		return b.toString();
	}

	/**
		Creates a new Vector by applying function `f` to all elements of `this`.

		The order of elements is preserved.

		If `f` is null, the result is unspecified.
	**/
	extern public inline function map<S>(f:T->S):Vector<S> {
		var length = length;
		var r = new Vector<S>(length);
		var len = length;
		for (i in 0...len) {
			var v = f(get(i));
			r.set(i, v);
		}
		return r;
	}

	/**
		Sorts `this` Vector according to the comparison function `f`, where
		`f(x,y)` returns 0 if x == y, a positive Int if x > y and a
		negative Int if x < y.

		This operation modifies `this` Vector in place.

		The sort operation is not guaranteed to be stable, which means that the
		order of equal elements may not be retained.

		If `f` is null, the result is unspecified.
	**/
	public inline function sort(f:T->T->Int):Void {
		this.sort(f);
	}
}
