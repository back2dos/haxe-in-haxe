package compiler;
import core.Globals;
import core.Globals.*;
import core.TType;
import core.Ast;
import core.Path;
import core.Timer;
import core.Define;
import context.Common;
import context.Parallel;
import compiler.hxb.HxbWriter;
import compiler.hxb.HxbData;
import compiler.hxb.HxbWriterConfig;
// haxe/src/compiler/generate.ml — mechanical draft; not compile-validated.
// Ordinary target/macro generators remain unresolved dispatch references, not backend implementations.
class MissingHxbModule extends haxe.Exception {public function new() super("Missing_hxb_module");}
class Generate {
 public static function checkAuxiliaryOutput(com:CommonContext,actx:Dynamic):Void {
  if (actx.xmlOut!=null) {if (actx.xmlOut=="hx") Genhxold.generate(com);else {Common.log(com,"Generating xml: "+actx.xmlOut);Path.mkdirFromPath(actx.xmlOut);Genxml.generate(com,actx.xmlOut);}}
  if (actx.jsonOut!=null) {Common.log(com,"Generating json : "+actx.jsonOut);Path.mkdirFromPath(actx.jsonOut);Genjson.generate(com.timerCtx,com.types,actx.jsonOut);}
 }
 public static function createWriter(com:CommonContext,config:Dynamic):{writer:Dynamic,close:Void->haxe.io.Bytes} {
  var anon=new typing.TanonIdentification();var writer=HxbWriter.create(config,function(w,s,p) com.warning(w,com.warningOptions,s,p),anon);
  return {writer:writer,close:function() {var out=new haxe.io.BytesOutput();HxbWriter.export(writer,out);return out.getBytes();}};
 }
 public static function exportHxb(fromCache:Bool,com:CommonContext,config:Dynamic,cc:Dynamic,platform:String,m:ModuleDef):Null<{path:String,bytes:haxe.io.Bytes}> {
  return switch m.mExtra.mKind {
   case MCode|MMacro|MFake|MExtern:
    var path=[platform].concat(m.mPath.pack).concat([m.mPath.name]).join("/")+".hxb";
    if (fromCache) {
     var cache=try cc.getHxbModule(m.mPath) catch (e:Dynamic) {if (e!="Not_found") throw e;throw new MissingHxbModule();};
     var out=new haxe.io.BytesOutput();HxbData.writeHeader(out);
     for (chunk in (cast cache.mcChunks:Array<Dynamic>)) {HxbData.writeChunkPrefix(chunk.kind,chunk.data.length,out);out.write(chunk.data);}
     {path:path,bytes:out.getBytes()};
    }else {var writer=createWriter(com,config);HxbWriter.writeModule(writer.writer,m);{path:path,bytes:writer.close()};}
   case _:null;
  };
 }
 public static function checkHxbOutput(com:CommonContext,config:Dynamic):Void {
  function matchPathList(list:Array<Array<String>>,path:Array<String>):Bool return Lambda.exists(list,function(part) return Ast.matchPath(true,path,part));
  function tryWrite(fromCache:Bool):Void {
   var path=StringTools.replace(config.archivePath,"$target",Globals.platformName(com.platform));var stop=Timer.startTimer(com.timerCtx,["generate","hxb"]);Path.mkdirFromPath(path);var zip=new core.ZipOutput(path,0);
   function export(com:CommonContext,config:Dynamic):Void {
    var cc=CommonCache.getCache(com),target=Common.platformNameMacro(com);
    function emit(m:ModuleDef):Null<{path:String,bytes:haxe.io.Bytes}> {
     var path=m.mPath.pack.concat([m.mPath.name]);
     return !matchPathList(config.exclude,path)||matchPathList(config.include,path) ? Timer.time(com.timerCtx,["generate","hxb",sTypePath(m.mPath)],function() return exportHxb(fromCache,com,config,cc,target,m)) : null;
    }
    var input=com.modules.copy();var output=Parallel.runWithPool(com.sctx.pool,function(pool) return ParallelArray.map(pool,emit,input,null));for (entry in output) if (entry!=null) zip.addEntry(entry.bytes,entry.path);
   }
   var failed:Dynamic=null;var didFail=false;
   try {if (config.targetConfig.generate) export(com,config.targetConfig);if (config.macroConfig.generate) {var macroCom=com.getMacros();if (macroCom!=null) export(macroCom,config.macroConfig);}}
   catch (e:Dynamic) {failed=e;didFail=true;}
   zip.close();stop();if (didFail) throw failed;
  }
  try {if (com.sctx.isServer) try tryWrite(true) catch (_:MissingHxbModule) tryWrite(false);else tryWrite(false);}
  catch (e:SysError) com.error("Could not write to "+config.archivePath+": "+e.message,nullPos);
 }
 public static function parseSwfHeader(com:CommonContext,h:String):Dynamic {
  var parts=h.split(":");return switch parts {
   case [w,h,fps]:{width:OcamlInt.ofString(w),height:OcamlInt.ofString(h),fps:OcamlFloat.ofString(fps),color:0xFFFFFF};
   case [w,h,fps,color]:var color=StringTools.startsWith(color,"0x")?color:"0x"+color;{width:OcamlInt.ofString(w),height:OcamlInt.ofString(h),fps:OcamlFloat.ofString(fps),color:OcamlInt.ofString(color)};
   case _:com.error("Invalid SWF header format, expected width:height:fps[:color]",nullPos);null;
  };
 }
 public static function deleteFile(file:String):Void {try sys.FileSystem.deleteFile(file) catch (_:Dynamic) {}}
 public static function maybeGenerateDumpDependencies(ctx:Dynamic,tctx:Dynamic):Void {
  var com:CommonContext=tctx.com;if (com.partScope.dumpConfig.dumpDependencies) {codegen.Dump.dumpDependencies(com);if (!com.isMacroContext&&tctx.g.macros!=null) codegen.Dump.dumpDependencies(tctx.g.macros.typer.com,"macro");}
 }
 public static function generate(com:CommonContext,tctx:Dynamic,ext:String,actx:Dynamic):Void {
  if (Path.fileExtension(com.file)==ext) deleteFile(com.file);
  if ([Flash,Cpp,Hl].contains(com.platform)) for (t in com.types) codegen.FixOverrides.fixOverrides(com,t);
  switch com.platform {case Neko|Hl|Eval if (actx.interp):case Cpp if (Common.defined(com,Define.Cppia)):case Cpp|Php:Path.mkdirFromPath(com.file+"/.");case _:Path.mkdirFromPath(com.file);}
  if (actx.interp) {
   var stop=Timer.startTimer(com.timerCtx,["interp"]);try MacroContext.interpret(tctx,com.partScope.runtimeArgs) catch (e:Dynamic) {stop();throw e;}stop();
  } else {
   var name:String;var generator:Dynamic;
   switch com.platform {
    case Flash:var header=try parseSwfHeader(com,Common.definedValue(com,Define.SwfHeader)) catch (e:Dynamic) {if (e!="Not_found") throw e;null;};generator=function(ctx) Genswf.generate(header,com.nativeLibs.swfLibs,com.flashVersion,ctx);name="swf";
    case Neko:generator=function(ctx) Genneko.generate(com.nekoLibPaths,ctx);name="neko";
    case Js:generator=function(ctx) Genjs.generate(com.jsGen,ctx);name="js";
    case Lua:generator=Genlua.generate;name="lua";case Php:generator=Genphp7.generate;name="php";case Cpp:generator=Gencpp.generate;name="cpp";
    case Jvm:generator=function(ctx) Genjvm.generate(actx.jvmFlag,ctx);name="jvm";case Python:generator=Genpy.generate;name="python";case Hl:generator=Genhl.generate;name="hl";
    case Eval:generator=function(_) MacroContext.interpret(tctx,[]);name="eval";
    case Cross|CustomTarget(_):generator=function(_) {};name="";
   }
   if (name!="") {Common.log(com,"Generating "+name+": "+com.file);Timer.time(com.timerCtx,["generate",name],function() generator(Common.toGctx(com)));}
  }
 }
}
