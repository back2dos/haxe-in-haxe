package compiler;
import context.Common;
import compiler.ParsedArg;
import compiler.Args.PartArgs;
import compiler.Args.RequestArgs;
import core.ds.ArgumentError;
// haxe/src/compiler/highLevel.ml; haxelib expansion deferred explicitly.
class HighLevel {
 public static function createContextFromPart(sctx:Dynamic,requestScope:RequestScope,hasDisplay:Bool,hasNext:Bool,part:PartArgs):CommonContext {
  sctx.compilationStep++;var com=Compiler.createContext(sctx,requestScope,part.runtimeArgs,hasNext);
  for (arg in part.args) switch arg {
   case AddLib(_):throw new ArgumentError("Haxelib integration is outside the source-only HXB milestone");
   case _:
  }
  com.parsedArgs=part.args.copy();return com;
 }
 public static function entry(sctx:Dynamic,requestScope:RequestScope,requestArgs:RequestArgs):Int {
  var cwd=Sys.getCwd(),hasDisplay=requestArgs.displayArg!=null,parts:Array<PartArgs>=requestArgs.parts,code=0;
  for (i in 0...parts.length) {var com=createContextFromPart(sctx,requestScope,hasDisplay,i+1<parts.length,parts[i]);code=Compiler.compileCtx(sctx,com);Sys.setCwd(cwd);if (code!=0||i+1==parts.length||hasDisplay) break;}
  Sys.setCwd(cwd);return code;
 }
}
