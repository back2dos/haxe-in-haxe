package filters.safe;

import core.Ast;
import core.TType;
import core.Globals;
import core.Type as TypeOps;
import core.ExtType;
import core.Meta;
import typing.Error;

// haxe/src/filters/safe/safeFilters.ml — mechanical draft; not compiled or validated.
class SafeFilters {
	public static function fixReturnDynamicFromVoidFunction(_:Dynamic, e:TExpr):TExpr {
		function loop(returnIsVoid:Bool, e:TExpr):TExpr {
			return switch e.eexpr {
				case TFunction(fn):
					var body = loop(ExtType.isVoid(TypeOps.follow(fn.tfType)), fn.tfExpr);
					{eexpr:TFunction({tfArgs:fn.tfArgs, tfType:fn.tfType, tfExpr:body}), etype:e.etype, epos:e.epos};
				case TReturn(returnExpr) if (returnExpr != null && returnIsVoid && TypeOps.tDynamic == TypeOps.follow(returnExpr.etype)):
					var p = {pfile:e.epos.pfile, pmin:e.epos.pmin, pmax:returnExpr.epos.pmin - 1};
					var exprs = [loop(returnIsVoid, returnExpr), {eexpr:TReturn(null), etype:e.etype, epos:p}];
					{eexpr:TMeta({name:MergeBlock, params:[], pos:Globals.nullPos}, TypeOps.mk(TBlock(exprs), e.etype, e.epos)), etype:e.etype, epos:e.epos};
				case _: TypeOps.mapExpr(e -> loop(returnIsVoid, e), e);
			};
		}
		return loop(true, e);
	}
	public static function checkAbstractAsValue(_:Dynamic, e:TExpr):TExpr {
		function loop(e:TExpr):Void {
			switch e.eexpr {
				case TField({eexpr:TTypeExpr(_)}, _):
				case TTypeExpr(TClassDecl({clKind:KAbstractImpl(a)})) if (!Meta.has(RuntimeValue, a.aMeta)):
					Error.raiseTypingError("Cannot use abstract as value", e.epos);
				case _: TypeOps.iter(loop, e);
			}
		}
		loop(e); return e;
	}
	public static function markSwitchBreakLoops(_:Dynamic, e:TExpr):TExpr {
		function addLoopLabel(n:Int, e:TExpr):TExpr {
			return {eexpr:TMeta({name:LoopLabel, params:[{expr:EConst(CInt(Std.string(n), null)), pos:e.epos}], pos:e.epos}, e), etype:e.etype, epos:e.epos};
		}
		var inSwitch = false;
		var didFound = -1;
		var num = 0;
		var curNum = 0;
		function run(e:TExpr):TExpr {
			return switch e.eexpr {
				case TFunction(_):
					var oldNum = num; num = 0;
					var ret = TypeOps.mapExpr(run, e); num = oldNum; ret;
				case TWhile(_, _, _):
					var lastSwitch = inSwitch; var lastFound = didFound; var lastNum = curNum;
					inSwitch = false; ++num; curNum = num; didFound = -1;
					var newE = TypeOps.mapExpr(run, e);
					if (didFound != -1) newE = addLoopLabel(didFound, newE);
					didFound = lastFound; inSwitch = lastSwitch; curNum = lastNum; newE;
				case TSwitch(_):
					var lastSwitch = inSwitch; inSwitch = true;
					var newE = TypeOps.mapExpr(run, e); inSwitch = lastSwitch; newE;
				case TBreak:
					if (inSwitch) { didFound = curNum; addLoopLabel(curNum, e); } else e;
				case _: TypeOps.mapExpr(run, e);
			};
		}
		return run(e);
	}
}
