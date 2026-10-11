package generators.cpp.gen;

import core.Globals;
import core.Ast;
import core.TType;
import core.TFunctions.*;
import core.Meta;
import generators.Gctx;
import generators.cpp.CppAst;
import generators.cpp.CppStrings.*;
import generators.cpp.CppTypeUtils.*;
import generators.cpp.CppAstTools.*;
import generators.cpp.CppSourceWriter;
import generators.cpp.CppContext;
import generators.cpp.gen.CppGen.*;
import generators.cpp.gen.CppCppia.ScriptType;

class CppGenInterfaceImplementation {
	public static function generateProtocolDelegate(ctx:Context, protocol:String, fullClassName:String, functions:Array<TcppInterfaceFunction>,
			output:String->Void):Void {
		var name = "_hx_" + protocol + "_delegate";
		output("@interface " + name + " : NSObject<" + protocol + "> {\n");
		output("\t::hx::Object *haxeObj;\n");
		output("}\n");
		output("@end\n\n");
		output("@implementation " + name + "\n");
		output("- (id)initWithImplementation:( ::hx::Object *)inInplemnetation {\n");
		output("  if (self = [super init]) {\n");
		output("     self->haxeObj = inInplemnetation;\n");
		output("     GCAddRoot(&self->haxeObj);\n");
		output("  }\n");
		output("  return self;\n");
		output("}\n");
		output("- (void)dealloc {\n");
		output("   GCRemoveRoot(&self->haxeObj);\n");
		output("   #ifndef OBJC_ARC\n");
		output("   [super dealloc];\n");
		output("   #endif\n");
		output("}\n\n");

		function dumpDelegate(func:TcppInterfaceFunction):Void {
			var retStr = tcppToString(func.iffReturn);
			var fa = switch Ast.getMetaString(func.iffField.cfMeta, Meta.ObjcProtocol) {
				case null: {fieldName: func.iffName, argNames: func.iffArgs.map(function(a) return a.tfaName)};
				case nativeName:
					var parts = nativeName.split(":");
					{fieldName: parts[0], argNames: parts};
			}
			var fieldName = fa.fieldName, argNames = fa.argNames;
			output("- (" + retStr + ") " + fieldName);

			var first = true;
			// port: List.iter2 raises Invalid_argument (after the common prefix) on lists of different lengths.
			var n = func.iffArgs.length < argNames.length ? func.iffArgs.length : argNames.length;
			for (i in 0...n) {
				var arg = func.iffArgs[i], signatureName = argNames[i];
				if (first) output(" :(" + tcppToString(arg.tfaType) + ")" + name) else
					output(" " + signatureName + ":(" + tcppToString(arg.tfaType) + ")" + name);
				first = false;
			}
			if (func.iffArgs.length != argNames.length) {
				core.Error.abort({
					var argString = func.iffArgs.map(function(arg) return arg.tfaName).join(",");
					"Invalid arg count in delegate in " + func.iffName + " '" + func.iffName + "," + argString + "' != '" + argNames.join(",") + "'";
				}, func.iffField.cfPos);
			}
			output(" {\n");
			output("\t::hx::NativeAttach _hx_attach;\n");
			output((if (retStr == "void") "\t" else "\treturn ") + fullClassName + "::" + func.iffName + "(haxeObj");
			for (arg in func.iffArgs) output("," + arg.tfaName);
			output(");\n}\n\n");
		}
		for (f in functions) dumpDelegate(f);

		output("@end\n\n");
	}

