package filters;

import core.Ast;
import core.TType;
import core.TFunctions as TypeOps;

// haxe/src/filters/localUsage.ml — mechanical draft; not compiled or validated.
enum Usage {
	Block(visit:(Usage->Void)->Void);
	Loop(visit:(Usage->Void)->Void);
	Function(visit:(Usage->Void)->Void);
	Declare(variable:TVar);
	Use(variable:TVar);
	Assign(variable:TVar);
}
class LocalUsage {
	public static function localUsage(f:Usage->Void, e:TExpr):Void {
		switch e.eexpr {
			case TBinop(OpAssign | OpAssignOp(_), {eexpr:TLocal(v)}, e2):
				localUsage(f, e2); f(Assign(v));
			case TUnop(Increment | Decrement, _, {eexpr:TLocal(v)}): f(Assign(v));
			case TLocal(v): f(Use(v));
			case TVar(v, eo):
				if (eo != null) localUsage(f, eo);
				f(Declare(v));
			case TFunction(tf):
				f(Function(function(f) {
					for (a in tf.tfArgs) f(Declare(a.variable));
					localUsage(f, tf.tfExpr);
				}));
			case TBlock(l): f(Block(function(f) { for (e in l) localUsage(f, e); }));
			case TWhile(_, _, _): f(Loop(function(f) { core.Texpr.iter(e -> localUsage(f, e), e); }));
			case TTry(body, catches):
				localUsage(f, body);
				for (c in catches) f(Block(function(f) { f(Declare(c.variable)); localUsage(f, c.expr); }));
			case _: core.Texpr.iter(e -> localUsage(f, e), e);
		}
	}
}
