// binary trees (allocation, recursion, virtual calls): the first program of -D hxmc.wasm-gc
class Node {
	public var left:Null<Node>;
	public var right:Null<Node>;

	public function new(left, right) {
		this.left = left;
		this.right = right;
	}

	public function check():Int
		return left == null ? 1 : 1 + left.check() + right.check();
}

class Trees {
	static function make(depth:Int):Node
		return depth == 0 ? new Node(null, null) : new Node(make(depth - 1), make(depth - 1));

	static function main() {
		var max = 16;
		var long = make(max);
		var depth = 4;
		while (depth <= max) {
			var iterations = 1 << (max - depth + 4);
			var check = 0;
			for (i in 0...iterations)
				check += make(depth).check();
			Sys.println(iterations + " trees of depth " + depth + " check: " + check);
			depth += 2;
		}
		Sys.println("long lived tree check: " + long.check());
	}
}
