package generators.cpp.gen;

import core.Globals;
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

class CppGenClassHeader {
	public static function genMemberVariable(ctx:Context, isStatic:Bool, v:TcppClassVariable):Void {
		var tcppStr = tcppToString(v.tcvType);

		if (!isStatic && v.tcvIsStackonly)
			core.Error.abort('${core.TPrinting.Printer.sType(v.tcvField.cfType)} is marked as stack only and therefor cannot be used as the type for a non static variable',
				v.tcvField.cfPos);

		var output = ctx.ctxOutput;
		var suffix = if (isStatic) "\t\tstatic " else "\t\t";

		output('$suffix$tcppStr ${v.tcvName};\n');

		if (!isStatic && v.tcvIsGcElement) {
			var getPtr = switch v.tcvType {
				case TCppString: ".raw_ref()";
				case _: ".mPtr";
			}
			output('\t\tinline $tcppStr _hx_set_${v.tcvName}(::hx::StackContext* _hx_ctx, $tcppStr _hx_v) { HX_OBJ_WB(this, _hx_v$getPtr) return ${v.tcvName} = _hx_v; }\n');
		}
	}

	public static function genDynamicFunction(ctx:Context, classDef:TClass, isStatic:Bool, func:TcppClassFunction):Void {
		var output = ctx.ctxOutput;
		var prefix = if (isStatic) "\t\tstatic " else "\t\t";
		var signature = funcToCallableString("::hx::Callable", func);

		output('${prefix}inline $signature& ${func.tcfName}_dyn() { return ${func.tcfName}; }\n');
	}

	public static function genMemberFunction(ctx:Context, classDef:TClass, isStatic:Bool, func:TcppClassFunction):Void {
		var output = ctx.ctxOutput;

		var attrs:Array<String> = [];
		// port: fold_static then fold_virtual prepend to the list.
		if (isStatic) attrs = ["static"].concat(attrs);
		if (!isStatic && func.tcfIsVirtual) {
			if (func.tcfIsExternal && !func.tcfIsScriptable) {
				var key = '${joinClassPath(classDef.clPath, ".")}.${func.tcfField.cfName}';
				switch ctx.ctxClassMemberTypes.get(key) {
					case null:
					case v: attrs = [v].concat(attrs);
				}
			} else attrs = ["virtual"].concat(attrs);
		}
		var attributes = attrs.join(" ");

		var returnTypeStr = switch func.tcfReturn {
			case TCppVoid:
				"void";
			case other:
				tcppToString(other);
		}

		output('\t\t$attributes $returnTypeStr ${func.tcfName}(${printArgList(func.tcfArgs, "")});\n');

		if ((!func.tcfIsVirtual || !func.tcfIsOverriding) && func.tcfIsReflective) {
			var prefix = if (isStatic) "static " else "";
			var signature = funcToCallableString("::hx::Callable", func);
			output('\t\t$prefix$signature ${func.tcfName}_dyn();\n');

			// port: inside the `if`, as upstream parses `if c then let ... in ...; output "\n"`.
			output("\n");
		}
	}

