package typing;

import core.TType;
import core.TType.*;
import core.TFunctions.*;
import core.TOther.*;
import core.Globals;
import core.Error.*;
import context.Typecore.*;
import context.TyperPass;
import context.TyperManager;
import context.Common;
import context.Define;
import typing.Typer.*;
import context.Resolution.*;

// haxe/src/typing/typerEntry.ml — mechanical draft; not compile-validated.
class TyperEntry {
 public static function loadStdTypes(ctx:Dynamic):Void {
  var stdTypes:Dynamic;
  try stdTypes=TypeloadModule.loadModule(ctx,{pack:[],name:"StdTypes"},Globals.nullPos) catch(e:Dynamic) {
   switch e {case Error({errMessage:ModuleNotFound({pack:[],name:"StdTypes"})}): raiseStdNotFound(); case _: throw e;}
  }
  var types:Array<Dynamic>=stdTypes.mTypes.copy(); types.reverse();
  for(t in types) {
   ctx.m.importResolution.add(moduleTypeResolution(t,null,Globals.nullPos));
   switch t {
    case TAbstractDecl(a): switch a.aPath.name {
     case "Void": var t=TAbstract(a,[]); Type.unify(t,ctx.t.tvoid); ctx.t.tvoid=t;
     case "Float": var t=TAbstract(a,[]); Type.unify(t,ctx.t.tfloat); ctx.t.tfloat=t;
     case "Int": var t=TAbstract(a,[]); Type.unify(t,ctx.t.tint); ctx.t.tint=t;
     case "Bool": var t=TAbstract(a,[]); Type.unify(t,ctx.t.tbool); ctx.t.tbool=t;
     case "Dynamic": ctx.g.tDynamicDef=TAbstract(a,extractParamTypes(a.aParams));
     case "Null":
      ctx.t.tnull=function(t:Dynamic):Dynamic {
       try return !isNull(t,true) && !isExplicitNull(t)?TAbstract(a,[t]):t;
       catch(err:Dynamic) {
        if(err!="Exit") throw err;
        var r={value:lazyAvailable(tDynamic)};
        r.value=lazyWait(function() {var t1=!isNull(t)?TAbstract(a,[t]):t; r.value=lazyAvailable(t1); return t1;});
        return TLazy(r);
       }
      };
     case _:
    }
    case TTypeDecl(td): if(td.tPath.name=="Iterator") ctx.t.titerator=t -> TType(td,[t]);
    case TEnumDecl(_) | TClassDecl(_):
   }
  }
 }
 public static function loadString(ctx:Dynamic):Void {
  var m=TypeloadModule.loadModule(ctx,{pack:[],name:"String"},Globals.nullPos);
  for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TClassDecl(({clPath:{pack:[],name:"String"}} => c)): var t=TInst(c,[]); Type.unify(t,ctx.t.tstring); ctx.t.tstring=t; case _:}
 }
 public static function loadStd(ctx:Dynamic):Void {
  var m=TypeloadModule.loadModule(ctx,{pack:[],name:"Std"},Globals.nullPos);
  for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TClassDecl(({clPath:{pack:[],name:"Std"}} => c)): ctx.com.std=c; case _:}
 }
 public static function loadAny(ctx:Dynamic):Void {
  var m=TypeloadModule.loadModule(ctx,{pack:[],name:"Any"},Globals.nullPos);
  for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TAbstractDecl(a) if(a.aPath.name=="Any"): var t=TAbstract(a,[]); Type.unify(t,ctx.t.tany); ctx.t.tany=t; case _:}
 }
 public static function loadArray(ctx:Dynamic):Void {
  var m=TypeloadModule.loadModule(ctx,{pack:[],name:"Array"},Globals.nullPos);
  for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TClassDecl(({clPath:{pack:[],name:"Array"}} => c)): ctx.t.tarray=t -> TInst(c,[t]); return; case _:}
  throw "Could not locate Array";
 }
 public static function loadUnit(ctx:Dynamic):Void {
  var m=TypeloadModule.loadModule(ctx,{pack:["haxe"],name:"Unit"},Globals.nullPos);
  for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TEnumDecl(en) if(en.ePath.name=="Unit"): ctx.t.tunit=TEnum(en,[]); case _:}
 }
 public static function loadEnumTools(ctx:Dynamic):Void {
  var m=TypeloadModule.loadModule(ctx,{pack:["haxe"],name:"EnumTools"},Globals.nullPos);
  switch m.mTypes {
   case [TClassDecl(c1),TClassDecl(c2)]: ctx.g.globalUsing=[{c:c1,pos:c1.clPos},{c:c2,pos:c2.clPos}].concat(ctx.g.globalUsing);
   case [TClassDecl(c1)]:
    var m=TypeloadModule.loadModule(ctx,{pack:["haxe"],name:"EnumValueTools"},Globals.nullPos);
    switch m.mTypes {case [TClassDecl(c2)]: ctx.g.globalUsing=[{c:c1,pos:c1.clPos},{c:c2,pos:c2.clPos}].concat(ctx.g.globalUsing); case _: throw "Invalid EnumValueTools module";}
   case _: throw "Invalid EnumTools module";
  }
 }
 public static function loadLocalWrapper(ctx:Dynamic):Dynamic {
  var t=ctx.t;
  if(ctx.com.platform==Jvm) {
   var m=TypeloadModule.loadModule(ctx,{pack:["jvm"],name:"NativeArray"},Globals.nullPos);
   var cnativearray:Dynamic=null;
   for(md in (cast m.mTypes:Array<Dynamic>)) switch md {case TClassDecl(({clPath:{pack:["jvm"],name:"NativeArray"}} => cl)): cnativearray=cl; break; case _:}
   if(cnativearray==null) throw "Not_found";
   return {
    capturedType:function(t:Dynamic):Dynamic return TInst(cnativearray,[t]),
    mkRef:function(v:Dynamic,ve:Dynamic,p:Dynamic):Dynamic {
     if(ve==null) {
      var eone=mk(TConst(TInt(1)),t.tint,p);
      var element=switch v.vType {case TInst(_,[t]):t; case _: throw "Invalid native local wrapper type";};
      return mk(TNew(cnativearray,[element],[eone]),v.vType,p);
     }
     var e=Inline.mkUntypedCall("__array__",p,[ve]); e.etype=v.vType; return e;
    },
    mkRefAccess:function(e:Dynamic,v:Dynamic):Dynamic {var copy=Reflect.copy(e); copy.etype=v.vType; return mk(TArray(copy,mk(TConst(TInt(0)),t.tint,e.epos)),e.etype,e.epos);},
    mkInit:function(av:Dynamic,v:Dynamic,pos:Dynamic):Dynamic {var earray=Inline.mkUntypedCall("__array__",pos,[mk(TLocal(v),v.vType,pos)]); earray.etype=av.vType; return mk(TVar(av,earray),t.tvoid,pos);}
   };
  }
  return {
   capturedType:t.tarray,
   mkRef:function(v:Dynamic,ve:Dynamic,p:Dynamic):Dynamic return mk(TArrayDecl(ve==null?[]:[ve]),v.vType,p),
   mkRefAccess:function(e:Dynamic,v:Dynamic):Dynamic {var copy=Reflect.copy(e); copy.etype=v.vType; return mk(TArray(copy,mk(TConst(TInt(0)),t.tint,e.epos)),e.etype,e.epos);},
   mkInit:function(av:Dynamic,v:Dynamic,pos:Dynamic):Dynamic return mk(TVar(av,mk(TArrayDecl([mk(TLocal(v),v.vType,pos)]),av.vType,pos)),t.tvoid,pos)
  };
 }
 public static function loadCoro(ctx:Dynamic):Void {
  ctx.t.tcoro.tcoro=AtomicLazy.fromFun(function() {
   var m=TypeloadModule.loadModule(ctx,{pack:["haxe","coro"],name:"Coroutine"},Globals.nullPos);
   for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TAbstractDecl(({aPath:{pack:["haxe","coro"],name:"Coroutine"}} => a)): return function(args:Dynamic,ret:Dynamic):Dynamic return TAbstract(a,[TFun(args,ret)]); case _:}
   throw "Could not locate abstract Coroutine<T> (was it redefined?)";
  });
  ctx.t.tcoro.continuation=AtomicLazy.fromFun(function() {
   var m=TypeloadModule.loadModule(ctx,{pack:["haxe","coro"],name:"IContinuation"},Globals.nullPos);
   for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TClassDecl(({clPath:{pack:["haxe","coro"],name:"IContinuation"}} => cl)): return TInst(cl,[ctx.t.tany]); case _:}
   throw "Could not locate class IContinuation<T> (was it redefined?)";
  });
  ctx.t.tcoro.suspensionResultClass=AtomicLazy.fromFun(function() {
   var m=TypeloadModule.loadModule(ctx,{pack:["haxe","coro"],name:"SuspensionResult"},Globals.nullPos);
   for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TClassDecl(({clPath:{pack:["haxe","coro"],name:"SuspensionResult"}} => cl)): return cl; case _:}
   throw "Could not locate class SuspensionResult<T> (was it redefined?)";
  });
  ctx.t.tcoro.tasyncIterator=AtomicLazy.fromFun(function() {
   var m=TypeloadModule.loadModule(ctx,{pack:["haxe","coro"],name:"AsyncIterator"},Globals.nullPos);
   for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TTypeDecl(({tPath:{pack:["haxe","coro"],name:"AsyncIterator"}} => td)): return function(t:Dynamic):Dynamic return TType(td,[t]); case _:}
   throw "Could not locate typedef AsyncIterator<T> (was it redefined?)";
  });
  var m=TypeloadModule.loadModule(ctx,{pack:["haxe"],name:"Exception"},Globals.nullPos);
  for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TClassDecl(({clPath:{pack:["haxe"],name:"Exception"}} => cl)): ctx.t.texception=TInst(cl,[]); case _:}
 }
 public static function create(com:Dynamic,macros:Dynamic):Dynamic {
  var ctx:Dynamic={com:com,t:com.basic,g:null,
   m:{curmod:nullModule,importResolution:new ResolutionList(["import","typer"]),ownResolution:null,enumWithType:null,moduleUsing:[],importStatements:[],isDisplayFile:false},
   c:{curclass:nullClass,tthis:tDynamic,getBuildInfos:function() return null},f:TyperManager.createCtxF(nullField),e:TyperManager.createCtxE(FunStatic,FunFunction),
   pass:PBuildModule,allowInline:true,allowTransform:true,typeParams:[],memoryMarker:memoryMarker};
  ctx.g={coreApi:null,macros:macros,moduleCheckPolicies:[],delayed:[for(_ in 0...TyperPass.allTyperPassesLength) {tasks:[],tasksLate:[]}],delayedMinIndex:0,debugDelayed:[],retainMeta:Common.defined(com,Define.RetainUntypedMeta),globalUsing:[],complete:false,typeHints:[],loadOnlyCachedModules:false,returnPartialType:false,buildCount:0,tDynamicDef:tDynamic,continuationApi:null,
   doMacro:MacroContext.typeMacro,doLoadMacro:MacroContext.loadMacroPrime,doLoadModule:TypeloadModule.loadModule,doLoadTypeDef:Typeload.loadTypeDef,getBuildInfo:InstanceBuilder.getBuildInfo,doFormatString:formatString,doLoadCoreClass:Typeload.loadCoreClass,delayedDisplay:null,callArgContext:null,rootTyper:ctx};
  loadStdTypes(ctx); loadString(ctx); loadStd(ctx); loadAny(ctx); loadUnit(ctx); loadArray(ctx); loadEnumTools(ctx); loadCoro(ctx);
  ctx.com.localWrapper=loadLocalWrapper(ctx); ctx.g.complete=true; return ctx;
 }
 static function __init__():Void {createContextRef=create;}
}
