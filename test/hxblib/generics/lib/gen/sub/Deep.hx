package gen.sub;

import gen.Containers;

class Deep {
	public var e:Expr;

	public function new(e:Expr)
		this.e = e;

	public function eval():Float
		return Tools.accept(e, new Eval());
}

class Tree<T> {
	public var value:T;
	public var children:Array<Tree<T>>;

	public function new(value:T, ?children:Array<Tree<T>>) {
		this.value = value;
		this.children = children == null ? [] : children;
	}

	public function fold<R>(f:(R, T) -> R, init:R):R {
		var acc = f(init, value);
		for (c in children)
			acc = c.fold(f, acc);
		return acc;
	}
}

typedef IntTree = Tree<Int>;

function makeTree():IntTree
	return new Tree(1, [new Tree(2), new Tree(3, [new Tree(4)])]);