	public static function genClassHeader(ctx:Context, tcppClass:TcppClass, hFile:SourceWriter, scriptable:Bool, parents:Array<String>):Void {
		var classPath = tcppClass.tclClass.clPath;
		var defString = joinClassPath(classPath, "_");

		beginHeaderFile(hFile.writeH, defString, false);

		/* Include the real header file for the super class */
		switch tcppClass.tclClass.clSuper {
			case null:
			case sup:
				var klass = sup.cls;
				var includeFiles = getAllMetaStringPath(klass.clMeta, Meta.Include);
				if (includeFiles.length > 0) for (inc in includeFiles) hFile.addInclude(pathOfString(inc)) else hFile.addInclude(klass.clPath);
		}

		/* And any interfaces ... */
		for (imp in realInterfaces(tcppClass.tclClass.clImplements)) {
			var iface = imp.cls;
			var includeFiles = getAllMetaStringPath(iface.clMeta, Meta.Include);
			if (includeFiles.length > 0) for (inc in includeFiles) hFile.addInclude(pathOfString(inc)) else hFile.addInclude(iface.clPath);
		}

		/* Only need to forward-declare classes that are mentioned in the header file
			(ie, not the implementation) */
		var outputH = hFile.write;
		var classPath = tcppClass.tclClass.clPath;
		var r = CppReferences.findReferencedTypesFlags(ctx, TClassDecl(tcppClass.tclClass), null, ctx.ctxSuperDeps, PathMap.empty(), true, false, scriptable);
		for (i in 0...r.deps.length) genForwardDecl(hFile, r.deps[i], r.flags[i]);
		outputH("\n");

		outputH(getClassCode(tcppClass.tclClass, Meta.HeaderCode));
		var includes = getAllMetaStringPath(tcppClass.tclClass.clMeta, Meta.HeaderInclude);
		function printer(inc:String) outputH("#include \"" + inc + "\"\n");
		for (inc in includes) printer(inc);

		beginNamespace(outputH, classPath);
		outputH("\n\n");
		outputH(getClassCode(tcppClass.tclClass, Meta.HeaderNamespaceCode));

		var externClass = Gctx.defined(ctx.ctxCommon, Define.DllExport);
		var attribs = "HXCPP_" + (if (externClass) "EXTERN_" else "") + "CLASS_ATTRIBUTES";

		var acc = parents;
		for (i in tcppClass.tclClass.clImplements) {
			if (isNativeClass(i.cls)) acc = ['public virtual ${joinClassPath(i.cls.clPath, "::")}'].concat(acc);
		}
		var allParents = acc.copy();
		allParents.reverse();
		var parentString = switch allParents {
			case []: "";
			case xs: " : " + xs.join(", ");
		}

		outputH('class $attribs ${tcppClass.tclName}$parentString\n{\n\tpublic:\n');
	}

	public static function generateNativeHeader(baseCtx:Context, tcppClass:TcppClass):Void {
		var commonCtx = baseCtx.ctxCommon;
		var classDef = tcppClass.tclClass;
		var classPath = classDef.clPath;
		var scriptable = hasTcppClassFlag(tcppClass, Scriptable);

		var hFile = CppSourceWriter.newHeaderFile(commonCtx, commonCtx.file, classPath);
		var ctx = CppContext.fileContext(baseCtx, hFile, tcppClass.tclDebugLevel, true);

		var ps = switch classDef.clSuper {
			case null: {parent: "", sup: ""};
			case {cls: klass, params: params}:
				var name = tcppToStringSuffix("_obj", CppGen.cppInstanceType(commonCtx.basic, klass, params, CppRetyper.withStackValueType));
				{parent: name, sup: name};
		}
		var parent = ps.parent, sup = ps.sup;
		var outputH = hFile.write;
		var defString = joinClassPath(classPath, "_");

		genClassHeader(ctx, tcppClass, hFile, scriptable, if (sup == "") [] else ['public $parent']);

		CppGen.generateNativeConstructor(ctx, outputH, tcppClass, true);

		if (hasTcppClassFlag(tcppClass, Boot)) outputH("\t\tstatic void __boot();\n");

		for (v in tcppClass.tclStaticVariables) genMemberVariable(ctx, true, v);

		for (f in tcppClass.tclStaticFunctions) genMemberFunction(ctx, classDef, true, f);

		for (f in tcppClass.tclStaticDynamicFunctions) genDynamicFunction(ctx, classDef, true, f);

		for (v in tcppClass.tclVariables) genMemberVariable(ctx, false, v);

		for (f in tcppClass.tclFunctions) genMemberFunction(ctx, classDef, false, f);

		for (f in tcppClass.tclDynamicFunctions) genDynamicFunction(ctx, classDef, false, f);

		outputH(getClassCode(classDef, Meta.HeaderClassCode));
		outputH("};\n\n");

		endNamespace(outputH, classPath);

		endHeaderFile(outputH, defString);

		hFile.close();
	}

