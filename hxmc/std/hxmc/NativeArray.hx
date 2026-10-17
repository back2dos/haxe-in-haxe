package hxmc;

/**
	Fixed-size, GC-managed storage specialized for its element type.

	Bool uses 8-bit elements, Int uses 32 bits, Float and Int64 use 64 bits,
	and other types use references (including boxed nullable numbers).
	Elements start at zero, false or null. Indices must be in 0...length;
	out-of-bounds access and casts between different storage types are unsafe.
	Conversions to and from Array copy the elements.
	Constructing NativeArray<T> while T is erased requires `@:generic` on
	the enclosing function or class;
	ordinary generic functions can read and write existing native arrays.
**/
@:final extern class NativeArray<T> implements ArrayAccess<T> {
	public var length(default, never):Int;
	public function new(length:Int):Void;

	public inline function fill(value:T):Void {
		for (i in 0...length) this[i] = value;
	}

	// Preserve the runtime element layout even when T is erased.
	public function copy():NativeArray<T>;

	public inline function toArray():Array<T> {
		var result:Array<T> = [];
		result.resize(length);
		for (i in 0...length) result[i] = this[i];
		return result;
	}

	public static inline function fromArray<T>(array:Array<T>):NativeArray<T> {
		var result = new NativeArray<T>(array.length);
		for (i in 0...array.length) result[i] = array[i];
		return result;
	}

	public static inline function blit<T>(src:NativeArray<T>, srcPos:Int, dest:NativeArray<T>, destPos:Int, length:Int):Void {
		if (src == dest && srcPos < destPos) {
			var i = length;
			while (i > 0) {
				i--;
				dest[destPos + i] = src[srcPos + i];
			}
		} else {
			for (i in 0...length) dest[destPos + i] = src[srcPos + i];
		}
	}

	public inline function iterator():NativeArrayIterator<T> return new NativeArrayIterator(this);
}

@:generic class NativeArrayIterator<T> {
	var array:NativeArray<T>;
	var index = 0;
	public inline function new(array:NativeArray<T>) this.array = array;
	public inline function hasNext():Bool return index < array.length;
	public inline function next():T return array[index++];
}
