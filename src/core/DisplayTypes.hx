package core;

import Type as StdType;
import core.Globals.Pos;
import core.Ast;
import core.TType;
import core.TFunctions.*;
// haxe/src/core/displayTypes.ml — mechanical shared-model draft; not compile-validated.
// Completion serialization remains references to deferred display/JSON helpers.
enum SymbolKindValue { Class;Interface;Enum;TypeAlias;Abstract;Field;Property;Method;Constructor;Function;Variable;Struct;EnumAbstract;Operator;EnumMember;Constant;Module; }
class SymbolKind {public static function toInt(kind:SymbolKindValue):Int return StdType.enumIndex(kind)+1;}
typedef SymbolInformationData={var name:String;var kind:SymbolKindValue;var pos:Pos;var containerName:Null<String>;var deprecated:Bool;}
class SymbolInformation {public static function make(name:String,kind:SymbolKindValue,pos:Pos,containerName:Null<String>,deprecated:Bool):SymbolInformationData return {name:name,kind:kind,pos:pos,containerName:containerName,deprecated:deprecated};}
typedef ExpectedTypeCompletion={var expectedType:Dynamic;var expectedTypeFollowed:Dynamic;var compatibleTypes:Array<Dynamic>;}
enum CompletionResultKindValue {
 CRField(item:Dynamic,pos:Pos,iterator:Null<T>,keyValueIterator:Null<{key:T,value:T}>);CRStructureField;CRToplevel(expected:Null<ExpectedTypeCompletion>);CRMetadata;CRTypeHint;CRExtends;CRImplements;CRStructExtension(intersection:Bool);CRImport;CRUsing;CRNew;CRPattern(expected:Null<ExpectedTypeCompletion>,outermost:Bool);CROverride;CRTypeRelation;CRTypeDecl;
}
// CompletionResultKind.toJson is preserved in deferred/display/CompletionResultKind.hx.
// It serves display protocol serialization and has no HXB-path callers.
enum DisplayModeValue { DMNone;DMDefault;DMUsage(definition:Bool,descendants:Bool,base:Bool);DMDefinition;DMTypeDefinition;DMImplementation;DMPackage;DMHover;DMModuleSymbols(filter:Null<String>);DMSignature; }
enum ErrorPolicy { EPIgnore;EPShow; }
enum DisplayFilePolicy { DFPOnly;DFPAlso;DFPNo; }
typedef DisplaySettings={var dmsKind:DisplayModeValue;var dmsFullTyping:Bool;var dmsForceMacroTyping:Bool;var dmsErrorPolicy:ErrorPolicy;var dmsCheckCoreApi:Bool;var dmsInline:Bool;var dmsDisplayFilePolicy:DisplayFilePolicy;var dmsExitDuringTyping:Bool;var dmsPopulateCache:Bool;var dmsPerFile:Bool;}
class DisplayMode {
 public static final defaultDisplaySettings:DisplaySettings={dmsKind:DMDefault,dmsFullTyping:false,dmsForceMacroTyping:false,dmsErrorPolicy:EPIgnore,dmsCheckCoreApi:false,dmsInline:false,dmsDisplayFilePolicy:DFPOnly,dmsExitDuringTyping:true,dmsPopulateCache:false,dmsPerFile:false};
 public static final defaultCompilationSettings:DisplaySettings={dmsKind:DMNone,dmsFullTyping:true,dmsForceMacroTyping:true,dmsErrorPolicy:EPShow,dmsCheckCoreApi:true,dmsInline:true,dmsDisplayFilePolicy:DFPNo,dmsExitDuringTyping:false,dmsPopulateCache:true,dmsPerFile:false};
 public static function create(dm:DisplayModeValue):DisplaySettings {
  var settings:DisplaySettings=cast core.ds.Record.copy(defaultDisplaySettings);settings.dmsKind=dm;
  switch dm {case DMNone:return defaultCompilationSettings;case DMDefault|DMDefinition|DMTypeDefinition|DMPackage|DMHover|DMSignature:
   case DMUsage(_,_,_)|DMImplementation:settings.dmsFullTyping=true;settings.dmsForceMacroTyping=true;settings.dmsDisplayFilePolicy=DFPAlso;settings.dmsExitDuringTyping=false;
   case DMModuleSymbols(filter):settings.dmsDisplayFilePolicy=filter==null?DFPOnly:DFPNo;settings.dmsExitDuringTyping=false;settings.dmsForceMacroTyping=false;settings.dmsPerFile=true;
  }return settings;
 }
 public static function toString(dm:DisplayModeValue):String return switch dm {case DMNone:"none";case DMDefault:"field";case DMDefinition:"position";case DMTypeDefinition:"type-definition";case DMImplementation:"implementation";case DMPackage:"package";case DMHover:"type";case DMUsage(true,_,_):"rename";case DMUsage(false,_,_):"references";case DMModuleSymbols(null):"module-symbols";case DMModuleSymbols(s):"workspace-symbols "+s;case DMSignature:"signature";};
}
enum Symbol { SKClass(cls:TClass);SKInterface(cls:TClass);SKEnum(en:TEnum);SKTypedef(td:TDef);SKAbstract(abs:TAbstract);SKField(field:TClassField,cls:Null<TClass>);SKConstructor(field:TClassField);SKEnumField(field:TEnumField);SKVariable(variable:TVar);SKOther; }
typedef CompletionSubject={var sName:Null<String>;var sStartPos:Pos;var sInsertPos:Pos;}
typedef HoverResult={var hitem:Dynamic;var hpos:Pos;var hexpected:Null<core.WithType.WithTypeValue>;}
typedef FieldsResult={var fitems:Array<Dynamic>;var fkind:CompletionResultKindValue;var fsubject:CompletionSubject;}
enum SignatureKind { SKCall;SKArrayAccess; }
enum MissingFieldCause { AbstractParent(cls:TClass,params:TParams);ImplementedInterface(cls:TClass,params:TParams);PropertyAccessor(field:TClassField,getter:Bool);FieldAccess;FinalFields(fields:Array<TClassField>); }
typedef MissingFieldsDiagnostics={var mfPos:Pos;var mfOn:ModuleType;var mfFields:Array<{field:TClassField,type:T,completion:Dynamic}>;var mfCause:MissingFieldCause;}
typedef ReplaceableCode={var reason:String;var replacement:String;var displayRange:Pos;var replaceRange:Pos;}
typedef DiagnosticsContext={var replaceableCode:Array<ReplaceableCode>;var importPositions:Dynamic;var deadBlocks:Dynamic;var messages:Array<Dynamic>;}
enum DisplayExceptionKind { DisplayHover(result:HoverResult);DisplayFields(result:FieldsResult); }
class DisplayTypes {
 public static function makeSubject(name:Null<String>,insertPos:Pos,?startPos:Pos):CompletionSubject return {sName:name,sStartPos:startPos==null?insertPos:startPos,sInsertPos:insertPos};
 public static function stringOfSymbol(symbol:Symbol):String return switch symbol {case SKClass(c)|SKInterface(c):c.clPath.name;case SKEnum(e):e.ePath.name;case SKTypedef(t):t.tPath.name;case SKAbstract(a):a.aPath.name;case SKField(cf,_)|SKConstructor(cf):cf.cfName;case SKEnumField(ef):ef.efName;case SKVariable(v):v.vName;case SKOther:"";};
}
