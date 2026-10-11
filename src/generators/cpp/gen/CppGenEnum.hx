package generators.cpp.gen;

import core.TType;
import core.Meta;
import core.Define;
import generators.Gctx;
import generators.cpp.CppAst;
import generators.cpp.CppStrings.*;
import generators.cpp.CppAstTools.*;
import generators.cpp.CppSourceWriter;
import generators.cpp.CppContext;
import generators.cpp.gen.CppGen.*;

class CppGenEnum {
	public static function constructorArgCount(constructor:TEnumField):Int {
		return switch constructor.efType {
			case TFun(sig): sig.args.length;
			case _: 0;
		}
	}

	public static function genEnumConstructor(remapClassName:String, className:String, outputCpp:String->Void, constructor:TcppEnumField):Void {
		switch constructor.tefArgs {
			case null:
				outputCpp(remapClassName + " " + className + "::" + constructor.tefName + ";\n\n");
			case args:
				outputCpp('$remapClassName $className::${constructor.tefName}(${printRetypedTfunArgList(true, args)})\n');
				outputCpp('{\n\treturn ::hx::CreateEnum<$className>(${constructor.tefHash},${constructor.tefField.efIndex},${args.length})');

				for (i in 0...args.length) outputCpp('->_hx_init($i,${args[i].tfaName})');

				outputCpp(";\n}\n\n");
		}
	}

	public static function genStaticReflection(className:String, outputCpp:String->Void, constructor:TcppEnumField):Void {
		var dyn = if (constructorArgCount(constructor.tefField) > 0) "_dyn()" else "";
		outputCpp('\tif (inName==${constructor.tefHash}) { outValue = $className::${constructor.tefName}$dyn; return true; }\n');
	}

	public static function genDynamicConstructor(className:String, outputCpp:String->Void, constructor:TcppEnumField):Void {
		var count = constructorArgCount(constructor.tefField);
		if (count > 0) {
			outputCpp('STATIC_HX_DEFINE_DYNAMIC_FUNC$count($className, ${constructor.tefName}, return)\n\n');
		}
	}

