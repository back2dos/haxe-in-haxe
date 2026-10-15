package mac;

import haxe.macro.Context;
import haxe.macro.Expr;

class Macros {
	public static macro function stringify(e:Expr):Expr {
		return macro $v{haxe.macro.ExprTools.toString(e)};
	}

	public static macro function compileTime():Expr {
		return macro $v{1 + 2 * 3};
	}

	public static macro function repeat(e:Expr, n:Int):Expr {
		return macro $b{[for (_ in 0...n) e]};
	}

	#if macro
	public static function addGetters():Array<Field> {
		var fields = Context.getBuildFields();
		var extra:Array<Field> = [];
		for (f in fields) {
			switch f.kind {
				case FVar(t, _) if (t != null):
					var name = f.name;
					extra.push({
						name: "get" + name.charAt(0).toUpperCase() + name.substr(1),
						access: [APublic],
						pos: f.pos,
						kind: FFun({
							args: [],
							ret: t,
							expr: macro return $i{name}
						})
					});
				case _:
			}
		}
		return fields.concat(extra);
	}
	#end
}
