package core;

import core.Ast.Binop;
import core.Ast.ClassField;
import core.Ast.Documentation;
import core.Ast.Expr;
import core.Ast.Metadata;
import core.Ast.MetadataEntry;
import core.Ast.QuoteStatus;
import core.Ast.Unop;
import core.Ast.UnopFlag;
import core.Ast.WhileFlag;
import core.ds.AtomicLazy;
import core.Globals.GlobalTypePath;
import core.Globals.Pos;
import core.Message.CompilerMessage;
import haxe.ds.IntMap;
import haxe.ds.StringMap;

// Direct structural port of haxe/src/core/tType.ml.  This is deliberately a
// data model only; typing operations belong to the typing modules.
typedef TypeMap<T> = StringMap<T>;

enum FieldKind { Var(kind:VarKind); Method(kind:MethodKind); }
typedef VarKind = { var vRead:VarAccess; var vWrite:VarAccess; }
enum VarAccess { AccNormal; AccNo; AccNever; AccCtor; AccCall; AccPrivateCall; AccInline; AccRequire(condition:String, message:Null<String>); }
enum MethodKind { MethNormal; MethInline; MethDynamic; MethMacro; }
enum ModuleCheckPolicy { NoFileSystemCheck; CheckFileModificationTime; CheckFileContentModification; }
enum ModuleTaintingReason { CheckDisplayFile; DefineType; DefineModule; ServerInvalidate; ServerInvalidateFiles; ServerInvalidateModule; }
enum ModuleSkipReason { DependencyDirty(path:GlobalTypePath, reason:ModuleSkipReason); Tainted(reason:ModuleTaintingReason); FileChanged(file:String); Shadowed(file:String); LibraryChanged; }
enum ModuleCacheState { MSGood; MSBad(reason:ModuleSkipReason); MSUnknown; }
enum TypeParamHost { TPHType; TPHConstructor; TPHMethod; TPHEnumConstructor; TPHAnonField; TPHLocal; TPHUnbound; }
enum CacheBoundObject { Resource(name:String, data:String); IncludeFile(file:String, contents:String); Message(value:CompilerMessage); }

