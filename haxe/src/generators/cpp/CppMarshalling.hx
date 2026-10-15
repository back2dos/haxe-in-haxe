package generators.cpp;

import core.TType;
import core.TFunctions.*;
import core.Meta;
import generators.cpp.CppError.CppErrorKind;

class CppMarshalling {
	public static function isMarshallingManagedClass(cls:TClass):Bool
		return hasClassFlag(cls, CExtern) && Meta.has(Meta.CppManagedType, cls.clMeta);

	public static function isMarshallingNativeEnum(a:TAbstract):Bool
		return a.aEnum && a.aExtern && Meta.has(Meta.CppValueType, a.aMeta);

	public static function isMarshallingNativeValueClass(cls:TClass):Bool
		return hasClassFlag(cls, CExtern) && Meta.has(Meta.CppValueType, cls.clMeta);

	public static function isStackOnlyMarshallingNativeValueClass(cls:TClass):Bool {
		if (isMarshallingNativeValueClass(cls)) {
			function getMetaField(field:String):Null<core.Ast.ObjectField> {
				var m = Meta.get(Meta.CppValueType, cls.clMeta);
				return switch m.exprs {
					case [{expr: EObjectDecl(decls)}]:
						var found = null;
						for (d in decls) if (d.key.name == field) {
							found = d;
							break;
						}
						found;
					case _:
						null;
				}
			}
			function flagError(pos:core.Globals.Pos):Dynamic return CppError.cppAbort(InvalidFlagsField, pos);
			var flags = switch getMetaField("flags") {
				case {expr: {expr: EArrayDecl(decls)}}:
					var r = [];
					for (d in decls) switch d.expr {
						case EConst(Ident(c)): r.push(c);
						case _: flagError(d.pos);
					}
					r;
				case null:
					[];
				case f:
					flagError(f.key.pos);
			}
			return flags.indexOf("StackOnly") >= 0;
		} else return false;
	}

	public static function isMarshallingNativePointer(cls:TClass):Bool
		return hasClassFlag(cls, CExtern) && Meta.has(Meta.CppPointerType, cls.clMeta);

	public static function isMarshallingNativeValueClassTvar(tvar:TVar):Bool {
		return switch follow(tvar.vType) {
			case TInst(cls, _): isMarshallingNativeValueClass(cls);
			case _: false;
		}
	}
}
