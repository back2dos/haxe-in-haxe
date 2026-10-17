import haxe.ds.Vector;

// expect: new NativeArray<T> requires a known element type
class VectorErased {
	static function make<T>(n:Int):Vector<T> return new Vector<T>(n);
	static function main() {
		var v:Vector<Int> = make(2);
		Sys.println(v[0]);
	}
}