	public static function generate(baseCtx:Context, tcppEnum:TcppEnum):Void {
		var commonCtx = baseCtx.ctxCommon;
		var classPath = tcppEnum.teEnum.ePath;
		var justClassName = classPath.name;
		var className = justClassName + "_obj";
		var remapClassName = ("::" + (joinClassPathRemap(classPath, "::")));
		var cppFile = CppSourceWriter.newPlacedCppFile(commonCtx, classPath);
		var outputCpp = cppFile.write;
		var debug = if (Meta.has(Meta.NoDebug, tcppEnum.teEnum.eMeta) || (Gctx.defined(commonCtx, Define.NoDebug))) 0 else 1;

		var ctx = CppContext.fileContext(baseCtx, cppFile, debug, false);
		var strq = function(s) return CppStrings.strq(ctx.ctxCommon, s);
		var classIdTxt = "0x" + hex(tcppEnum.teId, 8);

		if (debug > 1) printEndline("Found enum definition:" + (joinClassPath(classPath, "::")));

		cppFile.writeH("#include <hxcpp.h>\n\n");

		var r = CppReferences.findReferencedTypesFlags(ctx, TEnumDecl(tcppEnum.teEnum), null, ctx.ctxSuperDeps, PathMap.empty(), false, false, false);
		var referenced = r.deps, flags = r.flags;
		for (p in referenced) addInclude(cppFile, p);

		beginNamespace(outputCpp, classPath);
		outputCpp("\n");

		for (c in tcppEnum.teConstructors) genEnumConstructor(remapClassName, className, outputCpp, c);

		outputCpp("bool " + className + "::__GetStatic(const ::String &inName, ::Dynamic &outValue, ::hx::PropertyAccess inCallProp)\n{\n");
		for (c in tcppEnum.teConstructors) genStaticReflection(className, outputCpp, c);
		outputCpp("\treturn super::__GetStatic(inName, outValue, inCallProp);\n}\n\n");

		outputCpp("HX_DEFINE_CREATE_ENUM(" + className + ")\n\n");

		outputCpp("bool " + className + "::_hx_isInstanceOf(int inClassId) {\n");
		outputCpp("\treturn inClassId == (int)0x00000001 || inClassId == ::hx::EnumBase_obj::_hx_ClassId || inClassId == _hx_ClassId;\n");
		outputCpp("}\n");

		outputCpp("int " + className + "::__FindIndex(::String inName)\n{\n");
		for (constructor in tcppEnum.teConstructors) outputCpp('\tif (inName==${constructor.tefHash}) return ${constructor.tefField.efIndex};\n');
		outputCpp("\treturn super::__FindIndex(inName);\n");
		outputCpp("}\n\n");

		/* Dynamic versions of constructors */
		for (c in tcppEnum.teConstructors) genDynamicConstructor(className, outputCpp, c);

		outputCpp("int " + className + "::__FindArgCount(::String inName)\n{\n");
		for (constructor in tcppEnum.teConstructors)
			outputCpp('\tif (inName==${constructor.tefHash}) return ${constructorArgCount(constructor.tefField)};\n');

		outputCpp("\treturn super::__FindArgCount(inName);\n");
		outputCpp("}\n\n");

		/* Dynamic "Get" Field function - string version */
		outputCpp("::hx::Val " + className + "::__Field(const ::String &inName,::hx::PropertyAccess inCallProp)\n{\n");
		function dumpConstructorTest(constructor:TcppEnumField):Void {
			outputCpp("\tif (inName==" + constructor.tefHash + ") return " + constructor.tefName);
			if ((constructorArgCount(constructor.tefField)) > 0) outputCpp("_dyn()");
			outputCpp(";\n");
		}
		for (c in tcppEnum.teConstructors) dumpConstructorTest(c);
		outputCpp("\treturn super::__Field(inName,inCallProp);\n}\n\n");

		outputCpp("static ::String " + className + "_sStaticFields[] = {\n");
		for (constructor in tcppEnum.teConstructors) outputCpp("\t" + constructor.tefHash + ",\n");

		outputCpp("\t::String(null())\n};\n\n");

		/* ENUM - Mark static as used by GC - they are const now, so no marking*/
		/* ENUM - Visit static as used by GC - none */

		outputCpp("::hx::Class " + className + "::__mClass;\n\n");

		outputCpp("::Dynamic __Create_" + className + "() { return new " + className + "; }\n\n");

		outputCpp("void " + className + "::__register()\n{\n");
		var textName = strq(joinClassPath(classPath, "."));
		outputCpp("\n::hx::Static(__mClass) = ::hx::_hx_RegisterClass(" + textName + ", ::hx::TCanCast< " + className + " >," + className
			+ "_sStaticFields,0,\n");
		outputCpp("\t&__Create_" + className + ", &__Create,\n");
		outputCpp("\t&super::__SGetClass(), &Create" + className + ", 0\n");
		outputCpp("#ifdef HXCPP_VISIT_ALLOCS\n    , 0\n#endif\n");
		outputCpp("#ifdef HXCPP_SCRIPTABLE\n    , 0\n#endif\n");
		outputCpp(");\n");
		outputCpp("\t__mClass->mGetStaticField = &" + className + "::__GetStatic;\n");
		outputCpp("}\n\n");

		outputCpp("void " + className + "::__boot()\n{\n");
		switch core.Texpr.buildMetadata(commonCtx.basic, TEnumDecl(tcppEnum.teEnum)) {
			case null:
			case expr:
				var ctx = CppContext.fileContext(ctx, cppFile, 1, false);
				genCppInit(ctx, className, "boot", "__mClass->__meta__ = ", expr);
		}

		for (constructor in tcppEnum.teConstructors) switch constructor.tefArgs {
			case null:
				outputCpp('${constructor.tefName} = ::hx::CreateConstEnum<$className>(${constructor.tefHash}, ${constructor.tefField.efIndex});\n');
			case _:
		}

		outputCpp("}\n\n");

		outputCpp("\n");
		endNamespace(outputCpp, classPath);
		cppFile.close();

		var hFile = CppSourceWriter.newHeaderFile(commonCtx, commonCtx.file, classPath);
		var sup = "::hx::EnumBase_obj";
		var outputH = hFile.write;
		var defString = joinClassPath(classPath, "_");

		beginHeaderFile(hFile.writeH, defString, false);

		// port: List.iter2 raises Invalid_argument on lists of different lengths (they have the same length here).
		for (i in 0...referenced.length) genForwardDecl(hFile, referenced[i], flags[i]);

		outputH(getCode(tcppEnum.teEnum.eMeta, Meta.HeaderCode));

		beginNamespace(outputH, classPath);

		outputH("\n\n");
		outputH("class " + className + " : public " + sup + "\n");
		outputH("{\n\ttypedef " + sup + " super;\n");
		outputH("\t\ttypedef " + className + " OBJ_;\n");
		outputH("\n\tpublic:\n");
		outputH("\t\tenum { _hx_ClassId = " + classIdTxt + " };\n\n");
		outputH("\t\t" + className + "() {};\n");
		outputH("\t\tHX_DO_ENUM_RTTI;\n");
		outputH("\t\tstatic void __boot();\n");
		outputH("\t\tstatic void __register();\n");
		outputH("\t\tstatic bool __GetStatic(const ::String &inName, ::Dynamic &outValue, ::hx::PropertyAccess inCallProp);\n");
		outputH("\t\t::String GetEnumName() const override { return " + (strq(joinClassPath(classPath, "."))) + "; }\n");
		outputH("\t\t::String __ToString() const override { return " + (strq(justClassName + ".")) + " + _hx_tag; }\n");
		outputH("\t\tbool _hx_isInstanceOf(int inClassId) override;\n\n");

		for (constructor in tcppEnum.teConstructors) {
			outputH('\t\tstatic $remapClassName ${constructor.tefName}');
			switch constructor.tefArgs {
				case null:
					outputH(";\n");
					outputH('\t\tstatic inline $remapClassName ${constructor.tefName}_dyn() { return ${constructor.tefName}; }\n');
				case args:
					outputH('(${printRetypedTfunArgList(true, args)});\n');
					outputH('\t\tstatic ::Dynamic ${constructor.tefName}_dyn();\n');
			}
		}

		outputH("};\n\n");

		endNamespace(outputH, classPath);

		endHeaderFile(outputH, defString);
		hFile.close();
	}
}
