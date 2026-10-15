package generators.cpp.filters;

import generators.cpp.CppAst;
import generators.cpp.CppAstTools.*;
import generators.cpp.CppError;

class CppFilterValueType {
	/* If we are constructing a value type of reference state, inspect the surrounding context and choose a more appropriate construction */
	public static function filterDetermineConstruction(returnType:Tcpp, cppexpr:TcppExpr):TcppExpr {
		function mkCppexpr(newExpr:TcppExprExpr, newType:Tcpp):TcppExpr return {cppexpr: newExpr, cpptype: newType, cpppos: cppexpr.cpppos};

		return switch [cppexpr.cpptype, returnType, cppexpr.cppexpr] {
			/* Allocating a value type directly into a pointer type is ambiguous at best and UB C++ at worse, so forbid it entirely */
			case [_, TCppStar(TCppMarshalNativeType(ValueClass(_) | ValueEnum(_), _), _), CppCall(FuncNew(_), _)] |
				[_, TCppPointer(_, TCppMarshalNativeType(ValueClass(_) | ValueEnum(_), _)), CppCall(FuncNew(_), _)] |
				[_, TCppRawPointer(_, TCppMarshalNativeType(ValueClass(_) | ValueEnum(_), _)), CppCall(FuncNew(_), _)]:
				CppError.cppAbort(HeapAllocationOfValueType, cppexpr.cpppos);
			case [TCppMarshalNativeType(valueType, Reference), TCppMarshalNativeType(_, Stack), CppCall(FuncNew(_), args)]:
				var stack = TCppMarshalNativeType(valueType, Stack);
				{cppexpr: CppCall(FuncNew(stack), args), cpptype: stack, cpppos: cppexpr.cpppos};
			case [TCppMarshalNativeType(valueType, Reference), TCppMarshalNativeType(_, Promoted), CppCall(FuncNew(_), args)]:
				var promoted = TCppMarshalNativeType(valueType, Promoted);
				{cppexpr: CppCall(FuncNew(promoted), args), cpptype: promoted, cpppos: cppexpr.cpppos};
			/* When constructing to a reference we lack enough info to make a more precise choice */
			/* So just allocate on the stack and wrap in a reference */
			/* This comes up with function calls e.g. foo(new MyValueType()) */
			/* TFun does not give us enough info to make a more precise allocation */
			case [TCppMarshalNativeType(valueType, Reference), _, CppCall(FuncNew(_), args)]:
				var stack = TCppMarshalNativeType(valueType, Stack);
				var reference = TCppMarshalNativeType(valueType, Reference);
				mkCppexpr(CppCast({cppexpr: CppCall(FuncNew(stack), args), cpptype: stack, cpppos: cppexpr.cpppos}, reference), reference);
			case _:
				cppexpr;
		}
	}

	/* Handle casting to and from value type enums and scalar values */
	public static function filterValueEnumCasting(returnType:Tcpp, cppexpr:TcppExpr):TcppExpr {
		function mkCppexpr(newExpr:TcppExprExpr, newType:Tcpp):TcppExpr return {cppexpr: newExpr, cpptype: newType, cpppos: cppexpr.cpppos};

		return switch [cppexpr.cpptype, returnType] {
			/* Casting from from a scalar to a value type enum */
			case [TCppScalar(s), TCppMarshalNativeType(ValueEnum(abs), Stack | Promoted)]:
				var casted = mkCppexpr(CppCastScalar(cppexpr, getNativeMarshalledType(ValueEnum(abs))), returnType);
				mkCppexpr(CppCall(FuncNew(returnType), [casted]), returnType);
			case [TCppScalar(s), TCppMarshalNativeType(e = ValueEnum(_), Reference)]:
				var promoted = filterValueEnumCasting(TCppMarshalNativeType(e, Promoted), cppexpr);
				mkCppexpr(CppCast(promoted, returnType), returnType);
			/* Casting going from a value type enum to a scalar */
			case [TCppMarshalNativeType(e = ValueEnum(_), Stack | Promoted), TCppScalar(s)]:
				var reference = TCppMarshalNativeType(e, Reference);
				var casted = mkCppexpr(CppCast(cppexpr, reference), reference);
				filterValueEnumCasting(returnType, casted);
			case [TCppMarshalNativeType(ValueEnum(_), Reference), TCppScalar(s)]:
				var dereference = mkCppexpr(CppDereference(cppexpr), cppexpr.cpptype);
				mkCppexpr(CppCastScalar(dereference, s), returnType);
			case _:
				cppexpr;
		}
	}

	public static function filterAddBoxedPointerConstruction(returnType:Tcpp, cppexpr:TcppExpr):TcppExpr {
		function mkCppexpr(newExpr:TcppExprExpr, newType:Tcpp):TcppExpr return {cppexpr: newExpr, cpptype: newType, cpppos: cppexpr.cpppos};

		return switch [returnType, cppexpr.cppexpr] {
			/* | CppVarDecl (var, Some expr) when is_pointer_type var.tcppv_type ->
				let construct = mk_cppexpr (CppCall ((FuncNew var.tcppv_type), [ expr ])) var.tcppv_type in
				{ cppexpr with cppexpr = CppVarDecl(var, Some construct) }
				| CppVarDecl (var, None) when is_pointer_type var.tcppv_type ->
				let construct = mk_cppexpr (CppCall ((FuncNew var.tcppv_type), [])) var.tcppv_type in
				{ cppexpr with cppexpr = CppVarDecl(var, Some construct) } */
			case [TCppMarshalNativeType(Pointer(_), Stack | Promoted), CppNull]:
				mkCppexpr(CppCall(FuncNew(returnType), [cppexpr]), returnType);
			case [TCppMarshalNativeType(valueType = Pointer(_), Reference), CppNull]:
				var stack = TCppMarshalNativeType(valueType, Stack);
				var ctor = mkCppexpr(CppCall(FuncNew(stack), [cppexpr]), stack);
				mkCppexpr(CppCast(ctor, returnType), returnType);
			case _:
				cppexpr;
		}
	}
}
