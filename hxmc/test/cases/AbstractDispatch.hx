// Abstract classes no concrete class extends: their methods call, and close
// over, abstract methods and interface methods they leave unimplemented
// (dispatched: no instance can run them, but they must compile; the
// fuzzer's exec lane, seeds 7586, 7662, 7692), next to an abstract method
// that an extending class implements.
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

class AbstractDispatch {
	static function main() {
		var u:Unextended = null;
		Sys.println(u == null ? "no instance" : u.show());
		var b = new Impl();
		Sys.println(b.twice());
		Sys.println(b.closure()());
	}
}
