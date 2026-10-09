package compiler;
import core.Globals;
import core.DisplayTypes;
import core.ClassPath.ClassPathScope;
import core.DefineRegistry;
import core.Message.WarningCode;
import core.ds.ArgumentError;
import core.ds.Failure;
import core.ds.Cancelled;
import core.ds.NotFound;
import core.ds.OcamlInt;
import compiler.Args.ArgContext;
import context.Typecore.Typer;
import context.TyperPass;
import Std as StdTools;

import core.Globals.*;
import core.TType;
import core.Message;
import core.Message.CompilerMessage as MessageData;
import core.Error;
import core.Define;
import core.Timer;
import core.Path;
import context.Common;
import context.Common.*;
import context.Parallel;
import context.DumpConfig;
import compiler.io.CompilerIo;
import compiler.io.CompilerMessage;
import compiler.io.CompilerOutput;
import typing.Finalization;
import compiler.server.ServerCache;
import compiler.server.ServerMessage;
import compiler.server.ServerCompilationContext;
import context.CommonCache;
// haxe/src/compiler/compiler.ml. Display branches are rejected explicitly until the
// display services are ported (drafts in deferred/compiler/FullCompiler.hx).
class Compiler {
 public static function errorExt(com:CommonContext,err:Dynamic):Void com.errorExt(err);
 public static function error(com:CommonContext,msg:String,p:Pos):Void errorExt(com,Error.makeError(Custom(msg),p));
 public static function hasError(com:CommonContext):Bool return com.partScope.hasError;
 public static function handleDiagnostics(com:CommonContext,msg:String,p:Pos,kind:CompilerMessageKind,?diagnosticsKind:MessageKind):Dynamic {
  throw new ArgumentError("Display diagnostics require the display/server milestone");
 }
 public static function runOrDiagnose<A>(com:CommonContext,f:Void->A):A {
  if(Common.isDiagnostics(com))throw new ArgumentError("Display diagnostics require the display/server milestone");
  return f();
 }
 static function runCommandImpl(com:CommonContext,cmd:String):Int {
  var io=com.requestScope.io;
  // TODO: this is a hack
  var cmd=if(com.sctx.isServer) {
   var h=["__file__"=>com.file,"__platform__"=>platformName(com.platform)];
   Helper.expandEnv(cmd,h);
  } else cmd;
  var len=cmd.length;
  var result=if(len>3&&cmd.substr(0,3)=="cd "){Sys.setCwd(cmd.substr(3));0;}
  else if(!com.sctx.isServer)
   // In non-server mode, inherit stdin/stdout/stderr so that interactive commands work
   Sys.command(cmd);
  else
   // In server mode, capture stdout/stderr through the output target and
   // forward the client's stdin from request_scope.
   PipeThings.runCommand(io,cmd);
  return result;
 }
 public static function runCommand(com:CommonContext,cmd:String):Int return Timer.time(com.timerCtx,["command",cmd],function(cmd) return runCommandImpl(com,cmd),cmd);
 public static function checkDefines(com:CommonContext):Void {
  if (Common.defined(com,Define.DisableParallelism)) Parallel.enable=false;
  var keys:Array<String>=[for (k in com.defines.values.keys()) k];keys.sort(Reflect.compare);
  for (k in keys) {
   var v=com.defines.values.get(k),reason=Define.deprecationLut.get(k);if (reason==null) continue;var p=Globals.fakePos("-D "+k);
   switch reason {case DueTo(reason):com.warning(WDeprecatedDefine,[],reason,p);case InFavorOf(d):Define.rawDefineValue(com.defines,d,v);com.warning(WDeprecatedDefine,[],"-D "+k+" has been deprecated in favor of -D "+d,p);}
  }
 }
 public static function doType(com:CommonContext,mctx:Null<Typer>,actx:ArgContext,displayFileDotPath:Null<GlobalTypePath>):{typer:Typer,displayPath:Null<GlobalTypePath>} {
  var cs=com.cs;
  CommonCache.maybeAddContextSign(cs,com,"before_init_macros");
  if(com.display.dmsKind!=DMNone||displayFileDotPath!=null)throw new ArgumentError("Display services require the display/server milestone");
  Common.enterStage(com,CInitMacrosStart);
  ServerMessage.compilerStage(com);
  Setup.initNativeLibs(com,actx.hxbLibs);
  var configMacros=actx.configMacros.copy();configMacros.reverse();for(path in configMacros)mctx=typing.MacroContext.callInitMacro(com,mctx,path);
  Common.enterStage(com,CInitMacrosDone);checkDefines(com);Common.updatePlatformConfig(com);
  ServerMessage.compilerStage(com);
  var macros=mctx==null?null:mctx.g.macros;
  Setup.initNativeLibs(com,actx.nativeLibs);var tctx=Setup.createTyperContext(com,macros);
  DumpConfig.updateFromDefines(com.partScope.dumpConfig,com.defines);
  CommonCache.lockSignature(com,"after_init_macros");
  if(mctx!=null)typing.MacroContext.finalizeMacroApi(tctx,mctx);
  com.callbacks.run(com.errorExt,com.callbacks.getAfterInitMacros());
  runOrDiagnose(com,function() {
   var classes=actx.classes.copy();classes.reverse();for(path in classes){tctx.g.doLoadModule(tctx,path,nullPos);context.Typecore.flushPass(tctx.g,PBuildClass,"actx.classes");}
   Finalization.finalize(tctx);return null;
  });
  Common.enterStage(com,CTypingDone);
  ServerMessage.compilerStage(com);
  return {typer:tctx,displayPath:null};
 }
 static function finalizeTypingImpl(com:CommonContext,tctx:Dynamic):Void {
  var main=Finalization.maybeLoadMain(tctx);Common.enterStage(com,CFilteringStart);
  ServerMessage.compilerStage(com);
  var output=runOrDiagnose(com,function() return Finalization.generate(tctx,main));com.main.mainExpr=output.main.expr;com.main.mainFile=output.main.path;com.types=output.types;com.modules=output.modules;
 }
 public static function finalizeTyping(com:CommonContext,tctx:Typer):Void Timer.time(com.timerCtx,["finalize"],function(tctx) {finalizeTypingImpl(com,tctx);return null;},tctx);
 public static function filter(com:CommonContext,tctx:Typer,ectx:Dynamic,beforeDestruction:Void->Void):Void Timer.time(com.timerCtx,["filters"],function(_:Null<Bool>) return runOrDiagnose(com,function() {filters.Filters.run(com,ectx,beforeDestruction);return null;}),null);
 // Not upstream: experimental code generators (backend/) receive the filtered program here. Always null in the compiler itself.
 public static var generateHook:Null<CommonContext->Void>=null;
 public static function compile(com:CommonContext,actx:ArgContext,sctx:ServerCompilationContext):Void {
  if(com.display.dmsKind!=DMNone||actx.displayArg!=null)throw new ArgumentError("Display services require the display/server milestone");
  var mctx:Null<Typer>=switch com.platform {
   case CustomTarget(name):
    try typing.MacroContext.callInitMacro(com,null,name+".Init.init()") catch(e:core.Error.TypingError) {
     switch e.error.errMessage {
      // ignore if <target_name>.Init doesn't exist
      case ModuleNotFound({pack:[pack],name:"Init"}) if(pack==name):null;
      case _:throw e;
     }
    }
   case _:null;
  };
  var ext=Setup.initializeTarget(com,actx);Common.updatePlatformConfig(com);
  ServerCache.afterTargetInit(sctx,com);
  Timer.time(com.timerCtx,["init"],function(_:Null<Bool>) {var callbacks=actx.preCompilation.copy();callbacks.reverse();for(f in callbacks)f();if(actx.hxbOut!=null)com.hxbWriterConfig=compiler.hxb.HxbWriterConfig.processArgument(actx.hxbOut);return null;},null);
  Common.enterStage(com,CInitialized);
  ServerMessage.compilerStage(com);
  if(actx.classes.length==1&&actx.classes[0].pack.length==0&&actx.classes[0].name=="Std"&&!actx.forceTyping){if(actx.cmds.length==0&&!actx.didSomething)actx.raiseUsage();}
  else {
   var typed=Timer.time(com.timerCtx,["typing"],function(_:Null<Bool>)return doType(com,mctx,actx,null),null),tctx=typed.typer;
   // DisplayProcessing.handle_display_after_typing: only its non-display branch (display services are a later milestone)
   if(com.display.dmsKind==DMNone&&com.partScope.hasError&&Common.isCompilation(com))throw new Abort();
   var ectx=filters.exception.ExceptionInit.createExceptionContext(tctx);finalizeTyping(com,tctx);codegen.Dump.maybeGenerateDump(com,AfterTyping);
   var isCompilation=Common.isCompilation(com);com.callbacks.addAfterSave(function(){ServerCache.afterSave(sctx,com);if(isCompilation&&com.hxbWriterConfig!=null)Generate.checkHxbOutput(com,com.hxbWriterConfig);});
   filter(com,tctx,ectx,function(){});
   if(hasError(com)&&isCompilation)throw new Abort();if(isCompilation)Generate.checkAuxiliaryOutput(com,actx);
   Common.enterStage(com,CGenerationStart);ServerMessage.compilerStage(com);codegen.Dump.maybeGenerateDump(com,AfterDce);Generate.maybeGenerateDumpDependencies(com,tctx);
   if(!actx.noOutput)Generate.generate(com,tctx,ext,actx);if(generateHook!=null)generateHook(com);Common.enterStage(com,CGenerationDone);ServerMessage.compilerStage(com);
  }
  // The Haxe host owns signal handling; this port does not install OCaml Sys.catch_break.
  com.callbacks.run(com.errorExt,com.callbacks.getAfterGeneration());
  if(!actx.noOutput){var commands=actx.cmds.copy();commands.reverse();for(cmd in commands){var result=runCommand(com,cmd);if(result!=0)throw new Failure("Command failed with error "+result);}}
 }
 public static function makeIceMessage(com:CommonContext,msg:String,backtrace:String):String return msg+"\nHaxe: "+sVersionFull(com.sctx.version)+"; OS type: "+(Sys.systemName()=="Windows"?"windows":"unix")+";\n"+backtrace;
 static function compileSafeImpl(com:CommonContext,f:Void->Void):Void {
  try f()
  catch(e:core.Error.FatalError)errorExt(com,e.error)
  catch(e:syntax.Lexer.LexerError)error(com,syntax.Lexer.errorMsg(e.message),e.pos)
   catch(e:syntax.Parser.ParserError)error(com,syntax.Parser.errorMsg(e.error),e.pos)
  catch(e:context.Typecore.ForbidPackage){var sub=e.positions.map(p->Error.makeError(Custom(Error.complMsg("referenced here")),p));errorExt(com,Error.makeError(Custom("You cannot access the "+e.forbidden.name+" package while "+(e.reason=="macro"?"in a macro":"targeting "+e.reason)+" (for "+sTypePath(e.forbidden.path)+")"),e.forbidden.pos,sub));}
  catch(e:core.Error.TypingError)errorExt(com,e.error)
  catch(e:ArgumentError)error(com,"Error: "+e.message,nullPos)
  catch(e:Failure){if(!Helper.isDebugRun)error(com,"Error: "+e.message,nullPos);else throw e;}
  catch(e:core.Globals.InternalCompilerError){if(!Helper.isDebugRun)error(com,"Error: "+makeIceMessage(com,e.message,e.stack.toString()),nullPos);else throw e;}
  catch(e:Helper.HelpMessage)CompilerIo.writeOut(com.requestScope.io,e.message+"\n")
  catch(e:Abort)throw e
  catch(e:macros.eval.EvalTypes.SysExit)throw e
  catch(e:Cancelled)throw e
  catch(e:Dynamic){if(Sys.getEnv("OCAMLRUNPARAM")!="b"&&!Helper.isDebugRun)error(com,StdTools.string(e),nullPos);else {Sys.stderr().writeString(haxe.CallStack.toString(@:privateAccess haxe.Exception.caught(e).stack)+"\n");throw e;}}
 }
 public static function compileSafe(com:CommonContext,f:Void->Void):Void {try compileSafeImpl(com,f) catch (_:Abort) {}}
 public static function finalize(com:CommonContext):Void {CompilerIo.flush(com.requestScope.io);for (lib in com.hxbLibs) lib.close();if (!com.sctx.isServer) {for (lib in (cast com.nativeLibs.javaLibs:Array<Dynamic>)) lib.close();for (lib in (cast com.nativeLibs.swfLibs:Array<Dynamic>)) lib.close();}}
 public static function catchCompletionAndExit(com:CommonContext,sctx:ServerCompilationContext,run:CommonContext->Void):Int {
  try {run(com);return hasError(com)?1:0;}
  catch(e:macros.eval.EvalTypes.SysExit) {
   if(e.code!=0)com.partScope.hasError=true;
   ContextFlush.flushContext(com);finalize(com);return e.code;
  }
 }
 public static function processActx(com:CommonContext,actx:ArgContext):Void {
  com.doinline=com.display.dmsInline&&!Common.defined(com,Define.NoInline);com.timerCtx.measureTimes=actx.measureTimes?Yes:No;
  if(actx.displayArg!=null)throw new ArgumentError("Display services require the display/server milestone");
  if(Common.defined(com,Define.NoDeprecationWarnings))com.warningOptions.unshift([{woWarning:WDeprecated,woMode:WMDisable}]);
 }
 public static function compileCtx(sctx:ServerCompilationContext,com:CommonContext):Int return catchCompletionAndExit(com,sctx,function(com) {
  ServerCache.beforeAnything(sctx,com);
  Setup.setupCommonContext(com);compileSafe(com,function() {var actx=Args.processArgs(com);processActx(com,actx);compile(com,actx,sctx);});ContextFlush.flushContext(com);finalize(com);
 });
 public static function createContext(sctx:ServerCompilationContext,requestScope:RequestScope,runtimeArgs:Array<String>,hasNext:Bool):CommonContext {
  var part:PartScope={runtimeArgs:runtimeArgs,warnedPositions:new core.ds.Hashtbl<{file:String,offset:Int},{message:String,pos:Pos,options:Array<Array<core.Message.WarningOption>>}>(0),hasNext:hasNext,hasError:false,messages:[],reportMode:RMNone,messageCapture:null,compilationStep:sctx.compilationStep,passDebugMessages:[],dumpConfig:DumpConfig.createDefault(),parserState:{wasAutoTriggered:false,hadParserResume:false,displayModuleHasMacroDefines:false,delayedSyntaxCompletion:{value:null},specialIdentifierFiles:new core.ds.ThreadSafeHashtbl<String,String>(0)},fileKeys:new FileKeys(),storedTypedExprs:new context.Lookup.HashtblLookup(),cachedMacros:new context.Lookup.HashtblLookup()};
  return Common.create(sctx,requestScope,part,core.DisplayTypes.DisplayMode.create(DMNone));
 }
}
class Setup {
 public static function initializeTarget(com:CommonContext,actx:Dynamic):String {
  Common.initPlatform(com);com.classPaths.lockContext(com.customExt,Globals.platformName(com.platform),false);
  inline function addStd(dir:String):Void com.classPaths.modifyInplace(function(cp:core.ClassPath.IClassPath):Array<core.ClassPath.IClassPath> return switch cp.scope {case Std:[cp,new core.ClassPath.DirectoryClassPath(cp.path+dir+"/_std/",StdTarget)];case _:[cp];});
  return switch com.platform {
   case Cross:"?";case CustomTarget(name):name;
   case Flash:for (v in Common.flashVersions) {if (v.version>com.flashVersion) break;Common.rawDefine(com,"flash"+v.define);}com.packageRules.remove("flash");addStd("flash");"swf";
   case Neko:addStd("neko");"n";
   case Js:
    var version=try OcamlInt.ofString(Common.definedValue(com,Define.JsEs)) catch (e:Dynamic) {if (StdTools.isOfType(e,NotFound)) {Common.defineValue(com,Define.JsEs,"5");5;}else 0;};
    if (version<5) throw new Failure("Invalid -D js-es value, minimal supported version is 5");if (version>=5) Common.rawDefine(com,"js_es5");addStd("js");"js";
   case Lua:addStd("lua");"lua";case Php:addStd("php");"php";
   case Cpp:Common.defineValue(com,Define.HxcppApiLevel,"500");addStd("cpp");if (Common.defined(com,Define.Cppia)) actx.classes.unshift(Path.parsePath("cpp.cppia.HostClasses"));"cpp";
   case Jvm:addStd("jvm");com.packageRules.remove("java");"java";
   case Python:addStd("python");if (!Common.defined(com,Define.PythonVersion)) Common.defineValue(com,Define.PythonVersion,"3.3");"python";
   case Hl:addStd("hl");if (!Common.defined(com,Define.HlVer)) {
    var version=try sys.io.File.getContent(Common.findFile(com,"hl/hl_version")) catch (e:Dynamic) {if (!StdTools.isOfType(e,NotFound)) throw e;throw new Failure("The file hl_version could not be found. Please make sure HAXE_STD_PATH is set to the standard library corresponding to the used compiler version.");};Define.defineValue(com.defines,Define.HlVer,version);
   }"hl";
   case Eval:addStd("eval");"eval";
  };
 }
 public static function initNativeLibs(com:CommonContext,nativeLibs:Array<compiler.ParsedArg.NativeLibArg>):Void {
  // Native lib pass 1: Register
  var rev=nativeLibs.copy();rev.reverse();var fl=[for (lib in rev) context.NativeLibraryHandler.addNativeLib(com,lib)];
  // Native lib pass 2: Initialize
  for (f in fl) f();
 }
 public static function createTyperContext(com:CommonContext,macros:Dynamic):Typer {
  var buf=new StringBuf();buf.add("Defines: ");var keys:Array<String>=[for (k in com.defines.values.keys()) k];keys.sort(Reflect.compare);for (k in keys) {var v=com.defines.values.get(k);buf.add(v=="1"?k+";":k+"="+v+";");}
  var text=buf.toString();Common.log(com,text.substr(0,text.length-1));com.callbacks.run(com.errorExt,com.callbacks.getBeforeTyperCreate());return typing.TyperEntry.create(com,macros);
 }
 public static function executablePath():String return Sys.programPath();
 public static function getStdClassPaths():Array<{path:String,scope:Dynamic}> {
  var env=Sys.getEnv("HAXE_STD_PATH");if (env!=null) {
   var p=Path.removeTrailingSlash(env),parts=~/[;:]/g.split(p),result=[];var i=0;
   while (i<parts.length) {var s=parts[i];if (i+1<parts.length&&s.length==1&&~/^[a-zA-Z]$/.match(s)) {result.push({path:s+":"+parts[i+1],scope:Std});i+=2;}else {result.push({path:s,scope:Std});i++;}}return result;
  }
  var base=Path.getRealPath(try executablePath() catch (_:Dynamic) "./");
  if (Sys.systemName()!="Windows") {var prefix=haxe.io.Path.directory(base);return [{path:haxe.io.Path.join([prefix,"share","haxe/std"]),scope:Std},{path:haxe.io.Path.join([prefix,"lib","haxe/std"]),scope:Std},{path:haxe.io.Path.join([base,"std"]),scope:Std}];}
  return [{path:haxe.io.Path.join([base,"std"]),scope:Std}];
 }
 public static function initStdClassPaths(com:CommonContext):Void {var paths=getStdClassPaths();paths.reverse();for (entry in paths) try {if (sys.FileSystem.isDirectory(entry.path)) com.classPaths.add(new core.ClassPath.DirectoryClassPath(Path.addTrailingSlash(entry.path),entry.scope));}catch (_:Dynamic) {}com.classPaths.add(com.emptyClassPath);}
 static function versionDecimal():String {var result=StdTools.string(Globals.version/1000.);if(result.indexOf(".")<0)result+=".";while(result.length-result.indexOf(".")<4)result+="0";return result;}
 public static function setupCommonContext(com:CommonContext):Void {
  Common.defineValue(com,Define.HaxeVer,versionDecimal());Common.defineValue(com,Define.Haxe,Globals.sVersion);Common.rawDefine(com,"true");for (entry in Define.defaultValues) Define.rawDefineValue(com.defines,entry.key,entry.value);
  com.info=CompilerMessage.defaultInfoHandler(com);com.warning=CompilerMessage.defaultWarningHandler(com);com.errorExt=CompilerMessage.defaultErrorHandler(com);com.error=function(msg,p) com.errorExt(Error.makeError(Custom(msg),p));
  function filterMessages(keepErrors:Bool,predicate:MessageData->Bool):Array<MessageData> {var messages=com.partScope.messages.copy();messages.reverse();return messages.filter(function(cm) return switch Message.severity(cm) {case Error:keepErrors;case Information|Warning|Hint:predicate(cm);});}
  com.getMessages=function() return filterMessages(false,function(_) return true).map(function(cm) return switch Message.severity(cm) {case Error:throw "Unexpected error in get_messages";case Information|Warning|Hint:cm;});
  com.filterMessages=function(predicate) {var messages=filterMessages(true,predicate);messages.reverse();com.partScope.messages=messages;};com.runCommand=function(cmd) return Compiler.runCommand(com,cmd);initStdClassPaths(com);
 }
}
class ContextFlush {
 public static function flushContext(com:CommonContext):Void switch com.partScope.reportMode {case RMDiagnostics(_):case _:CompilerOutput.flushMessages(com.requestScope.resultHandler,Common.hasErrorToReport(com),com);};
}
