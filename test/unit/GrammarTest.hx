package unit;

import core.Ast;
import syntax.Grammar;

class GrammarTest {
	public static function main():Void {
		var parsed = Grammar.parse('package example; import foo.Bar; class Main extends Base { public static var count:Int = 1 + 2; public function new(x:Int) { var y = x; trace(y); } }', null, "Main.hx");
		assert(parsed.pack.join(".") == "example");
		assert(parsed.declarations.length == 2);
		assert(switch parsed.declarations[0].definition { case EImport(value): value.path[1].name == "Bar"; case _: false; });
		assert(switch parsed.declarations[1].definition { case EClass(c): c.name.name == "Main" && c.data.length == 2 && switch c.data[0].cffKind { case FVar(type, value): type != null && value != null; case _: false; }; case _: false; });
		var expr = Grammar.parse('class Main { function f() { return foo(1, 2).bar; } }').declarations[0];
		assert(switch expr.definition { case EClass(c): switch c.data[0].cffKind { case FFun(f): f.fExpr != null; case _: false; }; case _: false; });
	}
	static function assert(value:Bool):Void if (!value) throw "Grammar assertion failed";
}
