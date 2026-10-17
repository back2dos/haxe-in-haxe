// define: hxmc.check-vector-access
import haxe.ds.Vector;
import haxe.Int64;
import haxe.exceptions.ArgumentException;
import hxmc.NativeArray;
import hxmc.NativeGc;

#if !hxmc.check_vector_access
#error "VectorBounds must be typed with hxmc.check-vector-access"
#end

class VectorBounds {
	static var indices = 0;
	static var rhsCalls = 0;
	static function index(i:Int):Int { indices++; return i; }
	static function rhs():Float { rhsCalls++; return 2; }

	static function reject(f:Void->Void):Void {
		try f() catch (e:ArgumentException) {
			if (e.argument != "index" && e.argument != "range") throw e;
			return;
		}
		throw "Expected ArgumentException";
	}

	static function probe<T>(name:String, v:Vector<T>, value:T):Void {
		v[0] = value;
		for (i in [-1, v.length, 0x7FFFFFFF, 0x80000000]) {
			reject(() -> { var x = v[i]; });
			reject(() -> { v[i] = value; });
		}
		Sys.println('$name ${v.length} ${v[0] == value}');
	}

	// Kept separately to inspect the checks emitted for reads, writes and
	// read-modify-write operations (one unsigned bounds branch for each).
	@:noInline static function read(v:Vector<Int>, i:Int):Int return v[i];
	@:noInline static function write(v:Vector<Int>, i:Int, x:Int):Void v[i] = x;
	@:noInline static function multiply(v:Vector<Float>, i:Int, x:Float):Void v[i] *= x;
	@:noInline static function twice(v:Vector<Int>, i:Int):Int return v[i] + v[i];

	static function main() {
		probe("int", new Vector<Int>(2), 17);
		probe("float", new Vector<Float>(2), 1.25);
		probe("bool", new Vector<Bool>(2), true);
		probe("int64", new Vector<Int64>(2), Int64.make(2, 17));
		probe("string", new Vector<String>(2), "hello");
		probe("object", new Vector<{value:Int}>(2), {value: 23});
		probe("nullable", new Vector<Null<Int>>(2), 10000);
		probe("dynamic", new Vector<Dynamic>(2), {value: 31});

		var a = new Vector<Int>(2, 7), f = new Vector<Float>(2, 1.5);
		write(a, 1, 11);
		multiply(f, 0, 2);
		Sys.println('valid ${read(a, 1)} ${f[0]} twice=${twice(a, 1)}');
		reject(() -> { read(a, -1); });
		reject(() -> { write(a, 2, 99); });
		reject(() -> { multiply(f, 2, 99); });
		reject(() -> { new Vector<Int>(0)[0]; });
		reject(() -> { f[index(2)] *= rhs(); });
		f[index(0)] *= rhs();
		var post = a[index(0)]++;
		var pre = ++a[index(1)];
		Sys.println('compound ${a.join(",")} ${f[0]} post=$post pre=$pre indices=$indices rhs=$rhsCalls');

		// Callbacks that collect preserve the checked vector and its index.
		f[0] *= ({ NativeGc.collect(true); 2.0; });
		Sys.println('gc ${f[0]}');
		for (range in [[-1, 0, 1], [0, -1, 1], [0, 0, -1], [1, 0, 2], [0, 1, 2], [0x7FFFFFFF, 0, 1], [0, 0, 0x7FFFFFFF]])
			reject(() -> Vector.blit(a, range[0], a, range[1], range[2]));
		Vector.blit(a, a.length, a, a.length, 0);
		Vector.blit(a, 0, a, 1, 1);
		Sys.println('blit ${a.join(",")}');

		// The flag leaves NativeArray direct access and ordinary Array growth intact.
		var native = new NativeArray<Int>(2);
		native[1] = 41;
		var array = [1];
		array[2] = 3;
		Sys.println('other ${native[1]} ${array.length}');
	}
}