	public static function generateManagedHeader(baseCtx:Context, tcppClass:TcppClass):Void {
		var commonCtx = baseCtx.ctxCommon;
		var classDef = tcppClass.tclClass;
		var classPath = classDef.clPath;
		var smartClassName = classPath.name;
		var scriptable = hasTcppClassFlag(tcppClass, Scriptable);
		var className = tcppClass.tclName;
		var ptrName = classPointer(classDef);
		var canQuickAlloc = hasTcppClassFlag(tcppClass, QuickAlloc);
		var gcName = genGcName(classDef.clPath);

		var constructorTypeArgs = constructorArgVarList(tcppClass).map(function(a) return '${a.type} ${a.name}').join(",");

		var hFile = CppSourceWriter.newHeaderFile(commonCtx, commonCtx.file, classPath);
		var ctx = CppContext.fileContext(baseCtx, hFile, tcppClass.tclDebugLevel, true);
		var strq = function(s) return CppStrings.strq(ctx.ctxCommon, s);

		var ps = switch tcppClass.tclSuper {
			case null: {parent: "::hx::Object", sup: "::hx::Object"};
			case sup:
				var name = tcppToStringSuffix("_obj", CppGen.cppInstanceType(commonCtx.basic, sup.tclClass, sup.tclParams, CppRetyper.withStackValueType));
				{parent: name, sup: name};
		}
		var parent = ps.parent, sup = ps.sup;
		var outputH = hFile.write;
		var defString = joinClassPath(classPath, "_");

		genClassHeader(ctx, tcppClass, hFile, scriptable, ['public $parent']);

		outputH('\t\ttypedef $sup super;\n');
		outputH('\t\ttypedef $className OBJ_;\n');

		var classIdTxt = "0x" + hex(tcppClass.tclId, 8);

		outputH("\t\t" + className + "();\n");
		outputH("\n\tpublic:\n");
		outputH("\t\tenum { _hx_ClassId = " + classIdTxt + " };\n\n");
		outputH("\t\tvoid __construct(" + constructorTypeArgs + ");\n");
		outputH('\t\tinline void *operator new(size_t inSize, bool inContainer=${tcppClass.tclContainer != null}, const char* inName=$gcName)\n');
		outputH("\t\t\t{ return ::hx::Object::operator new(inSize,inContainer,inName); }\n");
		outputH("\t\tinline void *operator new(size_t inSize, int extra)\n");
		outputH('\t\t\t{ return ::hx::Object::operator new(inSize + extra, ${tcppClass.tclContainer != null}, $gcName); }\n');
		if (hasClassFlag(classDef, CAbstract)) outputH("\n") else if (CppGen.canInlineConstructor(baseCtx, classDef)) {
			outputH("\n");
			CppGen.generateConstructor(ctx, function(str) outputH("\t\t" + str), tcppClass, true);
		} else {
			outputH("\t\tstatic " + ptrName + " __new(" + constructorTypeArgs + ");\n");
			if (canQuickAlloc)
				outputH("\t\tstatic " + ptrName + " __alloc(::hx::Ctx *_hx_ctx" + (if (constructorTypeArgs == "") "" else "," + constructorTypeArgs) + ");\n");
		}
		if (!hasClassFlag(classDef, CAbstract)) {
			outputH("\t\tstatic void * _hx_vtable;\n");
			outputH("\t\tstatic ::Dynamic __CreateEmpty();\n");
			outputH("\t\tstatic ::Dynamic __Create(::hx::DynamicArray inArgs);\n");
		}
		if (tcppClass.tclDynamicFunctions.length > 0)
			outputH("\t\tstatic void __alloc_dynamic_functions(::hx::Ctx *_hx_alloc," + className + " *_hx_obj);\n");
		if (scriptable) outputH("\t\tstatic ::hx::ScriptFunction __script_construct;\n");
		outputH("\t\t//~" + className + "();\n\n");
		outputH("\t\tHX_DO_RTTI_ALL;\n");
		if (hasTcppClassFlag(tcppClass, MemberGet)) outputH("\t\t::hx::Val __Field(const ::String &inString, ::hx::PropertyAccess inCallProp);\n");
		if (hasTcppClassFlag(tcppClass, StaticGet))
			outputH("\t\tstatic bool __GetStatic(const ::String &inString, ::Dynamic &outValue, ::hx::PropertyAccess inCallProp);\n");
		if (hasTcppClassFlag(tcppClass, MemberSet))
			outputH("\t\t::hx::Val __SetField(const ::String &inString,const ::hx::Val &inValue, ::hx::PropertyAccess inCallProp);\n");
		if (hasTcppClassFlag(tcppClass, StaticSet))
			outputH("\t\tstatic bool __SetStatic(const ::String &inString, ::Dynamic &ioValue, ::hx::PropertyAccess inCallProp);\n");
		if (hasTcppClassFlag(tcppClass, GetFields)) outputH("\t\tvoid __GetFields(::Array< ::String> &outFields);\n");
		if (hasTcppClassFlag(tcppClass, Compare))
			outputH("\t\tint __Compare(const ::hx::Object *inRHS) const { " + "return const_cast<" + className
				+ " *>(this)->__compare(::Dynamic((::hx::Object *)inRHS)); }\n");

		outputH("\t\tstatic void __register();\n");
		if (tcppClass.tclContainer != null && tcppClass.tclContainer.match(Current)) {
			outputH("\t\tvoid __Mark(HX_MARK_PARAMS);\n");
			outputH("\t\tvoid __Visit(HX_VISIT_PARAMS);\n");
		}

		if (tcppClass.tclNativeInterfaces.length > 0) {
			outputH("\n\t\tHX_NATIVE_IMPLEMENTATION\n");

			for (func in CppGen.neededInterfaceFunctions(tcppClass.tclFunctions, tcppClass.tclNativeInterfaces)) {
				var retVal = tcppToString(func.iffReturn);
				var ret = if (retVal == "void") "" else "return ";
				var argNames = printArgNames(func.iffArgs);
				outputH("\t\t" + retVal + " " + func.iffName + "( " + printRetypedTfunArgList(true, func.iffArgs) + ") {\n");
				outputH("\t\t\t" + ret + "super::" + func.iffName + "( " + argNames + ");\n\t\t}\n");
			}

			outputH("\n");
		}

		outputH("\t\tbool _hx_isInstanceOf(int inClassId);\n");
		if (tcppClass.tclHaxeInterfaces.length > 0) {
			outputH("\t\tvoid *_hx_getInterface(int inHash);\n");
			/* generate header glue */
			var alreadyGlued = new haxe.ds.StringMap<Bool>();
			for (src in tcppClass.tclHaxeInterfaces) {
				function checkInterface(iface:TcppInterface):Void {
					function checkField(func:TcppInterfaceFunction):Void {
						var castStr = cppTfunSignature(false, func.iffArgs, func.iffReturn);
						var classImplementation = findClassImplementation(func, tcppClass);
						var realName = cppMemberNameOf(func.iffField);
						var castKey = realName + "::" + castStr;
						var castKey = switch iface.ifClass.clPath {
							case {pack: ["haxe"], name: "IMap"} if (realName == "set"):
								castKey + "*";
							case _:
								castKey;
						}
						var implementationKey = realName + "::" + classImplementation;
						if (castKey != implementationKey) {
							var glue = '${func.iffField.cfName}_${hex(genHash32(0, castStr), 8)}';
							if (!alreadyGlued.exists(castKey)) {
								alreadyGlued.set(castKey, true);
								var argList = printRetypedTfunArgList(true, func.iffArgs);
								var returnType = tcppToString(func.iffReturn);
								var headerCode = "\t\t" + returnType + " " + glue + "(" + argList + ");\n";
								outputH(headerCode);
								outputH("\n");
							}
						}
					}
					switch iface.ifExtends {
						case null:
						case sup: checkInterface(sup);
					}
					for (f in iface.ifFunctions) checkField(f);
				}
				checkInterface(src);
			}
		}

		if (tcppClass.tclInit != null) outputH("\t\tstatic void __init__();\n\n");
		outputH("\t\t::String __ToString() const { return " + strq(smartClassName) + "; }\n\n");

		if (hasTcppClassFlag(tcppClass, Boot)) outputH("\t\tstatic void __boot();\n");

		for (f in tcppClass.tclStaticFunctions) genMemberFunction(ctx, classDef, true, f);

		for (f in tcppClass.tclStaticDynamicFunctions) genDynamicFunction(ctx, classDef, true, f);

		for (v in tcppClass.tclStaticVariables) genMemberVariable(ctx, true, v);

		for (f in tcppClass.tclFunctions) genMemberFunction(ctx, classDef, false, f);

		for (f in tcppClass.tclDynamicFunctions) genDynamicFunction(ctx, classDef, false, f);

		for (field in tcppClass.tclVariables) genMemberVariable(ctx, false, field);

		outputH(getClassCode(classDef, Meta.HeaderClassCode));
		outputH("};\n\n");

		endNamespace(outputH, classPath);

		endHeaderFile(outputH, defString);

		hFile.close();
	}
}
