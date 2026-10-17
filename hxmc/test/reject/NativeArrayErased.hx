// expect: new NativeArray<T> requires a known element type
// expect: NativeArrayErased.hx:8
// expect: in NativeArrayErased_make
import hxmc.NativeArray;

class NativeArrayErased {
	static function make<T>(length:Int, value:T):NativeArray<T> {
		var a = new NativeArray<T>(length);
		a[0] = value;
		return a;
	}
	static function main() Sys.println(make(3, 12)[0]);
}
