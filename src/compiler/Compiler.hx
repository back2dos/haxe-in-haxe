package compiler;
import core.Globals;
import core.Globals.*;
import core.TType;
import core.Message;
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
// haxe/src/compiler/compiler.ml — mechanical draft; not compile-validated.
// Macro/display/cache/native service entry points remain unresolved hooks.
class Compiler {
 public static function errorExt(com:CommonContext,err:Dynamic):Void com.errorExt(err);
 public static function error(com:CommonContext,msg:String,p:Pos):Void errorExt(com,Error.makeError(Custom(msg),p));
 public static function hasError(com:CommonContext):Bool return com.partScope.hasError;
 public static function handleDiagnostics(com:CommonContext,msg:String,p:Pos,kind:Dynamic,?diagnosticsKind:Dynamic):Dynamic {
  if (diagnosticsKind==null) diagnosticsKind=DKCompilerMessage;
  com.partScope.hasError=true;Common.addDiagnosticsMessage(com,msg,p,kind,0,diagnosticsKind);
  return switch com.partScope.reportMode {case RMDiagnostics(_):DisplayOutput.emitDiagnostics(com);case _:throw "Invalid diagnostics report mode";};
 }
 public static function runOrDiagnose<A>(com:CommonContext,f:Void->A):A {
  if (!Common.isDiagnostics(com)) return f();
  try return f() catch (e:core.Error.Error) {
   com.partScope.hasError=true;Error.recurseError(function(depth,err) Common.addDiagnosticsMessage(com,Error.errorMsg(err.errMessage),err.errPos,MKError,depth),e.error);
   return switch com.partScope.reportMode {case RMDiagnostics(_):DisplayOutput.emitDiagnostics(com);case _:throw "Invalid diagnostics report mode";};
  } catch (e:syntax.Parser.Error) return handleDiagnostics(com,syntax.Parser.errorMsg(e.message),e.pos,MKError,DKParserError);
    catch (e:syntax.Lexer.Error) return handleDiagnostics(com,syntax.Lexer.errorMsg(e.message),e.pos,MKError,DKParserError);
 }
 static function runCommandImpl(com:CommonContext,cmd:String):Int {
  if (com.sctx.isServer) {var env=new Map();env.set("__file__",com.file);env.set("__platform__",Globals.platformName(com.platform));cmd=Helper.expandEnv(cmd,env);}
  if (cmd.length>3&&cmd.substr(0,3)=="cd ") {Sys.setCwd(cmd.substr(3));return 0;}
  return !com.sctx.isServer ? Sys.command(cmd) : PipeThings.runCommand(com.requestScope.io,cmd);
 }
 public static function runCommand(com:CommonContext,cmd:String):Int return Timer.time(com.timerCtx,["command",cmd],function() return runCommandImpl(com,cmd));
 public static function checkDefines(com:CommonContext):Void {
  if (Common.defined(com,Define.DisableParallelism)) Parallel.enable=false;
  var keys:Array<String>=[for (k in com.defines.values.keys()) k];keys.sort(Reflect.compare);
  for (k in keys) {
   var v=com.defines.values.get(k),reason=Define.deprecationLut.get(k);if (reason==null) continue;var p=Globals.fakePos("-D "+k);
   switch reason {case DueTo(reason):com.warning(WDeprecatedDefine,[],reason,p);case InFavorOf(d):Define.rawDefineValue(com.defines,d,v);com.warning(WDeprecatedDefine,[],"-D "+k+" has been deprecated in favor of -D "+d,p);}
  }
 }
 public static function doType(com:CommonContext,mctx:Dynamic,actx:Dynamic,displayFileDotPath:Dynamic):{typer:Dynamic,displayPath:Dynamic} {
  var cs=com.cs;CommonCache.maybeAddContextSign(cs,com,"before_init_macros");Common.enterStage(com,CInitMacrosStart);ServerMessage.compilerStage(com);
  Setup.initNativeLibs(com,actx.hxbLibs);
  var macros:Array<String>=actx.configMacros.copy();macros.reverse();for (path in macros) mctx=MacroContext.callInitMacro(com,mctx,path);
  Common.enterStage(com,CInitMacrosDone);checkDefines(com);Common.updatePlatformConfig(com);ServerMessage.compilerStage(com);
  var macroTyper=mctx==null?null:mctx.g.macros;Setup.initNativeLibs(com,actx.nativeLibs);var tctx=Setup.createTyperContext(com,macroTyper);
  displayFileDotPath=DisplayProcessing.maybeLoadDisplayFileBeforeTyping(tctx,displayFileDotPath);if (displayFileDotPath!=null) actx.classes.unshift(displayFileDotPath);
  DumpConfig.updateFromDefines(com.partScope.dumpConfig,com.defines);CommonCache.lockSignature(com,"after_init_macros");if (mctx!=null) MacroContext.finalizeMacroApi(tctx,mctx);
  try {
   com.callbacks.run(com.errorExt,com.callbacks.getAfterInitMacros());runOrDiagnose(com,function() {
    if (com.display.dmsKind!=DMNone) DisplayTexpr.checkDisplayFile(tctx,cs);
    var classes:Array<GlobalTypePath>=actx.classes.copy();classes.reverse();for (cpath in classes) {tctx.g.doLoadModule(tctx,cpath,nullPos);context.Typecore.flushPass(tctx.g,PBuildClass,"actx.classes");}
    Finalization.finalize(tctx);return null;
   });
  } catch (_:typing.TypeloadParse.DisplayInMacroBlock) {DisplayProcessing.loadDisplayModuleInMacro(tctx,displayFileDotPath,true);}
  Common.enterStage(com,CTypingDone);ServerMessage.compilerStage(com);
  switch com.display.dmsKind {case DMUsage(_)|DMImplementation:FindReferences.findPossibleReferences(tctx,cs);case _:}
  return {typer:tctx,displayPath:displayFileDotPath};
 }
 static function finalizeTypingImpl(com:CommonContext,tctx:Dynamic):Void {
  var main=Finalization.maybeLoadMain(tctx);Common.enterStage(com,CFilteringStart);ServerMessage.compilerStage(com);
  var output=runOrDiagnose(com,function() return Finalization.generate(tctx,main));com.main.mainExpr=output.main.expr;com.main.mainFile=output.main.path;com.types=output.types;com.modules=output.modules;
 }
 public static function finalizeTyping(com:CommonContext,tctx:Dynamic):Void Timer.time(com.timerCtx,["finalize"],function() finalizeTypingImpl(com,tctx));
 public static function filter(com:CommonContext,tctx:Dynamic,ectx:Dynamic,beforeDestruction:Void->Void):Void Timer.time(com.timerCtx,["filters"],function() runOrDiagnose(com,function() {filters.Filters.run(tctx,ectx,beforeDestruction);return null;}));
 public static function compile(com:CommonContext,actx:Dynamic,sctx:Dynamic):Void {
  DisplayProcessing.processDisplayConfiguration(com);var restore=Common.disableReportMode(com);var displayPath=DisplayProcessing.processDisplayFile(com,actx);restore();
  var mctx:Dynamic=null;
  switch com.platform {case CustomTarget(name):try mctx=MacroContext.callInitMacro(com,null,name+".Init.init()") catch (e:core.Error.Error) {
   switch e.error.errMessage {case ModuleNotFound({pack:[pack],name:"Init"}) if (pack==name):mctx=null;case _:throw e;}
  }case _:}
  var ext=Setup.initializeTarget(com,actx);Common.updatePlatformConfig(com);ServerCache.afterTargetInit(sctx,com);
  Timer.time(com.timerCtx,["init"],function() {var callbacks:Array<Void->Void>=actx.preCompilation.copy();callbacks.reverse();for (f in callbacks) f();if (actx.hxbOut!=null) com.hxbWriterConfig=compiler.hxb.HxbWriterConfig.processArgument(actx.hxbOut);});
  Common.enterStage(com,CInitialized);ServerMessage.compilerStage(com);
  var classes:Array<GlobalTypePath>=actx.classes;
  if (classes.length==1&&classes[0].pack.length==0&&classes[0].name=="Std"&&!actx.forceTyping) {
   if (actx.cmds.length==0&&!actx.didSomething) actx.raiseUsage();
  } else {
   var typed=Timer.time(com.timerCtx,["typing"],function() return doType(com,mctx,actx,displayPath));var tctx=typed.typer;displayPath=typed.displayPath;
   if (DisplayProcessing.handleDisplayAfterTyping(com,tctx,displayPath)) throw new Abort();
   var ectx=filters.exception.ExceptionInit.createExceptionContext(tctx);finalizeTyping(com,tctx);codegen.Dump.maybeGenerateDump(com,AfterTyping);
   var isCompilation=Common.isCompilation(com);
   com.callbacks.addAfterSave(function() {ServerCache.afterSave(sctx,com);if (isCompilation&&com.hxbWriterConfig!=null) Generate.checkHxbOutput(com,com.hxbWriterConfig);});
   if (Common.isDiagnostics(com)) filter(com,com,ectx,function() DisplayProcessing.handleDisplayAfterFinalization(com,tctx,displayPath));
   else {DisplayProcessing.handleDisplayAfterFinalization(com,tctx,displayPath);filter(com,com,ectx,function() {});}
   if (hasError(com)&&isCompilation) throw new Abort();if (isCompilation) Generate.checkAuxiliaryOutput(com,actx);
   Common.enterStage(com,CGenerationStart);ServerMessage.compilerStage(com);codegen.Dump.maybeGenerateDump(com,AfterDce);Generate.maybeGenerateDumpDependencies(com,tctx);
   if (!actx.noOutput) Generate.generate(com,tctx,ext,actx);
   Common.enterStage(com,CGenerationDone);ServerMessage.compilerStage(com);
  }
  SysSignals.catchBreak(false);com.callbacks.run(com.errorExt,com.callbacks.getAfterGeneration());
  if (!actx.noOutput) {var cmds:Array<String>=actx.cmds.copy();cmds.reverse();for (c in cmds) {var result=runCommand(com,c);if (result!=0) throw new Failure("Command failed with error "+result);}}
 }
 public static function makeIceMessage(com:CommonContext,msg:String,backtrace:String):String return msg+"\nHaxe: "+sVersionFull(com.sctx.version)+"; OS type: "+(Sys.systemName()=="Windows"?"windows":"unix")+";\n"+backtrace;
 static function compileSafeImpl(com:CommonContext,f:Void->Void):Void {
  try f()
  catch (e:core.Error.FatalError) errorExt(com,e.error)
  catch (e:syntax.Lexer.Error) error(com,syntax.Lexer.errorMsg(e.message),e.pos)
  catch (e:syntax.Parser.Error) error(com,syntax.Parser.errorMsg(e.message),e.pos)
  catch (e:context.Typecore.ForbidPackage) {
   if (com.display.dmsKind!=DMNone&&com.partScope.hasNext) {com.partScope.hasError=false;com.partScope.messages=[];}
   else {var sub=e.positions.map(function(p) return Error.makeError(Custom(Error.complMsg("referenced here")),p));errorExt(com,Error.makeError(Custom("You cannot access the "+e.pack+" package while "+(e.platform=="macro"?"in a macro":"targeting "+e.platform)+" (for "+sTypePath(e.module)+")"),e.pos,sub));}
  }
  catch (e:core.Error.Error) errorExt(com,e.error)
  catch (e:Arg.Bad) error(com,"Error: "+e.message,nullPos)
  catch (e:Failure) {if (Common.isDiagnostics(com)) handleDiagnostics(com,e.message,nullPos,MKError);else if (!Helper.isDebugRun) error(com,"Error: "+e.message,nullPos);else throw e;}
  catch (e:Globals.Ice) {var msg=makeIceMessage(com,e.message,e.backtrace);if (Common.isDiagnostics(com)) handleDiagnostics(com,msg,nullPos,MKError);else if (!Helper.isDebugRun) error(com,"Error: "+msg,nullPos);else throw e;}
  catch (e:Helper.HelpMessage) CompilerIo.writeOut(com.requestScope.io,e.message+"\n")
  catch (e:syntax.Parser.TypePath) DisplayOutput.handleTypePathException(com,e.path,e.cls,e.isImport,e.pos)
  catch (e:syntax.Parser.SyntaxCompletion) {DisplayOutput.handleSyntaxCompletion(com,e.kind,e.subject);error(com,"Error: No completion point was found",nullPos);}
  catch (e:DisplayException.DisplayException) DisplayOutput.handleDisplayException(com,e.value)
  catch (e:Abort) throw e
  catch (e:OutOfMemory) throw e
  catch (e:EvalTypes.SysExit) throw e
  catch (e:Hlinterp.SysExit) throw e
  catch (e:DisplayJson.JsonCompleted) throw e
  catch (e:Dynamic) {if (Sys.getEnv("OCAMLRUNPARAM")!="b"&&!Helper.isDebugRun) error(com,Printexc.toString(e),nullPos);else throw e;}
 }
 public static function compileSafe(com:CommonContext,f:Void->Void):Void {try compileSafeImpl(com,f) catch (_:Abort) {}}
 public static function finalize(com:CommonContext):Void {CompilerIo.flush(com.requestScope.io);for (lib in com.hxbLibs) lib.close();if (!com.sctx.isServer) {for (lib in (cast com.nativeLibs.javaLibs:Array<Dynamic>)) lib.close();for (lib in (cast com.nativeLibs.swfLibs:Array<Dynamic>)) lib.close();}}
 public static function catchCompletionAndExit(com:CommonContext,sctx:Dynamic,run:CommonContext->Void):Int {
  try {run(com);return hasError(com)?1:0;}catch (_:DisplayJson.JsonCompleted) {finalize(com);return 0;}
  catch (e:EvalTypes.SysExit) {if (e.code!=0) com.partScope.hasError=true;ContextFlush.flushContext(com);finalize(com);return e.code;}
  catch (e:Hlinterp.SysExit) {if (e.code!=0) com.partScope.hasError=true;ContextFlush.flushContext(com);finalize(com);return e.code;}
 }
 public static function processActx(com:CommonContext,actx:Dynamic):Void {
  com.doinline=com.display.dmsInline&&!Common.defined(com,Define.NoInline);com.timerCtx.measureTimes=actx.measureTimes?Yes:No;
  function checkDeprecationSettings():Void {if (Common.defined(com,Define.NoDeprecationWarnings)) com.warningOptions.unshift([{woWarning:WDeprecated,woMode:WMDisable}]);}
  switch DisplayProcessing.processDisplayArg(com,actx) {case Completed:throw new DisplayJson.JsonCompleted();case NeedsTyping:actx.didSomething=true;actx.forceTyping=true;checkDeprecationSettings();case NoCompletionPointFound:checkDeprecationSettings();}
 }
 public static function compileCtx(sctx:Dynamic,com:CommonContext):Int return catchCompletionAndExit(com,sctx,function(com) {
  ServerCache.beforeAnything(sctx,com);Setup.setupCommonContext(com);compileSafe(com,function() {var actx=Args.processArgs(com);processActx(com,actx);compile(com,actx,sctx);});ContextFlush.flushContext(com);finalize(com);
 });
 public static function createContext(sctx:Dynamic,requestScope:RequestScope,runtimeArgs:Array<String>,hasNext:Bool):CommonContext {
  var part:PartScope={runtimeArgs:runtimeArgs,warnedPositions:new Map(),hasNext:hasNext,hasError:false,messages:[],reportMode:RMNone,messageCapture:null,compilationStep:sctx.compilationStep,passDebugMessages:[],dumpConfig:DumpConfig.createDefault(),parserState:{wasAutoTriggered:false,hadParserResume:false,displayModuleHasMacroDefines:false,delayedSyntaxCompletion:Atomic.make(null),specialIdentifierFiles:core.ds.ThreadSafeHashtbl.create(0)},fileKeys:new FileKeys(),storedTypedExprs:new context.Lookup.HashtblLookup(),cachedMacros:new context.Lookup.HashtblLookup()};
  return Common.create(sctx,requestScope,part,core.DisplayTypes.DisplayMode.create(DMNone));
 }
}
class Setup {
 public static function initializeTarget(com:CommonContext,actx:Dynamic):String {
  Common.initPlatform(com);com.classPaths.lockContext(com.customExt,Globals.platformName(com.platform),false);
  function addStd(dir:String):Void com.classPaths.modifyInplace(function(cp) return switch cp.scope() {case Std:[cp,new core.ClassPath.DirectoryClassPath(cp.path()+dir+"/_std/",StdTarget)];case _:[cp];});
  return switch com.platform {
   case Cross:"?";case CustomTarget(name):name;
   case Flash:for (v in Common.flashVersions) {if (v.version>com.flashVersion) break;Common.rawDefine(com,"flash"+v.define);}com.packageRules.remove("flash");addStd("flash");"swf";
   case Neko:addStd("neko");"n";
   case Js:
    var version=try OcamlInt.ofString(Common.definedValue(com,Define.JsEs)) catch (e:Dynamic) {if (e=="Not_found") {Common.defineValue(com,Define.JsEs,"5");5;}else 0;};
    if (version<5) throw new Failure("Invalid -D js-es value, minimal supported version is 5");if (version>=5) Common.rawDefine(com,"js_es5");addStd("js");"js";
   case Lua:addStd("lua");"lua";case Php:addStd("php");"php";
   case Cpp:Common.defineValue(com,Define.HxcppApiLevel,"500");addStd("cpp");if (Common.defined(com,Define.Cppia)) actx.classes.unshift(Path.parsePath("cpp.cppia.HostClasses"));"cpp";
   case Jvm:addStd("jvm");com.packageRules.remove("java");"java";
   case Python:addStd("python");if (!Common.defined(com,Define.PythonVersion)) Common.defineValue(com,Define.PythonVersion,"3.3");"python";
   case Hl:addStd("hl");if (!Common.defined(com,Define.HlVer)) {
    var version=try sys.io.File.getContent(Common.findFile(com,"hl/hl_version")) catch (e:Dynamic) {if (e!="Not_found") throw e;throw new Failure("The file hl_version could not be found. Please make sure HAXE_STD_PATH is set to the standard library corresponding to the used compiler version.");};Define.defineValue(com.defines,Define.HlVer,version);
   }"hl";
   case Eval:addStd("eval");"eval";
  };
 }
 public static function initNativeLibs(com:CommonContext,nativeLibs:Array<Dynamic>):Void {var ordered=nativeLibs.copy();ordered.reverse();var callbacks=ordered.map(function(lib) return context.NativeLibraryHandler.addNativeLib(com,lib));for (f in callbacks) f();}
 public static function createTyperContext(com:CommonContext,macros:Dynamic):Dynamic {
  var buf=new StringBuf();buf.add("Defines: ");var keys:Array<String>=[for (k in com.defines.values.keys()) k];keys.sort(Reflect.compare);for (k in keys) {var v=com.defines.values.get(k);buf.add(v=="1"?k+";":k+"="+v+";");}
  var text=buf.toString();Common.log(com,text.substr(0,text.length-1));com.callbacks.run(com.errorExt,com.callbacks.getBeforeTyperCreate());return typing.TyperEntry.create(com,macros);
 }
 public static function executablePath():String return Extc.executablePath();
 public static function getStdClassPaths():Array<{path:String,scope:Dynamic}> {
  var env=Sys.getEnv("HAXE_STD_PATH");if (env!=null) {
   var p=Path.removeTrailingSlash(env),parts=~/[;:]/g.split(p),result=[];var i=0;
   while (i<parts.length) {var s=parts[i];if (i+1<parts.length&&s.length==1&&~/^[a-zA-Z]$/.match(s)) {result.push({path:s+":"+parts[i+1],scope:Std});i+=2;}else {result.push({path:s,scope:Std});i++;}}return result;
  }
  var base=Path.getRealPath(try executablePath() catch (_:Dynamic) "./");
  if (Sys.systemName()!="Windows") {var prefix=haxe.io.Path.directory(base);return [{path:haxe.io.Path.join([prefix,"share","haxe/std"]),scope:Std},{path:haxe.io.Path.join([prefix,"lib","haxe/std"]),scope:Std},{path:haxe.io.Path.join([base,"std"]),scope:Std}];}
  return [{path:haxe.io.Path.join([base,"std"]),scope:Std}];
 }
 public static function initStdClassPaths(com:CommonContext):Void {var paths=getStdClassPaths();paths.reverse();for (entry in paths) try {if (sys.FileSystem.isDirectory(entry.path)) com.classPaths.add(new core.ClassPath.DirectoryClassPath(Path.addTrailingSlash(entry.path),entry.scope));}catch (_:SysError) {}com.classPaths.add(com.emptyClassPath);}
 public static function setupCommonContext(com:CommonContext):Void {
  Common.defineValue(com,Define.HaxeVer,Printf.sprintf("%.3f",[Globals.version/1000.]));Common.defineValue(com,Define.Haxe,Globals.sVersion);Common.rawDefine(com,"true");for (entry in DefineList.defaultValues) Define.rawDefineValue(com.defines,entry.key,entry.value);
  com.info=CompilerMessage.defaultInfoHandler(com);com.warning=CompilerMessage.defaultWarningHandler(com);com.errorExt=CompilerMessage.defaultErrorHandler(com);com.error=function(msg,p) com.errorExt(Error.makeError(Custom(msg),p));
  function filterMessages(keepErrors:Bool,predicate:Dynamic->Bool):Array<Dynamic> {var messages=com.partScope.messages.copy();messages.reverse();return messages.filter(function(cm) return switch Message.cmSeverity(cm) {case Error:keepErrors;case Information|Warning|Hint:predicate(cm);});}
  com.getMessages=function() return filterMessages(false,function(_) return true).map(function(cm) return switch Message.cmSeverity(cm) {case Error:throw "Unexpected error in get_messages";case Information|Warning|Hint:cm;});
  com.filterMessages=function(predicate) {var messages=filterMessages(true,predicate);messages.reverse();com.partScope.messages=messages;};com.runCommand=function(cmd) return Compiler.runCommand(com,cmd);initStdClassPaths(com);
 }
}
class ContextFlush {
 public static function flushContext(com:CommonContext):Void switch com.partScope.reportMode {case RMDiagnostics(_):case _:CompilerOutput.flushMessages(com.requestScope.resultHandler,Common.hasErrorToReport(com),com);};
}
