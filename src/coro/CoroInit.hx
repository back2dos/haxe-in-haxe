package coro;
import core.TType;
import core.Globals.*;
import coro.ContTypes;
// haxe/src/coro/coroInit.ml — mechanical draft; not compile-validated.
class CoroInit {
 public static function loadModuleClass(ctx:Dynamic,path:Dynamic):TClass {
  var m=ctx.g.doLoadModule(ctx,path,nullPos);
  for(mt in (m.mTypes:Array<ModuleType>)) switch mt {case TClassDecl(c) if(c.clPath==path):return c; case _:} throw new NotFound();
 }
 public static function loadModuleAbstract(ctx:Dynamic,path:Dynamic):TAbstract {
  var m=ctx.g.doLoadModule(ctx,path,nullPos);
  for(mt in (m.mTypes:Array<ModuleType>)) switch mt {case TAbstractDecl(a) if(a.aPath==path):return a; case _:} throw new NotFound();
 }
 public static function makeContinuationApi(ctx:Dynamic):ContinuationApi {
  var base=loadModuleClass(ctx,{pack:["haxe","coro"],name:"BaseContinuation"});
  var state=TAbstract(loadModuleAbstract(ctx,{pack:["haxe","coro"],name:"SuspensionState"}),[]);
  var result=AtomicLazy.force(ctx.t.tcoro.suspensionResultClass);
  var api=ContTypes.createContinuationApi(base,state,result,AtomicLazy.force(ctx.t.tcoro.continuation),result.clStatics.find("suspended"),result.clFields.find("state"),result.clFields.find("result"),result.clFields.find("error"),base.clFields.find("completion"),base.clFields.find("context"),base.clFields.find("gotoLabel"));
  ctx.g.continuationApi=api; return api;
 }
}
