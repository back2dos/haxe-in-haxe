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
		var structural = Grammar.parse('typedef Cursor<T> = { function hasNext():Bool; function next():T; }').declarations[0];
		assert(switch structural.definition { case ETypedef(value): switch value.data.type { case CTAnonymous(fields): fields.length == 2; case _: false; }; case _: false; });
		var property = Grammar.parse('extern class Value { var length(default, null):Int; }').declarations[0];
		assert(switch property.definition { case EClass(value): switch value.data[0].cffKind { case FProp(get, set, _, _): get.name == "default" && set.name == "null"; case _: false; }; case _: false; });
		var functionType = Grammar.parse('class Mapper { function map(f:Int->String):Void; }').declarations[0];
		assert(switch functionType.definition { case EClass(value): switch value.data[0].cffKind { case FFun(func): switch func.fArgs[0].type.type { case CTFunction(_, _): true; case _: false; }; case _: false; }; case _: false; });
		var expressionBody = Grammar.parse('abstract Any(Dynamic) { extern inline function promote<T>():T return this; }').declarations[0];
		assert(switch expressionBody.definition { case EAbstract(value): switch value.data[0].cffKind { case FFun(func): func.fExpr != null; case _: false; }; case _: false; });
	}
	static function assert(value:Bool):Void if (!value) throw "Grammar assertion failed";
}
