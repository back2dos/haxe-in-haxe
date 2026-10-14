// mandelbrot as haxebench's (objects allocated in the inner loop), with a checksum
class Complex {
	public var i:Float;
	public var j:Float;

	public function new(i:Float, j:Float) {
		this.i = i;
		this.j = j;
	}
}

class Mandel {
	static inline var MaxIterations = 200;
	static inline var MaxRad = 1 << 16;

	static function main() {
		var sum = 0;
		var scale = 0.1 / 4;
		for (y in 0...40) {
			for (x in 0...70) {
				var iteration = 0;
				var offset = new Complex(x * scale - 2.5, y * scale - 1);
				var val = new Complex(0.0, 0.0);
				while (length2(val) < MaxRad && iteration < MaxIterations) {
					val = add(square(val), offset);
					iteration++;
				}
				sum += iteration;
			}
		}
		trace(sum);
		// a loop reading a global it does not write, and one that does
		var t = 0;
		for (k in 0...1000)
			t += table[k % 4] + scale2;
		trace(t);
		for (k in 0...10) {
			scale2 += 1;
			t += scale2;
		}
		trace(t);
	}

	static var table = [1, 2, 3, 4];
	static var scale2 = 3;

	static function length2(v:Complex):Float
		return v.i * v.i + v.j * v.j;

	static inline function add(a:Complex, b:Complex)
		return new Complex(a.i + b.i, a.j + b.j);

	static inline function square(v:Complex)
		return new Complex(v.i * v.i - v.j * v.j, 2.0 * v.i * v.j);
}