enum T { TMono(mono:TMono); TEnum(en:TEnum, params:TParams); TInst(cls:TClass, params:TParams); TType(def:TDef, params:TParams); TFun(signature:TSignature); TAnon(anon:TAnon); TDynamic(inner:Null<T>); TLazy(lazy:TLazy); TAbstract(abs:TAbstract, params:TParams); }
typedef TMono = { var tmType:Null<T>; var tmDownConstraints:Array<TMonoConstraint>; var tmUpConstraints:Array<{var type:T; var name:Null<String>;}>; var tmModifiers:Array<TMonoModifier>; }
enum TMonoConstraint { MMono(mono:TMono, name:Null<String>); MField(field:TClassField); MType(type:T, name:Null<String>); MEmptyStructure; }
enum TMonoConstraintKind { CUnknown; CStructural(fields:TypeMap<TClassField>, open:Bool); CMixed(kinds:Array<TMonoConstraintKind>); CTypes(types:Array<{var type:T; var name:Null<String>;}>); }
enum TMonoModifier { MNullable(callback:T->T); MOpenStructure; MDynamic; }
enum TLazyState { LAvailable(type:T); LProcessing(type:T); LWait(callback:Void->T); }
// tlazy ref: forcing a lazy type updates the cell that every TLazy sharing it sees.
class TLazy {
	public var value:TLazyState;
	public function new(value:TLazyState) this.value = value;
}
typedef TSignature = { var args:Array<{var name:String; var optional:Bool; var type:T;}>; var ret:T; }
typedef TParams = Array<T>;
typedef TypedTypeParam = { var ttpName:String; var ttpClass:TClass; var ttpHost:TypeParamHost; var ttpType:T; var ttpConstraints:Null<AtomicLazy<Array<T>>>; var ttpDefault:Null<T>; }
typedef TypeParams = Array<TypedTypeParam>;
enum TConstant { TInt(value:Int); TFloat(value:String); TString(value:String); TBool(value:Bool); TNull; TThis; TSuper; }
typedef TVarExtra = { var vParams:TypeParams; var vExpr:Null<TExpr>; }
enum TVarOrigin { TVOLocalVariable; TVOArgument; TVOForVariable; TVOPatternVariable; TVOCatchVariable; TVOLocalFunction; }
enum TVarKind { VUser(origin:TVarOrigin); VGenerated; VInlined; VInlinedConstructorVariable(fields:Array<String>); VExtractorVariable; VAbstractThis; }
typedef TVar = { var vId:Int; var vName:String; var vType:T; var vKind:TVarKind; var vExtra:Null<TVarExtra>; var vMeta:Metadata; var vFlags:Int; var vPos:Pos; }
typedef TFunc = { var tfArgs:Array<{var variable:TVar; var defaultValue:Null<TExpr>;}>; var tfType:T; var tfExpr:TExpr; }
enum AnonStatus { Closed; Const; Extend(types:Array<T>); ClassStatics(cls:TClass); EnumStatics(en:TEnum); AbstractStatics(abs:TAbstract); }
typedef TAnon = { var aFields:TypeMap<TClassField>; var aStatus:AnonStatus; }
enum TExprDef { TConst(value:TConstant); TLocal(variable:TVar); TArray(array:TExpr, index:TExpr); TBinop(op:Binop, left:TExpr, right:TExpr); TField(expr:TExpr, access:TFieldAccess); TTypeExpr(type:ModuleType); TParenthesis(expr:TExpr); TObjectDecl(fields:Array<{var key:{var name:String; var pos:Pos; var quote:QuoteStatus;}; var expr:TExpr;}>); TArrayDecl(values:Array<TExpr>); TCall(expr:TExpr, args:Array<TExpr>); TNew(cls:TClass, params:TParams, args:Array<TExpr>); TUnop(op:Unop, flag:UnopFlag, expr:TExpr); TFunction(func:TFunc); TVar(variable:TVar, expr:Null<TExpr>); TBlock(exprs:Array<TExpr>); TIf(condition:TExpr, thenExpr:TExpr, elseExpr:Null<TExpr>); TWhile(condition:TExpr, body:TExpr, flag:WhileFlag); TSwitch(switchExpr:TSwitch); TTry(expr:TExpr, catches:Array<{var variable:TVar; var expr:TExpr;}>); TReturn(expr:Null<TExpr>); TBreak; TContinue; TThrow(expr:TExpr); TCast(expr:TExpr, type:Null<ModuleType>); TMeta(meta:MetadataEntry, expr:TExpr); TEnumParameter(expr:TExpr, field:TEnumField, index:Int); TEnumIndex(expr:TExpr); TIdent(name:String); }
typedef TSwitch = { var switchSubject:TExpr; var switchCases:Array<TSwitchCase>; var switchDefault:Null<TExpr>; var switchExhaustive:Bool; }
typedef TSwitchCase = { var casePatterns:Array<TExpr>; var caseExpr:TExpr; }
enum TFieldAccess { FInstance(cls:TClass, params:TParams, field:TClassField); FStatic(cls:TClass, field:TClassField); FAnon(field:TClassField); FDynamic(name:String); FClosure(cls:Null<{var cls:TClass; var params:TParams;}>, field:TClassField); FEnum(en:TEnum, field:TEnumField); }
typedef TExpr = { var eexpr:TExprDef; var etype:T; var epos:Pos; }
typedef TClassField = { var cfName:String; var cfType:T; var cfPos:Pos; var cfNamePos:Pos; var cfDoc:Documentation; var cfMeta:Metadata; var cfKind:FieldKind; var cfParams:TypeParams; var cfExpr:Null<TExpr>; var cfExprUnoptimized:Null<TExpr>; var cfOverloads:Array<TClassField>; var cfFlags:Int; }
enum TClassKind { KNormal; KTypeParameter(param:TypedTypeParam); KExpr(expr:Expr); KGeneric; KGenericInstance(cls:TClass, params:TParams); KMacroType; KGenericBuild(fields:Array<ClassField>); KAbstractImpl(abs:TAbstract); KModuleFields(module:ModuleDef); }
typedef TInfos = { var mtPath:GlobalTypePath; var mtModule:ModuleDef; var mtPos:Pos; var mtNamePos:Pos; var mtPrivate:Bool; var mtDoc:Documentation; var mtMeta:Metadata; var mtParams:TypeParams; var mtUsing:Array<{var cls:TClass; var pos:Pos;}>; var mtRestore:Void->Void; }
typedef TClass = { var clPath:GlobalTypePath; var clModule:ModuleDef; var clPos:Pos; var clNamePos:Pos; var clPrivate:Bool; var clDoc:Documentation; var clMeta:Metadata; var clParams:TypeParams; var clUsing:Array<{var cls:TClass; var pos:Pos;}>; var clRestore:Void->Void; var clType:T; var clKind:TClassKind; var clFlags:Int; var clSuper:Null<{var cls:TClass; var params:TParams;}>; var clImplements:Array<{var cls:TClass; var params:TParams;}>; var clFields:TypeMap<TClassField>; var clStatics:TypeMap<TClassField>; var clOrderedStatics:Array<TClassField>; var clOrderedFields:Array<TClassField>; var clDynamic:Null<T>; var clArrayAccess:Null<T>; var clConstructor:Null<TClassField>; var clInit:Null<TClassField>; var clBuild:Void->BuildState; var clDescendants:Array<TClass>; }
typedef TEnumField = { var efName:String; var efType:T; var efPos:Pos; var efNamePos:Pos; var efDoc:Documentation; var efIndex:Int; var efParams:TypeParams; var efMeta:Metadata; }
typedef TEnum = { var ePath:GlobalTypePath; var eModule:ModuleDef; var ePos:Pos; var eNamePos:Pos; var ePrivate:Bool; var eDoc:Documentation; var eMeta:Metadata; var eParams:TypeParams; var eUsing:Array<{var cls:TClass; var pos:Pos;}>; var eRestore:Void->Void; var eType:T; var eFlags:Int; var eConstrs:TypeMap<TEnumField>; var eNames:Array<String>; }
typedef TDef = { var tPath:GlobalTypePath; var tModule:ModuleDef; var tPos:Pos; var tNamePos:Pos; var tPrivate:Bool; var tDoc:Documentation; var tMeta:Metadata; var tParams:TypeParams; var tUsing:Array<{var cls:TClass; var pos:Pos;}>; var tRestore:Void->Void; var tType:T; }
typedef TAbstract = { var aPath:GlobalTypePath; var aModule:ModuleDef; var aPos:Pos; var aNamePos:Pos; var aPrivate:Bool; var aDoc:Documentation; var aMeta:Metadata; var aParams:TypeParams; var aUsing:Array<{var cls:TClass; var pos:Pos;}>; var aRestore:Void->Void; var aOps:Array<{var op:Binop; var field:TClassField;}>; var aUnops:Array<{var op:Unop; var flag:UnopFlag; var field:TClassField;}>; var aImpl:Null<TClass>; var aThis:T; var aFrom:Array<T>; var aFromField:Array<{var type:T; var field:TClassField;}>; var aTo:Array<T>; var aToField:Array<{var type:T; var field:TClassField;}>; var aArray:Array<TClassField>; var aRead:Null<TClassField>; var aWrite:Null<TClassField>; var aCall:Null<TClassField>; var aConstructor:Null<TClassField>; var aExtern:Bool; var aEnum:Bool; }
enum ModuleType { TClassDecl(cls:TClass); TEnumDecl(en:TEnum); TTypeDecl(def:TDef); TAbstractDecl(abs:TAbstract); }
typedef ModuleDef = { var mId:Int; var mPath:GlobalTypePath; var mTypes:Array<ModuleType>; var mStatics:Null<TClass>; var mExtra:ModuleDefExtra; }
typedef ModuleDefDisplay = { var mInlineCalls:Array<{var callPos:Pos; var definitionPos:Pos;}>; var mTypeHints:Array<{var hintPos:Pos; var typePos:Pos;}>; var mImportPositions:Map<String, Bool>; }
enum ModuleDepOrigin { MDepFromTyping; MDepFromImport; MDepFromMacro; MDepFromMacroInclude; MDepFromMacroDefine; }
typedef ModuleDep = { var mdSign:String; var mdKind:ModuleKind; var mdPath:GlobalTypePath; var mdOrigin:ModuleDepOrigin; }
typedef ModuleDefExtra = { var mFile:Dynamic; var mSign:String; var mDisplay:ModuleDefDisplay; var mCheckPolicy:Array<ModuleCheckPolicy>; var mTime:Float; var mCacheState:ModuleCacheState; var mAdded:Int; var mChecked:Int; var mProcessed:Int; var mDeps:IntMap<ModuleDep>; var mDisplayDeps:Null<IntMap<ModuleDep>>; var mKind:ModuleKind; var mCacheBoundObjects:Array<CacheBoundObject>; var mFeatures:Map<String, Bool>; }
enum ClassFieldRefKind { CfrStatic; CfrMember; CfrConstructor; CfrInit; }
typedef ClassFieldRef = { var cfrSign:String; var cfrPath:GlobalTypePath; var cfrField:String; var cfrKind:ClassFieldRefKind; var cfrIsMacro:Bool; }
enum ModuleKind { MCode; MMacro; MFake; MExtern; MImport; }
enum BuildState { Built; Building(classes:Array<TClass>); BuildMacro(callbacks:Array<Void->Void>); }
typedef CoroTypes = { var tcoro:AtomicLazy<TSignature->T>; var continuation:AtomicLazy<T>; var suspensionResultClass:AtomicLazy<TClass>; var tasyncIterator:AtomicLazy<T->T>; }
typedef BasicTypes = { var tvoid:T; var tany:T; var tint:T; var tfloat:T; var tbool:T; var tnull:T->T; var tstring:T; var tarray:T->T; var texception:T; var titerator:T->T; var tunit:T; var tcoro:CoroTypes; }
enum ClassFieldScope { CFSStatic; CFSMember; CFSConstructor; }
enum FlagTClass { CExtern; CFinal; CInterface; CAbstract; CFunctionalInterface; CUsed; CExcluded; }
enum FlagTClassField { CfPublic; CfStatic; CfExtern; CfFinal; CfModifiesThis; CfOverride; CfAbstract; CfOverload; CfImpl; CfEnum; CfGeneric; CfDefault; CfPostProcessed; CfUsed; CfMaybeUsed; CfNoLookup; CfAbstractConstructor; }
enum FlagTEnum { EnExtern; EnExcluded; }
enum FlagTVar { VCaptured; VFinal; VAnalyzed; VAssigned; VCaught; VStatic; VUsedByTyper; VHxb; VCoroCaptured; VCoroScope; VCoroRestrictedSuspension; }

class TType {
	public static final flagTClassNames = ["CExtern", "CFinal", "CInterface", "CAbstract", "CFunctionalInterface", "CUsed", "CExcluded"];
	public static final flagTClassFieldNames = ["CfPublic", "CfStatic", "CfExtern", "CfFinal", "CfModifiesThis", "CfOverride", "CfAbstract", "CfOverload", "CfImpl", "CfEnum", "CfGeneric", "CfDefault", "CfPostProcessed", "CfUsed", "CfMaybeUsed", "CfNoLookup", "CfAbstractConstructor"];
	public static final flagTVarNames = ["VCaptured", "VFinal", "VAnalyzed", "VAssigned", "VCaught", "VStatic", "VUsedByTyper", "VHxb", "VCoroCaptured", "VCoroScope", "VRestrictedSuspension"];
}
