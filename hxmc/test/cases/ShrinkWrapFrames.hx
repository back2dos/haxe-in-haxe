// Functions whose shadow-stack frame ShrinkWrap pushes after their early
// exits: parameters used after allocations (the corpus' 64 KB nursery
// collects often, moving them), a callee inlined before the push, calls on
// the way to the frame's first use, a push after a loop.
class Node {
	public var kind:Int;
	public var name:String;
	public var next:Node;

	public function new(kind, name, next) {
		this.kind = kind;
		this.name = name;
		this.next = next;
	}
}

class ShrinkWrapFrames {
	static var log:Array<String> = [];

	static inline function tag(n:Node):String
		return n.name + "#" + n.kind;

	static function early(a:Node, b:Node):Bool {
		if (a.kind & 1 != 0) return true;
		if (b.kind & 2 != 0) return false;
		var parts = [a.name, b.name, Std.string(a.kind)];
		log.push(parts.join("/"));
		return a.kind > b.kind && a.name.length >= b.name.length;
	}

	static function viaCall(a:Node, b:Node):Int {
		if (a == null) return -1;
		var t = tag(b); // (inlined, allocates)
		if (a.kind == 7) return t.length;
		var copy = new Node(a.kind + b.kind, t + a.name, a);
		return copy.next.kind + copy.kind + copy.name.length;
	}

	static function afterLoop(n:Node):Int {
		var depth = 0;
		var m = n;
		while (m != null && m.kind != 3) {
			depth++;
			m = m.next;
		}
		if (depth < 2) return depth;
		var s = new StringBuf();
		var k = n;
		while (k != null) {
			s.add(k.name);
			k = k.next;
		}
		return depth * 1000 + s.toString().length;
	}

	static function main() {
		var chain:Node = null;
		for (i in 0...30)
			chain = new Node(i % 5, "n" + i, chain);
		var t = 0, c = 0, d = 0;
		for (i in 0...20000) {
			var a = new Node(i * 7, "a" + (i % 100), chain);
			var b = new Node(i * 3, "b" + (i % 13), null);
			if (early(a, b)) t++;
			c += viaCall(i % 9 == 0 ? null : a, b);
			d += afterLoop(i % 4 == 0 ? b : chain);
		}
		trace(t, c, d, log.length, log[log.length - 1]);
	}
}
