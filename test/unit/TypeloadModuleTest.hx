package unit;

import core.ClassPath.ClassPathScope;
import core.ClassPath.DirectoryClassPath;
import core.ClassPaths;
import core.Define;
import core.TType.ModuleType;
import core.TType.T;
import core.TType.TExprDef;
import typing.TypeloadModule;

class TypeloadModuleTest {
	public static function main():Void {
		var paths = new ClassPaths();
		paths.push(new DirectoryClassPath("test/", User));
		var loader = new TypeloadModule(paths, Define.emptyDefines());
		var module = loader.loadModule({pack:["unit", "moduleload"], name:"Example"});
		if (module.mId != 0 || module.mTypes.length != 4 || module.mExtra.mFile != "test/unit/moduleload/Example.hx") throw "Module loading failed";
		if (loader.loadModule({pack:["unit", "moduleload"], name:"Example"}) != module) throw "Module cache failed";
		var names = [for (type in module.mTypes) switch type { case TClassDecl(value): value.clPath.name; case TEnumDecl(value): value.ePath.name; case TTypeDecl(value): value.tPath.name; case TAbstractDecl(value): value.aPath.name; }];
		if (names.join(",") != "Example,Choice,Alias,Count") throw "Module shells failed";
		var cls = switch module.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected class"; };
		if (cls.clOrderedFields.length != 3 || cls.clOrderedStatics.length != 1 || cls.clConstructor != null) throw "Class field population failed";
		if (cls.clStatics.get("value").cfName != "value" || cls.clFields.get("choice").cfName != "choice") throw "Class field maps failed";
		switch cls.clFields.get("choice").cfType { case TEnum(en, _): if (en.ePath.name != "Choice") throw "Named enum hint failed"; case _: throw "Expected enum field type"; }
		switch cls.clFields.get("alias").cfType { case TType(def, _): if (def.tPath.name != "Alias") throw "Named typedef hint failed"; case _: throw "Expected typedef field type"; }
		var choice = switch module.mTypes[1] { case TEnumDecl(value): value; case _: throw "Expected enum"; };
		if (choice.eNames.join(",") != "One,Many" || choice.eConstrs.get("Many").efIndex != 1) throw "Enum constructor population failed";
		switch choice.eConstrs.get("Many").efType { case TFun(signature): if (signature.args.length != 2) throw "Enum constructor arguments failed"; case _: throw "Expected enum constructor function"; }
		var expressions = loader.loadModule({pack:["unit", "moduleload"], name:"Expressions"});
		var expressionClass = switch expressions.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected expressions class"; };
		switch expressionClass.clStatics.get("initial").cfExpr.eexpr { case TBinop(_, _, _): case _: throw "Field initializer was not typed"; }
		var run = expressionClass.clFields.get("run").cfExpr;
		switch run.eexpr {
			case TFunction(func): switch func.tfExpr.eexpr {
				case TBlock(values):
					switch values[0].eexpr { case TVar(_, _): case _: throw "Local variable was not typed"; }
					switch values[1].eexpr { case TReturn(value): switch value.eexpr { case TCall(_, _): case _: throw "Direct call was not typed"; }; case _: throw "Return was not typed"; }
				case _: throw "Function body was not typed";
			}
			case _: throw "Function expression was not typed";
		}
		var resolver = loader.loadModule({pack:["unit", "moduleload"], name:"Resolver"});
		var resolvedClass = switch resolver.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected resolver class"; };
		assertBasic("Int", resolvedClass.clFields.get("count").cfType);
		assertBasic("Float", resolvedClass.clFields.get("ratio").cfType);
		assertBasic("Bool", resolvedClass.clFields.get("enabled").cfType);
		assertBasic("String", resolvedClass.clFields.get("label").cfType);
		assertBasic("Void", resolvedClass.clFields.get("nothing").cfType);
		switch resolvedClass.clFields.get("anything").cfType { case TDynamic(_): case _: throw "Dynamic hint was not resolved"; }
		switch resolvedClass.clFields.get("helper").cfType { case TInst(value, _): if (value.clPath.name != "ResolverHelper") throw "Module type hint was not resolved"; case _: throw "Expected module class hint"; }
		switch resolvedClass.clFields.get("run").cfExpr.eexpr {
			case TFunction(func): switch func.tfExpr.eexpr {
				case TBlock([ {eexpr: TVar(_, _)}, {eexpr: TReturn(value)} ]): switch value.eexpr { case TCall({eexpr:TField(_, FInstance(_, _, field))}, _): if (field.cfName != "value") throw "Method lookup failed"; case _: throw "Instance method was not resolved"; }
				case _: throw "Expected return";
			}
			case _: throw "Expected resolver function";
		}
		switch resolvedClass.clFields.get("fromStatic").cfExpr.eexpr {
			case TFunction(func): switch func.tfExpr.eexpr {
				case TBlock([ {eexpr: TReturn(value)} ]): switch value.eexpr { case TCall({eexpr:TField(_, FStatic(_, field))}, _): if (field.cfName != "create") throw "Static method lookup failed"; case _: throw "Static method was not resolved"; }
				case _: throw "Expected static lookup return";
			}
			case _: throw "Expected static lookup function";
		}
	}

	static function assertBasic(name:String, type:T):Void switch type {
		case TAbstract(value, _): if (value.aPath.name != name) throw 'Expected $name basic type';
		case _: throw 'Expected $name basic type';
	}
}
