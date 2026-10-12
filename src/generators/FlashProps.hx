/*
	The Haxe Compiler
	Copyright (C) 2005-2019  Haxe Foundation

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

package generators;

import core.TType;
import core.TFunctions.*;
import core.Meta;
import core.ds.NotFound;

class FlashProps {
	public static function isGetterName(name:String):Bool return StringTools.startsWith(name, "get_");

	public static function isSetterName(name:String):Bool return StringTools.startsWith(name, "set_");

	public static function getPropertyName(accessorName:String):String return accessorName.substr(4, accessorName.length - 4);

	public static function isFlashProperty(cf:TClassField):Bool return Meta.has(Meta.FlashProperty, cf.cfMeta);

	public static function findPropertyForAccessor(isget:Bool, cl:TClass, tl:TParams, accessorName:String):Null<{cls:TClass, params:TParams, field:TClassField}> {
		var propName = getPropertyName(accessorName);
		try {
			var r = classField(cl, tl, propName);
			return switch r.owner {
				case null: null;
				case {cls: propCl, params: propTl}:
					var propCf = r.field;
					switch propCf.cfKind {
						case Var({vRead: AccCall | AccPrivateCall, vWrite: AccCall | AccPrivateCall | AccNever}) if (isget && isFlashProperty(propCf)):
							{cls: propCl, params: propTl, field: propCf};
						case Var({vRead: AccCall | AccPrivateCall | AccNever, vWrite: AccCall | AccPrivateCall}) if (!isget && isFlashProperty(propCf)):
							{cls: propCl, params: propTl, field: propCf};
						case _: null;
					}
			}
		} catch (_:NotFound) {
			return null;
		}
	}

	public static function isExternInstanceAccessor(isget:Bool, cl:TClass, tl:TParams, cf:TClassField):Null<{cls:TClass, params:TParams, field:TClassField}> {
		if (hasClassFlag(cl, CExtern) && (if (isget) isGetterName(cf.cfName) else isSetterName(cf.cfName)))
			return findPropertyForAccessor(isget, cl, tl, cf.cfName)
		else
			return null;
	}

	public static function findStaticPropertyForAccessor(isget:Bool, cl:TClass, accessorName:String):Null<TClassField> {
		var propName = getPropertyName(accessorName);
		var propCf = cl.clStatics.get(propName);
		if (propCf == null) return null;
		return switch propCf.cfKind {
			case Var({vRead: AccCall | AccPrivateCall, vWrite: AccCall | AccPrivateCall | AccNever}) if (isget && isFlashProperty(propCf)): propCf;
			case Var({vRead: AccCall | AccPrivateCall | AccNever, vWrite: AccCall | AccPrivateCall}) if (!isget && isFlashProperty(propCf)): propCf;
			case _: null;
		}
	}

	public static function isExternStaticAccessor(isget:Bool, cl:TClass, cf:TClassField):Null<TClassField> {
		if (hasClassFlag(cl, CExtern) && (if (isget) isGetterName(cf.cfName) else isSetterName(cf.cfName)))
			return findStaticPropertyForAccessor(isget, cl, cf.cfName)
		else
			return null;
	}
}
