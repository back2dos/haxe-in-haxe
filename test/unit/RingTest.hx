package unit;

import core.ds.Ring;

class RingTest {
	public static function main():Void {
		var ring = new Ring<Int>(3, 0);
		ring.push(1);
		ring.push(2);
		if (ring.isFilled()) throw "Ring must not be full yet";
		ring.push(3);
		if (!ring.isFilled()) throw "Ring must be full";
		ring.push(4);
		var values:Array<Int> = [];
		ring.iter(values.push);
		if (values.join(",") != "2,3,4") throw 'Unexpected ring order: ${values.join(",")}';
		if (ring.fold(0, function(sum, value) return sum + value) != 9) throw "Ring fold failed";
		if (ring.find(function(value) return value == 3) != 3) throw "Ring find failed";
		ring.resetFilled();
		if (ring.isFilled()) throw "Ring reset failed";
	}
}
