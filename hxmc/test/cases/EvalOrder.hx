// Operands are evaluated left to right: a static variable read before a later
// operand's call that assigns it keeps the value it had (the lowering spills
// a global read like any other memory read once a later operand has effects;
// the fuzzer's exec lane, seed 7739), in arithmetic, shifts, comparisons,
// string concatenation, array literals, call arguments and Math calls; and a
// method's receiver is read before its arguments' effects.
class P {
	public var name:String;

	public function new(n:String)
		name = n;

	public function show(x:Int):String
		return name + x;

	public function v(x:Int):String
		return name + "v" + x;
}

class Q extends P {
	override public function v(x:Int):String
		return name + "q" + x;
}

class EvalOrder {
	static var s:Int = 5;
	static var f:Float = 1.5;
	static var str = "a";
	static var cur:P = new P("a");

	var inst:P = new P("i");

	function new() {}

	static function setS():Int {
		s = 100;
		f = 10.0;
		return 1;
	}

	static function setStr():String {
		str = "b";
		return "c";
	}

	static function swap():Int {
		cur = new P("b");
		return 1;
	}

	function swapI():Int {
		inst = new Q("j");
		return 2;
	}

	static function reset() {
		s = 5;
		f = 1.5;
	}

	static function shifted():Int {
		// (the fuzzer's program: the static read, then a call assigning it)
		s = (s << (setS() & 7)) & 0xFFFFFF;
		return s;
	}

	static function main() {
		Sys.println(s + setS());
		reset();
		Sys.println(s << (setS() & 7));
		reset();
		Sys.println(s - setS());
		reset();
		Sys.println(f * setS());
		reset();
		Sys.println(s > setS());
		reset();
		Sys.println(str + setStr());
		reset();
		Sys.println([s, setS(), s]);
		reset();
		Sys.println(Math.max(s, setS()));
		reset();
		Sys.println(Std.string(s) + setS());
		reset();
		Sys.println(shifted());
		Sys.println(cur.show(swap()));
		cur = new P("a");
		Sys.println(cur.v(swap()));
		var m = new EvalOrder();
		Sys.println(m.inst.show(m.swapI()));
		m.inst = new P("i");
		Sys.println(m.inst.v(m.swapI()));
	}
}
