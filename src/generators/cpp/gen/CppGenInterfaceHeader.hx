package generators.cpp.gen;

import core.Globals;
import core.Ast;
import core.TType;
import core.TFunctions.*;
import core.Meta;
import core.Define;
import generators.Gctx;
import generators.cpp.CppAst;
import generators.cpp.CppStrings.*;
import generators.cpp.CppTypeUtils.*;
import generators.cpp.CppAstTools.*;
import generators.cpp.CppSourceWriter;
import generators.cpp.CppSourceWriter.SourceWriter;
import generators.cpp.CppContext;
import generators.cpp.gen.CppGen.*;

class CppGenInterfaceHeader {
	public static function attribs(commonCtx:Gctx):String {
		return switch Gctx.defined(commonCtx, Define.DllExport) {
			case true: "HXCPP_EXTERN_CLASS_ATTRIBUTES";
			case false: "HXCPP_CLASS_ATTRIBUTES";
		}
	}

	public static function genNativeFunction(ctx:Context, iface:TcppInterface, func:TcppInterfaceFunction):Void {
		var output = ctx.ctxOutput;
		var genArgs = function(args) return printRetypedTfunArgList(true, args);
		var strq = function(s) return CppStrings.strq(ctx.ctxCommon, s);

		output('\t\tvirtual ${tcppToString(func.iffReturn)} ${func.iffName}(${genArgs(func.iffArgs)})=0;\n');
		if (reflective(iface.ifClass, func.iffField)) {
			if (Gctx.defined(ctx.ctxCommon, Define.DynamicInterfaceClosures))
				output('\t\tinline ::Dynamic ${func.iffName}_dyn() { return __Field( ${strq(func.iffField.cfName)}, ::hx::paccDynamic ); }\n') else
				output('\t\tvirtual ::Dynamic ${func.iffName}_dyn()=0;\n');
		}
	}

	public static function genFunction(ctx:Context, iface:TcppInterface, func:TcppInterfaceFunction):Void {
		var output = ctx.ctxOutput;
		var argList = printRetypedTfunArgList(true, func.iffArgs);
		var returnType = switch func.iffReturn {
			case TCppMarshalNativeType(valueType, (Reference | Promoted)):
				tcppToString(TCppMarshalNativeType(valueType, Stack));
			case other:
				tcppToString(other);
		}
		var commaArgList = if (argList == "") argList else "," + argList;

		output('\t\t$returnType (::hx::Object :: *_hx_${func.iffName})($argList);\n');
		output('\t\tstatic $returnType ${func.iffName}( ::Dynamic _hx_$commaArgList );\n');
	}

	public static function genIncludes(hFile:SourceWriter, interfaceDef:TClass):Void {
		function addClassIncludes(cls:TClass):Void {
			switch getAllMetaStringPath(cls.clMeta, Meta.Include) {
				case []:
					hFile.addInclude(cls.clPath);
				case includes:
					for (inc in includes) hFile.addInclude(pathOfString(inc));
			}
		}

		/* Include the real header file for the super class */
		switch interfaceDef.clSuper {
			case null:
				// port: as upstream parses it, the interfaces below are part of this `| _ -> ();` match arm.
				/* And any interfaces ... */
				for (i in realInterfaces(interfaceDef.clImplements)) addClassIncludes(i.cls);
			case {cls: cls}: addClassIncludes(cls);
		}
	}

	public static function genForwardDecls(hFile:SourceWriter, tcppInterface:TcppInterface, ctx:Context, commonCtx:Gctx):Void {
		/* Only need to forward-declare classes that are mentioned in the header file (ie, not the implementation) */
		var r = CppReferences.findReferencedTypesFlags(ctx, TClassDecl(tcppInterface.ifClass), null, ctx.ctxSuperDeps, PathMap.empty(), true, false,
			tcppInterface.ifScriptable);

		for (i in 0...r.deps.length) genForwardDecl(hFile, r.deps[i], r.flags[i]);
	}

	public static function genHeaderIncludes(interfaceDef:TClass, outputH:String->Void):Void {
		outputH("\n");
		outputH(getClassCode(interfaceDef, Meta.HeaderCode));
		var includes = getAllMetaStringPath(interfaceDef.clMeta, Meta.HeaderInclude);
		function printer(inc:String) outputH("#include \"" + inc + "\"\n");
		for (inc in includes) printer(inc);
	}

