import gen.Containers;
import gen.sub.Deep;
import haxe.ds.Option;

using gen.Containers.StringExt;

class Main {
	static function main() {
		var s = new Stack<String>();
		s.push("a").push("b").push("c");
		trace(s.length);
		for (x in s)
			trace(x);
		trace(Tools.mapOpt(s.pop(), x -> x.shout()));
		var f = new Stack<Float>();
		trace(f.pop());

		var p = new Pair(1, "one");
		trace(p.swap().toString());
		var q:Pair<Int> = new Pair(2, "two");
		trace(q.second);

		var e = Add(Num(1.5), Add(Num(2), Num(3)));
		trace(Tools.accept(e, new Eval()));
		trace(new Deep(Num(4)).eval());

		trace(Tools.sum([1, 2, 3]));
		trace(Tools.sum([1.5, 2.5]));
		trace(Tools.describe({name: "x"}));
		trace(Tools.describe({name: "y", age: 3}));
		var c = Tools.counter();
		c();
		trace(c());

		var n:Named<Int> = {name: "n", value: 1};
		trace(n.name + n.value);

		var v = new Vec2(1, 2);
		v.x = 10;
		var w = -(v * 2);
		trace(w.x + w.y + w[0]);
		var fromPair:Vec2 = new Pair(3.0, 4.0);
		trace(fromPair.toString());

		var d = North;
		trace(d.flip());

		trace("hi".shout() + "ab".times(3));

		trace(Statics.initialized);
		trace(Statics.hook("x"));
		Statics.hook = s -> "custom " + s;
		trace(Statics.hook("y"));
		trace(UsesHidden.value());

		var t = makeTree();
		trace(t.fold((acc, v) -> acc + v, 0));
		var t2:IntTree = new Tree(5);
		trace(t2.children.length);
	}
}
