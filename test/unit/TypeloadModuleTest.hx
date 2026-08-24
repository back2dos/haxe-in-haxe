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
		paths.push(new DirectoryClassPath("haxe/std/", Std));
		var loader = new TypeloadModule(paths, Define.emptyDefines());
		var module = loader.loadModule({pack:["unit", "moduleload"], name:"Example"});
		if (module.mId != 0 || module.mTypes.length != 5 || module.mExtra.mFile != sys.FileSystem.fullPath("test/unit/moduleload/Example.hx")) throw "Module loading failed";
		if (loader.loadModule({pack:["unit", "moduleload"], name:"Example"}) != module) throw "Module cache failed";
		var names = [for (type in module.mTypes) switch type { case TClassDecl(value): value.clPath.name; case TEnumDecl(value): value.ePath.name; case TTypeDecl(value): value.tPath.name; case TAbstractDecl(value): value.aPath.name; }];
		if (names.join(",") != "Example,Choice,Alias,Count,Count_Impl_") throw "Module shells failed";
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
		var inheritance = loader.loadModule({pack:["unit", "moduleload"], name:"Inheritance"});
		var base = switch inheritance.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected base class"; };
		var iface = switch inheritance.mTypes[1] { case TClassDecl(value): value; case _: throw "Expected interface"; };
		var derived = switch inheritance.mTypes[2] { case TClassDecl(value): value; case _: throw "Expected derived class"; };
		switch derived.clSuper {
			case {cls:value}: if (value != base) throw "Superclass was not resolved";
			case null: throw "Superclass was not installed";
		}
		if (derived.clImplements.length != 1 || derived.clImplements[0].cls != iface) throw "Implemented interface was not resolved";
		if ((iface.clFlags & classFlag("CInterface")) == 0) throw "Interface class flag was not installed";
		var accessors = loader.loadModule({pack:["unit", "moduleload"], name:"Accessors"});
		var accessorClass = switch accessors.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected accessors class"; };
		switch accessorClass.clStatics.get("read").cfExpr.eexpr {
			case TFunction(func): switch func.tfExpr.eexpr {
				case TReturn({eexpr: TCall({eexpr:TField(_, FInstance(_, _, field))}, [])}): if (field.cfName != "get_message") throw "Property getter was not selected";
				case _: throw "Nullable property access was not typed as a getter call";
			}
			case _: throw "Expected property reader function";
		}
		var moduleFields = loader.loadModule({pack:["unit", "moduleload"], name:"ModuleFields"});
		if (moduleFields.mStatics == null) throw "Module fields class was not created";
		var hasModuleFieldsType = false;
		for (type in moduleFields.mTypes) switch type { case TClassDecl(value) if (value == moduleFields.mStatics): hasModuleFieldsType = true; case _: }
		if (!hasModuleFieldsType) throw "Module fields class was not added to module types";
		if (!moduleFields.mStatics.clStatics.exists("initial") || !moduleFields.mStatics.clStatics.exists("answer")) throw "Module fields were not populated";
		switch moduleFields.mStatics.clStatics.get("answer").cfExpr.eexpr {
			case TFunction(func): switch func.tfExpr.eexpr {
				case TReturn({eexpr:TBinop(OpAdd, {eexpr:TField(_, FStatic(_, field))}, _)}): if (field.cfName != "initial") throw "Module field reference selected the wrong field";
				case _: throw "Module field function body was not typed";
			}
			case _: throw "Expected module field function";
		}
		var count = switch module.mTypes[3] { case TAbstractDecl(value): value; case _: throw "Expected Count abstract"; };
		if (count.aImpl == null || count.aImpl.clPath.pack.join(".") != "unit.moduleload._Example" || count.aImpl.clPath.name != "Count_Impl_") throw "Abstract implementation class was not installed";
		switch count.aThis { case TAbstract(value, _): if (value.aPath.name != "Int") throw "Abstract underlying type was not resolved"; case _: throw "Expected abstract underlying type"; }
	}

	static function assertBasic(name:String, type:T):Void switch type {
		case TAbstract(value, _): if (value.aPath.name != name) throw 'Expected $name basic type';
		case _: throw 'Expected $name basic type';
	}

	static function classFlag(name:String):Int return 1 << core.TType.TType.flagTClassNames.indexOf(name);
}
