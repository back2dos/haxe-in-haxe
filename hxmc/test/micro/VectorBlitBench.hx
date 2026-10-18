import haxe.ds.Vector;

// haxe.ds.Vector.blit against the plain loop `for (i in 0...n) g[i] = c[i]`:
// Float and String vectors, n elements between two vectors and within one
// (overlapping, upward), the time per operation. Not a corpus case (times
// vary); built and run by hand, natively or as a module:
//   bin/hxmc/hxmc -cp hxmc/test/micro -main VectorBlitBench -cp bin/hxmc/std --custom-target hxmc=bin/blitbench
//   bin/blitbench [ops] [n...]           (default 2000000 element copies per row)
// For instruction counts, one row under callgrind minus the same row with 0
// operations: `bin/blitbench <ops> <n> <kind>` (kind: blit, loop, sblit, sloop,
// move, mloop). x86-64, instructions per operation, before hxmc/std/haxe/ds/
// Vector.hx (upstream's generic loop: each element read as Dynamic, a Float
// boxed, a call per element) -> after, and the loop:
//   blit  n=1 264 -> 46 (loop 39), n=4 888 -> 106 (99), n=8 1720 -> 147 (179),
//         n=37 7754 -> 205 (759), n=1000 223344 -> 1891 (20019)
//   sblit n=1 82 -> 51 (41), n=4 190 -> 150 (140), n=37 1378 -> 226 (1229),
//         n=1000 36047 -> 1902 (33009)
//   move  n=1 247 -> 36 (27), n=4 835 -> 93 (84), n=37 7305 -> 194 (711),
//         n=1000 211339 -> 1880 (19008)
class VectorBlitBench {
	static var sink = 0.0;

	static function row(kind:String, n:Int, ops:Int):Float {
		var c = new Vector<Float>(n + 1);
		var g = new Vector<Float>(n + 1);
		var cs = new Vector<String>(n + 1);
		var gs = new Vector<String>(n + 1);
		for (i in 0...n + 1) {
			c[i] = i * 0.5;
			cs[i] = "s" + i;
		}
		var t0 = Sys.time();
		switch kind {
			case "blit":
				for (k in 0...ops) {
					c[0] = k;
					Vector.blit(c, 0, g, 0, n);
				}
			case "loop":
				for (k in 0...ops) {
					c[0] = k;
					for (i in 0...n)
						g[i] = c[i];
				}
			case "sblit":
				for (k in 0...ops)
					Vector.blit(cs, 0, gs, 0, n);
			case "sloop":
				for (k in 0...ops)
					for (i in 0...n)
						gs[i] = cs[i];
			case "move":
				for (k in 0...ops)
					Vector.blit(c, 0, c, 1, n);
			case "mloop":
				for (k in 0...ops) {
					var i = n;
					while (i > 0) {
						c[i] = c[i - 1];
						i--;
					}
				}
			case _:
				throw "unknown kind " + kind;
		}
		var t = Sys.time() - t0;
		for (i in 0...n)
			sink += g[i] + c[i] + (gs[i] == null ? 0 : gs[i].length);
		return ops == 0 ? 0 : t * 1e9 / ops;
	}

	static function main() {
		var a = Sys.args();
		if (a.length == 3) {
			row(a[2], Std.parseInt(a[1]), Std.parseInt(a[0]));
			return;
		}
		var work = a.length > 0 ? Std.parseInt(a[0]) : 2000000;
		var sizes = a.length > 1 ? [for (s in a.slice(1)) Std.parseInt(s)] : [1, 4, 8, 37, 1000];
		Sys.println("n\tblit\tloop\tsblit\tsloop\tmove\tmloop (ns per operation)");
		for (n in sizes) {
			var ops = Std.int(Math.max(1000, work / n));
			var cells = [for (k in ["blit", "loop", "sblit", "sloop", "move", "mloop"]) Std.string(Math.round(row(k, n, ops) * 10) / 10)];
			Sys.println(n + "\t" + cells.join("\t"));
		}
		if (sink == -1) Sys.println(sink);
	}
}
