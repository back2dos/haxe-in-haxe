package context;

import core.Globals.GlobalTypePath;
import core.TType.TExpr;

/**
	The capture policy tells which handling we make of captured locals
	(the locals which are referenced in local functions)

	See details/implementation in Codegen.captured_vars
**/
enum CapturePolicy {
	/** do nothing, let the platform handle it **/
	CPNone;

	/** wrap all captured variables into a single-element array to allow modifications **/
	CPWrapRef;

	/** similar to wrap ref, but will only apply to the locals that are declared in loops **/
	CPLoopVars;
}

@:structInit class ExceptionsConfig {
	// Base types which may be thrown from Haxe code without wrapping.
	public var ecNativeThrows:Array<GlobalTypePath>;
	// Base types which may be caught from Haxe code without wrapping.
	public var ecNativeCatches:Array<GlobalTypePath>;
	/*
		Hint exceptions filter to avoid wrapping for targets, which can throw/catch any type
		Ignored on targets with a specific native base type for exceptions.
	*/
	public var ecAvoidWrapping:Bool;
	// Path of a native class or interface, which can be used for wildcard catches.
	public var ecWildcardCatch:GlobalTypePath;
	/*
		Path of a native base class or interface, which can be thrown.
		This type is used to cast `haxe.Exception.thrown(v)` calls to.
		For example `throw 123` is compiled to `throw (cast Exception.thrown(123):ec_base_throw)`
	*/
	public var ecBaseThrow:GlobalTypePath;
	/*
		Checks if throwing this expression is a special case for current target
		and should not be modified.
	*/
	public var ecSpecialThrow:TExpr->Bool;

	public inline function new(ecNativeThrows:Array<GlobalTypePath>, ecNativeCatches:Array<GlobalTypePath>, ecAvoidWrapping:Bool,
			ecWildcardCatch:GlobalTypePath, ecBaseThrow:GlobalTypePath, ecSpecialThrow:TExpr->Bool) {
		this.ecNativeThrows = ecNativeThrows;
		this.ecNativeCatches = ecNativeCatches;
		this.ecAvoidWrapping = ecAvoidWrapping;
		this.ecWildcardCatch = ecWildcardCatch;
		this.ecBaseThrow = ecBaseThrow;
		this.ecSpecialThrow = ecSpecialThrow;
	}

	public inline function clone():ExceptionsConfig return new ExceptionsConfig(ecNativeThrows, ecNativeCatches, ecAvoidWrapping,
		ecWildcardCatch, ecBaseThrow, ecSpecialThrow);
}

enum VarScope {
	FunctionScope;
	BlockScope;
}

enum VarScopingFlags {
	/**
		Variables are hoisted in their scope
	**/
	VarHoisting;

	/**
		It's not allowed to shadow existing variables in a scope.
	**/
	NoShadowing;

	/**
		It's not allowed to shadow a `catch` variable.
	**/
	NoCatchVarShadowing;

	/**
		Local vars cannot have the same name as the current top-level package or
		(if in the root package) current class name
	**/
	ReserveCurrentTopLevelSymbol;

	/**
		Local vars cannot have a name used for any top-level symbol
		(packages and classes in the root package)
	**/
	ReserveAllTopLevelSymbols;

	/**
		Reserve all type-paths converted to "flat path" with `Path.flat_path`
	**/
	ReserveAllTypesFlat;

	/**
		List of names cannot be taken by local vars
	**/
	ReserveNames(names:Array<String>);

	/**
		Cases in a `switch` won't have blocks, but will share the same outer scope.
	**/
	SwitchCasesNoBlocks;
}

@:structInit class VarScopingConfig {
	public var vsFlags:Array<VarScopingFlags>;
	public var vsScope:VarScope;

	public inline function new(vsFlags:Array<VarScopingFlags>, vsScope:VarScope) {
		this.vsFlags = vsFlags;
		this.vsScope = vsScope;
	}

	public inline function clone():VarScopingConfig return new VarScopingConfig(vsFlags, vsScope);
}

