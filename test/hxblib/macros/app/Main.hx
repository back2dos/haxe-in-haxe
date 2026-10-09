import mac.Macros;
import mac.Record;

class Point implements AutoGetters {
	var x:Int;
	var y:Int;

	public function new(x, y) {
		this.x = x;
		this.y = y;
	}
}

class Main {
	static function main() {
		trace(Macros.stringify(a + b * c));
		trace(Macros.compileTime());
		var i = 0;
		Macros.repeat(i++, 3);
		trace(i);
		var r = new Record("lib", 2);
		trace(r.getName() + r.getCount());
		var p = new Point(3, 4);
		trace(p.getX() + p.getY());
	}
}
