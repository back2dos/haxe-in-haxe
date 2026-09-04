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
import context.AbstractCast;
import context.SafeCom;
import typing.TyperBase;
import typing.TyperBase.*;
import typing.Fields.*;
import typing.FieldAccess;
import typing.FieldAccess.*;
import typing.CallUnification.*;

// haxe/src/typing/calls.ml — mechanical draft; not compile-validated.
class Calls {
 public static function makeCall(ctx:Dynamic,e:Dynamic,params:Array<Dynamic>,t:Dynamic,p:Dynamic,forceInline:Bool=false):Dynamic {
  switch follow(e.etype) {case TFun(args,_):if(args.length>0) {var last=args[args.length-1]; if(last.optional&&isPosInfos(last.type)&&args.length-1==params.length) params=params.concat([mkInfosT(ctx,p,[],last.type)]);} case _:}
  try {
   var ethis:Dynamic,cl:Dynamic,f:Dynamic;
   switch e.eexpr {case TField(on,fa):ethis=on; switch fa {case FInstance(c,_,cf)|FStatic(c,cf):cl=c; f=cf; case FAnon(cf):cl=null; f=cf; case _:throw "Exit";} case _:throw "Exit";}
   if(!forceInline) {if(!needsInline(ctx,cl,f)) throw "Exit";}
   else if(cl!=null) ctx.com.callbacks.addBeforeSave(function() {
    function hasOverride(c:Dynamic):Bool {if(c.clFields.exists(f.cfName)) return true; for(child in (cast c.clDescendants:Array<Dynamic>)) if(hasOverride(child)) return true; return false;}
    for(c in (cast cl.clDescendants:Array<Dynamic>)) if(hasOverride(c)) raiseTypingError("Cannot force inline-call to "+f.cfName+" because it is overridden",p);
   });
   var config=Inline.inlineConfig(cl,f,params,t); follow(f.cfType);
   switch [cl,ctx.c.curclass.clKind,params.length==0?null:params[0]] {
    case [c,KAbstractImpl(_),{eexpr:TLocal({vMeta:vmeta})}] if(c==ctx.c.curclass):
     if(!hasClassFieldFlag(f,CfAbstractConstructor)&&hasMeta(Meta.This,vmeta)&&hasClassFieldFlag(f,CfModifiesThis)) {
      if(TyperBase.assignToThisIsAllowed(ctx)) addClassFieldFlag(ctx.f.curfield,CfModifiesThis);
      else raiseTypingError("Abstract 'this' value can only be modified inside an inline function. '"+f.cfName+"' modifies 'this'",p);
     }
    case _:
   }
   var reduced=params.map(e -> Optimizer.reduceExpression(SafeCom.ofTyper(ctx),e));
   var forced=isForcedInline(cl,f);
   function inlineFunction(fd:Dynamic):Dynamic return Inline.typeInline(Inline.contextOfTyper(ctx),f,fd,ethis,reduced,t,config,p,forced);
   switch f.cfExprUnoptimized {
    case {eexpr:TFunction(fd)}:return inlineFunction(fd);
    case _:
     if(hasClassFieldFlag(f,CfPostProcessed)) warning(ctx,WInlineOptimizedField,"Inlining of cached field "+f.cfName+" might lead to unexpected output",p);
     switch f.cfExpr {case ({eexpr:TFunction(fd)} => expression):f.cfExprUnoptimized=expression; return inlineFunction(fd); case _:throw "Exit";}
   }
  } catch(err:Dynamic) {if(err!="Exit") throw err; return mk(TCall(e,params),t,p);}
 }
 public static function mkArrayGetCall(ctx:Dynamic,access:Dynamic,c:Dynamic,ebase:Dynamic,p:Dynamic):Dynamic {
  var cf=access.field;
  if(cf.cfExpr==null&&!hasClassFieldFlag(cf,CfExtern)) {if(!Meta.has(Meta.NoExpr,cf.cfMeta)) displayError(ctx.com,"Recursive array get method",p); return mk(TArray(ebase,access.index),access.ret,p);}
  var et=TyperBase.typeModuleType(ctx,TClassDecl(c),p),ef=mk(TField(et,FStatic(c,cf)),access.type,p);
  return makeCall(ctx,ef,[ebase,access.index],access.ret,p);
 }
 public static function mkArraySetCall(ctx:Dynamic,access:Dynamic,c:Dynamic,ebase:Dynamic,p:Dynamic):Dynamic {
  var cf=access.field;
  if(cf.cfExpr==null&&!hasClassFieldFlag(cf,CfExtern)) {if(!Meta.has(Meta.NoExpr,cf.cfMeta)) displayError(ctx.com,"Recursive array set method",p); var ea=mk(TArray(ebase,access.index),access.ret,p); return mk(TBinop(OpAssign,ea,access.value),access.ret,p);}
  var et=TyperBase.typeModuleType(ctx,TClassDecl(c),p),ef=mk(TField(et,FStatic(c,cf)),access.type,p);
  return makeCall(ctx,ef,[ebase,access.index,access.value],access.ret,p);
 }
 public static function abstractUsingParamType(sea:Dynamic):Dynamic return switch follow(sea.seThis.etype) {case TAbstract(a,tl) if(hasClassFieldFlag(sea.seAccess.faField,CfImpl)):applyParams(a.aParams,tl,a.aThis); case _:sea.seThis.etype;};
 public static function accGet(ctx:Dynamic,g:AccessKind):Dynamic {
  function inlineRead(fa:Dynamic):Dynamic {
   var cf=fa.faField,p=fa.faPos;
   var apply:Dynamic->Dynamic=switch fa.faHost {
    case FHStatic(_) | FHInstance(_,_): t -> t;
    case FHAbstract(a,_,_):if(a.aEnum) {var monos=Monomorph.spawnConstrainedMonos(t -> t,a.aParams); t -> applyParams(a.aParams,monos,t);} else t -> t;
    case _:throw "Invalid inline field host";
   };
   follow(cf.cfType);
   if(!ctx.com.display.dmsInline) return FieldAccess.getFieldExpr(fa,FRead);
   return switch [cf.cfKind,cf.cfExpr] {
    case [Method(_),_]:
     function checkClass(c:Dynamic):Bool return (hasClassFlag(c,CExtern)||hasClassFieldFlag(cf,CfExtern))&&!Meta.has(Meta.Runtime,cf.cfMeta);
     function wrapExtern(c:Dynamic):Dynamic {
      var m=c.clModule,path={pack:c.clModule.mPath.pack.concat(["_"+c.clModule.mPath.name]),name:c.clModule.mPath.name+"_Impl_"};
      var c2:Dynamic=null;
      for(mt in (cast m.mTypes:Array<Dynamic>)) switch mt {case TClassDecl(c) if(c.clPath==path):c2=c; break; case _:}
      if(c2==null) {c2=mkClass(m,path,c.clPos,Globals.nullPos); m.mTypes.unshift(TClassDecl(c2));}
      var wrapper:Dynamic=c2.clStatics.get(cf.cfName);
      if(wrapper==null) {wrapper=Reflect.copy(cf); wrapper.cfKind=Method(MethNormal); c2.clStatics.set(wrapper.cfName,wrapper); c2.clOrderedStatics.unshift(wrapper);}
      var et=TyperBase.typeModuleType(ctx,TClassDecl(c2),p);
      return FieldAccess.getFieldExpr(FieldAccess.create(et,wrapper,FHStatic(c2),true,p),FRead);
     }
     var edef=FieldAccess.getFieldExpr(fa,FRead);
     switch follow(fa.faOn.etype) {
      case TInst(c,_) if(checkClass(c)):displayError(ctx.com,"Can't create closure on an extern inline member method",p); edef;
      case TAnon(a):switch a.aStatus.value {
       case ClassStatics(c) if(hasClassFieldFlag(cf,CfExtern)):displayError(ctx.com,"Cannot create closure on @:extern inline method",p); edef;
       case ClassStatics(c) if(checkClass(c)):wrapExtern(c);
       case _:edef;
      }
      case _:edef;
     }
    case [Var(_),expression] if(expression!=null):
     function loop(e:Dynamic):Dynamic return mapExpr(loop,mk(e.eexpr,apply(e.etype),p));
     var e=Inline.inlineMetadata(loop(expression),cf.cfMeta),tf=apply(cf.cfType);
     !typeIseq(tf,e.etype)?mk(TCast(e,null),tf,e.epos):e;
    case [Var(_),null]:raiseTypingError("Recursive inline is not supported",p);
    case _:throw "Invalid inline field";
   };
  }
  function dispatcher(p:Dynamic):CallDispatcher return new CallDispatcher(ctx,MGet,WithType.value,p);
  return switch g {
   case AKNo(acc,p):if(!Common.ignoreError(ctx.com)) raiseTypingError("This expression cannot be accessed for reading",p); else accGet(ctx,acc);
   case AKExpr(e):e;
   case AKSafeNav(sn):TyperBase.safeNavBranch(ctx,sn,() -> accGet(ctx,sn.snAccess));
   case AKAccess(_):throw "Unresolved abstract array access";
   case AKResolve(sea,name):dispatcher(sea.seAccess.faPos).resolveCall(sea,name);
   case AKUsingAccessor(sea) | AKUsingField(sea) if(ctx.f.inDisplay):
    var field=FieldAccess.getFieldExpr(sea.seAccess,FGet),stored=storeTypedExpr(ctx.com,sea.seThis,field.epos);
    var meta={meta:Meta.StaticExtension,exprs:[makeStoredIdExpr(stored.id,field.epos)],pos:Globals.nullPos};
    var t=switch follow(field.etype) {case TFun(args,ret) if(args.length>0):TFun(args.slice(1),ret); case t:t;};
    mk(TMeta(meta,field),t,field.epos);
   case AKField(fa):switch fa.faField.cfKind {
    case Method(MethMacro):ctx.f.inDisplay?FieldAccess.getFieldExpr(fa,FRead):raiseTypingError("Invalid macro access",fa.faPos);
    case _:fa.faInline?inlineRead(fa):FieldAccess.getFieldExpr(fa,FRead);
   }
   case AKAccessor(fa):dispatcher(fa.faPos).fieldCall(fa,[],[]);
   case AKUsingAccessor(sea):dispatcher(sea.seAccess.faPos).fieldCall(sea.seAccess,[sea.seThis],[]);
   case AKUsingField(sea):
    var e=sea.seThis,field=FieldAccess.getFieldExpr(sea.seAccess,FGet);
    switch follow(field.etype) {
     case TFun(allArgs,ret) if(allArgs.length>0):
      var p=sea.seAccess.faPos,args=allArgs.slice(1); unify(ctx,abstractUsingParamType(sea),allArgs[0].type,e.epos);
      var callbackType=TFun(args,ret),wrapperType=TFun([{name:"_e",optional:false,type:e.etype}],callbackType);
      var vars=args.map(function(arg) {var t=arg.optional?ctx.t.tnull(arg.type):arg.type; return {optional:arg.optional,variable:arg.name==""?genLocal(ctx,t,e.epos):allocVar(VGenerated,arg.name,t,e.epos)};});
      var ve=allocVar(VGenerated,"_e",e.etype,e.epos);
      var call=makeCall(ctx,field,[ve].concat(vars.map(a -> a.variable)).map(v -> mk(TLocal(v),v.vType,p)),ret,p);
      var body=switch follow(ret) {case TAbstract({aPath:{pack:[],name:"Void"}},_):call; case _:mk(TReturn(call),tDynamic,p);};
      var callback=mk(TFunction({tfArgs:vars.map(arg -> {variable:arg.variable,defaultValue:arg.optional?Texpr.Builder.makeNull(arg.variable.vType,arg.variable.vPos):null}),tfType:ret,tfExpr:body}),callbackType,p);
      var wrapper=mk(TFunction({tfArgs:[{variable:ve,defaultValue:null}],tfType:callbackType,tfExpr:mk(TReturn(callback),tDynamic,p)}),wrapperType,p);
      makeCall(ctx,wrapper,[e],callbackType,p);
     case _:throw "Static extension field is not a function";
    }
  };
 }
 public static function checkDynamicSuperMethodCall(ctx:Dynamic,fa:Dynamic,p:Dynamic):Void switch fa {
  case {faOn:{eexpr:TConst(TSuper)},faField:{cfKind:Method(MethDynamic),cfName:name}}:ctx.com.error("Cannot call super."+name+" since it's a dynamic method",p);
  case _:
 }
 public static function buildCallAccess(ctx:Dynamic,acc:AccessKind,el:Array<Dynamic>,mode:Dynamic,withType:Dynamic,p:Dynamic):AccessKind {
  function getAccessor(fa:Dynamic,args:Array<Dynamic>):Dynamic return new CallDispatcher(ctx,MGet,WithType.value,fa.faPos).fieldCall(fa,args,[]);
  var dispatch=new CallDispatcher(ctx,mode,withType,p);
  return switch acc {
   case AKField(fa):checkDynamicSuperMethodCall(ctx,fa,p); AKExpr(dispatch.fieldCall(fa,[],el));
   case AKUsingField(sea):
    var e=dispatch.fieldCall(sea.seAccess,[sea.seThis],el);
    switch sea.seAccess.faHost {
     case FHAbstract(_) if(!ctx.allowTransform):switch e.eexpr {case TCall(({eexpr:TField(_,name)} => f),args) if(args.length>0):e=mk(TCall(mk(TField(args[0],name),tDynamic,f.epos),args.slice(1)),e.etype,e.epos); case _:throw "Invalid abstract call transform";}
     case _:
    } AKExpr(e);
   case AKResolve(sea,name):AKExpr(dispatch.exprCall(dispatch.resolveCall(sea,name),[],el));
   case AKNo(_,p):raiseTypingError("This expression cannot be called",p);
   case AKAccess(_):raiseTypingError("This expression cannot be called",p);
   case AKAccessor(fa):AKExpr(dispatch.exprCall(getAccessor(fa,[]),[],el));
   case AKUsingAccessor(sea):AKExpr(dispatch.exprCall(getAccessor(sea.seAccess,[sea.seThis]),[],el));
   case AKExpr(e):AKExpr(dispatch.exprCall(e,[],el));
   case AKSafeNav(sn):AKSafeNav({snPos:sn.snPos,snBase:sn.snBase,snTempVar:sn.snTempVar,snAccess:buildCallAccess(ctx,sn.snAccess,el,mode,withType,p)});
  };
 }
 public static function buildCall(ctx:Dynamic,acc:AccessKind,el:Array<Dynamic>,withType:Dynamic,p:Dynamic,?mode:Dynamic):Dynamic return accGet(ctx,buildCallAccess(ctx,acc,el,mode==null?MGet:mode,withType,p));
 public static function needsTempVar(e:Dynamic):Bool return switch e.eexpr {case TLocal(_)|TTypeExpr(_)|TConst(_):false; case TField(e,_)|TParenthesis(e):needsTempVar(e); case _:true;};
 public static function callToString(ctx:Dynamic,e:Dynamic,resume:Bool=false):Dynamic {
  if(!ctx.allowTransform) return mk(e.eexpr,ctx.t.tstring,e.epos);
  function generate(e:Dynamic):Dynamic {
   ctx.f.meta.unshift({meta:Meta.PrivateAccess,exprs:[],pos:e.epos});
   var acc=Fields.typeField(TypeFieldConfig.create(resume),ctx,e,"toString",e.epos,MCall([]),WithType.withType(ctx.t.tstring));
   ctx.f.meta.shift(); return buildCall(ctx,acc,[],WithType.withType(ctx.t.tstring),e.epos);
  }
  if(ctx.com.config.pfStatic&&!isNullable(e.etype)) return generate(e);
  var stringNull=mk(TConst(TString("null")),ctx.t.tstring,e.epos);
  if(needsTempVar(e)) {
   var tmp=allocVar(VGenerated,"tmp",e.etype,e.epos),local=mk(TLocal(tmp),tmp.vType,tmp.vPos);
   var check=mk(TBinop(OpEq,local,mk(TConst(TNull),tmp.vType,tmp.vPos)),ctx.t.tbool,e.epos);
   return mk(TBlock([mk(TVar(tmp,e),tmp.vType,tmp.vPos),mk(TIf(check,stringNull,generate(local)),ctx.t.tstring,tmp.vPos)]),ctx.t.tstring,e.epos);
  }
  var check=mk(TBinop(OpEq,e,mk(TConst(TNull),e.etype,e.epos)),ctx.t.tbool,e.epos);
  return mk(TIf(check,stringNull,generate(e)),ctx.t.tstring,e.epos);
 }
 public static function typeBind(ctx:Dynamic,e:Dynamic,signature:Dynamic,params:Array<Dynamic>,safe:Bool,p:Dynamic):Dynamic {
  var args:Array<Dynamic>=signature.args,ret=signature.ret,acount=0;
  function name(n:String):String {if(n==""&&!ctx.m.isDisplayFile) {acount++; return "a"+acount;} return n;}
  var given=[],missing=[],ordered=[],pi=0;
  for(ai in 0...args.length) {
   var a=args[ai],param=pi<params.length?params[pi]:null;
   if(ai==args.length-1&&param==null&&a.optional&&isPosInfos(a.type)) {ordered.push(mkInfosT(ctx,p,[],a.type)); continue;}
   var wildcard=param!=null&&switch param.expr {case EConst(Ident("_")):true; case _:false;};
   if(wildcard&&!ctx.com.config.pfCanSkipNonNullableArgument&&a.optional&&!isNullable(a.type)) raiseTypingError("Usage of _ is not supported for optional non-nullable arguments",param.pos);
   if(param==null||wildcard) {
    var v=allocVar(VGenerated,name(a.name),a.optional?ctx.t.tnull(a.type):a.type,p); missing.push({variable:v,optional:a.optional}); ordered.push(mk(TLocal(v),v.vType,p));
   } else {
    var value=typeExpr(ctx,param,WithType.withArgument(a.type,a.name)); value=AbstractCast.castOrUnify(ctx,a.type,value,param.pos);
    var v=allocVar(VGenerated,name(a.name),a.type,param.pos); given.push({variable:v,optional:a.optional,expr:value}); ordered.push(mk(TLocal(v),v.vType,p));
   }
   if(param!=null) pi++;
  }
  if(pi<params.length) raiseTypingError("Too many callback arguments",p);
  var declarations=given.map(pair -> mk(TVar(pair.variable,pair.expr),ctx.t.tvoid,pair.variable.vPos));
  function immutable(cf:Dynamic):Bool return switch cf.cfKind {case Method(k):k!=MethDynamic; case _:false;};
  switch e.eexpr {
   case TFunction(_)|TLocal({vKind:VUser(TVOLocalFunction)}):
   case TField(_,FStatic(_,cf)|FInstance(_,_,cf)) if(immutable(cf)):
   case TField(eobj,FClosure(pair,cf)) if(pair!=null&&immutable(cf)):
    var vobj=allocVar(VGenerated,genLocalPrefix,eobj.etype,eobj.epos); declarations.unshift(mk(TVar(vobj,eobj),ctx.t.tvoid,eobj.epos));
    e=mk(TField(mk(TLocal(vobj),eobj.etype,eobj.epos),FInstance(pair.c,pair.params,cf)),e.etype,e.epos);
   case _:var v=allocVar(VGenerated,genLocalPrefix,e.etype,e.epos); declarations.unshift(mk(TVar(v,e),ctx.t.tvoid,e.epos)); e=mk(TLocal(v),e.etype,e.epos);
  }
  var body:Dynamic;
  if(safe) {var base=TyperBase.getSafeNavBase(ctx,e); var sn:SafeNavAccess={snPos:p,snBase:base.base,snTempVar:base.tempVar,snAccess:AKExpr(e)}; body=TyperBase.safeNavBranch(ctx,sn,() -> makeCall(ctx,base.base,ordered,ret,p));}
  else body=makeCall(ctx,e,ordered,ret,p);
  if(!ExtType.isVoid(follow(ret))) body=mk(TReturn(body),ret,p);
  var fn={tfArgs:missing.map(arg -> {variable:arg.variable,defaultValue:arg.optional?Texpr.Builder.makeNull(arg.variable.vType,Globals.nullPos):null}),tfType:ret,tfExpr:body};
  var t=TFun(missing.map(arg -> {name:arg.variable.vName,optional:arg.optional,type:arg.variable.vType}),ret);
  return mk(TBlock(declarations.concat([mk(TFunction(fn),t,p)])),t,p);
 }
 public static function arrayAccess(ctx:Dynamic,e1:Dynamic,e2:Dynamic,mode:Dynamic,p:Dynamic):AccessKind {
  var hasAbstractArrayAccess=false;
  try return switch follow(e1.etype) {
   case TAbstract(a,pl) if(a.aImpl!=null&&a.aArray.length!=0):switch mode {
    case MSet(_):AKAccess(a,pl,a.aImpl,e1,e2);
    case _:hasAbstractArrayAccess=true; var f=AbstractCast.findArrayReadAccess(ctx,a,pl,e2,p); AKExpr(!ctx.allowTransform?mk(TArray(e1,e2),f.ret,p):mkArrayGetCall(ctx,f,a.aImpl,e1,p));
   }
   case _:throw "Not_found";
  } catch(err:Dynamic) {if(err!="Not_found") throw err;}
  var baseOk=true;
  function loop(et:Dynamic,skipAbstract:Bool=false):Dynamic return switch follow(et) {
   case TInst(c,tl) if(c.clArrayAccess!=null):applyParams(c.clParams,tl,c.clArrayAccess);
   case TInst(c,tl) if(c.clSuper!=null):applyParams(c.clParams,tl,loop(TInst(c.clSuper.c,c.clSuper.params)));
   case TInst({clPath:{pack:[],name:"ArrayAccess"}},[t]):t;
   case TInst({clPath:{pack:[],name:"Array"}},[t]) if(t==tDynamic):tDynamic;
   case TAbstract(a,tl) if(!skipAbstract&&Meta.has(Meta.ArrayAccess,a.aMeta)):var at=applyParams(a.aParams,tl,a.aThis); loop(at,fastEq(et,at));
   case _:
    var pt=spawnMonomorph(ctx,p),t=ctx.t.tarray(pt);
    try unifyRaise(et,t,p) catch(err:Dynamic) {switch err {
     case Error({errMessage:Unify(_)}):if(!ctx.f.untyped) {var msg=hasAbstractArrayAccess?"No @:arrayAccess function accepts an argument of "+sType(printContext(),e2.etype):"Array access is not allowed on "+sType(printContext(),e1.etype); baseOk=false; raiseOrDisplayMessage(ctx,msg,e1.epos);}
     case _:throw err;
    }} pt;
  };
  var pt=loop(e1.etype); if(baseOk) unify(ctx,e2.etype,ctx.t.tint,e2.epos); return AKExpr(mk(TArray(e1,e2),pt,p));
 }
 public static function fieldChain(ctx:Dynamic,path:Array<Dynamic>,access:AccessKind,mode:Dynamic,withType:Dynamic):AccessKind {
  for(i in 0...path.length) {var e=accGet(ctx,access),part=path[i],intermediate=i<path.length-1; access=Fields.typeFieldDefaultCfg(ctx,e,part.name,part.pos,intermediate?MGet:mode,intermediate?WithType.value:withType);}
  return access;
 }
}