	public static function genBody(tcppInterface:TcppInterface, ctx:Context, outputH:String->Void, iter:TcppInterfaceFunction->Void):Void {
		if (hasBootField(tcppInterface.ifClass)) outputH("\t\tstatic void __boot();\n");

		for (f in allInterfaceFunctions(tcppInterface)) iter(f);

		switch Ast.getMetaString(tcppInterface.ifClass.clMeta, Meta.ObjcProtocol) {
			case null:
				// port: as upstream parses it, the header class code below is part of this `| None -> ();` match arm.
				outputH(getClassCode(tcppInterface.ifClass, Meta.HeaderClassCode));
			case protocol:
				outputH("\t\tstatic id<" + protocol + "> _hx_toProtocol(::Dynamic inImplementation);\n");
		}
	}

	public static function generateNativeInterface(baseCtx:Context, tcppInterface:TcppInterface):Void {
		var commonCtx = baseCtx.ctxCommon;
		var classPath = tcppInterface.ifClass.clPath;

		var ps = switch tcppInterface.ifClass.clSuper {
			case null:
				{parent: "virtual ::hx::NativeInterface", sup: "::hx::NativeInterface"};
			case {cls: klass, params: params}:
				var name = tcppToStringSuffix("_obj", cppInstanceType(commonCtx.basic, klass, params, CppRetyper.withStackValueType));
				{parent: "virtual " + name, sup: name};
		}
		var parent = ps.parent, sup = ps.sup;

		var hFile = CppSourceWriter.newHeaderFile(commonCtx, commonCtx.file, classPath);
		var ctx = CppContext.fileContext(baseCtx, hFile, tcppInterface.ifDebugLevel, true);
		var outputH = hFile.write;
		var defString = joinClassPath(classPath, "_");

		beginHeaderFile(hFile.writeH, defString, true);

		genIncludes(hFile, tcppInterface.ifClass);
		genForwardDecls(hFile, tcppInterface, ctx, commonCtx);
		genHeaderIncludes(tcppInterface.ifClass, outputH);

		beginNamespace(outputH, classPath);
		outputH("\n\n");
		outputH(getClassCode(tcppInterface.ifClass, Meta.HeaderNamespaceCode));

		outputH("class " + (attribs(commonCtx)) + " " + tcppInterface.ifName + " : public " + parent);

		for (i in tcppInterface.ifClass.clImplements.filter(function(i) return isNativeGenClass(i.cls)))
			outputH(" , public virtual " + joinClassPath(i.cls.clPath, "::"));

		outputH("\n{\n\tpublic:\n");
		outputH("\t\ttypedef " + sup + " super;\n");
		outputH("\t\ttypedef " + tcppInterface.ifName + " OBJ_;\n");

		genBody(tcppInterface, ctx, outputH, function(f) genNativeFunction(ctx, tcppInterface, f));

		outputH("};\n\n");

		endNamespace(outputH, classPath);
		endHeaderFile(outputH, defString);

		hFile.close();
	}

	public static function generateManagedInterface(baseCtx:Context, tcppInterface:TcppInterface):Void {
		var commonCtx = baseCtx.ctxCommon;
		var classPath = tcppInterface.ifClass.clPath;

		var sup = switch tcppInterface.ifClass.clSuper {
			case null:
				"::hx::Object";
			case {cls: klass, params: params}:
				tcppToStringSuffix("_obj", cppInstanceType(commonCtx.basic, klass, params, CppRetyper.withStackValueType));
		}
		var hFile = CppSourceWriter.newHeaderFile(commonCtx, commonCtx.file, classPath);
		var ctx = CppContext.fileContext(baseCtx, hFile, tcppInterface.ifDebugLevel, true);
		var outputH = hFile.write;
		var defString = joinClassPath(classPath, "_");

		beginHeaderFile(hFile.writeH, defString, false);

		genIncludes(hFile, tcppInterface.ifClass);
		genForwardDecls(hFile, tcppInterface, ctx, commonCtx);
		genHeaderIncludes(tcppInterface.ifClass, outputH);

		beginNamespace(outputH, classPath);
		outputH("\n\n");
		outputH(getClassCode(tcppInterface.ifClass, Meta.HeaderNamespaceCode));

		outputH("class " + (attribs(commonCtx)) + " " + tcppInterface.ifName + " {\n");
		outputH("\tpublic:\n");
		outputH("\t\ttypedef " + sup + " super;\n");
		outputH("\t\tHX_DO_INTERFACE_RTTI;\n\n");

		genBody(tcppInterface, ctx, outputH, function(f) genFunction(ctx, tcppInterface, f));

		outputH("};\n\n");

		endNamespace(outputH, classPath);
		endHeaderFile(outputH, defString);

		hFile.close();
	}
}
