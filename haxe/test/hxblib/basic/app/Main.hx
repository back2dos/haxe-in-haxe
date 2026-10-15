import pack.Lib;

class Main {
	static function main() {
		var l = new Lib(21);
		trace(l.twice(x -> x * 2));
		trace(l.map(x -> "v" + x).get());
		trace(Lib.greet("world"));
		var c:Color = Rgb(1, 2, 3);
		switch c {
			case Rgb(r, g, b):
				trace(r + g + b);
			case Red | Green:
		}
		var lv:Level = High;
		trace(lv + 0);
		var m:Meters = 1.5;
		trace((m + new Meters(2)).toFloat());
		var p:Point = {x: 1, y: 2};
		trace(p.x + p.y);
		var s:Shape = new Square(3);
		trace(s.area());
		var b:Base = new Derived();
		trace(b.name());
		trace(b.over(1) + " " + b.over("s"));
		trace(pack.Lib.moduleLevel(1) + pack.Lib.moduleConst);
		trace(Lib.counter);
	}
}