@:structInit class PlatformConfig {
	/** has a static type system, with not-nullable basic types (Int/Float/Bool) **/
	public var pfStatic:Bool;

	/** has access to the "sys" package **/
	public var pfSys:Bool;

	/** captured variables handling (see before) **/
	public var pfCapturePolicy:CapturePolicy;

	/** when calling a method with optional args, do we replace the missing args with "null" constants **/
	public var pfPadNulls:Bool;

	/** add a final return to methods not having one already - prevent some compiler warnings **/
	public var pfAddFinalReturn:Bool;

	/** does the platform natively support overloaded functions **/
	public var pfOverload:Bool;

	/** can the platform use default values for non-nullable arguments **/
	public var pfCanSkipNonNullableArgument:Bool;

	/** type paths that are reserved on the platform **/
	public var pfReservedTypePaths:Array<GlobalTypePath>;

	/** supports function == function **/
	public var pfSupportsFunctionEquality:Bool;

	/** uses utf16 encoding with ucs2 api **/
	public var pfUsesUtf16:Bool;

	/** target supports accessing `this` before calling `super(...)` **/
	public var pfThisBeforeSuper:Bool;

	/** target supports threads **/
	public var pfSupportsThreads:Bool;

	/** target supports Unicode **/
	public var pfSupportsUnicode:Bool;

	/** target supports rest arguments **/
	public var pfSupportsRestArgs:Bool;

	/** exceptions handling config **/
	public var pfExceptions:ExceptionsConfig;

	/** the scoping of local variables **/
	public var pfScoping:VarScopingConfig;

	/** target supports atomic operations via haxe.Atomic **/
	public var pfSupportsAtomics:Bool;

	public inline function new(pfStatic:Bool, pfSys:Bool, pfCapturePolicy:CapturePolicy, pfPadNulls:Bool, pfAddFinalReturn:Bool,
			pfOverload:Bool, pfCanSkipNonNullableArgument:Bool, pfReservedTypePaths:Array<GlobalTypePath>,
			pfSupportsFunctionEquality:Bool, pfUsesUtf16:Bool, pfThisBeforeSuper:Bool, pfSupportsThreads:Bool, pfSupportsUnicode:Bool,
			pfSupportsRestArgs:Bool, pfExceptions:ExceptionsConfig, pfScoping:VarScopingConfig, pfSupportsAtomics:Bool) {
		this.pfStatic = pfStatic;
		this.pfSys = pfSys;
		this.pfCapturePolicy = pfCapturePolicy;
		this.pfPadNulls = pfPadNulls;
		this.pfAddFinalReturn = pfAddFinalReturn;
		this.pfOverload = pfOverload;
		this.pfCanSkipNonNullableArgument = pfCanSkipNonNullableArgument;
		this.pfReservedTypePaths = pfReservedTypePaths;
		this.pfSupportsFunctionEquality = pfSupportsFunctionEquality;
		this.pfUsesUtf16 = pfUsesUtf16;
		this.pfThisBeforeSuper = pfThisBeforeSuper;
		this.pfSupportsThreads = pfSupportsThreads;
		this.pfSupportsUnicode = pfSupportsUnicode;
		this.pfSupportsRestArgs = pfSupportsRestArgs;
		this.pfExceptions = pfExceptions;
		this.pfScoping = pfScoping;
		this.pfSupportsAtomics = pfSupportsAtomics;
	}

	public inline function clone():PlatformConfig return new PlatformConfig(pfStatic, pfSys, pfCapturePolicy, pfPadNulls,
		pfAddFinalReturn, pfOverload, pfCanSkipNonNullableArgument, pfReservedTypePaths, pfSupportsFunctionEquality, pfUsesUtf16,
		pfThisBeforeSuper, pfSupportsThreads, pfSupportsUnicode, pfSupportsRestArgs, pfExceptions, pfScoping, pfSupportsAtomics);
}
