package typing;
import core.WithType as WithTypeTools;
import core.WithType.WithTypeValue;
import core.MetaList.StrictMeta as MetaTag;
import core.Globals.Pos;
import core.Abstract as AbstractTools;
import core.Ast;
import core.Ast.*;
import core.TType;
import core.TType.*;
import core.TFunctions.*;
import core.TOther.*;
import core.TOther;
import core.TPrinting.*;
import core.Globals;
import core.Meta;
import core.WithType;
import core.Error.*;
import core.Error;
import context.Typecore.*;
import context.Typecore;
import context.Common;
import context.Common.*;
import core.Globals.*;
import core.TUnification.TUnification.*;
import core.Texpr.Builder;
import typing.FieldCallCandidate.FieldCallCandidateData;
import codegen.Overloads.Resolution;
import compiler.MessageReporting;
import context.Typecore.Typer as TyperContext;
import core.TUnification;
import core.Texpr;
import core.ds.AtomicLazy;
import core.Message;
import context.Typecore.TyperManager;
import typing.FieldAccess;
import typing.FieldAccess.*;
import typing.FieldCallCandidate.*;
import typing.CallUnification.*;

// haxe/src/typing/callUnification.ml — mechanical draft; not compile-validated.
typedef CallAttemptData={var call:Void->TExpr;var display:Null<Dynamic>;}
typedef CallAttemptFailure={var field:TClassField;var error:CompilerError;var display:Null<Dynamic>;}
typedef CallAttempts={var candidates:Array<FieldCallCandidateData<CallAttemptData>>;var failures:Array<CallAttemptFailure>;}
typedef CallParameter={var name:String;var optional:Bool;var type:T;}
enum OverloadKind {OverloadProper; OverloadMeta; OverloadNone;}
class CallUnification {
 public static function unifyCallArgs(ctx:TyperContext,el:Array<Expr>,args:Array<CallParameter>,r:T,callp:Pos,isInline:Bool,forceInline:Bool,inOverload:Bool,?callFieldP:Pos):Array<TExpr> {
  if(callFieldP==null) callFieldP=callp;
  function callError(err:core.Error.CallError,p:Pos):Dynamic return raiseErrorMsg(CallError(err),p);
  function argError(e:CompilerError,name:String,opt:Bool):Dynamic {
   var msg="For "+(opt?"optional ":"")+"function argument '"+name+"'",copy=Reflect.copy(e);
   switch e.errMessage {case Unify(l):copy.errMessage=Unify(l.concat([UnifyCustom(msg)])); case _:copy.errSub=[makeError(Custom(complMsg(msg)),e.errPos)].concat(e.errSub);}
   copy.errMessage=CallError(CouldNotUnify(copy.errMessage)); return raiseError(copy);
  }
  function posInfos(t:T):TExpr return mkInfosT(ctx,callp,[],t);
  function defaultValue(name:String,t:T):TExpr return isPosInfos(t)?posInfos(t):nullExpr(ctx.t.tnull(t),callp);
  var skipped:Array<{name:String,error:CompilerError}>=[],invalidSkips:Array<String>=[];
  function skip(name:String,ul:CompilerError,t:T):TExpr {
   if(!ctx.com.config.pfCanSkipNonNullableArgument&&!isNullable(t)) invalidSkips.unshift(name);
   skipped.unshift({name:name,error:ul}); return defaultValue(name,t);
  }
  function handleErrors(fn:Void->TExpr):TExpr {
   try return fn() catch(exc:Dynamic) {switch exc {
    case (core.ds.ExceptionTools.typing(_) => Some(e)):switch e.errMessage {case CallError(_)|ModuleNotFound(_):throw exc; case _:throw new context.Typecore.WithTypeError(e);}
    case _:throw exc;
   }}
  }
  function typeAgainst(name:String,t:T,e:Expr):TExpr return handleErrors(function() {var e=typeExpr(ctx,e,WithTypeTools.withArgument(t,name)); return castOrUnifyRaiseRef(ctx,t,e,e.epos);});
  function restError(fn:Void->Array<TExpr>,name:String):Array<TExpr> {try return fn() catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.withType(_) => Some(e)):return argError(e,name,false); case _:throw exc;}}}
  function loop(el:Array<Expr>,args:Array<CallParameter>):Array<TExpr> {
   if(el.length==0&&args.length==0) {if(invalidSkips.length>0) callError(CannotSkipNonNullable(invalidSkips[invalidSkips.length-1]),callp); return [];}
   if(args.length==1&&!args[0].optional) {
    var name=args[0].name,t=args[0].type;
    switch t {case TAbstract({aPath:{pack:["cpp"],name:"Rest"}},[element]):return restError(() -> el.map(e -> typeAgainst(name,element,e)),name); case _:}
    if(ExtType.isRest(follow(t))) return switch follow(t) {
     case TAbstract({aPath:{pack:["haxe"],name:"Rest"}},[argT]):
      function unexpectedSpread(p:Pos):Dynamic return argError(makeError(Custom("Cannot spread arguments with additional rest arguments"),p),name,false);
      var spread:Null<{expr:Expr,pos:Pos}>=el.length==1?switch el[0].expr {case EUnop(Spread,Prefix,e):{expr:e,pos:el[0].pos}; case _:null;}:null;
      if(ctx.com.config.pfSupportsRestArgs) {
       function typeRest(getType:Void->T):Array<TExpr> return el.map(function(e) return switch e.expr {case EUnop(Spread,Prefix,_):unexpectedSpread(e.pos); case _:typeAgainst(name,getType(),e);});
       if(spread!=null) restError(() -> [mk(TUnop(Spread,Prefix,typeAgainst(name,t,spread.expr)),t,spread.pos)],name);
       else if(ExtType.isMono(follow(argT))) restError(function() {var typed=typeRest(mkMono); Typecore.unify(ctx,unifyMin(ctx,typed),argT,Texpr.punionEl(callp,typed)); return typed;},name);
       else restError(() -> typeRest(() -> argT),name);
      } else {
       if(spread!=null) restError(() -> [typeAgainst(name,t,spread.expr)],name);
       else if(el.length==0) restError(() -> [typeAgainst(name,t,{expr:EArrayDecl([]),pos:callp})],name);
       else {
        var p=el[0].pos;
        for(e in el) switch e.expr {case EUnop(Spread,Prefix,_):unexpectedSpread(e.pos); case _:p=Ast.punion(p,e.pos);}
        restError(function() {
         var e:Expr={expr:EArrayDecl(el),pos:p};
         if(follow(argT)==tDynamic) {var dynamicType=makePtpTh(mkTypePath([],"Dynamic"),p); var ct=makePtpCt(mkTypePath([],"Array",[TPType(dynamicType)]),p); e={expr:ECheckType(e,{type:ct,pos:p}),pos:p};}
         return [typeAgainst(name,t,e)];
        },name);
       }
      }
     case _:throw "Invalid rest type";
    };
   }
   if(el.length==0) {
    var arg=args[0],tail=args.slice(1);
    if(!arg.optional) {var tailP=Reflect.copy(callp); tailP.pmin=callFieldP.pmin; return callError(NotEnoughArguments(args),tailP);}
    var rest=loop([],tail);
    if(!ctx.allowTransform) return [];
    if(rest.length==0&&!(isInline&&(ctx.com.doinline||forceInline))&&!ctx.com.config.pfPadNulls) return isPosInfos(arg.type)?[posInfos(arg.type)]:[];
    return [defaultValue(arg.name,arg.type)].concat(rest);
   }
   if(args.length==0) {
    if(skipped.length==0) {
     if(ctx.m.isDisplayFile&&!context.DeferredServices.display()) {typeExpr(ctx,el[0],WithTypeTools.value); loop(el.slice(1),[]);}
     return callError(TooManyArguments,el[0].pos);
    }
    var first=skipped[skipped.length-1]; return argError(first.error,first.name,true);
   }
   var e=el[0],arg=args[0],tailEl=el.slice(1),tailArgs=args.slice(1),name=arg.name,opt=arg.optional,t=arg.type;
   var bodyCapture=resetCallArgBodyCapture(ctx),restoreMonos:Void->Void=opt?monomorphTransaction(ctx):function() {},committed=false;
   function commit():Void {if(!committed) {committed=true; Common.commitCapturedMessages(ctx.com,bodyCapture.value);}}
   function drop():Void {committed=true;}
   var mightSkip=opt&&tailEl.length<tailArgs.length,optFollowedByRest=opt&&tailArgs.length==1&&ExtType.isRest(follow(tailArgs[0].type));
   function maybeRaiseCapturedError():Void {
    if(mightSkip||optFollowedByRest) for(cm in bodyCapture.value) if(Message.severity(cm)==MessageSeverity.Error) throw new context.Typecore.WithTypeError(makeError(Custom(cm.cmMessage),cm.cmPos));
   }
   try {
    try {var typed=typeAgainst(name,t,e); maybeRaiseCapturedError(); commit(); return [typed].concat(loop(tailEl,tailArgs));}
    catch(exc:Dynamic) {switch exc {
     case (core.ds.ExceptionTools.withType(_) => Some(ul)):
      if(mightSkip||optFollowedByRest) {drop(); restoreMonos(); var def=skip(name,ul,t); return [def].concat(loop(el,tailArgs));}
      var isFunction=switch follow(t) {case TFun(_):true; case _:false;};
      if(bodyCapture.value.length!=0&&!isFunction) {commit(); restoreMonos(); var def=defaultValue(name,t); return [def].concat(loop(tailEl,tailArgs));}
      commit(); if(skipped.length==0) return argError(ul,name,opt); var first=skipped[skipped.length-1]; return argError(first.error,first.name,true);
     case _:throw exc;
    }}
   } catch(exc:haxe.Exception){commit(); throw exc;}
  }
  var restore=enterCallArgs(ctx,inOverload);
  try {var result=loop(el,args); restore(); return result;} catch(exc:haxe.Exception){restore(); throw exc;}
 }
 public static function unifyTypedArgs(tmap:T->T,args:Array<CallParameter>,typed:Array<TExpr>,callPos:Pos):{typed:Array<CallParameter>,remaining:Array<CallParameter>} {
  var consumed=[];
  for(i in 0...typed.length) {
   if(i>=args.length) raiseErrorMsg(CallError(TooManyArguments),callPos);
   var e=typed[i],arg=args[i];
   try unifyRaise(tmap(e.etype),arg.type,e.epos) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)):switch err.errMessage {case Unify(_):var copy=Reflect.copy(err); copy.errMessage=CallError(CouldNotUnify(err.errMessage)); raiseError(copy); case _:throw exc;} case _:throw exc;}}
   consumed.push(arg); tmap=t -> t;
  }
  return {typed:consumed,remaining:args.slice(typed.length)};
 }
 public static function ensureCoroAvailability(com:CommonContext):Void {com.basic.tcoro.suspensionResultClass.force().clBuild();}
 public static function wrapWithResolveTo(com:CommonContext,ecall:TExpr,econt:TExpr,p:Pos):TExpr {
  var basic=com.basic,b=new coro.CoroElsewhere.TexprBuilder(basic,p),c=basic.tcoro.suspensionResultClass.force();
  var param=switch follow(ecall.etype) {case TInst(_,[t]):t; case _:throw "Expected SuspensionResult with one type parameter for coroutine call result";};
  var cf=c.clFields.get("resolveTo"); if(cf==null) throw core.ds.NotFound.raise();
  var type=applyParams(c.clParams,[param],cf.cfType);
  function resolve(call:TExpr,cont:TExpr):TExpr return b.call(b.instanceField(call,c,[param],cf,type),[cont],basic.tvoid);
  switch econt.eexpr {case TLocal(_)|TConst(_):return resolve(ecall,econt); case _:}
  var v=allocVar(VGenerated,"_hx_cont",econt.etype,econt.epos),local=b.local(v,v.vPos);
  var call=switch ecall.eexpr {case TCall(ef,args) if(args.length>0):mk(TCall(ef,[local].concat(args.slice(1))),ecall.etype,ecall.epos); case _:throw "Expected TCall with at least one argument (continuation)";};
  return b.voidBlock([b.varInit(v,econt),resolve(call,local)]);
 }
 public static function unifyFieldCall(ctx:TyperContext,fa:context.Typecore.FieldAccess,elTyped:Array<TExpr>,el:Array<Expr>,p:Pos,isInline:Bool):FieldCallCandidateData<Void->TExpr> {
  function expand(cf:TClassField):Array<TClassField> return [cf].concat(cf.cfOverloads);
  var candidates:Array<TClassField>,co:Null<TClass>,isStatic:Bool,map:T->T,tmap:T->T;
  switch fa.faHost {
   case FHStatic(c):candidates=expand(fa.faField); co=c; isStatic=true; map=t -> t; tmap=t -> t;
   case FHAnon:candidates=expand(fa.faField); co=null; isStatic=false; map=t -> t; tmap=t -> t;
   case FHInstance(c,tl):var cf=fa.faField; candidates=cf.cfName=="new"||!hasClassFieldFlag(cf,CfOverload)?expand(cf):(cast getOverloads(ctx.com,c,cf.cfName):Array<Dynamic>).map(pair -> pair.field); co=c; isStatic=false; map=TClassTools.getMapFunction(c,tl); tmap=t -> t;
   case FHAbstract(a,tl,c):map=t -> applyParams(a.aParams,tl,t); tmap=hasClassFieldFlag(fa.faField,CfAbstractConstructor)?(t -> t):(t -> map(a.aThis)); candidates=expand(fa.faField); co=c; isStatic=true;
  }
  var forced=isForcedInline(co,fa.faField),kind=hasClassFieldFlag(fa.faField,CfOverload)?OverloadProper:fa.faField.cfOverloads.length!=0?OverloadMeta:OverloadNone;
  function extractDisplay():Dynamic {var f=ctx.g.delayedDisplay; ctx.g.delayedDisplay=null; return f;}
  function raiseAugmentedDisplay(cf:Dynamic,de:Dynamic):Dynamic {
   // Original display augmentation is retained in deferred/display/typing/CallUnificationDisplay.hx.
   return context.DeferredServices.display();
  }
  function commitDisplay(fcc:FieldCallCandidateData<CallAttemptData>):FieldCallCandidateData<Void->TExpr> {if(fcc.fcData.display!=null) raiseAugmentedDisplay(fcc.fcField,fcc.fcData.display); return makeFieldCallCandidate(fcc.fcArgs,fcc.fcRet,fcc.fcMonos,fcc.fcType,fcc.fcField,fcc.fcData.call);}
  function attempt(cf:TClassField,inOverload:Bool):FieldCallCandidateData<CallAttemptData> {
   var monos=Monomorph.spawnConstrainedMonos(map,cf.cfParams),t=map(applyParams(cf.cfParams,monos,cf.cfType));
   function make(args:Array<CallParameter>,ret:T,coro:Bool):FieldCallCandidateData<CallAttemptData> {
    var split=unifyTypedArgs(tmap,args,elTyped,p),typed:Array<TExpr>;
    typed=unifyCallArgs(ctx,el,split.remaining,ret,p,isInline,forced,inOverload,fa.faFieldPos);
    typed=elTyped.concat(typed); args=split.typed.concat(split.remaining);
    var tf=coro?ctx.t.tcoro.tcoro.force()({args:args,ret:ret}):TFun({args:args,ret:ret});
    function makeCall():TExpr {var ef=mk(TField(fa.faOn,FieldAccess.applyFa(cf,fa.faHost)),t,fa.faPos); return makeCallRef(ctx,ef,typed,ret,p,isInline);}
    return makeFieldCallCandidate(typed,ret,monos,tf,cf,{call:makeCall,display:extractDisplay()});
   }
   return switch followWithCoro(t) {
    case Coro({args:args,ret:ret}) if(!TyperManager.isCoroutineContext(ctx)):
     var expanded=expandCoroType(ctx.com.basic,args,ret); ensureCoroAvailability(ctx.com); var fcc=make(expanded.args,expanded.ret,false);
     if(fcc.fcArgs.length==0) raiseTypingError("Unexpected overload candidate without arguments for coroutine call",p);
     var cont=fcc.fcArgs[0],original=fcc.fcData.call,copy=Reflect.copy(fcc); copy.fcData={call:function() return wrapWithResolveTo(ctx.com,original(),cont,p),display:fcc.fcData.display}; copy;
    case Coro({args:args,ret:ret}):make(args,ret,true);
    case NotCoro(TFun({args:args,ret:ret})):make(args,ret,false);
    case NotCoro(t):raiseTypingError(sType(printContext(),t)+" cannot be called",p);
   };
  }
  var unknownIdentError:Null<CompilerError>=null;
  function checkUnknown(err:CompilerError):Void switch err.errMessage {
   case CallError(CouldNotUnify(UnknownIdent(_)))|UnknownIdent(_):if(unknownIdentError==null) unknownIdentError=err;
   case _:for(sub in err.errSub) checkUnknown(sub);
  }
  function attempts(list:Array<TClassField>):CallAttempts {
   if(list.length==0) return {candidates:[],failures:[]};
   var cf=list[0],current=ctx.e.monomorphs,known=current.map(pair -> {mono:pair.mono,type:pair.mono.tmType,constraints:pair.mono.tmDownConstraints});
   try {
    var candidate=attempt(cf,true); ctx.e.monomorphs=current;
    if(kind==OverloadProper) {var rest=attempts(list.slice(1)); return {candidates:[candidate].concat(rest.candidates),failures:rest.failures};}
    return {candidates:[candidate],failures:[]};
   } catch(exc:Dynamic) {switch exc {
    case (core.ds.ExceptionTools.typing(_) => Some(err)):switch err.errMessage {
     case CallError(_):
      for(m in known) {if(m.type!=m.mono.tmType) m.mono.tmType=m.type; if(m.constraints!=m.mono.tmDownConstraints) m.mono.tmDownConstraints=m.constraints;}
      ctx.e.monomorphs=current; checkUnknown(err); var rest=attempts(list.slice(1));
      return {candidates:rest.candidates,failures:[{field:cf,error:err,display:extractDisplay()}].concat(rest.failures)};
     case _:throw exc;
    }
    case _:throw exc;
   }}
  }
  function checkAccess(cf:TClassField):Void {if(co!=null) checkFieldAccess(ctx,co,cf,isStatic,p);}
  function checkDisplayArgs():Void {if(ctx.m.isDisplayFile) for(e in el) if(Ast.exists(function(def) return switch def {case EDisplay(_):true; case _:false;},e)) {typeExpr(ctx,e,WithTypeTools.value); break;}}
  if(candidates.length==1) {
   var cf=candidates[0]; if(kind==OverloadProper) checkAccess(cf);
   try return commitDisplay(attempt(cf,false)) catch(exc:Dynamic) {switch exc {
    case (core.ds.ExceptionTools.typing(_) => Some(_)) if(Common.ignoreError(ctx.com)):
     checkDisplayArgs(); var tf=TFun({args:el.map(_ -> {name:"",optional:false,type:tDynamic}),ret:tDynamic});
     function call():TExpr {var ef=mk(TField(fa.faOn,FieldAccess.applyFa(fa.faField,fa.faHost)),tf,fa.faPos); return mk(TCall(ef,[]),tDynamic,p);}
     return makeFieldCallCandidate([],tDynamic,[],tf,fa.faField,call);
    case _:throw exc;
   }}
  }
  var all=attempts(candidates),success=all.candidates,failures=all.failures;
  function fail():FieldCallCandidateData<Void->TExpr> {
   var errors:Array<{field:TClassField,error:CompilerError}>=[];
   for(f in failures) {if(f.display!=null) raiseAugmentedDisplay(f.field,f.display); errors.push({field:f.field,error:f.error});}
   checkDisplayArgs(); errors=removeDuplicates((a:{field:TClassField,error:CompilerError},b:{field:TClassField,error:CompilerError}) -> MessageReporting.printError(a.error)!=MessageReporting.printError(b.error),errors);
   if(errors.length==1) return raiseTypingErrorExt(errors[0].error);
   if(unknownIdentError!=null) return raiseTypingErrorExt(unknownIdentError);
   var sub=[];
   for(f in errors) sub.unshift(makeError(Custom("Overload resolution failed for "+sType(printContext(),f.field.cfType)),p,[f.error]));
   sub.unshift(makeError(Custom("End of overload failure reasons"),p)); return raiseTypingErrorExt(makeError(Custom("Could not find a suitable overload, reasons follow"),p,sub));
  }
  if(kind==OverloadProper) {
   var compatible=Resolution.reduceCompatible(success);
   if(compatible.length==0) return fail();
   var fcc=compatible[0]; if(compatible.length==1) checkAccess(fcc.fcField);
   else {var pc=printContext(),sub=compatible.map(fcc -> makeError(Custom(complMsg(sType(pc,fcc.fcType))),fcc.fcField.cfNamePos)); sub.reverse(); displayErrorExt(ctx.com,makeError(Custom("Ambiguous overload, candidates follow"),p,sub));}
   return commitDisplay(fcc);
  }
  return success.length==0?fail():commitDisplay(success[success.length-1]);
 }
 public static function makeStaticCallBetter(ctx:TyperContext,c:TClass,cf:TClassField,tl:TParams,el:Array<TExpr>,t:T,p:Pos):TExpr {
  var fh=switch c.clKind {case KAbstractImpl(a) if(hasClassFieldFlag(cf,CfImpl)):FHAbstract(a,tl,c); case _:FHStatic(c);};
  var fa=FieldAccess.create(Builder.makeStaticThis(c,p),cf,fh,false,p);
  var fcc=unifyFieldCall(ctx,fa,el,[],p,false); return fcc.fcData();
 }
}
class CallDispatcher {
 final ctx:TyperContext; final mode:AccessMode; final withType:WithTypeValue; final p:Pos; final isSet:Bool;
 public function new(ctx:TyperContext,mode:AccessMode,withType:WithTypeValue,p:Pos) {this.ctx=ctx; this.mode=mode; this.withType=withType; this.p=p; isSet=switch mode {case MSet(_):true; case _:false;};}
 function checkAssign():Void {if(isSet&&!Common.ignoreError(ctx.com)) invalidAssign(p);}
 function makeFieldCall(fa:context.Typecore.FieldAccess,typed:Array<TExpr>,el:Array<Expr>):TExpr {
  var fcc=CallUnification.unifyFieldCall(ctx,fa,typed,el,p,fa.faInline);
  if(hasClassFieldFlag(fcc.fcField,CfGeneric)) return typeGenericFunctionRef(ctx,fa,fcc,withType,p);
  if(hasClassFieldFlag(fcc.fcField,CfAbstract)) switch fa.faOn.eexpr {case TConst(TSuper):displayError(ctx.com,"abstract method "+fcc.fcField.cfName+" cannot be accessed directly",p); case _:}
  return fcc.fcData();
 }
 function macroCall(ethis:TExpr,cf:TClassField,el:Array<Expr>):TExpr {
  // Original macro dispatch is retained in deferred/macros/typing/CallDispatcherMacros.hx.
  return context.DeferredServices.macros();
 }
 public function exprCall(e:TExpr,typed:Array<TExpr>,el:Array<Expr>):TExpr {
  checkAssign();
  function defaultCall(t:T):TExpr {
   var all=typed.concat(el.map(e -> typeExpr(ctx,e,WithTypeTools.value))),ret:T;
   if(t==tDynamic) ret=tDynamic; else if(ctx.f.isUntyped) ret=mkMono();
   else {
    var pos=switch e.eexpr {case TField(_,FAnon(cf)|FInstance(_,_,cf)|FStatic(_,cf)|FClosure(_,cf)):patchStringPos(e.epos,cf.cfName); case _:e.epos;};
    ret=raiseTypingError(sType(printContext(),e.etype)+" cannot be called",pos);
   }
   return mk(TCall(e,all),ret,p);
  }
  function make(args:Array<CallParameter>,ret:T):TExpr {var split=CallUnification.unifyTypedArgs(t -> t,args,typed,p); var all=CallUnification.unifyCallArgs(ctx,el,split.remaining,ret,p,false,false,false); return mk(TCall(e,typed.concat(all)),ret,p);}
  function loop(t:T):TExpr return switch followWithCoro(t) {
   case Coro({args:args,ret:ret}) if(!TyperManager.isCoroutineContext(ctx)):
    var expanded=expandCoroType(ctx.com.basic,args,ret); CallUnification.ensureCoroAvailability(ctx.com); var call=make(expanded.args,expanded.ret);
    var cont=switch call.eexpr {case TCall(_,args) if(args.length>0):args[0]; case _:throw "Expected TCall with at least one argument (continuation)";};
    CallUnification.wrapWithResolveTo(ctx.com,call,cont,p);
   case Coro({args:args,ret:ret}):make(args,ret);
   case NotCoro(TFun({args:args,ret:ret})):make(args,ret);
   case NotCoro(abstractType=TAbstract(a,tl)):
    if(a.aCall!=null&&a.aImpl!=null) {
     var on=Builder.makeStaticThis(a.aImpl,e.epos),fa=FieldAccess.create(on,a.aCall,FHAbstract(a,tl,a.aImpl),false,e.epos);
     fieldCall(fa,[e].concat(typed),el);
    } else if(Meta.has(MetaTag.Callable,a.aMeta)) loop(AbstractTools.getUnderlyingType(a,tl)); else defaultCall(abstractType);
   case NotCoro(TMono(_)):
    var ret=mkMono(),all=typed.concat(el.map(e -> typeExpr(ctx,e,WithTypeTools.value))); Typecore.unify(ctx,tfun(all.map(e -> e.etype),ret),e.etype,e.epos); mk(TCall(e,all),ret,p);
   case NotCoro(t):defaultCall(t);
  };
  return loop(e.etype);
 }
 public function resolveCall(sea:StaticExtensionAccess,name:String):TExpr return fieldCall(sea.seAccess,[sea.seThis,Texpr.Builder.makeString(ctx.t,name,Globals.nullPos)],[]);
 public function accessorCall(fa:context.Typecore.FieldAccess,typed:Array<TExpr>,el:Array<Expr>):TExpr return switch FieldAccess.resolveAccessor(fa,mode) {
  case AccessorFound(accessor):
   var dispatch=new CallDispatcher(ctx,MCall(el),withType,p),e=dispatch.fieldCall(accessor,typed,el),t=FieldAccess.getMapFunction(fa)(fa.faField.cfType);
   !typeIseqStrict(t,e.etype)?mk(TCast(e,null),t,e.epos):e;
  case AccessorAnon:
   var e=fa.faOn,t=FieldAccess.getMapFunction(fa)(fa.faField.cfType),all=typed.concat(el.map(e -> typeExpr(ctx,e,WithTypeTools.value))),tf=tfun(all.map(e -> e.etype),t),name=(isSet?"set":"get")+"_"+fa.faField.cfName;
   Calls.makeCall(ctx,mk(TField(e,quickFieldDynamic(e.etype,name)),tf,p),all,t,p);
  case _:raiseTypingError("Could not resolve accessor",p);
 };
 public function fieldCall(fa:context.Typecore.FieldAccess,typed:Array<TExpr>,el:Array<Expr>):TExpr return switch fa.faField.cfKind {
  case Method(MethNormal|MethInline|MethDynamic):checkAssign(); makeFieldCall(fa,typed,el);
  case Method(MethMacro):
   if(typed.length==0) macroCall(fa.faOn,fa.faField,el);
   else {var pushed=typed.map(e -> pushThis(ctx,e)),e=macroCall(fa.faOn,fa.faField,pushed.map(pair -> pair.expr).concat(el)); for(pair in pushed) pair.restore(); e;}
  case Var(v):switch (isSet?v.vWrite:v.vRead) {case AccCall|AccPrivateCall:accessorCall(fa,typed,el); case _:exprCall(FieldAccess.getFieldExpr(fa,FCall),typed,el);}
 };
}
