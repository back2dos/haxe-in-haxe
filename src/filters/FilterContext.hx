package filters;

import core.TType;
import core.Type as TypeOps;
import core.Meta;
import core.Timer;

// haxe/src/filters/filterContext.ml — mechanical draft; not compiled or validated.
class FilterContext {
	public static function withTimer<T>(timerCtx:Dynamic, level:Int, label:String, identifier:Dynamic, f:Void->T):T {
		var id = Timer.determineId(level, ["filters"], [label], identifier);
		return Timer.time(timerCtx, id, f);
	}
	public static function isRemovableClass(c:TClass):Bool {
		return switch c.clKind {
			case KGeneric:
				Meta.has(Remove, c.clMeta) || (c.clSuper != null && isRemovableClass(c.clSuper.cls))
					|| Lambda.exists(c.clParams, tp -> TypeOps.hasCtorConstraint(tp.ttpClass) || Meta.has(Const, tp.ttpClass.clMeta));
			case KTypeParameter(_): true; // Upstream: investigate why this happens (#4092).
			case _: false;
		};
	}
	public static function isRemovableField(isMacroContext:Bool, f:TClassField):Bool {
		return !TypeOps.hasClassFieldFlag(f, CfOverride) && (TypeOps.hasClassFieldFlag(f, CfExtern)
			|| TypeOps.hasClassFieldFlag(f, CfGeneric) || switch f.cfKind {
				case Var({vRead:AccRequire(_, _)}): true;
				case Method(MethMacro): !isMacroContext;
				case _: false;
			});
	}
}
