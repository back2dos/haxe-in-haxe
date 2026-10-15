import haxe.macro.Expr;

class MacroMain {
	static function main() {
		trace(answer(20));
	}

	static macro function answer(e:Expr):Expr {
		var n = switch e.expr {
			case EConst(CInt(s)): Std.parseInt(s);
			case _: 0;
		}
		var doubled = n * 2;
		return macro $v{doubled + 2};
	}
}
