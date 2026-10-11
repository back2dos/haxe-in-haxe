package generators.cpp;

import core.Globals.Pos;

enum CppErrorKind {
	InternalError;
	MissingValueSemantics;
	NativeMarshallingFunctionClosures;
	InvalidMarshallingTypeParameter;
	PointerTypeConstructor;
	ValueTypeUndefined;
	InvalidNamespaceField;
	InvalidTypeField;
	InvalidFlagsField;
	ExtendingManagedType;
	UnresolvedTypeParameter(s:String);
	PromotedStackOnlyValueType;
	HeapAllocationOfValueType;
	InvalidIntrinsicUse;
}

class CppError {
	public static function cppAbort(error:CppErrorKind, pos:Pos):Dynamic {
		function print(n:Int, s:String):String return "CPP" + StringTools.lpad(Std.string(n), "0", 4) + ": " + s;
		var str = switch error {
			case InternalError: print(0, "Internal compiler error");
			case MissingValueSemantics: print(1, "Marshalling type extern must be annotated with value semantics");
			case NativeMarshallingFunctionClosures: print(2, "Native marshalling types cannot have function closures created for them");
			case InvalidMarshallingTypeParameter: print(3, "Invalid parameter for a marshalling type");
			case PointerTypeConstructor: print(4, "Pointer type cannot have a constructor");
			case ValueTypeUndefined: print(5, "Marshalling value type extern cannot be used for a variable declaration with no expression");
			case InvalidNamespaceField: print(6, "Namespace field must be an array declaration of string literals");
			case InvalidTypeField: print(7, "Type field must be a string literal");
			case InvalidFlagsField: print(8, "Flags field must be an array of identifiers");
			case ExtendingManagedType: print(9, "Class cannot extend a managed type extern");
			case UnresolvedTypeParameter(s): print(10, 'Unable to resolve parameter $s, consider adding a type hint');
			case PromotedStackOnlyValueType: print(11, "Marshalling value type with the StackOnly flag cannot be promoted to the heap");
			case HeapAllocationOfValueType: print(12, "Value type cannot be allocated directly to a pointer");
			case InvalidIntrinsicUse: print(13, "Intrinsic functions can only be directly called");
		}
		return core.Error.abort(str, pos);
	}
}
