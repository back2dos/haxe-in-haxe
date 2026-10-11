package core.ds;

class Ring<T> {
	var values:Array<T>;
	var index:Int = 0;
	var numFilled:Int = 0;

	public function new(length:Int, initial:T) {
		values = [];
		for (_ in 0...length) values.push(initial);
	}

	public function push(value:T):Void {
		values[index] = value;
		numFilled++;
		index = index == values.length - 1 ? 0 : index + 1;
	}

	public function iter(callback:T->Void):Void {
		for (offset in 0...values.length) callback(values[(index + offset) % values.length]);
	}

	public function fold<Result>(initial:Result, callback:Result->T->Result):Result {
		var result = initial;
		for (offset in 0...values.length) result = callback(result, values[(index + offset) % values.length]);
		return result;
	}

	public function find(predicate:T->Bool):T {
		for (value in values) if (predicate(value)) return value;
		throw "Not_found";
	}

	public function isFilled():Bool {
		return numFilled >= values.length;
	}

	public function resetFilled():Void {
		numFilled = 0;
	}
}
