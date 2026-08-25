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
		var defines = Define.emptyDefines();
		Define.rawDefineValue(defines, "cross", "1");
		var loader = new TypeloadModule(paths, defines);
		try {
			new TypeloadModule(paths, Define.emptyDefines()).loadModule({pack:["unit", "moduleload"], name:"MacroField"});
			throw "Expected macro field rejection";
		} catch (error:Dynamic) {
			if ('$error'.indexOf("requires the Eval macro milestone") == -1) throw error;
		}
		try {
			new TypeloadModule(paths, Define.emptyDefines()).loadModule({pack:["unit", "moduleload"], name:"BuildMetadata"});
			throw "Expected build metadata rejection";
		} catch (error:Dynamic) {
			if ('$error'.indexOf("requires the Eval macro milestone") == -1) throw error;
		}
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
		if (expressionClass.clFields.get("unchecked").cfExpr == null) throw "Untyped expression body was not typed";
		switch expressionClass.clFields.get("typeTest").cfExpr.eexpr {
			case TFunction({tfExpr:{eexpr:TBlock([{eexpr:TReturn({eexpr:TCall({eexpr:TField(_, FStatic(_, field))}, [_, {eexpr:TTypeExpr(_)}])})}])}}):
				if (field.cfName != "isOfType") throw "Type test did not call Std.isOfType";
			case _: throw "Type test expression was not typed";
		}
		switch expressionClass.clFields.get("guarded").cfExpr.eexpr {
			case TFunction({tfExpr:{eexpr:TBlock([{eexpr:TTry(_, [{variable:variable, expr:_}])}])}}):
				if (variable.vName != "error") throw "Catch variable was not typed";
			case _: throw "Try/catch expression was not typed";
		}
		switch expressionClass.clFields.get("conditions").cfExpr.eexpr {
			case TFunction({tfExpr:{eexpr:TBlock([{eexpr:TWhile({eexpr:TParenthesis(_)}, _, _)}, {eexpr:TIf({eexpr:TParenthesis(_)}, _, _)}])}}):
			case _: throw "Control-flow conditions were not parenthesized";
		}
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
				case TBlock([{eexpr:TReturn({eexpr: TCall({eexpr:TField(_, FInstance(_, _, field))}, [])})}]): if (field.cfName != "get_message") throw "Property getter was not selected";
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
				case TBlock([{eexpr:TReturn({eexpr:TBinop(OpAdd, {eexpr:TField(_, FStatic(_, field))}, _)})}]): if (field.cfName != "initial") throw "Module field reference selected the wrong field";
				case _: throw "Module field function body was not typed";
			}
			case _: throw "Expected module field function";
		}
		var localStatics = loader.loadModule({pack:["unit", "moduleload"], name:"LocalStatics"});
		var localStaticsClass = switch localStatics.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected local-statics class"; };
		switch localStaticsClass.clStatics.get("run").cfExpr.eexpr {
			case TFunction(func): switch func.tfExpr.eexpr {
				case TBlock([{eexpr:TVar(first, _)}, {eexpr:TVar(second, _)}, _]):
					var staticFlag = 1 << core.TType.TType.flagTVarNames.indexOf("VStatic");
					var finalFlag = 1 << core.TType.TType.flagTVarNames.indexOf("VFinal");
					if ((first.vFlags & staticFlag) == 0 || (second.vFlags & staticFlag) == 0 || (second.vFlags & finalFlag) == 0) throw "Local static flags were not typed";
				case _: throw "Expected local static declarations";
			}
			case _: throw "Expected local-statics function";
		}
		var arrayComprehension = loader.loadModule({pack:["unit", "moduleload"], name:"ArrayComprehension"});
		var arrayComprehensionClass = switch arrayComprehension.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected array-comprehension class"; };
		if (arrayComprehensionClass.clStatics.get("collect").cfExpr == null) throw "Array comprehension was not typed";
		var overloads = loader.loadModule({pack:["unit", "moduleload"], name:"Overloads"});
		var overloadClass = switch overloads.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected overload class"; };
		if (overloadClass.clOrderedStatics.length != 1 || overloadClass.clStatics.get("call").cfOverloads.length != 2) throw "Overload fields were not grouped";
		var keyValueLoop = loader.loadModule({pack:["unit", "moduleload"], name:"KeyValueLoop"});
		var keyValueLoopClass = switch keyValueLoop.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected key/value-loop class"; };
		if (keyValueLoopClass.clStatics.get("visit").cfExpr == null) throw "Key/value loop was not typed";
		if (keyValueLoopClass.clStatics.get("visitMap").cfExpr == null) throw "Map value loop was not typed";
		assertLoopAllocationOrder(keyValueLoopClass.clStatics.get("visitArray").cfExpr, "array");
		assertLoopAllocationOrder(keyValueLoopClass.clStatics.get("visitRange").cfExpr, "range");
		var inlineLocal = loader.loadModule({pack:["unit", "moduleload"], name:"InlineLocalFunction"});
		var inlineLocalClass = switch inlineLocal.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected inline-local-function class"; };
		if (inlineLocalClass.clStatics.get("value").cfExpr == null) throw "Inline local function was not typed";
		var valueSwitch = loader.loadModule({pack:["unit", "moduleload"], name:"ValueSwitch"});
		var valueSwitchClass = switch valueSwitch.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected value-switch class"; };
		switch valueSwitchClass.clStatics.get("select").cfExpr.eexpr {
			case TFunction(func): switch func.tfExpr.eexpr {
				case TBlock([{eexpr:TReturn({eexpr:TSwitch({switchSubject:{eexpr:TLocal(_)}, switchCases:[{casePatterns:[{eexpr:TField(_, FStatic(_, field))}]}], switchDefault:{eexpr:TConst(TString("no"))}})})}]): if (field.cfName != "expected") throw "Value-switch pattern selected the wrong field";
				case _: throw "Value switch was not typed as a direct switch";
			}
			case _: throw "Expected value-switch function";
		}
		var count = switch module.mTypes[3] { case TAbstractDecl(value): value; case _: throw "Expected Count abstract"; };
		if (count.aImpl == null || count.aImpl.clPath.pack.join(".") != "unit.moduleload._Example" || count.aImpl.clPath.name != "Count_Impl_") throw "Abstract implementation class was not installed";
		switch count.aThis { case TAbstract(value, _): if (value.aPath.name != "Int") throw "Abstract underlying type was not resolved"; case _: throw "Expected abstract underlying type"; }
		var balancedTree = loader.loadModule({pack:["haxe", "ds"], name:"BalancedTree"});
		var balancedTreeClass = switch balancedTree.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected BalancedTree class"; };
		if (balancedTreeClass.clImplements.length != 1 || balancedTreeClass.clImplements[0].cls.clModule.mPath.name != "Constraints" || balancedTreeClass.clImplements[0].cls.clPath.name != "IMap") throw "Qualified secondary type was not resolved";
		switch balancedTreeClass.clImplements[0].params[0] { case TInst(typeParam, []) if (typeParam == balancedTreeClass.clParams[0].ttpClass): case _: throw "Class inheritance captured the wrong type-parameter scope"; }
		var callStack = loader.loadModule({pack:["haxe"], name:"CallStack"});
		var callStackAbstract:core.TType.TAbstract = null;
		for (type in callStack.mTypes) switch type { case TAbstractDecl(value) if (value.aPath.name == "CallStack"): callStackAbstract = value; case _: }
		if (callStackAbstract == null) throw "Expected CallStack abstract";
		var getLength = callStackAbstract.aImpl.clStatics.get("get_length");
		switch getLength.cfExpr.eexpr {
			case TFunction({tfArgs:[{variable:variable}]}):
				if (variable.vName != "this1") throw "Abstract this argument was not cross-target renamed";
			case _: throw "CallStack length getter was not typed";
		}
		switch callStackAbstract.aImpl.clStatics.get("exceptionStack").cfType {
			case TFun({args:[{type:TAbstract(type, [])}]}): if (type.aPath.name != "Bool") throw "Default argument type was not inferred";
			case _: throw "CallStack default argument was not typed as Bool";
		}
	}

	static function assertBasic(name:String, type:T):Void switch type {
		case TAbstract(value, _): if (value.aPath.name != name) throw 'Expected $name basic type';
		case _: throw 'Expected $name basic type';
	}

	static function classFlag(name:String):Int return 1 << core.TType.TType.flagTClassNames.indexOf(name);

	static function assertLoopAllocationOrder(expression:core.TType.TExpr, label:String):Void switch expression.eexpr {
		case TFunction({tfExpr:{eexpr:TBlock([{eexpr:TBlock(values)}])}}):
			var counter = switch values[0].eexpr { case TVar(variable, _): variable; case _: throw '$label counter declaration was not lowered'; };
			var loopVariable = switch values[2].eexpr {
				case TWhile({eexpr:TParenthesis(_)}, {eexpr:TBlock(body)}, _): switch body[0].eexpr { case TVar(variable, _): variable; case _: throw '$label loop variable declaration was not lowered'; };
				case _: throw '$label while loop was not lowered';
			};
			if (loopVariable.vId >= counter.vId) throw '$label loop variable must be allocated before generated iterator temporaries';
			if (counter.vName != "_g") throw '$label loop temporary was not cross-target renamed';
		case _: throw '$label loop lowering shape did not match upstream';
	}
}
