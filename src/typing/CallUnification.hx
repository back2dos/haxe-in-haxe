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
import core.WithType;
import core.Error.*;
import context.Typecore.*;
import context.Common;
import context.TyperManager;
import typing.FieldAccess;
import typing.FieldAccess.*;
import typing.FieldCallCandidate.*;
import typing.CallUnification.*;

// haxe/src/typing/callUnification.ml — mechanical draft; not compile-validated.
enum OverloadKind {OverloadProper; OverloadMeta; OverloadNone;}
class CallUnification {
 public static function unifyCallArgs(ctx:Dynamic,el:Array<Dynamic>,args:Array<Dynamic>,r:Dynamic,callp:Dynamic,isInline:Bool,forceInline:Bool,inOverload:Bool,?callFieldP:Dynamic):Array<Dynamic> {
  if(callFieldP==null) callFieldP=callp;
  function callError(err:Dynamic,p:Dynamic):Dynamic return raiseErrorMsg(CallError(err),p);
  function argError(e:Dynamic,name:String,opt:Bool):Dynamic {
   var msg="For "+(opt?"optional ":"")+"function argument '"+name+"'",copy=Reflect.copy(e);
   switch e.errMessage {case Unify(l):copy.errMessage=Unify(l.concat([UnifyCustom(msg)])); case _:copy.errSub=[makeError(Custom(complMsg(msg)),e.errPos)].concat(e.errSub);}
   copy.errMessage=CallError(CouldNotUnify(copy.errMessage)); return raiseError(copy);
  }
  function posInfos(t:Dynamic):Dynamic return mkInfosT(ctx,callp,[],t);
  function defaultValue(name:String,t:Dynamic):Dynamic return isPosInfos(t)?posInfos(t):nullExpr(ctx.t.tnull(t),callp);
  var skipped:Array<Dynamic>=[],invalidSkips:Array<String>=[];
  function skip(name:String,ul:Dynamic,t:Dynamic):Dynamic {
   if(!ctx.com.config.pfCanSkipNonNullableArgument&&!isNullable(t)) invalidSkips.unshift(name);
   skipped.unshift({name:name,error:ul}); return defaultValue(name,t);
  }
  function handleErrors(fn:Void->Dynamic):Dynamic {
   try return fn() catch(exc:Dynamic) {switch exc {
    case Error(e):switch e.errMessage {case CallError(_)|ModuleNotFound(_):throw exc; case _:throw WithTypeError(e);}
    case _:throw exc;
   }}
  }
  function typeAgainst(name:String,t:Dynamic,e:Dynamic):Dynamic return handleErrors(function() {var e=typeExpr(ctx,e,WithType.withArgument(t,name)); return castOrUnifyRaiseRef(ctx,t,e,e.epos);});
  function restError(fn:Void->Array<Dynamic>,name:String):Array<Dynamic> {try return fn() catch(exc:Dynamic) {switch exc {case WithTypeError(e):return argError(e,name,false); case _:throw exc;}}}
  function loop(el:Array<Dynamic>,args:Array<Dynamic>):Array<Dynamic> {
   if(el.length==0&&args.length==0) {if(invalidSkips.length>0) callError(CannotSkipNonNullable(invalidSkips[invalidSkips.length-1]),callp); return [];}
   if(args.length==1&&!args[0].optional) {
    var name=args[0].name,t=args[0].type;
    switch t {case TAbstract({aPath:{pack:["cpp"],name:"Rest"}},[element]):return restError(() -> el.map(e -> typeAgainst(name,element,e)),name); case _:}
    if(ExtType.isRest(follow(t))) return switch follow(t) {
     case TAbstract({aPath:{pack:["haxe"],name:"Rest"}},[argT]):
      function unexpectedSpread(p:Dynamic):Dynamic return argError(makeError(Custom("Cannot spread arguments with additional rest arguments"),p),name,false);
      var spread:Dynamic=el.length==1?switch el[0].expr {case EUnop(Spread,Prefix,e):{expr:e,pos:el[0].pos}; case _:null;}:null;
      if(ctx.com.config.pfSupportsRestArgs) {
       function typeRest(getType:Void->Dynamic):Array<Dynamic> return el.map(function(e) return switch e.expr {case EUnop(Spread,Prefix,_):unexpectedSpread(e.pos); case _:typeAgainst(name,getType(),e);});
       if(spread!=null) restError(() -> [mk(TUnop(Spread,Prefix,typeAgainst(name,t,spread.expr)),t,spread.pos)],name);
       else if(ExtType.isMono(follow(argT))) restError(function() {var typed=typeRest(mkMono); unify(ctx,unifyMin(ctx,typed),argT,punionEl(callp,typed)); return typed;},name);
       else restError(() -> typeRest(() -> argT),name);
      } else {
       if(spread!=null) restError(() -> [typeAgainst(name,t,spread.expr)],name);
       else if(el.length==0) restError(() -> [typeAgainst(name,t,{expr:EArrayDecl([]),pos:callp})],name);
       else {
        var p=el[0].pos;
        for(e in el) switch e.expr {case EUnop(Spread,Prefix,_):unexpectedSpread(e.pos); case _:p=Globals.punion(p,e.pos);}
        restError(function() {
         var e:Dynamic={expr:EArrayDecl(el),pos:p};
         if(follow(argT)==tDynamic) {var dynamicType=makePtpTh(mkTypePath({pack:[],name:"Dynamic"}),p); var ct=makePtpCt(mkTypePath({pack:[],name:"Array"},[TPType(dynamicType)]),p); e={expr:ECheckType(e,{type:ct,pos:p}),pos:p};}
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
     if(ctx.m.isDisplayFile&&!Diagnostics.errorInDiagnosticsRun(ctx.com,el[0].pos)) {typeExpr(ctx,el[0],WithType.value); loop(el.slice(1),[]);}
     return callError(TooManyArguments,el[0].pos);
    }
    var first=skipped[skipped.length-1]; return argError(first.error,first.name,true);
   }
   var e=el[0],arg=args[0],tailEl=el.slice(1),tailArgs=args.slice(1),name=arg.name,opt=arg.optional,t=arg.type;
   var bodyCapture=resetCallArgBodyCapture(ctx),restoreMonos:Void->Void=opt?monomorphTransaction(ctx):function() {},committed=false;
   function commit():Void {if(!committed) {committed=true; commitCapturedMessages(ctx.com,bodyCapture.value);}}
   function drop():Void {committed=true;}
   var mightSkip=opt&&tailEl.length<tailArgs.length,optFollowedByRest=opt&&tailArgs.length==1&&ExtType.isRest(follow(tailArgs[0].type));
   function maybeRaiseCapturedError():Void {
    if(mightSkip||optFollowedByRest) for(cm in (cast bodyCapture.value:Array<Dynamic>)) if(Message.cmSeverity(cm)==MessageSeverity.Error) throw WithTypeError(makeError(Custom(cm.cmMessage),cm.cmPos));
   }
   try {
    try {var typed=typeAgainst(name,t,e); maybeRaiseCapturedError(); commit(); return [typed].concat(loop(tailEl,tailArgs));}
    catch(exc:Dynamic) {switch exc {
     case WithTypeError(ul):
      if(mightSkip||optFollowedByRest) {drop(); restoreMonos(); var def=skip(name,ul,t); return [def].concat(loop(el,tailArgs));}
      var isFunction=switch follow(t) {case TFun(_):true; case _:false;};
      if(bodyCapture.value.length!=0&&!isFunction) {commit(); restoreMonos(); var def=defaultValue(name,t); return [def].concat(loop(tailEl,tailArgs));}
      commit(); if(skipped.length==0) return argError(ul,name,opt); var first=skipped[skipped.length-1]; return argError(first.error,first.name,true);
     case _:throw exc;
    }}
   } catch(exc:Dynamic) {commit(); throw exc;}
  }
  var restore=enterCallArgs(ctx,inOverload);
  try {var result=loop(el,args); restore(); return result;} catch(exc:Dynamic) {restore(); throw exc;}
 }
 public static function unifyTypedArgs(tmap:Dynamic->Dynamic,args:Array<Dynamic>,typed:Array<Dynamic>,callPos:Dynamic):Dynamic {
  var consumed=[];
  for(i in 0...typed.length) {
   if(i>=args.length) raiseErrorMsg(CallError(TooManyArguments),callPos);
   var e=typed[i],arg=args[i];
   try unifyRaise(tmap(e.etype),arg.type,e.epos) catch(exc:Dynamic) {switch exc {case Error(err):switch err.errMessage {case Unify(_):var copy=Reflect.copy(err); copy.errMessage=CallError(CouldNotUnify(err.errMessage)); raiseError(copy); case _:throw exc;} case _:throw exc;}}
   consumed.push(arg); tmap=t -> t;
  }
  return {typed:consumed,remaining:args.slice(typed.length)};
 }
 public static function ensureCoroAvailability(com:Dynamic):Void {AtomicLazy.force(com.basic.tcoro.suspensionResultClass).clBuild();}
 public static function wrapWithResolveTo(com:Dynamic,ecall:Dynamic,econt:Dynamic,p:Dynamic):Dynamic {
  var basic=com.basic,b=new CoroElsewhere.TexprBuilder(basic,p),c=AtomicLazy.force(basic.tcoro.suspensionResultClass);
  var param=switch follow(ecall.etype) {case TInst(_,[t]):t; case _:throw "Expected SuspensionResult with one type parameter for coroutine call result";};
  var cf=c.clFields.get("resolveTo"); if(cf==null) throw "Not_found";
  var type=applyParams(c.clParams,[param],cf.cfType);
  function resolve(call:Dynamic,cont:Dynamic):Dynamic return b.call(b.instanceField(call,c,[param],cf,type),[cont],basic.tvoid);
  switch econt.eexpr {case TLocal(_)|TConst(_):return resolve(ecall,econt); case _:}
  var v=allocVar(VGenerated,"_hx_cont",econt.etype,econt.epos),local=b.local(v,v.vPos);
  var call=switch ecall.eexpr {case TCall(ef,args) if(args.length>0):mk(TCall(ef,[local].concat(args.slice(1))),ecall.etype,ecall.epos); case _:throw "Expected TCall with at least one argument (continuation)";};
  return b.voidBlock([b.varInit(v,econt),resolve(call,local)]);
 }
 public static function unifyFieldCall(ctx:Dynamic,fa:Dynamic,elTyped:Array<Dynamic>,el:Array<Dynamic>,p:Dynamic,isInline:Bool):Dynamic {
  function expand(cf:Dynamic):Array<Dynamic> return [cf].concat(cf.cfOverloads);
  var candidates:Array<Dynamic>,co:Dynamic,isStatic:Bool,map:Dynamic->Dynamic,tmap:Dynamic->Dynamic;
  switch fa.faHost {
   case FHStatic(c):candidates=expand(fa.faField); co=c; isStatic=true; map=t -> t; tmap=t -> t;
   case FHAnon:candidates=expand(fa.faField); co=null; isStatic=false; map=t -> t; tmap=t -> t;
   case FHInstance(c,tl):var cf=fa.faField; candidates=cf.cfName=="new"||!hasClassFieldFlag(cf,CfOverload)?expand(cf):(cast getOverloads(ctx.com,c,cf.cfName):Array<Dynamic>).map(pair -> pair.field); co=c; isStatic=false; map=TClass.getMapFunction(c,tl); tmap=t -> t;
   case FHAbstract(a,tl,c):map=t -> applyParams(a.aParams,tl,t); tmap=hasClassFieldFlag(fa.faField,CfAbstractConstructor)?(t -> t):(t -> map(a.aThis)); candidates=expand(fa.faField); co=c; isStatic=true;
  }
  var forced=isForcedInline(co,fa.faField),kind=hasClassFieldFlag(fa.faField,CfOverload)?OverloadProper:fa.faField.cfOverloads.length!=0?OverloadMeta:OverloadNone;
  function extractDisplay():Dynamic {var f=ctx.g.delayedDisplay; ctx.g.delayedDisplay=null; return f;}
  function raiseAugmentedDisplay(cf:Dynamic,de:Dynamic):Dynamic {
   var text=genDocTextOpt(cf.cfDoc); if(text==null) throw DisplayException(de); var doc=new Javadoc(text);
   switch de {
    case DisplayHover(hover):switch hover.hexpected {
     case WithType(t,si) if(si!=null):
      var next=switch si {
       case FunctionArgument(info) if(info.siDoc==null):var copy=Reflect.copy(info); copy.siDoc=doc.getParamInfo(info.siName); FunctionArgument(copy);
       case StructureField(info) if(info.siDoc==null):var copy=Reflect.copy(info); copy.siDoc=doc.getParamInfo(info.siName); StructureField(copy);
       case _:si;
      };
      return DisplayException.raiseHover(hover.hitem,WithType(t,next),hover.hpos);
     case _:throw DisplayException(de);
    }
    case _:throw DisplayException(de);
   }
  }
  function commitDisplay(fcc:Dynamic):Dynamic {if(fcc.fcData.display!=null) raiseAugmentedDisplay(fcc.fcField,fcc.fcData.display); var copy=Reflect.copy(fcc); copy.fcData=fcc.fcData.call; return copy;}
  function attempt(cf:Dynamic,inOverload:Bool):Dynamic {
   var monos=Monomorph.spawnConstrainedMonos(map,cf.cfParams),t=map(applyParams(cf.cfParams,monos,cf.cfType));
   function make(args:Array<Dynamic>,ret:Dynamic,coro:Bool):Dynamic {
    var split=unifyTypedArgs(tmap,args,elTyped,p),typed:Array<Dynamic>;
    try typed=unifyCallArgs(ctx,el,split.remaining,ret,p,isInline,forced,inOverload,fa.faFieldPos) catch(exc:Dynamic) {switch exc {case DisplayException(de):typed=raiseAugmentedDisplay(cf,de); case _:throw exc;}}
    typed=elTyped.concat(typed); args=split.typed.concat(split.remaining);
    var tf=coro?AtomicLazy.force(ctx.t.tcoro.tcoro)(args,ret):TFun(args,ret);
    function makeCall():Dynamic {var ef=mk(TField(fa.faOn,FieldAccess.applyFa(cf,fa.faHost)),t,fa.faPos); return makeCallRef(ctx,ef,typed,ret,p,isInline);}
    return makeFieldCallCandidate(typed,ret,monos,tf,cf,{call:makeCall,display:extractDisplay()});
   }
   return switch followWithCoro(t) {
    case Coro(args,ret) if(!TyperManager.isCoroutineContext(ctx)):
     var expanded=expandCoroType(ctx.com.basic,args,ret); ensureCoroAvailability(ctx.com); var fcc=make(expanded.args,expanded.ret,false);
     if(fcc.fcArgs.length==0) raiseTypingError("Unexpected overload candidate without arguments for coroutine call",p);
     var cont=fcc.fcArgs[0],original=fcc.fcData.call,copy=Reflect.copy(fcc); copy.fcData={call:function() return wrapWithResolveTo(ctx.com,original(),cont,p),display:fcc.fcData.display}; copy;
    case Coro(args,ret):make(args,ret,true);
    case NotCoro(TFun(args,ret)):make(args,ret,false);
    case NotCoro(t):raiseTypingError(sType(printContext(),t)+" cannot be called",p);
   };
  }
  var unknownIdentError:Dynamic=null;
  function checkUnknown(err:Dynamic):Void switch err.errMessage {
   case CallError(CouldNotUnify(UnknownIdent(_)))|UnknownIdent(_):if(unknownIdentError==null) unknownIdentError=err;
   case _:for(sub in (cast err.errSub:Array<Dynamic>)) checkUnknown(sub);
  }
  function attempts(list:Array<Dynamic>):Dynamic {
   if(list.length==0) return {candidates:[],failures:[]};
   var cf=list[0],current=ctx.e.monomorphs,known=(cast current:Array<Dynamic>).map(pair -> {mono:pair.mono,type:pair.mono.tmType,constraints:pair.mono.tmDownConstraints});
   try {
    var candidate=attempt(cf,true); ctx.e.monomorphs=current;
    if(kind==OverloadProper) {var rest=attempts(list.slice(1)); return {candidates:[candidate].concat(rest.candidates),failures:rest.failures};}
    return {candidates:[candidate],failures:[]};
   } catch(exc:Dynamic) {switch exc {
    case Error(err):switch err.errMessage {
     case CallError(_):
      for(m in known) {if(m.type!=m.mono.tmType) m.mono.tmType=m.type; if(m.constraints!=m.mono.tmDownConstraints) m.mono.tmDownConstraints=m.constraints;}
      ctx.e.monomorphs=current; checkUnknown(err); var rest=attempts(list.slice(1));
      return {candidates:rest.candidates,failures:[{field:cf,error:err,display:extractDisplay()}].concat(rest.failures)};
     case _:throw exc;
    }
    case _:throw exc;
   }}
  }
  function checkAccess(cf:Dynamic):Void {if(co!=null) checkFieldAccess(ctx,co,cf,isStatic,p);}
  function checkDisplayArgs():Void {if(ctx.m.isDisplayFile) for(e in el) if(Ast.exists(function(def) return switch def {case EDisplay(_):true; case _:false;},e)) {typeExpr(ctx,e,WithType.value); break;}}
  if(candidates.length==1) {
   var cf=candidates[0]; if(kind==OverloadProper) checkAccess(cf);
   try return commitDisplay(attempt(cf,false)) catch(exc:Dynamic) {switch exc {
    case Error(_) if(Common.ignoreError(ctx.com)):
     checkDisplayArgs(); var tf=TFun(el.map(_ -> {name:"",optional:false,type:tDynamic}),tDynamic);
     function call():Dynamic {var ef=mk(TField(fa.faOn,FieldAccess.applyFa(fa.faField,fa.faHost)),tf,fa.faPos); return mk(TCall(ef,[]),tDynamic,p);}
     return makeFieldCallCandidate([],tDynamic,[],tf,fa.faField,call);
    case _:throw exc;
   }}
  }
  var all=attempts(candidates),success:Array<Dynamic>=all.candidates,failures:Array<Dynamic>=all.failures;
  function fail():Dynamic {
   var errors=[];
   for(f in failures) {if(f.display!=null) raiseAugmentedDisplay(f.field,f.display); errors.push({field:f.field,error:f.error});}
   checkDisplayArgs(); errors=removeDuplicates((a,b) -> MessageReporting.printError(a.error)!=MessageReporting.printError(b.error),errors);
   if(errors.length==1) return raiseTypingErrorExt(errors[0].error);
   if(unknownIdentError!=null) return raiseTypingErrorExt(unknownIdentError);
   var sub=[];
   for(f in errors) sub.unshift(makeError(Custom("Overload resolution failed for "+sType(printContext(),f.field.cfType)),p,[f.error]));
   sub.unshift(makeError(Custom("End of overload failure reasons"),p)); return raiseTypingErrorExt(makeError(Custom("Could not find a suitable overload, reasons follow"),p,sub));
  }
  if(kind==OverloadProper) {
   var compatible:Array<Dynamic>=Overloads.Resolution.reduceCompatible(success);
   if(compatible.length==0) return fail();
   var fcc=compatible[0]; if(compatible.length==1) checkAccess(fcc.fcField);
   else {var pc=printContext(),sub=compatible.map(fcc -> makeError(Custom(complMsg(sType(pc,fcc.fcType))),fcc.fcField.cfNamePos)); sub.reverse(); displayErrorExt(ctx.com,makeError(Custom("Ambiguous overload, candidates follow"),p,sub));}
   return commitDisplay(fcc);
  }
  return success.length==0?fail():commitDisplay(success[success.length-1]);
 }
 public static function makeStaticCallBetter(ctx:Dynamic,c:Dynamic,cf:Dynamic,tl:Array<Dynamic>,el:Array<Dynamic>,t:Dynamic,p:Dynamic):Dynamic {
  var fh=switch c.clKind {case KAbstractImpl(a) if(hasClassFieldFlag(cf,CfImpl)):FHAbstract(a,tl,c); case _:FHStatic(c);};
  var fa=FieldAccess.create(Builder.makeStaticThis(c,p),cf,fh,false,p);
  var fcc=unifyFieldCall(ctx,fa,el,[],p,false); return fcc.fcData();
 }
}
class CallDispatcher {
 final ctx:Dynamic; final mode:Dynamic; final withType:Dynamic; final p:Dynamic; final isSet:Bool;
 public function new(ctx:Dynamic,mode:Dynamic,withType:Dynamic,p:Dynamic) {this.ctx=ctx; this.mode=mode; this.withType=withType; this.p=p; isSet=switch mode {case MSet(_):true; case _:false;};}
 function checkAssign():Void {if(isSet&&!Common.ignoreError(ctx.com)) invalidAssign(p);}
 function makeFieldCall(fa:Dynamic,typed:Array<Dynamic>,el:Array<Dynamic>):Dynamic {
  var fcc=CallUnification.unifyFieldCall(ctx,fa,typed,el,p,fa.faInline);
  if(hasClassFieldFlag(fcc.fcField,CfGeneric)) return typeGenericFunctionRef(ctx,fa,fcc,withType,p);
  if(hasClassFieldFlag(fcc.fcField,CfAbstract)) switch fa.faOn.eexpr {case TConst(TSuper):displayError(ctx.com,"abstract method "+fcc.fcField.cfName+" cannot be accessed directly",p); case _:}
  return fcc.fcData();
 }
 function macroCall(ethis:Dynamic,cf:Dynamic,el:Array<Dynamic>):Dynamic {
  if(ctx.e.macroDepth>300) raiseTypingError("Stack overflow",p); ctx.e.macroDepth++; ctx.e.withTypeStack.unshift(withType);
  var ethisF:Void->Void=function() {};
  function macroInMacro():Void->Dynamic return function() return typeExpr(ctx,{expr:EThrow({expr:EConst(String("macro-in-macro",SDoubleQuotes)),pos:p}),pos:p},withType,mode);
  function handle(result:Dynamic,merge:Bool):Void->Dynamic return switch result {
   case MError:function() return typeExpr(ctx,{expr:EConst(Ident("null")),pos:p},WithType.value,mode);
   case MSuccess({expr:EMeta({meta:Meta.MergeBlock},{expr:EBlock(el)})}) if(merge):function() {var e=typeBlockRef(ctx,el,withType,p); return mk(TMeta({meta:Meta.MergeBlock,exprs:[],pos:p},e),e.etype,e.epos);};
   case MSuccess(e):function() return typeExpr(ctx,e,withType,mode);
   case MMacroInMacro:macroInMacro();
  };
  var f:Void->Dynamic=switch ethis.eexpr {
   case TTypeExpr(TClassDecl(c)):DeprecationCheck.checkCf(createDeprecationContext(ctx),cf,p); handle(ctx.g.doMacro(ctx,MExpr,c.clPath,cf.cfName,el,p),true);
   case _:switch follow(ethis.etype) {
    case TInst(c,_):
     function loop(c:Dynamic):Void->Dynamic {
      if(c.clFields.exists(cf.cfName)) {var pushed=pushThis(ctx,ethis); ethisF=pushed.restore; return handle(ctx.g.doMacro(ctx,MExpr,c.clPath,cf.cfName,[pushed.expr].concat(el),p),false);}
      if(c.clSuper==null) throw "Cannot locate member macro"; return loop(c.clSuper.c);
     } loop(c);
    case _:throw "Invalid member macro receiver";
   }
  };
  ctx.e.macroDepth--; ctx.e.withTypeStack.shift();
  var old=ctx.com.errorExt;
  ctx.com.errorExt=function(err:Dynamic) {
   var ep=err.errPos;
   if(ep.pfile!=p.pfile||ep.pmax<p.pmin||ep.pmin>p.pmax) {
    var copy=Reflect.copy(err);
    if(ep==Globals.nullPos) copy.errPos=p; else copy.errSub=[makeError(Custom(complMsg("Called from macro here")),p)].concat(err.errSub); old(copy);
   } else old(err);
  };
  try {var e=f(); ctx.com.errorExt=old; ethisF(); return e;} catch(exc:Dynamic) {ctx.com.errorExt=old; ethisF(); throw exc;}
 }
 public function exprCall(e:Dynamic,typed:Array<Dynamic>,el:Array<Dynamic>):Dynamic {
  checkAssign();
  function defaultCall(t:Dynamic):Dynamic {
   var all=typed.concat(el.map(e -> typeExpr(ctx,e,WithType.value))),ret:Dynamic;
   if(t==tDynamic) ret=tDynamic; else if(ctx.f.untyped) ret=mkMono();
   else {
    var pos=switch e.eexpr {case TField(_,FAnon(cf)|FInstance(_,_,cf)|FStatic(_,cf)|FClosure(_,cf)):patchStringPos(e.epos,cf.cfName); case _:e.epos;};
    ret=raiseTypingError(sType(printContext(),e.etype)+" cannot be called",pos);
   }
   return mk(TCall(e,all),ret,p);
  }
  function make(args:Array<Dynamic>,ret:Dynamic):Dynamic {var split=CallUnification.unifyTypedArgs(t -> t,args,typed,p); var all=CallUnification.unifyCallArgs(ctx,el,split.remaining,ret,p,false,false,false); return mk(TCall(e,typed.concat(all)),ret,p);}
  function loop(t:Dynamic):Dynamic return switch followWithCoro(t) {
   case Coro(args,ret) if(!TyperManager.isCoroutineContext(ctx)):
    var expanded=expandCoroType(ctx.com.basic,args,ret); CallUnification.ensureCoroAvailability(ctx.com); var call=make(expanded.args,expanded.ret);
    var cont=switch call.eexpr {case TCall(_,args) if(args.length>0):args[0]; case _:throw "Expected TCall with at least one argument (continuation)";};
    CallUnification.wrapWithResolveTo(ctx.com,call,cont,p);
   case Coro(args,ret):make(args,ret);
   case NotCoro(TFun(args,ret)):make(args,ret);
   case NotCoro((TAbstract(a,tl) => abstractType)):
    if(a.aCall!=null&&a.aImpl!=null) {
     var on=Builder.makeStaticThis(a.aImpl,e.epos),fa=FieldAccess.create(on,a.aCall,FHAbstract(a,tl,a.aImpl),false,e.epos);
     fieldCall(fa,[e].concat(typed),el);
    } else if(Meta.has(Meta.Callable,a.aMeta)) loop(Abstract.getUnderlyingType(a,tl)); else defaultCall(abstractType);
   case NotCoro(TMono(_)):
    var ret=mkMono(),all=typed.concat(el.map(e -> typeExpr(ctx,e,WithType.value))); unify(ctx,tfun(all.map(e -> e.etype),ret),e.etype,e.epos); mk(TCall(e,all),ret,p);
   case NotCoro(t):defaultCall(t);
  };
  return loop(e.etype);
 }
 public function resolveCall(sea:Dynamic,name:String):Dynamic return fieldCall(sea.seAccess,[sea.seThis,Texpr.Builder.makeString(ctx.t,name,Globals.nullPos)],[]);
 public function accessorCall(fa:Dynamic,typed:Array<Dynamic>,el:Array<Dynamic>):Dynamic return switch FieldAccess.resolveAccessor(fa,mode) {
  case AccessorFound(accessor):
   var dispatch=new CallDispatcher(ctx,MCall(el),withType,p),e=dispatch.fieldCall(accessor,typed,el),t=FieldAccess.getMapFunction(fa,fa.faField.cfType);
   !typeIseqStrict(t,e.etype)?mk(TCast(e,null),t,e.epos):e;
  case AccessorAnon:
   var e=fa.faOn,t=FieldAccess.getMapFunction(fa,fa.faField.cfType),all=typed.concat(el.map(e -> typeExpr(ctx,e,WithType.value))),tf=tfun(all.map(e -> e.etype),t),name=(isSet?"set":"get")+"_"+fa.faField.cfName;
   Calls.makeCall(ctx,mk(TField(e,quickFieldDynamic(e.etype,name)),tf,p),all,t,p);
  case _:raiseTypingError("Could not resolve accessor",p);
 };
 public function fieldCall(fa:Dynamic,typed:Array<Dynamic>,el:Array<Dynamic>):Dynamic return switch fa.faField.cfKind {
  case Method(MethNormal|MethInline|MethDynamic):checkAssign(); makeFieldCall(fa,typed,el);
  case Method(MethMacro):
   if(typed.length==0) macroCall(fa.faOn,fa.faField,el);
   else {var pushed=typed.map(e -> pushThis(ctx,e)),e=macroCall(fa.faOn,fa.faField,pushed.map(pair -> pair.expr).concat(el)); for(pair in pushed) pair.restore(); e;}
  case Var(v):switch (isSet?v.vWrite:v.vRead) {case AccCall|AccPrivateCall:accessorCall(fa,typed,el); case _:exprCall(FieldAccess.getFieldExpr(fa,FCall),typed,el);}
 };
}
