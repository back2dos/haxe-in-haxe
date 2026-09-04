package filters;

import core.TType;
import core.Type as TypeOps;
import context.Common;
import context.SafeCom;
import core.Define;

// haxe/src/filters/filtersCommon.ml — mechanical draft; not compiled or validated.
class FiltersCommon {
	public static function removeGenericBase(t:ModuleType):Void {
		switch t {
			case TClassDecl(c) if (FilterContext.isRemovableClass(c)): TypeOps.addClassFlag(c, CExtern);
			case _:
		}
	}
	public static function isOverridden(cls:TClass, field:TClassField):Bool {
		function loopInheritance(c:TClass):Bool {
			return c.clFields.exists(field.cfName) || Lambda.exists(c.clDescendants, loopInheritance);
		}
		return Lambda.exists(cls.clDescendants, loopInheritance);
	}
	public static function isCached(com:Dynamic, t:ModuleType):Bool {
		var m = TypeOps.tInfos(t).mtModule.mExtra;
		return m.mProcessed != 0 && m.mProcessed < com.partScope.compilationStep;
	}
	public static function applyFiltersOnce(ctx:Dynamic, scom:Dynamic, filters:Dynamic, t:ModuleType):Void {
		var detailTimes = Std.parseInt(Common.definedValueSafe(ctx.com, FilterTimes, "0"));
		if (detailTimes == null) detailTimes = 0;
		if (!isCached(ctx.com, t)) SafeCom.runExpressionFiltersSafe(scom, detailTimes, filters, t);
	}
}
