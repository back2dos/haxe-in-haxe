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
		var controlBlock = Grammar.parse('class Main { function run(items:Array<Int>) { for (item in items) { trace(item); } } }').declarations[0];
		assert(switch controlBlock.definition { case EClass(value): switch value.data[0].cffKind { case FFun(func): func.fExpr != null; case _: false; }; case _: false; });
		var unaryNegative = Grammar.parse('class Main { static var value = -1; }').declarations[0];
		assert(switch unaryNegative.definition { case EClass(value): switch value.data[0].cffKind { case FVar(_, {expr:EUnop(Neg, _, _)}): true; case _: false; }; case _: false; });
		var interval = Grammar.parse('class Main { static function run(items:Array<Int>) { for (i in 0...items.length) {} } }').declarations[0];
		assert(switch interval.definition { case EClass(value): switch value.data[0].cffKind { case FFun(func): func.fExpr != null; case _: false; }; case _: false; });
		var switched = Grammar.parse('class Main { static function run(value:Int):Bool { return switch (value) { case 0: true; default: false; } } }').declarations[0];
		assert(switch switched.definition { case EClass(value): switch value.data[0].cffKind { case FFun(func): func.fExpr != null; case _: false; }; case _: false; });
		var finalField = Grammar.parse('class Holder { final value:Int; }').declarations[0];
		assert(switch finalField.definition { case EClass(value): switch value.data[0].cffKind { case FVar(type, _): type != null; case _: false; }; case _: false; });
		var switchStatements = Grammar.parse('class Main { static function run(value:Int) { switch (value) { case 0: trace(value); trace("zero"); default: trace("other"); } } }').declarations[0];
		assert(switch switchStatements.definition { case EClass(value): switch value.data[0].cffKind { case FFun(func): switch func.fExpr.expr { case EBlock([{expr: ESwitch(_, cases, _)}]): switch cases[0].expr.expr { case EBlock(values): values.length == 2; case _: false; }; case _: false; }; case _: false; }; case _: false; });
		var privateAccess = Grammar.parse('class Main { function run(value:Dynamic) return @:privateAccess value.hidden; }').declarations[0];
		assert(switch privateAccess.definition { case EClass(value): switch value.data[0].cffKind { case FFun(func): switch func.fExpr.expr { case EReturn({expr: EMeta(entry, _)}): entry.meta == "privateAccess"; case _: false; }; case _: false; }; case _: false; });
		var callStack = Grammar.parse(sys.io.File.getContent("haxe/std/haxe/CallStack.hx"), core.Define.emptyDefines(), "haxe/std/haxe/CallStack.hx");
		assert(callStack.declarations.length == 2);
	}
	static function assert(value:Bool):Void if (!value) throw "Grammar assertion failed";
}
