// the Mandelbrot set (Float loops, an Int array, a checksum)
class Mandelbrot {
	static function main() {
		var w = 600, h = 400, maxIter = 200;
		var counts = [];
		for (y in 0...h)
			for (x in 0...w) {
				var cr = (x - w * 0.7) / (w * 0.35), ci = (y - h * 0.5) / (h * 0.45);
				var zr = 0.0, zi = 0.0, i = 0;
				while (i < maxIter && zr * zr + zi * zi < 4) {
					var t = zr * zr - zi * zi + cr;
					zi = 2 * zr * zi + ci;
					zr = t;
					i++;
				}
				counts.push(i);
			}
		var sum = 0, inside = 0;
		for (c in counts) {
			sum = (sum * 31 + c) | 0;
			if (c == maxIter) inside++;
		}
		Sys.println("checksum " + sum + ", inside " + inside + " of " + counts.length);
	}
}
