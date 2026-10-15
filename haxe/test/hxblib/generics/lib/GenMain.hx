import gen.Containers;
import gen.sub.Deep;

class GenMain {
	static function main() {
		var s = new Stack<Int>();
		s.push(1).push(2);
		trace(s.pop());
		trace(new Deep(Add(Num(1), Num(2))).eval());
		trace(gen.sub.Deep.makeTree().fold((a, b) -> a + b, 0));
	}
}
