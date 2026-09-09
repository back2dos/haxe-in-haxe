package examples;

enum Shape {
	Circle(radius:Float);
	Rectangle(width:Float, height:Float);
}

class Shapes {
	static function area(shape:Shape):Float {
		return switch shape {
			case Circle(radius): Math.PI * radius * radius;
			case Rectangle(width, height): width * height;
		};
	}

	static function main():Void {
		var shapes = [Circle(2), Rectangle(3, 4), Circle(1)];
		var total = 0.0;
		for (shape in shapes) {
			var value = area(shape);
			trace('$shape -> $value');
			total += value;
		}
		trace('total -> $total');
	}
}
