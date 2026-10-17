// Abstract classes no concrete class extends: their methods call, and close
// over, abstract methods and interface methods they leave unimplemented
// (dispatched: no instance can run them, but they must compile; the
// fuzzer's exec lane, seeds 7586, 7662, 7692), next to an abstract method
// that an extending class implements. And a method overridden two classes
// down only (by a subclass of a subclass), called where that class is not
// lowered yet: dispatched (seed 60658: the direct subclasses alone were
// looked at).
interface I {
	function name():String;
}

abstract class Unextended implements I {
	abstract public function value():Float;

	public function show():String {
		var f = value;
		var g = name;
		return name() + " " + this.value() + " " + f() + g();
	}
}

abstract class Base {
	abstract public function value():Int;

	public function twice():Int
		return value() * 2;

	public function closure():() -> Int
		return value;
}

class Impl extends Base {
	public function new() {}

	public function value():Int
		return 21;
}

class Top {
	public function new() {}

	public function m():String
		return "Top";
}

class Middle extends Top {}

class Bottom extends Middle {
	override public function m():String
		return "Bottom";
}

class AbstractDispatch {
	static function main() {
		Sys.println((true ? new Bottom() : new Top()).m());
		var u:Unextended = null;
		Sys.println(u == null ? "no instance" : u.show());
		var b = new Impl();
		Sys.println(b.twice());
		Sys.println(b.closure()());
	}
}
