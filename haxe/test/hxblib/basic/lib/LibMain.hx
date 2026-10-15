import pack.Lib;

class LibMain {
	static function main() {
		trace(Lib.greet("lib"));
		trace(new Derived().name());
	}
}
