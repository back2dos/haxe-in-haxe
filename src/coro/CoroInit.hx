package coro;
import core.TType;
import core.TFunctions.NotFound;
import core.ds.AtomicLazy;
import core.ds.PMap;
import core.Globals;
import core.Globals.*;
import coro.ContTypes;
// haxe/src/coro/coroInit.ml — mechanical draft; not compile-validated.
class CoroInit {
 public static function loadModuleClass(ctx:Dynamic,path:Dynamic):TClass {
  var m=ctx.g.doLoadModule(ctx,path,nullPos);
  for(mt in (m.mTypes:Array<ModuleType>)) switch mt {case TClassDecl(c) if(c.clPath==path):return c; case _:} throw NotFound.raise();
 }
 public static function loadModuleAbstract(ctx:Dynamic,path:Dynamic):TAbstract {
  var m=ctx.g.doLoadModule(ctx,path,nullPos);
  for(mt in (m.mTypes:Array<ModuleType>)) switch mt {case TAbstractDecl(a) if(a.aPath==path):return a; case _:} throw NotFound.raise();
 }
 public static function makeContinuationApi(ctx:Dynamic):ContinuationApi {
  var base=loadModuleClass(ctx,{pack:["haxe","coro"],name:"BaseContinuation"});
  var state=TAbstract(loadModuleAbstract(ctx,{pack:["haxe","coro"],name:"SuspensionState"}),[]);
  var result=(ctx.t.tcoro.suspensionResultClass).force();
  var api=ContTypes.createContinuationApi(base,state,result,(ctx.t.tcoro.continuation).force(),PMap.find("suspended",result.clStatics),PMap.find("state",result.clFields),PMap.find("result",result.clFields),PMap.find("error",result.clFields),PMap.find("completion",base.clFields),PMap.find("context",base.clFields),PMap.find("gotoLabel",base.clFields));
  ctx.g.continuationApi=api; return api;
 }
}