	public static function generateManagedInterface(baseCtx:Context, tcppInterface:TcppInterface):Void {
		var classPath = tcppInterface.ifClass.clPath;
		var cppFile = CppSourceWriter.newPlacedCppFile(baseCtx.ctxCommon, classPath);
		var cppCtx = CppContext.fileContext(baseCtx, cppFile, tcppInterface.ifDebugLevel, false);
		var ctx = cppCtx;
		var outputCpp = cppFile.write;
		var strq = function(s) return CppStrings.strq(ctx.ctxCommon, s);

		cppFile.writeH("#include <hxcpp.h>\n\n");

		var allReferenced = CppReferences.findReferencedTypes(ctx, TClassDecl(tcppInterface.ifClass), ctx.ctxSuperDeps, ctx.ctxConstructorDeps, false, false,
			tcppInterface.ifScriptable);
		for (p in allReferenced) addInclude(cppFile, p);

		if (tcppInterface.ifScriptable) cppFile.writeH("#include <hx/Scriptable.h>\n");

		cppFile.writeH("\n");

		outputCpp(getClassCode(tcppInterface.ifClass, Meta.CppFileCode));
		var includes = getAllMetaStringPath(tcppInterface.ifClass.clMeta, Meta.CppInclude);
		function printer(inc:String) outputCpp("#include \"" + inc + "\"\n");
		for (inc in includes) printer(inc);

		beginNamespace(outputCpp, classPath);
		outputCpp("\n");

		function genFunction(func:TcppInterfaceFunction):Void {
			var argList = printRetypedTfunArgList(true, func.iffArgs);
			var returnType = tcppToString(func.iffReturn);
			var returnStr = if (returnType == "void") "" else "return ";
			var commaArgList = if (argList == "") argList else "," + argList;
			var castStr = '::hx::interface_cast< ${tcppInterface.ifName} *>';

			outputCpp('$returnType ${tcppInterface.ifName}::${func.iffName}( ::Dynamic _hx_$commaArgList ) {\n');
			outputCpp("#ifdef HXCPP_CHECK_POINTER\n");
			outputCpp("\tif (::hx::IsNull(_hx_)) ::hx::NullReference(\"Object\", false);\n");
			outputCpp("#ifdef HXCPP_GC_CHECK_POINTER\n");
			outputCpp("\tGCCheckPointer(_hx_.mPtr);\n");
			outputCpp("#endif\n");
			outputCpp("#endif\n");
			outputCpp('\t$returnStr( _hx_.mPtr->*( ${castStr}(_hx_.mPtr->_hx_getInterface(${tcppInterface.ifHash})))->_hx_${func.iffName} )(${printArgNames(func.iffArgs)});\n}\n');
		}

		for (f in allInterfaceFunctions(tcppInterface)) genFunction(f);

		outputCpp("\n");

		outputCpp(getClassCode(tcppInterface.ifClass, Meta.CppNamespaceCode));

		outputCpp("\n");

		/* cl_interface */
		// port: List.fold_right var_folder then fun_folder: the functions end up before the variables.
		var members = ["\t::String(null())"];
		var i = tcppInterface.ifVariables.length;
		while (--i >= 0) {
			var cur = tcppInterface.ifVariables[i];
			if (reflective(tcppInterface.ifClass, cur)) members = [strq(cur.cfName)].concat(members);
		}
		var i = tcppInterface.ifFunctions.length;
		while (--i >= 0) {
			var cur = tcppInterface.ifFunctions[i];
			if (reflective(tcppInterface.ifClass, cur.iffField)) members = [strq(cur.iffField.cfName)].concat(members);
		}
		members = members.map(function(n) return '\t$n');

		var sMemberFields = if (members.length > 1) {
			var memberFields = tcppInterface.ifName + "_sMemberFields";
			var concat = members.join(",\n");

			outputCpp('static ::String $memberFields[] = {\n$concat\n};\n\n');

			memberFields;
		} else "0 /* sMemberFields */";

		var allFunctions = allInterfaceFunctions(tcppInterface);

		if (tcppInterface.ifScriptable) {
			function dumpScriptField(idx:Int, func:TcppInterfaceFunction):Void {
				var args = printRetypedTfunArgList(true, func.iffArgs);
				var returnType = tcppToString(func.iffReturn);
				var ret = if (returnType == "Void" || returnType == "void") " " else "return ";

				outputCpp("\t" + returnType + " " + func.iffName + "( " + args + " ) {\n");
				outputCpp("\t\t::hx::CppiaCtx *__ctx = ::hx::CppiaCtx::getCurrent();\n");
				outputCpp("\t\t::hx::AutoStack __as(__ctx);\n");
				outputCpp("\t\t__ctx->pushObject(this);\n");
				for (arg in func.iffArgs) {
					var scriptType = switch CppCppia.toScriptType(arg.tfaType) {
						case ScriptInt | ScriptFloat | ScriptBool if (arg.tfaOptional): ScriptObject;
						case other: other;
					}
					outputCpp('\t\t__ctx->push${CppCppia.toScriptTypeString(scriptType)}(${arg.tfaName});\n');
				}
				var interfaceSlot = Std.string(func.iffScriptSlot == null ? 0 : -func.iffScriptSlot);
				outputCpp("\t\t" + ret + "__ctx->run" + CppCppia.toScriptTypeString(CppCppia.toScriptType(func.iffReturn)) + "(__GetScriptVTable()[" + interfaceSlot
					+ "]);\n");
				outputCpp("\t}\n");
			}

			var scriptName = tcppInterface.ifName + "__scriptable";

			outputCpp("class " + scriptName + " : public ::hx::Object {\n");
			outputCpp("public:\n");

			for (i in 0...allFunctions.length) dumpScriptField(i, allFunctions[i]);
			outputCpp("};\n\n");

			function generateScriptFunction(func:TcppInterfaceFunction):{signature:String, func:TcppInterfaceFunction} {
				var scriptName = ("__s_" + func.iffField.cfName);

				outputCpp("\nstatic void CPPIA_CALL " + scriptName + "(::hx::CppiaCtx *ctx) {\n");

				var scriptReturnType = CppCppia.toScriptType(func.iffReturn);

				switch func.iffReturn {
					case TCppVoid:
					case TCppMarshalNativeType(nativeType, _):
						outputCpp('ctx->return${CppCppia.toScriptTypeString(scriptReturnType)}(${tcppToString(TCppMarshalNativeType(nativeType, Reference))}(');
					case _:
						outputCpp('ctx->return${CppCppia.toScriptTypeString(scriptReturnType)}(');
				}

				var signature = {
					outputCpp(tcppInterface.ifName + "::" + func.iffName + "(ctx->getThis()" + if (func.iffArgs.length > 0) "," else "");

					var signature = CppCppia.toScriptTypeSignature(scriptReturnType), sep = "", size = "sizeof(void*)";
					for (arg in func.iffArgs) {
						var scriptType = switch CppCppia.toScriptType(arg.tfaType) {
							case ScriptInt | ScriptFloat | ScriptBool if (arg.tfaOptional): ScriptObject;
							case other: other;
						}
						outputCpp('${sep}ctx->get${CppCppia.toScriptTypeString(scriptType)}($size)');
						signature = signature + CppCppia.toScriptTypeSignature(scriptType);
						sep = ",";
						size = size + "+sizeof(" + CppCppia.toScriptTypeSize(scriptType) + ")";
					}
					outputCpp(")");
					signature;
				}

				switch func.iffReturn {
					case TCppVoid:
					case TCppMarshalNativeType(nativeType, _):
						outputCpp("))");
					case _:
						outputCpp(")");
				}
				outputCpp(";\n}\n");
				return {signature: signature, func: func};
			}

			switch allFunctions {
				case []:
					outputCpp("static ::hx::ScriptNamedFunction *__scriptableFunctions = 0;\n");
				case _:
					var sigAndFuncs = allFunctions.map(generateScriptFunction);

					outputCpp("static ::hx::ScriptNamedFunction __scriptableFunctions[] = {\n");
					function dumpFunc(sf:{signature:String, func:TcppInterfaceFunction}):Void {
						outputCpp('\t::hx::ScriptNamedFunction("${sf.func.iffField.cfName}", __s_${sf.func.iffField.cfName}, "${sf.signature}", false),\n');
					}
					for (sf in sigAndFuncs) dumpFunc(sf);
					outputCpp("\t::hx::ScriptNamedFunction() };\n");
			}

			function mapper(f:TcppInterfaceFunction):String return '\t${cppTfunSignature(true, f.iffArgs, f.iffReturn)}&$scriptName::${f.iffName}';
			var strings = allFunctions.map(mapper).join(",\n");

			outputCpp('\n\n${tcppInterface.ifName} ${tcppInterface.ifName}_scriptable = {\n$strings\n};\n');
		}

		var classNameText = joinClassPath(classPath, ".");

		outputCpp("::hx::Class " + tcppInterface.ifName + "::__mClass;\n\n");

		outputCpp("void " + tcppInterface.ifName + "::__register()\n{\n");

		outputCpp("\t::hx::Static(__mClass) = new ::hx::Class_obj();\n");
		outputCpp("\t__mClass->mName = " + strq(classNameText) + ";\n");
		outputCpp("\t__mClass->mSuper = &super::__SGetClass();\n");
		outputCpp("\t__mClass->mMembers = ::hx::Class_obj::dupFunctions(" + sMemberFields + ");\n");
		outputCpp("\t__mClass->mCanCast = ::hx::TIsInterface< (int)" + tcppInterface.ifHash + " >;\n");
		outputCpp("\t::hx::_hx_RegisterClass(__mClass->mName, __mClass);\n");
		if (tcppInterface.ifScriptable)
			outputCpp("  HX_SCRIPTABLE_REGISTER_INTERFACE(\"" + classNameText + "\"," + tcppInterface.ifName + ");\n");
		outputCpp("}\n\n");

		if (hasBootField(tcppInterface.ifClass)) {
			outputCpp("void " + tcppInterface.ifName + "::__boot()\n{\n");

			var dotName = joinClassPath(tcppInterface.ifClass.clPath, ".");

			switch tcppInterface.ifMeta {
				case null:
				case expr: genCppInit(ctx, dotName, "boot", "__mClass->__meta__ = ", expr);
			}

			switch tcppInterface.ifRtti {
				case null:
				case expr: genCppInit(ctx, dotName, "boot", "__mClass->__rtti__ = ", expr);
			}

			outputCpp("}\n\n");
		}

		endNamespace(outputCpp, classPath);

		if (Meta.has(Meta.ObjcProtocol, tcppInterface.ifClass.clMeta)) {
			var fullClassName = ("::" + joinClassPathRemap(classPath, "::")) + "_obj";
			var protocol = switch Ast.getMetaString(tcppInterface.ifClass.clMeta, Meta.ObjcProtocol) {
				case null: "";
				case p: p;
			}
			generateProtocolDelegate(ctx, fullClassName, protocol, allFunctions, outputCpp);
			outputCpp("id<" + protocol + "> " + fullClassName + "::_hx_toProtocol(::Dynamic inImplementation) {\n");
			outputCpp("\treturn [ [_hx_" + protocol + "_delegate alloc] initWithImplementation:inImplementation.mPtr];\n");
			outputCpp("}\n\n");
		}

		cppFile.close();
	}
}
