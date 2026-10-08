package macros;

import core.Globals.Pos;
import core.Ast;
import core.TType;

/**
	haxe/src/macro/macroApi.ml: the compiler side of the macro API (`compiler_api`)
	and the encoding/decoding of compiler values. Upstream is a functor over the
	interpreter; there is only Eval here, so it uses Eval's values directly.
**/
class InvalidExpr extends haxe.Exception {
	public static final instance = new InvalidExpr();

	public function new() super("Invalid_expr");

	public static inline function raise():InvalidExpr return instance;
}

class Abort extends haxe.Exception {
	public function new() super("Abort");
}

@:structInit class CompilerOptions {
	public var optInlining:Null<Bool>;
	public var optTransform:Null<Bool>;

	public inline function new(optInlining:Null<Bool>, optTransform:Null<Bool>) {
		this.optInlining = optInlining;
		this.optTransform = optTransform;
	}
}

typedef MacroValue = macros.eval.EvalValue.Value;

/** Our access to the compiler from the macro api (`'value compiler_api`). **/
@:structInit class CompilerApi {
	public var pos:Pos;
	public var getCom:Void->context.Common.CommonContext;
	public var getMacroCom:Void->context.Common.CommonContext;
	public var getMacroStack:Void->Array<Pos>;
	public var initMacrosDone:Void->Bool;
	public var getType:String->Null<T>;
	public var getModule:String->Array<T>;
	public var includeModule:String->Void;
	public var afterInitMacros:(Void->Void)->Void;
	public var afterTyping:(Array<ModuleType>->Void)->Void;
	public var onGenerate:(Array<T>->Void)->Bool->Void;
	public var afterGenerate:(Void->Void)->Void;
	public var onTypeNotFound:(String->MacroValue)->Void;
	public var parseString:String->Pos->Bool->Expr;
	public var registerFileContents:String->String->Void;
	// `parse f s`: runs the parser function `f` on the source `s`
	public var parse:(syntax.Parser.ParserContext->core.ds.Stream<syntax.Lexer.LexedToken>->Dynamic)->String->Dynamic;
	public var typeExpr:Expr->TExpr;
	public var resolveType:ComplexType->Pos->T;
	public var resolveComplexType:TypeHint->TypeHint;
	public var storeTypedExpr:TExpr->Expr;
	public var allowPackage:String->Void;
	public var getLocalType:Void->Null<T>;
	public var getExpectedType:Void->Null<T>;
	public var getCallArguments:Void->Null<Array<Expr>>;
	public var getLocalMethod:Void->String;
	public var getLocalImports:Void->Array<Import>;
	public var getLocalUsing:Void->Array<TClass>;
	public var getLocalVars:Void->haxe.ds.StringMap<TVar>;
	public var getBuildFields:Void->MacroValue;
	public var defineType:MacroValue->Null<String>->Void;
	public var defineModule:String->Array<MacroValue>->Array<{path:Array<PlacedName>, mode:ImportMode}>->Array<TypePath>->Void;
	public var moduleDependency:String->String->Void;
	public var currentModule:Void->ModuleDef;
	public var formatString:String->Pos->Expr;
	public var castOrUnify:T->TExpr->Pos->Bool;
	public var addGlobalMetadata:String->String->{a:Bool, b:Bool, c:Bool}->Pos->Void;
	public var registerDefine:String->core.Define.UserDefine->Void;
	public var registerMetadata:String->core.Meta.UserMeta->Void;
	public var addModuleCheckPolicy:Array<String>->Array<Int>->Bool->Void;
	public var decodeExpr:MacroValue->Expr;
	public var encodeExpr:Expr->MacroValue;
	public var encodeCtype:TypeHint->MacroValue;
	public var decodeType:MacroValue->T;
	public var info:(msg:String, p:Pos, ?depth:Int) -> Void;
	public var warning:(w:core.Message.WarningCode, msg:String, p:Pos, ?depth:Int) -> Void;
	public var displayError:(msg:String, p:Pos, ?sub:Array<core.Error.MacroError>) -> Void;
	// `with_imports imports usings f`
	public var withImports:Array<Import>->Array<Array<PlacedName>>->(Void->Dynamic)->Dynamic;
	public var withOptions:CompilerOptions->(Void->Dynamic)->Dynamic;
	public var excString:String->Dynamic;
	public var getHxbWriterConfig:Void->MacroValue;
	public var setHxbWriterConfig:MacroValue->Void;

	public function new(pos, getCom, getMacroCom, getMacroStack, initMacrosDone, getType, getModule, includeModule, afterInitMacros, afterTyping, onGenerate,
			afterGenerate, onTypeNotFound, parseString, registerFileContents, parse, typeExpr, resolveType, resolveComplexType, storeTypedExpr, allowPackage,
			getLocalType, getExpectedType, getCallArguments, getLocalMethod, getLocalImports, getLocalUsing, getLocalVars, getBuildFields, defineType,
			defineModule, moduleDependency, currentModule, formatString, castOrUnify, addGlobalMetadata, registerDefine, registerMetadata,
			addModuleCheckPolicy, decodeExpr, encodeExpr, encodeCtype, decodeType, info, warning, displayError, withImports, withOptions, excString,
			getHxbWriterConfig, setHxbWriterConfig) {
		this.pos = pos;
		this.getCom = getCom;
		this.getMacroCom = getMacroCom;
		this.getMacroStack = getMacroStack;
		this.initMacrosDone = initMacrosDone;
		this.getType = getType;
		this.getModule = getModule;
		this.includeModule = includeModule;
		this.afterInitMacros = afterInitMacros;
		this.afterTyping = afterTyping;
		this.onGenerate = onGenerate;
		this.afterGenerate = afterGenerate;
		this.onTypeNotFound = onTypeNotFound;
		this.parseString = parseString;
		this.registerFileContents = registerFileContents;
		this.parse = parse;
		this.typeExpr = typeExpr;
		this.resolveType = resolveType;
		this.resolveComplexType = resolveComplexType;
		this.storeTypedExpr = storeTypedExpr;
		this.allowPackage = allowPackage;
		this.getLocalType = getLocalType;
		this.getExpectedType = getExpectedType;
		this.getCallArguments = getCallArguments;
		this.getLocalMethod = getLocalMethod;
		this.getLocalImports = getLocalImports;
		this.getLocalUsing = getLocalUsing;
		this.getLocalVars = getLocalVars;
		this.getBuildFields = getBuildFields;
		this.defineType = defineType;
		this.defineModule = defineModule;
		this.moduleDependency = moduleDependency;
		this.currentModule = currentModule;
		this.formatString = formatString;
		this.castOrUnify = castOrUnify;
		this.addGlobalMetadata = addGlobalMetadata;
		this.registerDefine = registerDefine;
		this.registerMetadata = registerMetadata;
		this.addModuleCheckPolicy = addModuleCheckPolicy;
		this.decodeExpr = decodeExpr;
		this.encodeExpr = encodeExpr;
		this.encodeCtype = encodeCtype;
		this.decodeType = decodeType;
		this.info = info;
		this.warning = warning;
		this.displayError = displayError;
		this.withImports = withImports;
		this.withOptions = withOptions;
		this.excString = excString;
		this.getHxbWriterConfig = getHxbWriterConfig;
		this.setHxbWriterConfig = setHxbWriterConfig;
	}

	public function clone():CompilerApi {
		return new CompilerApi(pos, getCom, getMacroCom, getMacroStack, initMacrosDone, getType, getModule, includeModule, afterInitMacros, afterTyping,
			onGenerate, afterGenerate, onTypeNotFound, parseString, registerFileContents, parse, typeExpr, resolveType, resolveComplexType, storeTypedExpr,
			allowPackage, getLocalType, getExpectedType, getCallArguments, getLocalMethod, getLocalImports, getLocalUsing, getLocalVars, getBuildFields,
			defineType, defineModule, moduleDependency, currentModule, formatString, castOrUnify, addGlobalMetadata, registerDefine, registerMetadata,
			addModuleCheckPolicy, decodeExpr, encodeExpr, encodeCtype, decodeType, info, warning, displayError, withImports, withOptions, excString,
			getHxbWriterConfig, setHxbWriterConfig);
	}

	/**
		A null compiler API that holds no references to any compilation context,
		used to clear the interpreter's curapi between compilations. Any access fails.
	**/
	public static function nullApi():CompilerApi {
		function die():Dynamic return core.Globals.die("Macro API accessed after compilation cleanup", "MacroApi.nullApi");
		return new CompilerApi(core.Globals.nullPos, () -> die(), () -> die(), () -> die(), () -> die(), _ -> die(), _ -> die(), _ -> die(), _ -> die(),
			_ -> die(), (_, _) -> die(), _ -> die(), _ -> die(), (_, _, _) -> die(), (_, _) -> die(), (_, _) -> die(), _ -> die(), (_, _) -> die(),
			_ -> die(), _ -> die(), _ -> die(), () -> die(), () -> die(), () -> die(), () -> die(), () -> die(), () -> die(), () -> die(), () -> die(),
			(_, _) -> die(), (_, _, _, _) -> die(), (_, _) -> die(), () -> die(), (_, _) -> die(), (_, _, _) -> die(), (_, _, _, _) -> die(),
			(_, _) -> die(), (_, _) -> die(), (_, _, _) -> die(), _ -> die(), _ -> die(), _ -> die(), _ -> die(), (_, _, ?_) -> die(), (_, _, _, ?_) -> die(),
			(_, _, ?_) -> die(), (_, _, _) -> die(), (_, _) -> die(), _ -> die(), () -> die(), _ -> die());
	}
}

enum EnumType {
	IExpr;
	IEFieldKind;
	IBinop;
	IUnop;
	IConst;
	ITParam;
	ICType;
	IField;
	IType;
	IFieldKind;
	IMethodKind;
	IVarAccess;
	IAccess;
	IClassKind;
	ITypedExpr;
	ITConstant;
	IModuleType;
	IFieldAccess;
	IAnonStatus;
	IQuoteStatus;
	IImportMode;
	IDisplayKind;
	IDisplayMode;
	ICapturePolicy;
	IVarScope;
	IVarScopingFlags;
	IPlatform;
	IPackageRule;
	IMessage;
	IFunctionKind;
	IStringLiteralKind;
}
