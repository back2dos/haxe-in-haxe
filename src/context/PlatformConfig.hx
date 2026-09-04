package context;
import core.Globals.GlobalTypePath;
import core.TType.TExpr;
// Draft mechanical translation of haxe/src/context/platformConfig.ml; unvalidated.
enum CapturePolicy { CPNone; CPWrapRef; CPLoopVars; }
typedef ExceptionsConfig = {
	var ecNativeThrows:Array<GlobalTypePath>;
	var ecNativeCatches:Array<GlobalTypePath>;
	var ecAvoidWrapping:Bool;
	var ecWildcardCatch:GlobalTypePath;
	var ecBaseThrow:GlobalTypePath;
	var ecSpecialThrow:TExpr->Bool;
}
enum VarScope { FunctionScope; BlockScope; }
enum VarScopingFlags {
	VarHoisting;
	NoShadowing;
	NoCatchVarShadowing;
	ReserveCurrentTopLevelSymbol;
	ReserveAllTopLevelSymbols;
	ReserveAllTypesFlat;
	ReserveNames(names:Array<String>);
	SwitchCasesNoBlocks;
}
typedef VarScopingConfig = { var vsFlags:Array<VarScopingFlags>; var vsScope:VarScope; }
typedef PlatformConfig = {
	var pfStatic:Bool;
	var pfSys:Bool;
	var pfCapturePolicy:CapturePolicy;
	var pfPadNulls:Bool;
	var pfAddFinalReturn:Bool;
	var pfOverload:Bool;
	var pfCanSkipNonNullableArgument:Bool;
	var pfReservedTypePaths:Array<GlobalTypePath>;
	var pfSupportsFunctionEquality:Bool;
	var pfUsesUtf16:Bool;
	var pfThisBeforeSuper:Bool;
	var pfSupportsThreads:Bool;
	var pfSupportsUnicode:Bool;
	var pfSupportsRestArgs:Bool;
	var pfExceptions:ExceptionsConfig;
	var pfScoping:VarScopingConfig;
	var pfSupportsAtomics:Bool;
}
