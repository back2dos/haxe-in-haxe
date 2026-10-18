// A module-level main (upstream's unit suite: unit.TestMain): -main names
// the module, whose statics hold main (Common.getEntryPoint), and a class of
// the module's name, when there is one, is not the entry point then.
final greeting = "module-level main";
var calls = 0;

function twice(x:Int):Int {
	calls++;
	return x * 2;
}

function main() {
	Sys.println(greeting);
	Sys.println(twice(21));
	Sys.println(ModuleMain.label() + " " + Helper.run());
	Sys.println("calls " + calls);
}

class ModuleMain {
	public static function label()
		return "class";

	static function main()
		Sys.println("not the entry point");
}

private class Helper {
	public static function run()
		return twice(4) + 1;
}
