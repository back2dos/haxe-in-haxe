package typing;
import core.Ast;
import core.Ast as AstTools;
import core.ClassPaths.ResolvedFile;
import core.Globals;
import core.Globals.*;
import core.Meta as MetadataTools;
import core.MetaList.StrictMeta as MetaTag;
import core.Path.UniqueKey;
import core.Define;
import core.DisplayTypes.DisplayModeValue;
import core.Error.*;
import core.ds.NotFound;
import core.ds.Record;
import context.Common;
import context.Common.*;
import context.Typecore.ForbidPackage;
import context.DeferredServices;
import syntax.Parser;
import syntax.ParserConfig;
import syntax.ParserEntry;
import syntax.Grammar;
import syntax.Lexer;

typedef SourceParseResult = {var data:Package;var warnings:Array<ParseWarning>;}
typedef SourceModuleResult = {var file:ResolvedFile;var declarations:Array<TypeDecl>;var warnings:Array<ParseWarning>;}

// Source-only module parser from haxe/src/typing/typeloadParse.ml. Interactive
// ConditionDisplay/PdiHandler and parser-cache services belong to later milestones.
// The legacy TypeloadParse entry remains available to the bootstrap loader.
class SourceParser {
 public static function parseFileFromString(com:CommonContext,file:String,p:Pos,source:String):ParseResult<Package> {
  return core.Timer.time(com.timerCtx,["parsing"],function(source:String) {
   com.requestScope.stats.sFilesParsed++;
   var result=ParserEntry.parse(ParserConfig.fileParserConfig(com,file),Grammar.parseFileStream,Lexer.createFileCtx(file),new Lexer(source,file),file);
   if(com.display.dmsKind!=DMNone) DeferredServices.display();
   Common.log(com,"Parsed "+file);
   return result;
  },source);
 }
 public static function parseFile(com:CommonContext,rfile:ResolvedFile,p:Pos):ParseResult<Package> {
  var key=com.partScope.fileKeys.get(rfile.file),contents:Null<String>=null;
  if(com.fileContents.length==0&&Common.defined(com,Define.DisplayStdin)&&core.display.DisplayPosition.displayPosition.isInFile(key)) DeferredServices.display();
  for(entry in com.fileContents) if(entry.fileKey==key) {contents=entry.content;break;}
  if(contents==null) {
   var bytes:haxe.io.Bytes;
   try bytes=sys.io.File.getBytes(rfile.file) catch(_:Dynamic) return raiseTypingError("Could not open "+rfile.file,p);
   if(!validUtf8(bytes)) return raiseTypingError("Malformed file. Source files must be encoded with UTF-8.",Globals.filePos(rfile.file));
   contents=bytes.toString();
  }
  return parseFileFromString(com,rfile.file,p,contents);
 }
 // Decode validity is checked before creating a host String, matching Sedlex's
 // malformed-input failure rather than allowing replacement characters.
 static function validUtf8(bytes:haxe.io.Bytes):Bool {
  var i=0;
  while(i<bytes.length) {
   var c=bytes.get(i++);if(c<0x80) continue;
   var n=c>=0xc2&&c<=0xdf?1:c>=0xe0&&c<=0xef?2:c>=0xf0&&c<=0xf4?3:-1;
   if(n<0||i+n>bytes.length) return false;
   var first=bytes.get(i);
   if((c==0xe0&&first<0xa0)||(c==0xed&&first>=0xa0)||(c==0xf0&&first<0x90)||(c==0xf4&&first>=0x90)) return false;
   for(_ in 0...n) {var next=bytes.get(i++);if(next<0x80||next>0xbf) return false;}
  }
  return true;
 }
 public static var parseHook:CommonContext->ResolvedFile->Pos->ParseResult<Package>=parseFile;
 public static function handleParserResult(com:CommonContext,p:Pos,result:ParseResult<Package>):SourceParseResult {
  function handleError(error:ParseErrorInfo):Void switch com.display.dmsErrorPolicy {
   case EPShow:if(Common.isDiagnostics(com)) DeferredServices.display();else raiseTypingError(Parser.errorMsg(error.message),error.pos);
   case EPIgnore:com.partScope.hasError=true;
  }
  return switch result {
   case ParseSuccess(data,pdi):
    if(pdi.pdWasDisplayFile) {if(pdi.pdErrors.length>0) handleError(pdi.pdErrors[0]);DeferredServices.display();}
    {data:data,warnings:pdi.pdWarnings};
   case ParseError(data,error,_):handleError(error);{data:data,warnings:[]};
  };
 }
 public static function parseModuleFile(com:CommonContext,rfile:ResolvedFile,p:Pos):SourceParseResult return handleParserResult(com,p,parseHook(com,rfile,p));
 public static function resolveModuleFile(com:CommonContext,path:GlobalTypePath,remap:{value:Array<String>},p:Pos):ResolvedFile {
  try return com.moduleToFile.find(path) catch(_:NotFound) {}
  var classPaths:core.ClassPaths=com.classPaths;
  var forbidden=false,pack=path.pack.copy();
  if(pack.length>0) switch com.packageRules.get(pack[0]) {
   case Forbidden:forbidden=true;
   case Remap(name):pack[0]=name;remap.value=pack.copy();
   case null:
  }
  // The pre-existing ClassPaths API signals absence as null through this method.
  var lookup=classPaths.findFileNoRaise(pack.concat([path.name]).join("/")+".hx");
  if(lookup==null) throw NotFound.raise();
  var rfile=lookup.resolvedFile;
  if(Sys.systemName()=="Windows") switch path.name.toLowerCase() {
   case "con","aux","prn","nul","com1","com2","com3","lpt1","lpt2","lpt3":
    var size=try sys.FileSystem.stat(rfile.file).size catch(_:Dynamic) 0;if(size<=0) throw NotFound.raise();
   case _:
  }
  if(path.pack.length>0&&path.pack[0]=="std") {
   var key=com.partScope.fileKeys.get(rfile.file);
   for(cp in classPaths.getStdPaths()) if(UniqueKey.startsWith(key,com.partScope.fileKeys.get(cp.path))) throw NotFound.raise();
  }
  if(forbidden) {
   var meta:Metadata=[];
   switch parseHook(com,rfile,p) {
    case ParseSuccess(data,_):
     for(decl in data.declarations) {
      var found:Null<Metadata>=switch decl.definition {
       case EClass(d):d.meta;case EEnum(d):d.meta;case EAbstract(d):d.meta;case ETypedef(d):d.meta;case EStatic(d):d.meta;
       case EImport(_)|EUsing(_):null;
      };
      if(found!=null) {meta=found;break;}
     }
    case ParseError(_,_,_):
   }
   if(!MetadataTools.has(MetaTag.NoPackageRestrict,meta)) throw new ForbidPackage({name:path.pack[0],path:path,pos:p},[],Common.platformNameMacro(com));
  }
  com.moduleToFile.add(path,rfile);return rfile;
 }
 public static function parseModule(com:CommonContext,path:GlobalTypePath,p:Pos):SourceModuleResult {
  var remap={value:path.pack.copy()},rfile=resolveModuleFile(com,path,remap,p),parsed=parseModuleFile(com,rfile,p),pack=parsed.data.pack;
  function same(a:Array<String>,b:Array<String>):Bool {if(a.length!=b.length)return false;for(i in 0...a.length)if(a[i]!=b[i])return false;return true;}
  if(!same(pack,remap.value)) {
   function sPack(pack:Array<String>):String return pack.length==0?"`package;`":"`package "+pack.join(".")+";`";
   if(p==Globals.nullPos) Common.displayError(com,"Invalid commandline class : "+Globals.sTypePath(path)+" should be "+Globals.sTypePath({pack:pack,name:path.name}),p);
   else Common.displayError(com,sPack(pack)+" in "+rfile.file+" should be "+sPack(path.pack),Record.withFields(p,{pmax:p.pmin}));
  }
  var declarations=parsed.data.declarations;
  if(!same(remap.value,path.pack)) {
   var redirected:Array<TypeDecl>=[{definition:EImport({path:remap.value.concat([path.name]).map(s->({name:s,pos:Globals.nullPos}:core.Ast.PlacedName)),mode:INormal}),pos:Globals.nullPos}];
   function build(name:PlacedName,params:Array<TypeParam>,priv:Bool,p:Pos):Void {
    var tp=priv?AstTools.mkTypePath([],"Dynamic"):AstTools.mkTypePath(remap.value,path.name,params.map(tp->TPType(AstTools.makePtpTh(AstTools.mkTypePath([],tp.tpName.name),Globals.nullPos))),name.name);
    redirected.push({definition:ETypedef({name:name,doc:null,meta:[],params:params,flags:priv?[TDPrivate]:[],data:AstTools.makePtpTh(tp,name.pos)}),pos:p});
   }
   for(decl in declarations) switch decl.definition {
    case EClass(d):build(d.name,d.params,d.flags.contains(HPrivate),decl.pos);
    case EEnum(d):build(d.name,d.params,d.flags.contains(EPrivate),decl.pos);
    case ETypedef(d):build(d.name,d.params,d.flags.contains(TDPrivate),decl.pos);
    case EAbstract(d):build(d.name,d.params,d.flags.contains(AbPrivate),decl.pos);
    case EStatic(d):build(d.name,d.params,Lambda.exists(d.flags,f->f.access==AStatic&&f.pos==Globals.nullPos),decl.pos);
    case EImport(_)|EUsing(_):
   }
   declarations=redirected;
  }
  return {file:rfile,declarations:declarations,warnings:parsed.warnings};
 }
}
