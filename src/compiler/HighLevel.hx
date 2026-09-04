package compiler;
import context.Common;
// haxe/src/compiler/highLevel.ml — mechanical batch-entry draft; not compile-validated.
// add_libs (upstream lines 5–56) is deferred with haxelib integration. Its call remains unresolved.
class HighLevel {
 public static function createContextFromPart(sctx:Dynamic,requestScope:RequestScope,hasDisplay:Bool,hasNext:Bool,part:Dynamic):CommonContext {
  sctx.compilationStep++;var com=Compiler.createContext(sctx,requestScope,part.runtimeArgs,hasNext);
  function expandPartLibs(hasGlobal:Bool,args:Array<Dynamic>):Array<Dynamic> {
   var result=[];for (arg in args) {var expanded=switch arg {
    case Expand(ex):switch ex.state {
     case AlreadyExpanded(expanded):expanded;
     case NotYetExpanded(AddLibs(libs)):var lines=addLibs(requestScope.timerCtx,libs,hasGlobal?["--haxelib-global"]:[],sctx.cs,hasDisplay);var expanded=Args.parseArgs(lines);ex.state=AlreadyExpanded(expanded);expanded;
    }
    case _:[arg];
   };result=result.concat(expanded);}return result;
  }
  var hasGlobal=Lambda.exists((cast part.args:Array<Dynamic>),function(arg) return arg==HaxelibGlobal);com.parsedArgs=expandPartLibs(hasGlobal,part.args);return com;
 }
 public static function entry(sctx:Dynamic,requestScope:RequestScope,requestArgs:Dynamic):Int {
  var cwd=Sys.getCwd(),hasDisplay=requestArgs.displayArg!=null,parts:Array<Dynamic>=requestArgs.parts,code=0;
  for (i in 0...parts.length) {var com=createContextFromPart(sctx,requestScope,hasDisplay,i+1<parts.length,parts[i]);code=Compiler.compileCtx(sctx,com);Sys.setCwd(cwd);if (code!=0||i+1==parts.length||hasDisplay) break;}
  Sys.setCwd(cwd);return code;
 }
}
