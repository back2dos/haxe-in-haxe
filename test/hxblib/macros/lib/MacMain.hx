import mac.Macros;
import mac.Record;

class MacMain {
	static function main() {
		trace(Macros.stringify(1 + 2));
		trace(Macros.compileTime());
		var r = new Record("r", 1);
		trace(r.getName());
	}
}
