import compiler.Args;
import compiler.HighLevel;
import compiler.io.CompilerIo;
import compiler.io.CompilerOutput;
import context.Common;
import context.Parallel.ManagedPool;
import core.Globals;
import core.Timer;
import core.ds.TaskPool;

// Batch entry from haxe/src/compiler/haxe.ml, server/server.ml:create_request_scope
// and server/serverCompilationContext.ml:create. This exercises the translated
// pipeline separately from the historical bootstrap entry in haxe.Main.
class TranslatedPipeline {
 static function main():Void {
  // The development host can rewrite HAXE_STD_PATH while launching --run.
  Sys.putEnv("HAXE_STD_PATH",sys.FileSystem.fullPath("haxe/std"));
  var output="test/generated/testing/translated-basic.hxb";
  var arguments=Sys.args();
  var defaultCase=arguments.length==0;
  if(defaultCase) {
   sys.FileSystem.createDirectory("test/generated/testing");
   if(sys.FileSystem.exists(output)) sys.FileSystem.deleteFile(output);
   arguments=["-cp","test/conformance","--main","unit.moduleload.Basic","--interp","--no-output","--hxb",output];
  }
  var pool=ManagedPool.create(function() return new TaskPool(TaskPool.recommendedDomainCount()-1));
  var version:core.Globals.CompilerVersion={version:Globals.version,major:Globals.versionMajor,minor:Globals.versionMinor,revision:Globals.versionRevision,pre:Globals.versionPre,extra:null};
  // Compilation-cache services are deferred; source-only batch loading never
  // dereferences cs. All active shared context fields follow upstream defaults.
  var sctx={isServer:false,version:version,verbose:false,cs:null,
   classPaths:new core.ds.Hashtbl<String,Array<String>>(0),changedDirectories:new core.ds.Hashtbl<String,Array<Dynamic>>(0),
   compilationStep:0,delays:new Array<Void->Void>(),wasCompilation:false,macroContextSetup:false,currentStdin:null,persistentCwd:null,pool:pool};
  var io=CompilerIo.createStdioIo();
  var request:RequestScope={stats:Stats.create(),timerCtx:Timer.makeContext(Timer.make(["other"])),cancellationRequested:false,io:io,resultHandler:CompilerOutput.createCliResultHandler(io)};
  var code:Int;
  try code=HighLevel.entry(sctx,request,Args.expandArgs(Args.parseArgs(arguments))) catch(e:Dynamic) {
   var stack=Std.isOfType(e,haxe.Exception)?(cast(e,haxe.Exception)).stack:haxe.CallStack.exceptionStack();
   Sys.stderr().writeString(haxe.CallStack.toString(stack)+"\n"+Std.string(e)+"\n");
   switch core.ds.ExceptionTools.unification(e) {case Some(errors): for(error in errors) Sys.stderr().writeString(core.Error.unifyErrorMsg(core.TPrinting.printContext(),error)+"\n"); case None:}
   Sys.stderr().writeString("Before failure: parsed="+request.stats.sFilesParsed+" typed="+request.stats.sModulesTyped+" classes="+request.stats.sClassesBuilt+" methods="+request.stats.sMethodsTyped+"\n");
   ManagedPool.release(pool);Sys.exit(1);return;
  }
  ManagedPool.release(pool);
  if(code==0&&defaultCase) {
   if(request.stats.sModulesTyped==0||!sys.FileSystem.exists(output)) throw "Pipeline reported success without typing modules and writing HXB";
   var input=sys.io.File.read(output,true),entries=haxe.zip.Reader.readZip(input);input.close();
   var basic=false;for(entry in entries) if(entry.fileName=="eval/unit/moduleload/Basic.hxb"&&entry.fileSize>0) basic=true;
   if(!basic) throw "HXB archive is missing the typed Basic module";
  }
  Sys.println("Translated pipeline exit="+code+" parsed="+request.stats.sFilesParsed+" typed="+request.stats.sModulesTyped+" methods="+request.stats.sMethodsTyped);
  Sys.exit(code);
 }
}
