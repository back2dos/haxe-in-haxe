class Point {
	public var x:Int; public var y:Int;
	public function new(x, y) { this.x = x; this.y = y; }
}
class Objects {
	static function main() {
		var total = 0;
		for (round in 0...20) {
			var pts = [for (i in 0...20000) new Point((i * 7919) % 10007, (i * 104729) % 1009)];
			pts.sort((a, b) -> a.x != b.x ? a.x - b.x : a.y - b.y);
			var filtered = pts.filter(p -> p.y % 3 == 0).map(p -> p.x + p.y);
			for (v in filtered) total += v;
		}
		Sys.println(total);
	}
}
