package typing;

import core.Ast;
import core.Ast.*;
import core.TType;
import core.TType.*;
import core.TFunctions.*;
import core.TOther.*;
import core.TPrinting.*;
import core.Globals;
import core.Meta;
import core.Error.*;
import context.Typecore.*;
import context.TyperPass;
import context.TyperManager;
import typing.FunctionArguments;

// haxe/src/typing/typeloadFunction.ml — mechanical draft; not compile-validated.
class TypeloadFunction {
 public static function saveFieldState(ctx:Dynamic):Void->Void {var locals=ctx.f.locals; return function() {ctx.f.locals=locals;};}
 public static function typeFunctionParams(ctx:Dynamic,fd:Dynamic,host:Dynamic,fname:String):Dynamic return Typeload.typeTypeParams(ctx,host,{pack:[],name:fname},fd.fParams);
 static function typeFunctionInner(ctx:Dynamic,args:FunctionArguments,ret:Dynamic,syntax:Dynamic,doDisplay:Bool,p:Dynamic):Dynamic {
  ctx.e.ret=ret; ctx.e.opened=[];
  enterFieldTypingPass(ctx.g,{name:"type_function",path:ctx.c.curclass.clPath.pack.concat([ctx.c.curclass.clPath.name,ctx.f.curfield.cfName])});
  args.bringIntoContext(ctx);
  if(syntax==null) {
   if(ignoreError(ctx.com)) syntax={expr:EBlock([]),pos:p};
   else if(ctx.e.curfun==FunMember && hasClassFlag(ctx.c.curclass,CAbstract)) raiseTypingError("Function body or abstract modifier required",p);
   else raiseTypingError("Function body required",p);
  }
  var positionDebug=Meta.has(Meta.Custom(":debug.position"),ctx.f.curfield.cfMeta);
  var e:Dynamic;
  if(!doDisplay) {
   if(positionDebug) Sys.println("syntax:\n"+Expr.dumpWithPos(syntax));
   e=typeExpr(ctx,syntax,NoValue);
  } else {
   var displayDebug=Meta.has(Meta.Custom(":debug.display"),ctx.f.curfield.cfMeta);
   if(displayDebug) Sys.println("before processing:\n"+Expr.dumpWithPos(syntax));
   if(!ctx.com.partScope.parserState.hadParserResume) syntax=Display.preprocessExpr(ctx.com,syntax);
   if(displayDebug) Sys.println("after processing:\n"+Expr.dumpWithPos(syntax));
   e=typeExpr(ctx,syntax,NoValue);
  }
  switch e.eexpr {case TMeta({meta:Meta.MergeBlock},({eexpr:TBlock(_)} => e1)): e=e1; case _:}
  function hasReturn(e:Dynamic):Bool {
   function loop(e:Dynamic):Void switch e.eexpr {case TReturn(v) if(v!=null): throw "Exit"; case TFunction(_): case _: iter(loop,e);}
   try {loop(e); return false;} catch(err:Dynamic) {if(err!="Exit") throw err; return true;}
  }
  switch follow(ret) {
   case TAbstract({aPath:{pack:[],name:"Void"}},_):
   case TMono(_) if(!hasReturn(e)): unify(ctx,ctx.t.tvoid,ret,p);
   case _: try TypeloadCheck.returnFlow(ctx,e) catch(err:Dynamic) {if(err!="Exit") throw err;}
  }
  function findSuper(e:Dynamic):Void switch e.eexpr {case TCall({eexpr:TConst(TSuper)},_): throw "Exit"; case TFunction(_): case _: iter(findSuper,e);}
  function superConstructor():Dynamic {
   var sup=ctx.c.curclass.clSuper;
   if(sup==null) return null;
   try {var cf=getConstructor(sup.c); return {wasForced:Meta.has(Meta.CompilerGenerated,cf.cfMeta),type:TInst(sup.c,sup.params)};}
   catch(err:Dynamic) {if(err!="Not_found") throw err; return null;}
  }
  if(ctx.e.curfun==FunConstructor) {
   var constructorBody=e;
   delay(ctx.g,PForce,function() TypeloadCheck.checkFinalVars(ctx,constructorBody));
   var sup=superConstructor();
   if(sup!=null) try {
    findSuper(e);
    if(sup.wasForced) e=concat(mk(TCall(mk(TConst(TSuper),sup.type,e.epos),[]),ctx.t.tvoid,e.epos),e);
    else displayError(ctx.com,"Missing super constructor call",p);
   } catch(err:Dynamic) {if(err!="Exit") throw err;}
  }
  if((ctx.e.curfun==FunMember || ctx.e.curfun==FunConstructor) && ctx.f.vthis!=null) {
   var v=ctx.f.vthis;
   var ev=mk(TVar(v,mk(TConst(TThis),ctx.c.tthis,p)),ctx.t.tvoid,p);
   switch e.eexpr {
    case TBlock(l):
     if(ctx.com.config.pfThisBeforeSuper) e=mk(TBlock([ev].concat(l)),e.etype,e.epos);
     else {
      function hasV(e:Dynamic):Bool return switch e.eexpr {case TLocal(v1) if(v1==v): true; case _: checkExpr(hasV,e);};
      function insert(l:Array<Dynamic>):Array<Dynamic> {if(l.length==0) return []; var first=l[0]; return hasV(first)?[ev].concat(l):[first].concat(insert(l.slice(1)));}
      e=mk(TBlock(insert(l)),e.etype,e.epos);
     }
    case _: e=mk(TBlock([ev,e]),e.etype,p);
   }
  }
  for(r in (cast ctx.e.opened:Array<Dynamic>)) r.value=Closed;
  if(Meta.has(Meta.Custom(":debug.mono"),ctx.f.curfield.cfMeta)) {
   var pctx=printContext();
   function printMono(i:Int,m:Dynamic):String return StringTools.lpad(Std.string(i)," ",4)+": "+MonomorphPrinting.sMono(sType,pctx,true,m);
   Sys.println("BEFORE:");
   var monos=[];
   var values:Array<Dynamic>=ctx.e.monomorphs;
   for(i in 0...values.length) {
    var m=values[i].mono, mp=values[i].pos, s=printMono(i,m);
    var spos="unknown";
    if(mp.pmin!=-1) {var coords=Lexer.getPosCoords(mp); spos=coords.line1+":"+coords.column1;}
    Sys.println(s+" ("+spos+")"); safeMonoClose(ctx,m,mp); monos.push({index:i,mono:m,pos:mp,text:s});
   }
   Sys.println("CHANGED:");
   for(m in monos) {var s=printMono(m.index,m.mono); if(s!=m.text) Sys.println(s);}
  } else for(m in (cast ctx.e.monomorphs:Array<Dynamic>)) safeMonoClose(ctx,m.mono,m.pos);
  if(positionDebug) Sys.println("typing:\n"+Texpr.dumpWithPos("",e));
  return e;
 }
 public static function typeFunction(ctx:Dynamic,args:FunctionArguments,ret:Dynamic,e:Dynamic,doDisplay:Bool,p:Dynamic):Dynamic {
  var save=saveFieldState(ctx);
  try {var result=typeFunctionInner(ctx,args,ret,e,doDisplay,p); save(); return result;} catch(err:Dynamic) {save(); throw err;}
 }
 public static function addConstructor(ctxC:Dynamic,c:Dynamic,forceConstructor:Bool,p:Dynamic):Void {
  if(c.clConstructor!=null) return;
  var constructor:Dynamic=null;
  try constructor=getConstructorClass(c,extractParamTypes(c.clParams)) catch(err:Dynamic) {if(err!="Not_found") throw err;}
  if(constructor!=null && !hasClassFlag(c,CExtern)) {
   var cfsup=constructor.field, csup=constructor.c, cparams=constructor.params;
   var cf=mkField("new",cfsup.cfType,p,Globals.nullPos);
   cf.cfKind=cfsup.cfKind; cf.cfParams=cfsup.cfParams;
   cf.cfMeta=(cast cfsup.cfMeta:Array<Dynamic>).filter(m -> m.meta==Meta.CompilerGenerated);
   var t=spawnMonomorph(ctxC,p);
   var r=makeLazy(ctxC.g,t,function() {
    var ctx=TyperManager.cloneForField(ctxC,cf,cf.cfParams);
    follow(cfsup.cfType);
    for(cf in (cast cfsup.cfOverloads:Array<Dynamic>)) follow(cf.cfType);
    function mapArg(arg:Dynamic):Dynamic {
     var v=arg.variable, def=arg.defaultValue;
     function nullValue(v:Dynamic):Dynamic return Texpr.Builder.makeNull(v.vType,v.vPos);
     if(def!=null && !ctx.com.config.pfStatic) return {variable:v,defaultValue:nullValue(v)};
     switch [ctx.com.platform,def] {
      case [Flash,{eexpr:TConst(TString(_))}] if(!hasClassFlag(csup,CExtern)): return {variable:v,defaultValue:nullValue(v)};
      case [Cpp,{eexpr:TConst(TString(_))}]: return arg;
      case [Cpp,_] if(def!=null): var v1=Reflect.copy(v); v1.vType=ctx.t.tnull(v.vType); return {variable:v1,defaultValue:nullValue(v1)};
      case _: return arg;
     }
    }
    var args:Array<Dynamic>=switch cfsup.cfExpr {
     case {eexpr:TFunction(f)}: f.tfArgs.map(mapArg);
     case _:
      var values=getValueMeta(cfsup.cfMeta);
      switch follow(cfsup.cfType) {
       case TFun(args,_): args.map(function(arg) {
        var def:Dynamic;
        if(values.exists(arg.name)) def=FunctionArguments.typeFunctionArgValue(ctx,arg.type,values.get(arg.name),false);
        else def=arg.optional?Texpr.Builder.makeNull(arg.type,Globals.nullPos):null;
        return mapArg({variable:allocVar(VUser(TVOArgument),arg.name,arg.optional?ctx.t.tnull(arg.type):arg.type,p),defaultValue:def});
       });
       case t: displayError(ctxC.com,"Unexpected constructor type: "+sTypeKind(t),cfsup.cfNamePos); [];
      }
    };
    var cp=c.clPos;
    var vars=args.map(arg -> {variable:allocVar(VUser(TVOArgument),arg.variable.vName,applyParams(csup.clParams,cparams,arg.variable.vType),arg.variable.vPos),defaultValue:arg.defaultValue});
    var superCall=mk(TCall(mk(TConst(TSuper),TInst(csup,cparams),cp),vars.map(arg -> mk(TLocal(arg.variable),arg.variable.vType,cp))),ctx.t.tvoid,cp);
    var constr=mk(TFunction({tfArgs:vars,tfType:ctx.t.tvoid,tfExpr:superCall}),TFun(vars.map(arg -> {name:arg.variable.vName,optional:arg.defaultValue!=null,type:arg.variable.vType}),ctx.t.tvoid),cp);
    cf.cfExpr=constr; cf.cfType=t; unify(ctx,t,constr.etype,cp); return t;
   },"add_constructor");
   cf.cfType=TLazy(r); c.clConstructor=cf;
  } else if(forceConstructor) {
   var constr=mk(TFunction({tfArgs:[],tfType:ctxC.t.tvoid,tfExpr:mk(TBlock([]),ctxC.t.tvoid,p)}),tfun([],ctxC.t.tvoid),p);
   var cf=mkField("new",constr.etype,p,Globals.nullPos);
   cf.cfExpr=constr; cf.cfType=constr.etype; cf.cfMeta=[{meta:Meta.CompilerGenerated,exprs:[],pos:Globals.nullPos}]; cf.cfKind=Method(MethNormal); c.clConstructor=cf;
  }
 }
 static function __init__():Void {Typeload.typeFunctionParamsRef=typeFunctionParams;}
}
