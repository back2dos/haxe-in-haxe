package haxe.io;

// hxc target (backend/): Bytes is its own data; indexing reads and writes bytes.
abstract BytesData(Bytes) from Bytes to Bytes {
	public var length(get, never):Int;

	inline function get_length():Int
		return this.length;

	@:arrayAccess inline function get(i:Int):Int
		return this.get(i);

	@:arrayAccess inline function set(i:Int, v:Int):Int {
		this.set(i, v);
		return v;
	}
}
