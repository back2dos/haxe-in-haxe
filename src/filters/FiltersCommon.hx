/*
	The Haxe Compiler
	Copyright (C) 2005-2019  Haxe Foundation

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

package filters;

import core.TType;
import core.TFunctions as TypeOps;
import context.Common;
import context.SafeCom;
import core.Define;

class FiltersCommon {
	public static function removeGenericBase(t:ModuleType):Void {
		switch t {
			case TClassDecl(c) if (FilterContext.isRemovableClass(c)):
				TypeOps.addClassFlag(c, CExtern);
			case _:
		}
	}

	/**
		Check if `field` is overridden in subclasses
	**/
	public static function isOverridden(cls:TClass, field:TClassField):Bool {
		function loopInheritance(c:TClass):Bool {
			return c.clFields.exists(field.cfName) || core.ds.ArrayTools.exists(c.clDescendants, loopInheritance);
		}
		return core.ds.ArrayTools.exists(cls.clDescendants, loopInheritance);
	}

	public static function isCached(com:CommonContext, t:ModuleType):Bool {
		var m = TypeOps.tModule(t).mExtra;
		return m.mProcessed != 0 && m.mProcessed < com.partScope.compilationStep;
	}

	public static function applyFiltersOnce(ctx:context.Typecore.Typer, scom:SafeContext,
			filters:Array<{name:String, run:SafeContext->TExpr->TExpr}>, t:ModuleType):Void {
		var detailTimes = try core.ds.OcamlInt.ofString(Common.definedValueSafe(ctx.com, Define.FilterTimes, "0")) catch (_:Dynamic) 0;
		if (!isCached(ctx.com, t)) SafeCom.runExpressionFiltersSafe(scom, detailTimes, filters, t);
	}
}
