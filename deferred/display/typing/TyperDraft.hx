// Preserved translation draft with display service bodies; deferred HXB milestone.
package typing;
import core.WithType as WithTypeTools;
import core.WithType.WithTypeValue;
import core.MetaList.StrictMeta as MetaTag;
import core.Globals.Pos;
import core.display.DisplayPosition;
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
import context.TyperPass;
import context.Typecore.TyperManager;
import context.Common;
import core.Define;
import context.AbstractCast;
import context.Resolution.*;
import typing.TyperBase;
import typing.TyperBase.*;
import typing.Fields.*;
import typing.Calls.*;
import typing.CallUnification.*;
import typing.Typeload.*;
import typing.FieldAccess.*;
import typing.Operators.*;

// haxe/src/typing/typer.ml — mechanical draft; not compile-validated.
class Typer {
 public static function terminatorType(ctx:Dynamic,withType:Dynamic,p:Dynamic):Dynamic return switch withType {case NoValue:tDynamic; case WithType(t,_):t; case Value(_):spawnMonomorph(ctx,p);};
 public static function getIteratorParam(t:Dynamic):Dynamic return switch follow(t) {
  case TAnon(a):
   if(a.aStatus.value!=Closed) throw "Not_found";
   var hasNext=a.aFields.get("hasNext"),next=a.aFields.get("next"); if(hasNext==null||next==null) throw "Not_found";
   switch [follow(hasNext.cfType),follow(next.cfType)] {
    case [TFun({args:[],ret:tb}),TFun({args:[],ret:t})]:switch follow(tb) {case TAbstract({aPath:{pack:[],name:"Bool"}},[]):if(a.aFields.fold((_,n) -> n+1,0)!=2) throw "Not_found"; t; case _:throw "Not_found";}
    case _:throw "Not_found";
   }
  case _:throw "Not_found";
 };
 public static function getIterableParam(t:Dynamic):Dynamic return switch follow(t) {
  case TAnon(a):if(a.aStatus.value!=Closed) throw "Not_found"; var field=a.aFields.get("iterator"); if(field==null) throw "Not_found";
   switch follow(field.cfType) {case TFun({args:[],ret:it}):var t=getIteratorParam(it); if(a.aFields.fold((_,n) -> n+1,0)!=1) throw "Not_found"; t; case _:throw "Not_found";}
  case _:throw "Not_found";
 };
 public static function getOwnResolution(ctx:Dynamic):Dynamic {
  if(ctx.m.ownResolution!=null) return ctx.m.ownResolution;
  var rl=new ResolutionList(["own",Globals.sTypePath(ctx.m.curmod.mPath)]);
  if(ctx.m.curmod.mStatics!=null) rl.add(classStaticsResolution(ctx.m.curmod.mStatics,Globals.nullPos));
  for(mt in (cast ctx.m.curmod.mTypes:Array<Dynamic>)) rl.add(moduleTypeResolution(mt,null,Globals.nullPos));
  ctx.m.ownResolution=rl; return rl;
 }
 public static function maybeTypeAgainstEnum(ctx:Dynamic,f:Void->AccessKind,withType:Dynamic,isCall:Bool,p:Dynamic):AccessKind {
  try return switch withType {
   case WithType(t,_):
    function loop(stack:Array<Dynamic>,t:Dynamic):Dynamic return switch follow(t) {
     case TEnum(en,_):{isEnum:true,path:en.ePath,fields:en.eNames,type:TEnumDecl(en)};
     case TAbstract(a,_) if(a.aImpl!=null&&a.aEnum):{isEnum:false,path:a.aPath,fields:(cast a.aImpl.clOrderedStatics:Array<Dynamic>).filter(cf -> hasClassFieldFlag(cf,CfEnum)).map(cf -> cf.cfName),type:TAbstractDecl(a)};
     case TAbstract(a,pl) if(!Meta.has(MetaTag.CoreType,a.aMeta)):
      var froms=TyperBase.getAbstractFroms(ctx,a,pl); if(froms.length!=1||stack.exists(t2 -> shallowEq(t,t2))) throw "Exit"; loop([t].concat(stack),froms[0].type);
     case _:throw "Exit";
    };
    var expected=loop([],t),old=ctx.m.enumWithType; ctx.m.enumWithType=expected.type;
    var access:AccessKind;
    try access=f() catch(exc:Dynamic) {
     ctx.m.enumWithType=old;
     switch exc {case (core.ds.ExceptionTools.typing(_) => Some({errMessage:UnknownIdent(n)})):raiseOrDisplayMessage(ctx,StringError.stringError(n,expected.fields,"Identifier '"+n+"' is not part of "+Globals.sTypePath(expected.path)),p); access=AKExpr(mk(TConst(TNull),mkMono(),p)); case _:throw exc;}
    }
    ctx.m.enumWithType=old;
    switch access {case AKExpr(e):switch follow(e.etype) {case TFun({args:_,ret:ret}) if(expected.isEnum):try core.TUnification.unify(ret,t) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.unification(_) => Some(_)): case _:throw exc;}} case _:} case _:}
    access;
   case _:throw "Exit";
  } catch(exc:Dynamic) {if(exc!="Exit") throw exc; return f();}
 }
 public static function unifyMinRaise(ctx:Dynamic,el:Array<Dynamic>):Dynamic {try return UnifyMin.unifyMinRaise(ctx.t,el) catch(exc:Dynamic) {if(exc!=UnifyMin.NoValue) throw exc; return spawnMonomorph(ctx,Globals.nullPos);}}
 public static function unifyMin(ctx:Dynamic,el:Array<Dynamic>):Dynamic {try return unifyMinRaise(ctx,el) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)):switch err.errMessage {case Unify(_):if(!ctx.f.isUntyped) displayErrorExt(ctx.com,err); return el[0].etype; case _:throw exc;} case _:throw exc;}}}
 public static function unifyMinForTypeSource(ctx:Dynamic,el:Array<Dynamic>,src:Dynamic):Dynamic {if(src==ImplicitReturn&&el.exists(e -> ExtType.isVoid(follow(e.etype)))) return ctx.com.basic.tvoid; return unifyMin(ctx,el);}
 public static function enumFieldAccess(ctx:Dynamic,en:Dynamic,ef:Dynamic,mode:Dynamic,p:Dynamic,pt:Dynamic):AccessKind {
  var et=TyperBase.typeModuleType(ctx,TEnumDecl(en),p),acc=AKExpr(mk(TField(et,FEnum(en,ef)),enumFieldType(ctx,en,ef,p),p));
  return switch mode {case MSet(_):AKNo(acc,p); case _:acc;};
 }
 public static function resolveAgainstExpectedEnum(ctx:Dynamic,i:String):Dynamic {
  function loop(mt:Dynamic):Dynamic return switch mt {
   case TAbstractDecl(a) if(a.aImpl!=null&&a.aEnum):var cf=a.aImpl.clStatics.get(i); if(cf==null||!hasClassFieldFlag(cf,CfEnum)) throw "Not_found"; staticAbstractFieldResolution(a,a.aImpl,cf,null,Globals.nullPos);
   case TClassDecl(_)|TAbstractDecl(_):throw "Not_found";
   case TTypeDecl(t):switch follow(t.tType) {case TEnum(e,_):loop(TEnumDecl(e)); case TAbstract(a,_) if(a.aEnum):loop(TAbstractDecl(a)); case _:throw "Not_found";}
   case TEnumDecl(en):var ef=en.eConstrs.get(i); if(ef==null) throw "Not_found"; enumConstructorResolution(en,ef,null,Globals.nullPos);
  };
  if(ctx.m.enumWithType==null) throw "Not_found"; return loop(ctx.m.enumWithType);
 }
 public static function typeIdentRaise(ctx:Dynamic,i:String,p:Dynamic,mode:Dynamic,withType:Dynamic):AccessKind {
  function resolve(res:Dynamic):AccessKind {
   ImportHandling.markImportPosition(ctx,res.rPos);
   return switch res.rKind {
    case RTypeImport(_,mt):AKExpr(TyperBase.typeModuleType(ctx,mt,p));
    case RClassFieldImport(_,c,cf):fieldAccess(ctx,mode,cf,FHStatic(c),TyperBase.typeModuleType(ctx,TClassDecl(c),p),p);
    case RAbstractFieldImport(_,a,c,cf):var et=TyperBase.typeModuleType(ctx,TClassDecl(c),p),inlined=switch cf.cfKind {case Var({vRead:AccInline}):true; case _:false;}; AKField(FieldAccess.create(et,cf,FHAbstract(a,extractParamTypes(a.aParams),c),inlined,p));
    case REnumConstructorImport(_,en,ef):enumFieldAccess(ctx,en,ef,mode,p,res.rPos);
    case _:throw "Invalid identifier resolution";
   };
  }
  switch i {
   case "true"|"false":var acc=AKExpr(mk(TConst(TBool(i=="true")),ctx.t.tbool,p)); return mode==MGet?acc:AKNo(acc,p);
   case "this":
    var acc=AKExpr(TyperBase.getThis(ctx,p));
    return switch mode {
     case MSet(_):addClassFieldFlag(ctx.f.curfield,CfModifiesThis); switch ctx.c.curclass.clKind {case KAbstractImpl(_):if(!TyperBase.assignToThisIsAllowed(ctx)) raiseTypingError("Abstract 'this' value can only be modified inside an inline function",p); acc; case _:AKNo(acc,p);}
     case MCall(_):switch ctx.c.curclass.clKind {case KAbstractImpl(_):acc; case _:AKNo(acc,p);}
     case MGet:acc;
    };
   case "abstract":return switch [mode,ctx.c.curclass.clKind] {
    case [MSet(_),KAbstractImpl(_)]:raiseTypingError("Property 'abstract' is read-only",p);
    case [MGet,KAbstractImpl(a)]|[MCall(_),KAbstractImpl(a)]:var e=TyperBase.getThis(ctx,p); AKExpr(mk(e.eexpr,TAbstract(a,extractParamTypes(a.aParams)),e.epos));
    case _:raiseTypingError("Property 'abstract' is reserved and only available in abstracts",p);
   };
   case "super":
    var sup=ctx.c.curclass.clSuper; if(sup==null) raiseTypingError("Current class does not have a superclass",p);
    switch ctx.e.curfun {case FunMember|FunConstructor: case FunMemberAbstract:raiseTypingError("Cannot access super inside an abstract function",p); case FunStatic:raiseTypingError("Cannot access super inside a static function",p); case FunMemberClassLocal|FunMemberAbstractLocal:raiseTypingError("Cannot access super inside a local function",p);}
    return AKExpr(mk(TConst(TSuper),TInst(sup.c,sup.params),p));
   case "null":
    var t=switch withType {case WithType(t,_):switch follow(t) {case TMono(r) if(!isNullable(t)):Monomorph.addModifier(r,MNullable(ctx.t.tnull)); case _:} t; case _:ctx.t.tnull(spawnMonomorph(ctx,p));};
    var acc=AKExpr(nullExpr(t,p)); return mode==MGet?acc:AKNo(acc,p);
   case _:
  }
  if(ctx.f.locals.exists(i)) {
   var v=ctx.f.locals.get(i); addVarFlag(v,VUsedByTyper);
   if(v.vExtra==null) return AKExpr(mk(TLocal(v),v.vType,p));
   var params=v.vExtra.vParams,e=v.vExtra.vExpr,t=applyParams(params,Monomorph.spawnConstrainedMonos(t -> t,params),v.vType);
   return switch e {
    case {eexpr:TFunction(_)} if(ctx.com.display.dmsInline):switch mode {
     case MSet(_):raiseTypingError("Cannot set inline closure",p);
     case MGet:raiseTypingError("Cannot create closure on inline closure",p);
     case MCall(_):var c=mkClass(ctx.m.curmod,{pack:["local"],name:v.vName},e.epos,Globals.nullPos),cf=mkField(v.vName,v.vType,e.epos,Globals.nullPos); cf.cfParams=params; cf.cfExpr=e; cf.cfKind=Method(MethInline); addClassFlag(c,CExtern); c.clFields=PMap.empty().add(cf.cfName,cf); var on=mk(TConst(TNull),TInst(c,[]),p); AKField(FieldAccess.create(on,cf,FHInstance(c,[]),true,p));
    }
    case _:AKExpr(mk(TLocal(v),t,p));
   };
  }
  try {
   if(ctx.e.curfun==FunStatic) throw "Not_found";
   var raw=classField(ctx,ctx.c.curclass,extractParamTypes(ctx.c.curclass.clParams),i,p);
   return fieldAccess(ctx,mode,raw.field,raw.host==null?FHAnon:FHInstance(raw.host.c,raw.host.params),TyperBase.getThis(ctx,p),p);
  } catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
  if(ctx.c.curclass.clStatics.exists(i)) {
   var f=ctx.c.curclass.clStatics.get(i),impl=hasClassFieldFlag(f,CfImpl),isEnum=hasClassFieldFlag(f,CfEnum);
   if(impl&&!hasClassFieldFlag(ctx.f.curfield,CfImpl)&&!isEnum) raiseTypingError("Cannot access non-static field "+f.cfName+" from static method",p);
   var on:Dynamic,host:Dynamic;
   switch ctx.c.curclass.clKind {
    case KAbstractImpl(a) if(impl&&!isEnum):var tl=extractParamTypes(a.aParams),e=TyperBase.getThis(ctx,p); on=mk(e.eexpr,TAbstract(a,tl),e.epos); host=FHAbstract(a,tl,ctx.c.curclass);
    case _:on=TyperBase.typeModuleType(ctx,TClassDecl(ctx.c.curclass),p); host=FHStatic(ctx.c.curclass);
   }
   return fieldAccess(ctx,mode,f,host,on,p);
  }
  try return resolve(resolveAgainstExpectedEnum(ctx,i)) catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
  try return resolve(getOwnResolution(ctx).resolve(i)) catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
  return resolve(ctx.m.importResolution.resolve(i));
 }
 public static function typeIdent(ctx:Dynamic,i:String,p:Dynamic,mode:Dynamic,withType:Dynamic):AccessKind {
  try return typeIdentRaise(ctx,i,p,mode,withType) catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
  try {
   if(TyperBase.isLowerIdent(i,p)) throw "Not_found";
   var e:Dynamic; try e=TyperBase.typeModuleType(ctx,Typeload.loadTypeDefPrime(ctx,[],i,i,p),p) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some({errMessage:ModuleNotFound({pack:[],name:name})})) if(name==i):throw "Not_found"; case _:throw exc;}}
   return AKExpr(e);
  } catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
  var resolved=false;
  for(tp in (cast ctx.typeParams:Array<Dynamic>)) if(tp.ttpName==i) {
   resolved=true; var c=switch follow(extractParamType(tp)) {case TInst(c,_):c; case _:throw "Invalid type parameter";};
   if(TypeloadCheck.isGenericParameter(ctx,c)&&Meta.has(MetaTag.Const,c.clMeta)) {var e=TyperBase.typeModuleType(ctx,TClassDecl(c),p); return AKExpr(mk(e.eexpr,extractParamType(tp),e.epos));}
   break;
  }
  if(ctx.f.isUntyped) return i=="__this__"?AKExpr(mk(TConst(TThis),ctx.c.tthis,p)):AKExpr(mk(TIdent(i),mkMono(),p));
  if(ctx.e.curfun==FunStatic&&ctx.c.curclass.clFields.exists(i)) raiseTypingError("Cannot access "+i+" in static function",p);
  if(resolved) {displayError(ctx.com,"Only @:const type parameters on @:generic classes can be used as value",p); return AKExpr(mk(TConst(TNull),tDynamic,p));}
  var err=UnknownIdent(i);
  if(ctx.f.inDisplay) raiseErrorMsg(err,p);
  if(ctx.f.inCallArgs) throw new context.Typecore.WithTypeError(makeError(err,p));
  if(Diagnostics.errorInDiagnosticsRun(ctx.com,p)) {DisplayToplevel.handleUnresolvedIdentifier(ctx,i,p,false); DisplayFields.handleMissingIdent(ctx,i,mode,withType,p); return AKExpr(mk(TIdent(i),mkMono(),p));}
  if(ctx.com.display.dmsKind==DMNone) return raiseErrorMsg(err,p);
  displayError(ctx.com,errorMsg(err),p); return AKExpr(mk(TIdent(i),mkMono(),p));
 }
 public static function handleEfield(ctx:Dynamic,e:Dynamic,p0:Dynamic,mode:Dynamic,withType:Dynamic):AccessKind {
  function dotPath(first:Dynamic,next:Array<Dynamic>):AccessKind {
   var name=first.name,p=first.pos,path=[first].concat(next);
   try return fieldChain(ctx,next,typeIdentRaise(ctx,name,p,MGet,WithTypeTools.value),mode,withType) catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
   try return TyperDotPath.resolveDotPath(ctx,path,mode,withType) catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
   try return fieldChain(ctx,next,typeIdent(ctx,name,p,MGet,WithTypeTools.value),mode,withType) catch(exc:Dynamic) {switch exc {
    case (core.ds.ExceptionTools.typing(_) => Some(err)):switch err.errMessage {
     case UnknownIdent(_) if(err.errPos==p):
      try {
       var pack=[],upper:Dynamic=null,sub:Dynamic=null,position:Dynamic=null;
       for(part in path) {
        if(part.letterCase==PLowercase) {if(upper==null) pack.push(part.name); else {position=upper.pos; break;}}
        else if(upper==null) {upper=part; position=part.pos;} else {sub=part.name; position=part.pos; break;}
       }
       if(upper==null) throw "Not_found";
       var mpath={pack:pack,name:upper.name};
       if(ctx.com.moduleLut.mem(mpath)) return raiseErrorMsg(TypeNotFound(mpath,sub==null?upper.name:sub,NotDefined),position);
       return raiseErrorMsg(ModuleNotFound(mpath),position);
      } catch(failure:Dynamic) {
       if(failure!="Not_found") throw failure;
       if(ctx.f.inDisplay) DisplayToplevel.collectAndRaise(ctx,TKType,WithTypeTools.noValue,CRToplevel(null),{name:path.map(part -> part.name).join("."),pos:p0},p0);
       return raiseError(err);
      }
     case _:throw exc;
    }
    case _:throw exc;
   }}
  }
  function loop(parts:Array<Dynamic>,expr:Dynamic):AccessKind return switch expr.expr {
   case EField(e,s,EFNormal):loop([TyperDotPath.mkDotPathPart(s,expr.pos)].concat(parts),e);
   case EConst(Ident(i)):dotPath(TyperDotPath.mkDotPathPart(i,expr.pos),parts);
   case EField(obj,s,EFSafe):
    var on=accGet(ctx,typeAccess(ctx,obj.expr,obj.pos,MGet,WithTypeTools.value)),base=TyperBase.getSafeNavBase(ctx,on);
    var access=fieldChain(ctx,[TyperDotPath.mkDotPathPart(s,expr.pos)].concat(parts),AKExpr(base.base),mode,withType);
    AKSafeNav({snPos:expr.pos,snBase:base.base,snTempVar:base.tempVar,snAccess:access});
   case _:switch typeAccess(ctx,expr.expr,expr.pos,MGet,WithTypeTools.value) {case AKSafeNav(sn):AKSafeNav({snPos:sn.snPos,snBase:sn.snBase,snTempVar:sn.snTempVar,snAccess:fieldChain(ctx,parts,sn.snAccess,mode,withType)}); case acc:fieldChain(ctx,parts,acc,mode,withType);}
  };
  return loop([],{expr:e,pos:p0});
 }
 public static function typeAccess(ctx:Dynamic,e:Dynamic,p:Dynamic,mode:Dynamic,withType:Dynamic):AccessKind return switch e {
  case EConst(Ident(s)):typeIdent(ctx,s,p,mode,withType);
  case EField(e1,"new",kind):
   if(kind==EFSafe) raiseTypingError("?.new is not supported",p);
   var on=typeExpr(ctx,e1,WithTypeTools.value);
   switch on.eexpr {
    case TTypeExpr(TClassDecl(c)):
     switch mode {case MSet(_):raiseTypingError("Cannot set constructor",p); case MCall(_):raiseTypingError("Cannot call constructor like this, use 'new "+Globals.sTypePath(c.clPath)+"()' instead",p); case MGet:}
     var monos=Monomorph.spawnConstrainedMonos(t -> t,switch c.clKind {case KAbstractImpl(a):a.aParams; case _:c.clParams;});
     var fa=FieldAccess.getConstructorAccess(c,monos,p),cf=fa.faField; noAbstractConstructor(c,p); checkConstructorAccess(ctx,c,cf,p);
     var args=switch follow(FieldAccess.getMapFunction(fa,cf.cfType)) {case TFun({args:args,ret:_}):args; case _:throw "Invalid constructor type";};
     var vars=args.map(arg -> allocVar(VGenerated,arg.name,arg.type,c.clPos)),el=vars.map(v -> mk(TLocal(v),v.vType,p)),call:Dynamic,t:Dynamic;
     switch [c.clKind,fa.faHost] {
      case [KAbstractImpl(a),FHAbstract(_)]:t=TAbstract(a,monos); call=new CallDispatcher(ctx,MCall([]),WithTypeTools.value,p).fieldCall(fa,el,[]);
      case [KAbstractImpl(a),FHInstance(c,pl)]:var enew=mk(TNew(c,monos,el),TInst(c,pl),p); t=TAbstract(a,monos); call=mkCast(enew,t,p);
      case _:t=TInst(c,monos); call=mk(TNew(c,monos,el),t,p);
     }
     AKExpr(mk(TFunction({tfArgs:vars.map(v -> {variable:v,defaultValue:null}),tfType:t,tfExpr:mk(TReturn(call),t,p)}),TFun({args:vars.map(v -> {name:v.vName,optional:false,type:v.vType}),ret:t}),p));
    case _:raiseTypingError("Binding new is only allowed on class types",p);
   }
  case EField(_):handleEfield(ctx,e,p,mode,withType);
  case EArray(e1,e2):typeArrayAccess(ctx,e1,e2,p,mode);
  case ECall(e,el):typeCallAccess(ctx,e,el,mode,withType,null,p);
  case EDisplay(e,dk):AKExpr(TyperDisplay.handleEdisplay(ctx,e,dk,mode,withType));
  case _:AKExpr(typeExpr(ctx,{expr:e,pos:p},withType,mode));
 };
 public static function typeArrayAccess(ctx:Dynamic,e1:Dynamic,e2:Dynamic,p:Dynamic,mode:Dynamic):AccessKind {
  var a1=typeAccess(ctx,e1.expr,e1.pos,MGet,WithTypeTools.value),index=typeExpr(ctx,e2,WithTypeTools.value);
  return switch a1 {case AKSafeNav(sn):AKSafeNav({snPos:sn.snPos,snBase:sn.snBase,snTempVar:sn.snTempVar,snAccess:Calls.arrayAccess(ctx,accGet(ctx,sn.snAccess),index,mode,p)}); case _:Calls.arrayAccess(ctx,accGet(ctx,a1),index,mode,p);};
 }
 public static function typeVars(ctx:Dynamic,vl:Array<Dynamic>,p:Dynamic):Dynamic {
  var vars=vl.map(function(ev) {
   var name=ev.evName.name,pv=ev.evName.pos; DeprecationCheck.checkIs(ctx.com,ctx.m.curmod,ctx.c.curclass.clMeta,ctx.f.curfield.cfMeta,name,ev.evMeta,pv);
   try {
    var t=Typeload.loadTypeHint(ctx,p,LoadNormal,ev.evType),e:Dynamic=null;
    if(ev.evExpr!=null) {
     var old=ctx.e.inLoop; if(ev.evStatic) ctx.e.inLoop=false;
     try {e=typeExpr(ctx,ev.evExpr,WithTypeTools.withLocalVariable(t,name)); ctx.e.inLoop=old;} catch(exc:Dynamic) {ctx.e.inLoop=old; throw exc;}
     e=AbstractCast.castOrUnify(ctx,t,e,p);
    }
    var v=Meta.has(MetaTag.This,ev.evMeta)?addLocal(ctx,VAbstractThis,name,t,pv):addLocalWithOrigin(ctx,TVOLocalVariable,name,t,pv); v.vMeta=ev.evMeta;
    DisplayEmitter.checkDisplayMetadata(ctx,v.vMeta); if(ev.evFinal) addVarFlag(v,VFinal); if(ev.evStatic) addVarFlag(v,VStatic);
    if(ctx.f.inDisplay&&DisplayPosition.displayPosition.enclosedIn(pv)) DisplayEmitter.displayVariable(ctx,v,pv);
    return {variable:v,expr:e};
   } catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)):checkError(ctx,err); return {variable:addLocal(ctx,VGenerated,name,tDynamic,pv),expr:null}; case _:throw exc;}}
  });
  for(pair in vars) delayIfMono(ctx.g,PTypeField,pair.variable.vType,function() {if(ExtType.isVoid(follow(pair.variable.vType))) raiseTypingError("Variables of type Void are not allowed",pair.variable.vPos);});
  if(vars.length==1) return mk(TVar(vars[0].variable,vars[0].expr),ctx.t.tvoid,p);
  var block=mk(TBlock(vars.map(pair -> mk(TVar(pair.variable,pair.expr),ctx.t.tvoid,p))),ctx.t.tvoid,p); return mk(TMeta({meta:MetaTag.MergeBlock,exprs:[],pos:p},block),block.etype,block.epos);
 }
 public static function formatString(ctx:Dynamic,s:String,p:Dynamic):Dynamic return FormatString.formatString(ParserConfig.fileParserConfig(ctx.com,p.pfile),s,p,function(next:Dynamic,p:Dynamic) return ctx.f.inDisplay&&DisplayPosition.displayPosition.enclosedIn(p)?Display.preprocessExpr(ctx.com,{expr:next,pos:p}):{expr:next,pos:p});
 public static function typeBlock(ctx:Dynamic,el:Array<Dynamic>,withType:Dynamic,p:Dynamic):Dynamic {
  var result=[];
  for(i in 0...el.length) {
   var expected=i==el.length-1?withType:WithTypeTools.noValue;
   try {var e=typeExpr(ctx,el[i],expected); switch e.eexpr {case TMeta({meta:MetaTag.MergeBlock},{eexpr:TBlock(list)}):result=result.concat(list); case _:result.push(e);}}
   catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)):checkError(ctx,err); if(expected!=NoValue) result.push(mk(TConst(TNull),mkMono(),el[i].pos)); case _:throw exc;}}
  }
  return mk(TBlock(result),result.length==0?ctx.t.tvoid:result[result.length-1].etype,p);
 }
 public static function typeObjectDecl(ctx:Dynamic,fl:Array<Dynamic>,withType:Dynamic,p:Dynamic):Dynamic {
  var dynamicParameter:Dynamic=null;
  var kind:ObjectDeclKind=switch withType {
   case WithType(t,_):
    function loop(hadCast:Bool,seen:Array<Dynamic>,t:Dynamic):ObjectDeclKind return switch follow(t) {
     case TAnon(a):ODKWithStructure(a);
     case (TAbstract(a,pl) => followed) if(!Meta.has(MetaTag.CoreType,a.aMeta)&&!seen.exists(t -> shallowEq(followed,t))):
      var matches=[];
      for(from in TyperBase.getAbstractFroms(ctx,a,pl)) {var result=loop(from.kind==FromField,[followed].concat(seen),from.type); if(result!=ODKPlain) matches.unshift(result);}
      matches.length==0?ODKPlain:matches.length==1?matches[0]:ODKFailed;
     case TDynamic(t) if(t!=null):dynamicParameter=t; ODKWithStructure({aStatus:{value:Closed},aFields:PMap.empty()});
     case TInst(c,tl) if(!hadCast&&Meta.has(MetaTag.StructInit,c.clMeta)):ODKWithClass(c,tl);
     case _:ODKPlain;
    } loop(false,[],t);
   case _:ODKPlain;
  };
  function typeFields(fieldMap:Dynamic):Dynamic {
   var fields=PMap.empty(),extra=[];
   var result=fl.map(function(field) {
    var n=field.name.name,pn=field.name.pos,valid=Lexer.isValidIdentifier(n);
    if(fields.exists(n)) raiseTypingError("Duplicate field in object declaration : "+n,pn);
    var e:Dynamic,original:Dynamic=null;
    try {
     var t:Dynamic;
     if(dynamicParameter!=null) t=dynamicParameter;
     else {original=fieldMap.get(n); if(original==null) throw "Not_found"; if(ctx.f.inDisplay&&DisplayPosition.displayPosition.enclosedIn(pn)) DisplayEmitter.displayField(ctx,Unknown,CFSMember,original,pn); t=original.cfType;}
     e=typeExpr(ctx,field.expr,WithTypeTools.withStructureField(t,n)); e=AbstractCast.castOrUnify(ctx,t,e,e.epos);
     if(isNull(t)&&!isNull(e.etype)) e=mk(TCast(e,null),ctx.t.tnull(e.etype),e.epos);
     try typeEq(EqStrict,e.etype,t) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.unification(_) => Some(_)):e=mk(TCast(e,null),t,e.epos); case _:throw exc;}}
    } catch(exc:Dynamic) {if(exc!="Not_found") throw exc; if(valid) extra.unshift({name:n,pos:pn}); e=typeExpr(ctx,field.expr,WithTypeTools.value); original=null;}
    if(valid) {
     if(StringTools.startsWith(n,"$")) raiseTypingError("Field names starting with a dollar are not allowed",p);
     var cf=mkField(n,e.etype,Globals.punion(pn,e.epos),pn);
     if(original!=null) {if(hasClassFieldFlag(original,CfFinal)) addClassFieldFlag(cf,CfFinal); cf.cfKind=original.cfKind;}
     fields=fields.add(n,cf);
    }
    return {name:field.name,expr:e};
   });
   var t=mkAnon({value:Const},fields);
   if(!ctx.f.isUntyped) {
    var missing=[]; fieldMap.iter(function(name:String,cf:Dynamic) {if(!Meta.has(MetaTag.Optional,cf.cfMeta)&&!fields.exists(name)) missing.unshift(name);});
    if(missing.length==1) raiseOrDisplay(ctx,[UnifyCustom("Object requires field "+missing[0])],p);
    else if(missing.length>1) raiseOrDisplay(ctx,[UnifyCustom("Object requires fields: "+missing.join(", "))],p);
    for(field in extra) raiseOrDisplay(ctx,[hasExtraField(t,field.name)],field.pos);
   }
   return {type:t,fields:result};
  }
  function plain():Dynamic {
   var fields=[],types=PMap.empty();
   for(field in fl) {
    var name=field.name.name,pf=field.name.pos,valid=Lexer.isValidIdentifier(name);
    if(types.exists(name)) raiseTypingError("Duplicate field in object declaration : "+name,pf);
    var e=typeExpr(ctx,field.expr,WithTypeTools.namedStructureField(name));
    switch follow(e.etype) {case TAbstract({aPath:{pack:[],name:"Void"}},_):raiseTypingError("Fields of type Void are not allowed in structures",e.epos); case _:}
    var cf=mkField(name,e.etype,Globals.punion(pf,e.epos),pf);
    if(ctx.f.inDisplay&&DisplayPosition.displayPosition.enclosedIn(pf)) DisplayEmitter.displayField(ctx,Unknown,CFSMember,cf,pf);
    fields.push({name:field.name,expr:e});
    if(valid) {if(StringTools.startsWith(name,"$")) raiseTypingError("Field names starting with a dollar are not allowed",p); types=types.add(name,cf);}
   }
   var status={value:Const}; ctx.e.opened.unshift(status); return mk(TObjectDecl(fields),mkAnon(status,types),p);
  }
  return switch kind {
   case ODKPlain|ODKFailed:plain();
   case ODKWithStructure(a) if(a.aFields.isEmpty()&&dynamicParameter==null):plain();
   case ODKWithStructure(a):var typed=typeFields(a.aFields); mk(TObjectDecl(typed.fields),typed.type,p);
   case ODKWithClass(c,tl):
    noAbstractConstructor(c,p); var fa=FieldAccess.getConstructorAccess(c,tl,p),ctor=fa.faField;
    var args:Array<Dynamic>=switch follow(FieldAccess.getMapFunction(fa,ctor.cfType)) {case TFun({args:args,ret:_}):args; case _:throw "Invalid structure constructor";};
    var argsWithPos=[];
    for(i in 0...args.length) {var pos=ctor.cfNamePos; switch ctor.cfExpr {case {eexpr:TFunction(tf)}:if(i<tf.tfArgs.length) pos=tf.tfArgs[i].variable.vPos; case _:} argsWithPos.push({arg:args[i],pos:pos});}
    var fields=PMap.empty();
    for(pair in argsWithPos) {var arg=pair.arg,f=mkField(arg.name,arg.type,pair.pos,pair.pos); if(arg.optional) f.cfMeta=[{meta:MetaTag.Optional,exprs:[],pos:Globals.nullPos}]; if(c.clFields.exists(arg.name)) f.cfDoc=c.clFields.get(arg.name).cfDoc; fields=fields.add(arg.name,f);}
    var typed=typeFields(fields),input:Array<Dynamic>=typed.fields.copy(); input.reverse();
    var declarations=[],locals=[],hadSideEffect=false;
    for(field in input) {
     var e=field.expr;
     switch e.eexpr {
      case TConst(_)|TTypeExpr(_)|TFunction(_):locals.unshift(field);
      case _:
       if(hadSideEffect) {var v=genLocal(ctx,e.etype,e.epos); declarations.unshift(mk(TVar(v,e),e.etype,e.epos)); locals.unshift({name:field.name,expr:mk(TLocal(v),v.vType,e.epos)});}
       else {locals.unshift(field); hadSideEffect=OptimizerTexpr.hasSideEffect(e);}
     }
    }
    var el=argsWithPos.map(function(pair) {
     var arg=pair.arg;
     for(field in locals) if(field.name.name==arg.name) return field.expr;
     switch ctor.cfExpr {case {eexpr:TFunction(fn)}:for(pair in (cast fn.tfArgs:Array<Dynamic>)) if(pair.variable.vName==arg.name&&pair.defaultValue!=null) return pair.defaultValue; case _:}
     var t=arg.type; if(typeHasMeta(Abstract.followWithAbstractsWithoutNull(t),MetaTag.NotNull)) t=ctx.t.tnull(t); return mk(TConst(TNull),t,p);
    });
    var e=mk(TNew(c,tl,el),TInst(c,tl),p); mk(TBlock(declarations.concat([e])),e.etype,e.epos);
  };
 }
 public static function typeNew(ctx:Dynamic,ptp:Dynamic,el:Array<Dynamic>,withType:Dynamic,forceInline:Bool,p:Dynamic):Dynamic {
  if(ptp.posFull==Globals.nullPos) {
   var pp=p;
   if(el.length>0&&el[0].pos.pfile==p.pfile&&p.pmin<el[0].pos.pmin) {pp=Reflect.copy(p); var min=p.pmin+4,max=el[0].pos.pmin-2; pp.pmin=min<max?min:p.pmin; pp.pmax=max;}
   ptp=makePtp(ptp.path,pp);
  }
  function unifyConstructor(c:Dynamic,fa:Dynamic):Dynamic {try {var fcc=unifyFieldCall(ctx,fa,[],el,p,fa.faInline); checkConstructorAccess(ctx,c,fcc.fcField,p); return fcc;} catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)):return raiseTypingErrorExt(err); case _:throw exc;}}}
  function getParams(info:Dynamic,tl:Null<Array<Dynamic>>):Array<Dynamic> {
   function tlOrMonos(params:Dynamic):Array<Dynamic> return tl==null?Monomorph.spawnConstrainedMonos(t -> t,params):tl;
   function defaultParams(c:Dynamic):Array<Dynamic> {var tl=tlOrMonos(c.clParams); unifyConstructor(c,FieldAccess.getConstructorAccess(c,tl,p)); return tl;}
   return switch info.buildKind {
    case BuildGeneric(c):switch withType {
     case WithType(t,_):switch follow(t) {case TInst(c,tl) if(c.clPath==info.buildPath):tl; case TInst({clKind:KGenericInstance(c,tl)},_) if(c.clPath==info.buildPath):tl; case TAbstract(a,tl) if(a.aPath==info.buildPath):tl; case _:defaultParams(c);}
     case _:defaultParams(c);
    }
    case _:tlOrMonos(info.buildParams);
   };
  }
  ctx.e.callArgumentStack.unshift(el); ctx.e.withTypeStack.unshift(withType);
  function restore():Void {ctx.e.withTypeStack.shift(); ctx.e.callArgumentStack.shift();}
  var t:Dynamic;
  try t=Typeload.loadInstance(ctx,ptp,ParamCustom(getParams),LoadNormal) catch(exc:Dynamic) {restore(); if(el.exists(e -> DisplayPosition.displayPosition.enclosedIn(e.pos))) for(e in el) typeExpr(ctx,e,WithTypeTools.value); throw exc;}
  DisplayEmitter.checkDisplayType(ctx,t,ptp); t=follow(t);
  function buildConstructor(ao:Dynamic,c:Dynamic,tl:Array<Dynamic>):Dynamic {
   var fa=FieldAccess.getConstructorAccess(c,tl,p); if(forceInline) {fa=Reflect.copy(fa); fa.faInline=true;}
   var cf=fa.faField; noAbstractConstructor(c,p);
   switch cf.cfKind {case Var({vRead:AccRequire(r,msg)}):if(msg!=null) raiseTypingError(msg,p); else errorRequire(r,p); case _:}
   return unifyConstructor(c,fa);
  }
  // Upstream only invokes restore on the failing instance-load path above.
  try return switch Abstract.followWithForwardCtor(t) {
   case TInst(({clKind:KTypeParameter(ttp)} => c),params):
    if(!TypeloadCheck.isGenericParameter(ctx,c)) raiseTypingError("Only generic type parameters can be constructed",p);
    var constraint=TyperBase.getConstructibleConstraint(ctx,getConstraints(ttp),p);
    if(constraint==null) raiseTypingErrorExt(makeError(NoConstructor(TClassDecl(c)),p));
    mk(TNew(c,params,unifyCallArgs(ctx,el,constraint.args,constraint.ret,p,false,false,false)),t,p);
   case TAbstract(a,tl) if(a.aImpl!=null&&!Meta.has(MetaTag.MultiType,a.aMeta)):var fcc=buildConstructor(a,a.aImpl,tl),e=fcc.fcData(); mk(e.eexpr,t,e.epos);
   case TInst(c,params):var fcc=buildConstructor(null,c,params); mk(TNew(c,params,fcc.fcArgs),t,p);
   case TAbstract(a,params) if(a.aImpl!=null):var fcc=buildConstructor(null,a.aImpl,params); mk(TNew(a.aImpl,params,fcc.fcArgs),t,p);
   case _:raiseTypingError(sType(printContext(),t)+" cannot be constructed",p);
  } catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)):switch err.errMessage {case NoConstructor(_):if(Diagnostics.errorInDiagnosticsRun(ctx.com,p)) DisplayFields.handleMissingFieldRaise(ctx,t,"new",MCall(el),withType,p); displayErrorExt(ctx.com,err); return mk(TConst(TNull),t,p); case _:throw exc;} case _:throw exc;}}
 }
 public static function typeTry(ctx:Dynamic,e1:Dynamic,catches:Array<Dynamic>,withType:Dynamic,p:Dynamic):Dynamic {
  var body=typeExpr(ctx,Expr.ensureBlock(e1),withType),typed:Array<Dynamic>=[],expressions=[body];
  function checkUnreachable(cases:Array<Dynamic>,t:Dynamic,p:Dynamic):Void {
   if(cases.length==0) return;
   var first=cases[0],v=first.variable,e=first.expr;
   function unreachable():Void {displayError(ctx.com,"This block is unreachable",p); var pc=printContext(); displayError(ctx.com,sType(pc,t)+" can be caught to "+sType(pc,v.vType)+", which is handled here",e.epos);}
   try switch [follow(t),follow(v.vType)] {
    case [_,TDynamic(_)]|[_,TInst({clPath:{pack:["haxe"],name:"Error"}},_)]:unreachable();
    case [_,TInst({clPath:path},_)] if(path==ctx.com.config.pfExceptions.ecWildcardCatch):unreachable();
    case [TDynamic(_),_]:
    case _:core.TUnification.unify(t,v.vType); unreachable();
   } catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.unification(_) => Some(_)):checkUnreachable(cases.slice(1),t,p); case _:throw exc;}}
  }
  function checkParams(params:Array<Dynamic>,p:Dynamic):Void {for(pt in params) if(Abstract.followWithAbstracts(pt)!=tDynamic) raiseTypingError("Catch class parameter must be Dynamic",p);}
  for(catchSyntax in catches) {
   var th=catchSyntax.type==null?makePtpTh({tpackage:["haxe"],tname:"Exception",tsub:null,tparams:[]},Globals.nullPos):catchSyntax.type;
   var t=Typeload.loadComplexType(ctx,true,LoadNormal,th);
   function loop(t:Dynamic):Dynamic return switch follow(t) {
    case TInst(({clKind:KTypeParameter(_)} => c),_) if(!TypeloadCheck.isGenericParameter(ctx,c)):raiseTypingError("Cannot catch non-generic type parameter",p);
    case TInst(_,params)|TEnum(_,params):checkParams(params,th.pos); t;
    case TAbstract(a,params) if(Meta.has(MetaTag.RuntimeValue,a.aMeta)):checkParams(params,th.pos); t;
    case TAbstract(a,tl) if(!Meta.has(MetaTag.CoreType,a.aMeta)):loop(Abstract.getUnderlyingType(a,tl));
    case TDynamic(_):t;
    case _:raiseTypingError("Catch type must be a class, an enum or Dynamic",catchSyntax.expr.pos);
   };
   var t2=loop(t); checkUnreachable(typed,t2,catchSyntax.expr.pos);
   var locals=saveLocals(ctx),v=addLocalWithOrigin(ctx,TVOCatchVariable,catchSyntax.name.name,t,catchSyntax.name.pos);
   if(ctx.m.isDisplayFile&&DisplayPosition.displayPosition.enclosedIn(catchSyntax.name.pos)) DisplayEmitter.displayVariable(ctx,v,catchSyntax.name.pos);
   var e=typeExpr(ctx,catchSyntax.expr,withType);
   if(ctx.m.isDisplayFile&&DisplayPosition.displayPosition.enclosedIn(catchSyntax.pos)) TyperDisplay.displayExpr(ctx,catchSyntax.expr,e,DKMarked,MGet,withType,catchSyntax.pos);
   v.vType=t2; locals(); typed.unshift({variable:v,expr:e}); expressions.unshift(e);
  }
  var t:Dynamic=switch withType {
   case NoValue:ctx.t.tvoid;
   case Value(_):unifyMin(ctx,expressions);
   case WithType(t,src) if(ExtType.isMono(follow(t))||ExtType.isVoid(follow(t))):unifyMinForTypeSource(ctx,expressions,src);
   case WithType(t,_):body=AbstractCast.castOrUnify(ctx,t,body,body.epos); typed=typed.map(pair -> {variable:pair.variable,expr:AbstractCast.castOrUnify(ctx,t,pair.expr,pair.expr.epos)}); t;
  };
  typed.reverse(); return mk(TTry(body,typed),t,p);
 }
 public static function typeMapDeclaration(ctx:Dynamic,e1:Dynamic,el:Array<Dynamic>,withType:Dynamic,p:Dynamic):Dynamic {
  var expected:Dynamic=switch withType {
   case WithType(t,_):switch follow(t) {case TAbstract({aPath:{pack:["haxe","ds"],name:"Map"}},[tk,tv]):{key:tk,value:tv}; case TInst({clPath:{pack:["haxe","ds"],name:"IntMap"}},[tv]):{key:ctx.t.tint,value:tv}; case TInst({clPath:{pack:["haxe","ds"],name:"StringMap"}},[tv]):{key:ctx.t.tstring,value:tv}; case TInst({clPath:{pack:["haxe","ds"],name:"ObjectMap"|"EnumValueMap"}},[tk,tv]):{key:tk,value:tv}; case _:null;}
   case _:null;
  };
  var keys=Hashtbl.create(0);
  function checkKey(e:Dynamic):Void {
   if(keys.mem(e.eexpr)) raiseTypingErrorExt(makeError(Custom("Duplicate key"),e.epos,[makeError(Custom(complMsg("Previously defined here")),keys.find(e.eexpr))]));
   switch e.eexpr {case TConst(_):keys.add(e.eexpr,e.epos); case _:}
  }
  var pairs=[e1].concat(el).map(e -> switch e.expr {case EBinop(OpArrow,a,b):{key:a,value:b}; case EDisplay(_):typeExpr(ctx,e,expected==null?WithTypeTools.value:WithTypeTools.withType(expected.key)); raiseTypingError("Expected a => b",e.pos); case _:raiseTypingError("Expected a => b",e.pos);});
  var keyExprs=[],valueExprs=[];
  for(pair in pairs) {
   var key=typeExpr(ctx,pair.key,expected==null?WithTypeTools.value:WithTypeTools.withType(expected.key)); checkKey(key);
   if(expected!=null) key=AbstractCast.castOrUnify(ctx,expected.key,key,key.epos);
   var value=typeExpr(ctx,pair.value,expected==null?WithTypeTools.value:WithTypeTools.withType(expected.value)); if(expected!=null) value=AbstractCast.castOrUnify(ctx,expected.value,value,value.epos);
   keyExprs.unshift(key); valueExprs.unshift(value);
  }
  var tk=expected==null?unifyMinRaise(ctx,keyExprs):expected.key,tv=expected==null?unifyMinRaise(ctx,valueExprs):expected.value;
  var m=TypeloadModule.loadModule(ctx,{pack:["haxe","ds"],name:"Map"},Globals.nullPos),a:Dynamic,c:Dynamic;
  if(m.mTypes.length>0) switch m.mTypes[0] {case TAbstractDecl(abstractType) if(abstractType.aImpl!=null):a=abstractType; c=abstractType.aImpl; case _:a=null; c=null;} else {a=null; c=null;}
  if(a==null) raiseTypingError("Module haxe.ds.Map is expected to contain an abstract type with an implementation, but found ["+(cast m.mTypes:Array<Dynamic>).map(sModuleTypeKind).join(", ")+"]",p);
  var tmap=TAbstract(a,[tk,tv]),cf=c.clStatics.get("set"); if(cf==null) throw "Not_found";
  var v=genLocal(ctx,tmap,p),ev=mk(TLocal(v),tmap,p),ec=TyperBase.typeModuleType(ctx,TClassDecl(c),p),ef=mk(TField(ec,FStatic(c,cf)),tfun([tk,tv],ctx.t.tvoid),p);
  var result=[ev]; for(i in 0...keyExprs.length) result.push(makeCall(ctx,ef,[ev,keyExprs[i],valueExprs[i]],ctx.com.basic.tvoid,p)); result.reverse();
  result.unshift(mk(TVar(v,mk(TNew(c,[tk,tv],[]),tmap,p)),tDynamic,p)); return mk(TBlock(result),tmap,p);
 }
 public static function typeLocalFunction(ctxFrom:Dynamic,kind:Dynamic,f:Dynamic,withType:Dynamic,wantCoroutine:Bool,p:Dynamic):Dynamic {
  var name:Dynamic=null,inlined=false;
  switch kind {case FKNamed(n,inlineValue):name=n; inlined=inlineValue; case _:}
  var params=TypeloadFunction.typeFunctionParams(ctxFrom,f,TPHLocal,name==null?"localfun":name.name);
  var curfun=switch ctxFrom.e.curfun {case FunStatic:FunStatic; case FunMemberAbstract|FunMemberAbstractLocal:FunMemberAbstractLocal; case _:FunMemberClassLocal;};
  var isCoroutine=wantCoroutine;
  if(name==null) switch withType {case WithType(t,_) if(!ExtType.isMono(follow(t))):isCoroutine=switch followWithCoro(t) {case Coro(_):true; case _:false;}; case _:}
  var ctx=TyperManager.cloneForExpr(ctxFrom,curfun,isCoroutine?FunCoroutine:FunFunction),vname:Dynamic=null,pname=p;
  if(name==null) {if(params.length>0||isCoroutine) vname={name:genLocalPrefix,kind:VGenerated};}
  else {Naming.checkLocalVariableName(ctx.com,name.name,TVOLocalFunction,p); vname={name:name.name,kind:VUser(TVOLocalFunction)}; pname=name.pos;}
  ctx.typeParams=params.concat(ctx.typeParams); if(!inlined) ctx.e.inLoop=false;
  var rt=Typeload.loadTypeHint(ctx,p,LoadReturn,f.fType);
  function typeArg(_:Int,opt:Bool,t:Dynamic,p:Dynamic):Dynamic return Typeload.loadTypeHint(ctx,p,LoadNormal,t,opt);
  var args=new FunctionArguments(ctx.com,typeArg,false,ctx.f.inDisplay,null,f.fArgs),targs=args.forType();
  function maybeUnifyArg(t1:Dynamic,t2:Dynamic):Void switch follow(t1) {case TMono(_):unify(ctx,t2,t1,p); case _:}
  function maybeUnifyRet(tr:Dynamic):Void switch [follow(tr),follow(rt)] {case [TAbstract({aPath:{pack:[],name:"Void"}},_),_] if(kind!=FKArrow): case [_,TMono(_)]:unify(ctx,rt,tr,p); case _:}
  function matrix(list:Array<Dynamic>):Void {
   var arity=targs.length,m=new UnificationMatrix(arity+1);
   for(t in list) switch followWithCoro(t) {
    case NotCoro(TFun({args:args,ret:ret}))|Coro(args,ret) if(args.length==arity):for(i in 0...args.length) m.join(dynamifyMonos(args[i].type),i+1); m.join(dynamifyMonos(ret),0);
    case _:
   }
   for(i in 0...targs.length) {var t=m.getType(i+1); if(t!=null) maybeUnifyArg(targs[i].type,t);}
   var ret=m.getType(0); if(ret!=null) maybeUnifyRet(ret);
  }
  switch withType {
   case WithType(t,_):
    function loop(stack:Array<Dynamic>,t:Dynamic):Void switch followWithCoro(t) {
     case NotCoro(TFun({args:args2,ret:tr}))|Coro(args2,tr) if(args2.length==targs.length):for(i in 0...targs.length) maybeUnifyArg(targs[i].type,args2[i].type); maybeUnifyRet(tr);
     case NotCoro(TAbstract(a,tl)):
      var froms=TyperBase.getAbstractFroms(ctx,a,tl);
      if(froms.length==1) {if(!stack.exists(t2 -> shallowEq(t,t2))) loop([t].concat(stack),froms[0].type);}
      else {
       var pending=froms.copy(),seen=[],flat=[];
       while(pending.length>0) {
        var next=pending.shift().type;
        switch follow(next) {case (TAbstract(a,tl) => t) if(!seen.exists(t2 -> shallowEq(t,t2))):seen.unshift(t); pending=pending.concat(TyperBase.getAbstractFroms(ctx,a,tl)); case _:flat.push(next);}
       }
       matrix(flat);
      }
     case _:
    }
    loop([],t);
   case NoValue:if(name==null) displayError(ctx.com,"Unnamed lvalue functions are not supported",p);
   case _:
  }
  var ft=isCoroutine?AtomicLazy.force(ctx.t.tcoro.tcoro)(targs,rt):TFun({args:targs,ret:rt});
  if(withType!=NoValue) ft=applyParams(params,Monomorph.spawnConstrainedMonos(t -> t,params),ft);
  var v:Dynamic=null;
  if(vname!=null) {v=addLocal(ctx,vname.kind,vname.name,ft,pname); if(params.length>0) v.vExtra=varExtra(params,null);}
  var oldInArgs=ctx.f.inCallArgs,resets=oldInArgs&&!inOverloadCallArgs(ctx); if(resets) ctx.f.inCallArgs=false;
  var capture=resets?callArgBodyCapture(ctx):null,deactivate:Void->Void=capture==null?function() {}:activateMessageCapture(ctx.com,capture),body:Dynamic;
  try {
   try body=TypeloadFunction.typeFunction(ctx,args,rt,f.fExpr,ctx.f.inDisplay,p) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)) if(resets):checkError(ctx,err); body=mk(TBlock([]),ctx.t.tvoid,p); case _:throw exc;}}
   deactivate(); ctx.f.inCallArgs=oldInArgs;
  } catch(exc:Dynamic) {deactivate(); ctx.f.inCallArgs=oldInArgs; throw exc;}
  var tf={tfArgs:args.forExpr(ctx),tfType:rt,tfExpr:body},e=mk(TFunction(tf),ft,p),config=TypeloadFields.getCoroConfig(ctx,ctx.f.meta);
  if(config!=null) {if(v==null) throw "No_value"; e=Coro.funToCoro(Coro.createCoroContext(ctx,config,CoroTypes.LocalFunc(tf,v)));}
  if(v==null) return e;
  Typeload.generateArgsMeta(ctx.com,null,m -> v.vMeta.unshift(m),f.fArgs);
  if(params.length>0||inlined) v.vExtra=varExtra(params,inlined?e:null);
  if(ctx.f.inDisplay&&DisplayPosition.displayPosition.enclosedIn(v.vPos)) DisplayEmitter.displayVariable(ctx,v,v.vPos);
  function usage(event:Dynamic):Void switch event {case LocalUsage.Block(f)|LocalUsage.Loop(f)|LocalUsage.Function(f):f(usage); case LocalUsage.Use(v2)|LocalUsage.Assign(v2) if(v==v2):throw "Exit"; case LocalUsage.Use(_)|LocalUsage.Assign(_)|LocalUsage.Declare(_):}
  var recursive=false;
  try LocalUsage.localUsage(usage,e) catch(exc:Dynamic) {if(exc!="Exit") throw exc; recursive=true;}
  var exprs=withType!=NoValue&&!inlined?[mk(TLocal(v),v.vType,p)]:[];
  if(recursive||(params.length>0&&withType!=NoValue)) {
   if(inlined) displayError(ctx.com,"Inline function cannot be recursive",e.epos);
   exprs=[mk(TVar(v,mk(TConst(TNull),ft,p)),ctx.t.tvoid,p),mk(TBinop(OpAssign,mk(TLocal(v),ft,p),e),ft,p)].concat(exprs);
  } else if(inlined&&!ctx.m.isDisplayFile) exprs.unshift(mk(TBlock([]),ctx.t.tvoid,p)); else exprs.unshift(mk(TVar(v,e),ctx.t.tvoid,p));
  if(exprs.length==1) return exprs[0];
  var block=mk(TBlock(exprs),v.vType,p); return mk(TMeta({meta:MetaTag.MergeBlock,exprs:[],pos:Globals.nullPos},block),v.vType,p);
 }
 public static function typeArrayDecl(ctx:Dynamic,el:Array<Dynamic>,withType:Dynamic,p:Dynamic):Dynamic {
  var allowDynamic=false;
  function loop(seen:Array<Dynamic>,t:Dynamic):Dynamic return switch follow(t) {
   case TInst({clPath:{pack:[],name:"Array"}},[tp]):switch follow(tp) {case TMono(_):null; case t:if(t==tDynamic) allowDynamic=true; tp;}
   case TAnon(_):try getIterableParam(t) catch(exc:Dynamic) {if(exc!="Not_found") throw exc; null;}
   case (TAbstract(a,pl) => t) if(!seen.exists(t2 -> shallowEq(t,t2))):
    var types=[];
    for(from in TyperBase.getAbstractFroms(ctx,a,pl)) {var next=loop([t].concat(seen),from.type); if(next!=null) types.unshift(next);}
    types.length==1?types[0]:null;
   case t:if(t==tDynamic) {allowDynamic=true; t;} else null;
  };
  var tp=switch withType {case WithType(t,_):loop([],t); case _:null;};
  if(tp==null) {
   var typed=el.map(e -> typeExpr(ctx,e,WithTypeTools.value)),t:Dynamic;
   try t=unifyMinRaise(ctx,typed) catch(exc:Dynamic) {switch exc {
    case (core.ds.ExceptionTools.typing(_) => Some(err)):switch err.errMessage {case Unify(_):if(allowDynamic||ctx.f.isUntyped||ignoreError(ctx.com)) t=tDynamic; else t=raiseTypingErrorExt(makeError(Custom("Arrays of mixed types are only allowed if the type is forced to Array<Dynamic>"),err.errPos,[err])); case _:throw exc;}
    case _:throw exc;
   }}
   return mk(TArrayDecl(typed),ctx.t.tarray(t),p);
  }
  var typed=el.map(function(e) {var value=typeExpr(ctx,e,WithTypeTools.withType(tp)); return AbstractCast.castOrUnify(ctx,tp,value,value.epos);});
  return mk(TArrayDecl(typed),ctx.t.tarray(tp),p);
 }
 public static function typeArrayComprehension(ctx:Dynamic,e:Dynamic,withType:Dynamic,p:Dynamic):Dynamic {
  var v=genLocal(ctx,spawnMonomorph(ctx,p),p),ev=mk(TLocal(v),v.vType,p),reference=storeTypedExpr(ctx.com,ev,p).expr,initializer:Dynamic={expr:EConst(Ident("null")),pos:p};
  function map(expr:Dynamic):Dynamic {
   var ep=expr.pos;
   var def=switch expr.expr {
    case EFor(it,e):EFor(it,map(e));
    case EWhile(cond,e,flag):EWhile(cond,map(e),flag);
    case EIf(cond,e1,e2):EIf(cond,map(e1),e2==null?null:map(e2));
    case EBlock([e]):EBlock([map(e)]);
    case EBlock([]):return map({expr:EObjectDecl([]),pos:ep});
    case EBlock(el):var next=el.copy(); next[next.length-1]=map(next[next.length-1]); EBlock(next);
    case EParenthesis(e):EParenthesis(map(e));
    case EMeta(m,e):EMeta(m,map(e));
    case EBinop(OpArrow,a,b):initializer={expr:ENew(makePtp({tpackage:["haxe","ds"],tname:"Map",tparams:[],tsub:null},Globals.nullPos),[]),pos:p}; ECall({expr:efield(reference,"set"),pos:ep},[a,b]);
    case _:initializer={expr:EArrayDecl([]),pos:p}; ECall({expr:efield(reference,"push"),pos:ep},[expr]);
   };
   return {expr:def,pos:ep};
  }
  var mapped=map(e),ea=typeExpr(ctx,initializer,withType); unify(ctx,v.vType,ea.etype,p); var loop=typeExpr(ctx,mapped,NoValue);
  return mk(TBlock([mk(TVar(v,ea),ctx.t.tvoid,p),loop,ev]),v.vType,p);
 }
 public static function typeReturn(ctx:Dynamic,e:Dynamic,withType:Dynamic,p:Dynamic,implicit:Bool=false):Dynamic {
  var abstractCtor=ctx.e.curfun==FunMemberAbstract&&hasClassFieldFlag(ctx.f.curfield,CfAbstractConstructor);
  if(e==null&&abstractCtor) return mk(TReturn(mk(TCast(TyperBase.getThis(ctx,p),null),ctx.e.ret,p)),terminatorType(ctx,withType,p),p);
  if(e==null) {
   var v=ctx.t.tvoid; unify(ctx,v,ctx.e.ret,p);
   var expectVoid=switch withType {case WithType(t,_):ExtType.isVoid(follow(t)); case Value(ImplicitReturn):true; case _:false;};
   return mk(TReturn(null),expectVoid?v:terminatorType(ctx,withType,p),p);
  }
  if(abstractCtor) switch e.expr {case ECast({expr:EConst(Ident("this"))},null): case _:displayError(ctx.com,"Cannot return a value from constructor",p);}
  try {
   var expected=ExtType.isVoid(follow(ctx.e.ret))?WithTypeTools.noValue:implicit?WithTypeTools.ofImplicitReturn(ctx.e.ret):WithTypeTools.withType(ctx.e.ret);
   var e=typeExpr(ctx,e,expected);
   if(ExtType.isVoid(follow(ctx.e.ret))&&implicit) return e;
   e=AbstractCast.castOrUnify(ctx,ctx.e.ret,e,p);
   if(ExtType.isVoid(follow(e.etype))) {
    switch Texpr.skip(e).eexpr {case TConst(TNull):raiseTypingError("Cannot return `null` from Void-function",p); case _:}
    var t=terminatorType(ctx,withType,p); return mk(TBlock([e,mk(TReturn(null),t,p)]),t,e.epos);
   }
   return mk(TReturn(e),terminatorType(ctx,withType,p),p);
  } catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)):var p=err.errPos; checkError(ctx,err); return mk(TReturn(mk(TConst(TNull),mkMono(),p)),terminatorType(ctx,withType,p),p); case _:throw exc;}}
 }
 public static function typeCast(ctx:Dynamic,e:Dynamic,hint:Dynamic,p:Dynamic):Dynamic {
  var tpos=hint.pos,t=Typeload.loadComplexType(ctx,true,LoadNormal,hint);
  function check(pt:Dynamic):Void switch follow(pt) {case TMono(_): case t if(t==tDynamic): case _:raiseTypingError("Cast type parameters must be Dynamic",tpos);}
  function loop(t:Dynamic):Dynamic return switch follow(t) {
   case TInst(c,params):for(pt in params) check(pt); switch c.clKind {case KTypeParameter(_):raiseTypingError("Can't cast to a type parameter",tpos); case _:} TClassDecl(c);
   case TEnum(en,params):for(pt in params) check(pt); TEnumDecl(en);
   case TAbstract(a,params) if(Meta.has(MetaTag.RuntimeValue,a.aMeta)):for(pt in params) check(pt); TAbstractDecl(a);
   case TAbstract(a,params):loop(Abstract.getUnderlyingType(a,params));
   case _:raiseTypingError("Cast type must be a class or an enum",tpos);
  };
  var module=loop(t); return mk(TCast(typeExpr(ctx,e,WithTypeTools.value),module),t,p);
 }
 public static function getIfThenElseOperands(ctx:Dynamic,e1:Dynamic,e2:Dynamic,withType:Dynamic):Dynamic return switch withType {
  case NoValue:{type:ctx.t.tvoid,coerce:function(e:Dynamic) return e};
  case Value(_):{type:unifyMin(ctx,[e1,e2]),coerce:function(e:Dynamic) return e};
  case WithType(t,src) if(ExtType.isMono(follow(t))||ExtType.isVoid(follow(t))):{type:unifyMinForTypeSource(ctx,[e1,e2],src),coerce:function(e:Dynamic) return e};
  case WithType(t,_):{type:t,coerce:function(e:Dynamic) return AbstractCast.castOrUnify(ctx,t,e,e.epos)};
 };
 public static function makeIfThenElse(ctx:Dynamic,e0:Dynamic,e1:Dynamic,e2:Dynamic,withType:Dynamic,p:Dynamic):Dynamic {var operands=getIfThenElseOperands(ctx,e1,e2,withType),a=operands.coerce(e1),b=operands.coerce(e2); return mk(TIf(e0,a,b),operands.type,p);}
 public static function typeIf(ctx:Dynamic,e:Dynamic,e1:Dynamic,e2:Dynamic,withType:Dynamic,ternary:Bool,p:Dynamic):Dynamic {
  var condition=typeExpr(ctx,e,WithTypeTools.value); if(ternary&&condition.eexpr==TConst(TNull)) raiseTypingError("Cannot use null as ternary condition",condition.epos);
  condition=AbstractCast.castOrUnify(ctx,ctx.t.tbool,condition,condition.epos); var thenExpr=typeExpr(ctx,Expr.ensureBlock(e1),withType);
  if(e2==null) return mk(TIf(condition,thenExpr,null),ctx.t.tvoid,p);
  var elseExpr=typeExpr(ctx,Expr.ensureBlock(e2),withType); return makeIfThenElse(ctx,condition,thenExpr,elseExpr,withType,p);
 }
 public static function typeMeta(ctx:Dynamic,m:Dynamic,e1:Dynamic,withType:Dynamic,p:Dynamic,?mode:Dynamic):Dynamic {
  if(mode==null) mode=MGet;
  if(ctx.m.isDisplayFile) DisplayEmitter.checkDisplayMetadata(ctx,[m]); var old=ctx.f.meta; ctx.f.meta=[m].concat(ctx.f.meta);
  function expression():Dynamic return typeExpr(ctx,e1,withType,mode);
  function preserve():Dynamic {var e=expression(); return mk(TMeta(m,e),e.etype,e.epos);}
  var e:Dynamic=switch m.meta {
   case MetaTag.ToString:var e=expression(); switch follow(e.etype) {case TAbstract(a,_) if(a.aImpl!=null&&a.aImpl.clStatics.exists("toString")):callToString(ctx,e); case _:e;}
   case MetaTag.Markup:raiseTypingError("Markup literals must be processed by a macro",p);
   case MetaTag.Analyzer:preserve();
   case MetaTag.MergeBlock:switch e1.expr {case EBlock(el):var e=typeBlock(ctx,el,withType,p); mk(TMeta(m,e),e.etype,e.epos); case _:expression();}
   case MetaTag.StoredTypedExpr:TyperBase.typeStoredExpr(ctx,e1);
   case MetaTag.NoPrivateAccess:ctx.f.meta=(cast ctx.f.meta:Array<Dynamic>).filter(m -> m.meta!=MetaTag.PrivateAccess); expression();
   case MetaTag.Fixed if(ctx.com.platform==Cpp):preserve();
   case MetaTag.NullSafety:preserve();
   case MetaTag.BypassAccessor:var counter=ctx.e.bypassAccessor; ctx.e.bypassAccessor=counter+1; var e=expression(); if(ctx.e.bypassAccessor>counter) displayError(ctx.com,"Field access expression expected after @:bypassAccessor metadata",m.pos); e;
   case MetaTag.Inline:switch e1.expr {
    case ECall(e,el):accGet(ctx,typeCallAccess(ctx,e,el,MGet,WithTypeTools.value,m.pos,p));
    case ENew(t,el):var e=typeNew(ctx,t,el,withType,true,p); mk(TMeta({meta:MetaTag.Inline,exprs:[],pos:Globals.nullPos},e),e.etype,e.epos);
    case EFor(it,e2):ForLoop.typeForLoop(ctx,TyperDisplay.handleDisplay,it,e2,ForcedUnroll,p);
    case _:displayError(ctx.com,"Call or function expected after inline keyword",p); expression();
   }
   case MetaTag.ImplicitReturn:switch e1.expr {case EReturn(e):typeReturn(ctx,e,withType,e1.pos,true); case _:expression();}
   case MetaTag.Coroutine:
    var current=ctx.f.meta;
    function loop(e:Dynamic):Dynamic return switch e.expr {case EMeta(m,e):ctx.f.meta=[m].concat(ctx.f.meta); loop(e); case EFunction(kind,f):typeLocalFunction(ctx,kind,f,withType,true,p); case _:expression();};
    var e=loop(e1); ctx.f.meta=current; e;
   case MetaTag.Dollar(""):expression();
   case MetaTag.Dollar(s):displayError(ctx.com,"Reification $"+s+" is not allowed outside of `macro` expression",m.pos); expression();
   case MetaTag.Custom(":debug.import"):
    function print(list:Array<Dynamic>):Void Sys.println(list.map(res -> sResolutionKind(res.rKind)).join("\n"));
    Sys.println("OWN:"); print(getOwnResolution(ctx).getList()); Sys.println("IMPORT:"); print(ctx.m.importResolution.getList()); expression();
   case _:ctx.g.retainMeta?preserve():expression();
  };
  ctx.f.meta=old; return e;
 }
 public static function typeCallTarget(ctx:Dynamic,e:Dynamic,el:Array<Dynamic>,withType:Dynamic,pInline:Dynamic):AccessKind {
  var acc=maybeTypeAgainstEnum(ctx,() -> typeAccess(ctx,e.expr,e.pos,MCall(el),WithTypeTools.value),withType,true,e.pos);
  if(pInline==null) return acc;
  function check(cf:Dynamic):Void {if(hasClassFieldFlag(cf,CfAbstract)) displayError(ctx.com,"Cannot force inline on abstract method",pInline);}
  function loop(e:AccessKind):AccessKind return switch e {
   case AKSafeNav(sn):AKSafeNav({snPos:sn.snPos,snBase:sn.snBase,snTempVar:sn.snTempVar,snAccess:loop(sn.snAccess)});
   case AKField(fa):check(fa.faField); var copy=Reflect.copy(fa); copy.faInline=true; AKField(copy);
   case AKUsingField(sea):check(sea.seAccess.faField); var copy=Reflect.copy(sea),access=Reflect.copy(sea.seAccess); access.faInline=true; copy.seAccess=access; AKUsingField(copy);
   case AKExpr({eexpr:TLocal(_)}):displayError(ctx.com,"Cannot force inline on local functions",pInline); e;
   case _:e;
  };
  return loop(acc);
 }
 public static function typeCallAccess(ctx:Dynamic,e:Dynamic,el:Array<Dynamic>,mode:Dynamic,withType:Dynamic,pInline:Dynamic,p:Dynamic):AccessKind {
  try return AKExpr(typeCallBuiltin(ctx,e,el,mode,withType,p)) catch(exc:Dynamic) {if(exc!="Exit") throw exc; return buildCallAccess(ctx,typeCallTarget(ctx,e,el,withType,pInline),el,mode,withType,p);}
 }
 public static function typeCallBuiltin(ctx:Dynamic,e:Dynamic,el:Array<Dynamic>,mode:Dynamic,withType:Dynamic,p:Dynamic):Dynamic return switch e.expr {
  case EConst(Ident("trace")) if(el.length>0):
   var p=e.pos;
   if(Common.defined(ctx.com,Define.NoTraces)) nullExpr(ctx.t.tvoid,p);
   else {
    var first=el[0],rest=el.slice(1);
    function toStringMeta(e:Dynamic):Dynamic return {expr:EMeta({meta:MetaTag.ToString,exprs:[],pos:Globals.nullPos},e),pos:e.pos};
    var params=rest.length==0?[]:[{name:{name:"customParams",pos:Globals.nullPos,quotes:NoQuotes},expr:{expr:EArrayDecl(rest.map(toStringMeta)),pos:p}}],infos=mkInfos(ctx,p,params);
    if((platform(ctx.com,Js)||platform(ctx.com,Python))&&rest.length==0&&hasDce(ctx.com)) {
     var value=typeExpr(ctx,first,WithTypeTools.value); if(ExtType.isVoid(follow(value.etype))) raiseTypingError("Cannot use Void as value",value.epos);
     var information=typeExpr(ctx,infos,WithTypeTools.value);
     switch follow(value.etype) {case TAbstract(a,_) if(a.aImpl!=null&&a.aImpl.clStatics.exists("toString")):value=callToString(ctx,value); case _:}
     mk(TCall(mk(TIdent("`trace"),tDynamic,p),[value,information]),ctx.t.tvoid,p);
    } else {
     var root={expr:EConst(Ident("haxe")),pos:p},log={expr:efield(root,"Log"),pos:p},trace={expr:efield(log,"trace"),pos:p};
     typeExpr(ctx,{expr:ECall(trace,[toStringMeta(first),infos]),pos:p},NoValue);
    }
   }
  case EField({expr:EConst(Ident("super"))},_,_):throw "Exit";
  case EField(on,"bind",kind):var typed=typeExpr(ctx,on,WithTypeTools.value); switch follow(typed.etype) {case TFun({args:args,ret:ret}):typeBind(ctx,typed,{args:args,ret:ret},el,kind==EFSafe,e.pos); case _:throw "Exit";}
  case EConst(Ident("$type")) if(el.length>0):
   var expected=el.length==2&&(switch el[1].expr {case EConst(Ident("_")):true; case _:false;})?WithTypeTools.toString(withType):null;
   var value=typeExpr(ctx,el[0],withType),s=sType(printContext(),value.etype); if(expected!=null) s+=" (expected: "+expected+")"; warning(ctx,WInfo,s,value.epos); value;
  case EField(on,"match",kind) if(el.length==1):
   if(kind==EFSafe) raiseTypingError("?.match is not supported",e.pos);
   var typed=typeExpr(ctx,on,WithTypeTools.value);
   function hasEnumMatch(t:Dynamic):Bool return switch follow(t) {
    case TEnum(_):true;
    case TAbstract(a,tl) if(Meta.has(MetaTag.Forward,a.aMeta)&&!Meta.has(MetaTag.CoreType,a.aMeta)):if(a.aImpl!=null&&a.aImpl.clStatics.exists("match")&&hasClassFieldFlag(a.aImpl.clStatics.get("match"),CfImpl)) false; else hasEnumMatch(Abstract.getUnderlyingType(a,tl,true));
    case _:false;
   };
   if(!hasEnumMatch(typed.etype)) throw "Exit";
   Matcher.Match.matchExpr(ctx,on,[{values:[el[0]],guard:null,expr:{expr:EConst(Ident("true")),pos:e.pos},pos:e.pos}],{expr:{expr:EConst(Ident("false")),pos:e.pos},pos:e.pos},WithTypeTools.withType(ctx.t.tbool),true,e.pos);
  case EConst(Ident("__unprotect__")) if(el.length==1&&switch el[0].expr {case EConst(String(_)):true; case _:false;}):
   var value=typeExpr(ctx,el[0],WithTypeTools.value);
   if(Common.platform(ctx.com,Flash)) {var t=tfun([value.etype],value.etype); mk(TCall(mk(TIdent("__unprotect__"),t,p),[value]),value.etype,value.epos);} else value;
  case EDisplay(({expr:EConst(Ident("super"))} => subject),dk):TyperDisplay.handleDisplay(ctx,{expr:ECall(subject,el),pos:p},dk,mode,withType);
  case EConst(Ident("super")):
   if(ctx.e.curfun!=FunConstructor) raiseTypingError("Cannot call super constructor outside class constructor",p);
   var sup=ctx.c.curclass.clSuper; if(sup==null) raiseTypingError("Current class does not have a super",p);
   var c=sup.c,params=sup.params,fa=FieldAccess.getConstructorAccess(c,params,p),cf=fa.faField,t=TInst(c,params),on=mk(TConst(TSuper),t,e.pos);
   if(Meta.has(MetaTag.CompilerGenerated,cf.cfMeta)) displayError(ctx.com,errorMsg(NoConstructor(TClassDecl(c))),p);
   fa=FieldAccess.create(on,cf,FHInstance(c,params),false,p); var fcc=unifyFieldCall(ctx,fa,[],el,p,false);
   mk(TCall(mk(TConst(TSuper),t,e.pos),fcc.fcArgs),ctx.t.tvoid,p);
  case _:throw "Exit";
 };
 public static function typeExpr(ctx:Dynamic,syntax:Dynamic,withType:Dynamic,?mode:Dynamic):Dynamic {
  if(mode==null) mode=MGet;
  var e=syntax.expr,p=syntax.pos;
  return switch e {
   case EField({expr:EConst(String(s,_)),pos:ps},"code",EFNormal):if(UTF8.length(s)!=1) raiseTypingError("String must be a single UTF8 char",ps); mk(TConst(TInt(UCharExt.code(UTF8.get(s,0)))),ctx.t.tint,p);
   case EField(_,name,_) if(StringTools.startsWith(name,"$")):raiseTypingError("Field names starting with $ are not allowed",p);
   case EConst(Ident(s)):
    if(s=="super"&&withType!=NoValue&&!ctx.f.inDisplay) raiseTypingError("Cannot use super as value",p);
    accGet(ctx,maybeTypeAgainstEnum(ctx,() -> typeIdent(ctx,s,p,mode,withType),withType,false,p));
   case EField(_)|EArray(_)|ECall(_):accGet(ctx,typeAccess(ctx,e,p,mode,withType));
   case EConst(Regexp(r,opt)):
    var str=mk(TConst(TString(r)),ctx.t.tstring,p),options=mk(TConst(TString(opt)),ctx.t.tstring,p),t=Typeload.loadInstance(ctx,makePtp(mkTypePath({pack:["std"],name:"EReg"}),Globals.nullPos),ParamNormal,LoadNormal);
    var c=switch t {case TInst(c,[]):c; case _:throw "Invalid EReg class";}; mk(TNew(c,[],[str,options]),t,p);
   case EConst(String(s,SSingleQuotes)) if(s!=""):typeExpr(ctx,formatString(ctx,s,p),withType);
   case EConst(Int(s,suffix)) if(suffix!=null):switch suffix {
    case "i32":try mk(TConst(TInt(Int32.ofString(s))),ctx.com.basic.tint,p) catch(_:Dynamic) raiseTypingError("Cannot represent "+s+" with a 32 bit integer",p);
    case "i64":
     if(s.length>18&&s.substr(0,2)=="0x") raiseTypingError("Invalid hexadecimal integer",p);
     var value=Int64.ofString(s),high=Int64.toInt32(Int64.shiftRight(value,32)),low=Int64.toInt32(value);
     var root={expr:EConst(Ident("haxe")),pos:p},int64={expr:efield(root,"Int64"),pos:p},field={expr:efield(int64,"make"),pos:p};
     typeExpr(ctx,{expr:ECall(field,[{expr:EConst(Int(Std.string(high),null)),pos:p},{expr:EConst(Int(Std.string(low),null)),pos:p}]),pos:p},withType);
    case "u32":typeExpr(ctx,{expr:ECheckType({expr:EConst(Int(s,null)),pos:p},makePtpTh(mkTypePath({pack:["haxe"],name:"UInt32"}),p)),pos:p},withType);
    case other:raiseTypingError(other+" is not a valid integer suffix",p);
   }
   case EConst((Float(_,suffix) => c)) if(suffix!=null):suffix=="f64"?Texpr.typeConstant(ctx.com.basic,c,p):raiseTypingError(suffix+" is not a valid float suffix",p);
   case EConst(c):Texpr.typeConstant(ctx.com.basic,c,p);
   case EBinop(OpNullCoal,a,b):
    var reference=new ValueReference(ctx),e1=typeExpr(ctx,Expr.ensureBlock(a),WithTypeTools.value),e2=typeExpr(ctx,Expr.ensureBlock(b),WithTypeTools.withType(e1.etype)),operands=getIfThenElseOperands(ctx,e1,e2,withType);
    e2=operands.coerce(e2);
    var iftype=DeadEnd.hasDeadEnd(e2)?followWithoutType(e1.etype):switch e2.etype {case TAbstract({aPath:{pack:[],name:"Null"}},[_]):operands.type; case _:followWithoutType(operands.type);};
    var nullable=ctx.t.tnull(e1.etype),name=WithTypeTools.getExpectedName(withType); if(name==null||name=="") name="tmp";
    e1=reference.asVar(name,mk(e1.eexpr,nullable,e1.epos));
    var enull=Builder.makeNull(nullable,e1.epos),condition=mk(TBinop(OpNotEq,e1,enull),ctx.t.tbool,e1.epos),eif=mk(TIf(condition,operands.coerce(e1),e2),iftype,p); reference.toTexpr(eif);
   case EBinop(OpAssignOp(OpNullCoal),a,b):typeOpNullCoalAssign(ctx,a,b,withType,p);
   case EBinop(op,a,b):typeBinop(ctx,op,a,b,false,withType,p);
   case EBlock([]) if(switch withType {case NoValue:false; case WithType(t,ImplicitReturn):!ExtType.isMono(follow(t)); case _:true;}):typeExpr(ctx,{expr:EObjectDecl([]),pos:p},withType);
   case EBlock(list):var locals=saveLocals(ctx),e=typeBlock(ctx,list,withType,p); locals(); e;
   case EParenthesis(inner):var e=typeExpr(ctx,inner,withType); mk(TParenthesis(e),e.etype,p);
   case EObjectDecl(fields):typeObjectDecl(ctx,fields,withType,p);
   case EArrayDecl([({expr:EFor(_)|EWhile(_)} => e)]):typeArrayComprehension(ctx,e,withType,p);
   case EArrayDecl([({expr:EMeta({meta:MetaTag.Inline,exprs:[]},{expr:EFor(_)})} => e)]):typeArrayComprehension(ctx,e,withType,p);
   case EArrayDecl(list) if(list.length>0&&switch list[0].expr {case EBinop(OpArrow,_,_):true; case _:false;}):typeMapDeclaration(ctx,list[0],list.slice(1),withType,p);
   case EArrayDecl(list):
    switch withType {
     case WithType(t,_):switch follow(t) {
      case TAbstract({aPath:{pack:["haxe","ds"],name:"Map"}},[tk,_]):
       if(list.length==0) typeExpr(ctx,{expr:ENew(makePtp({tpackage:["haxe","ds"],tname:"Map",tparams:[],tsub:null},Globals.nullPos),[]),pos:p},withType);
       else if(list.length==1&&switch list[0].expr {case EDisplay(_):true; case _:false;}) typeExpr(ctx,list[0],WithTypeTools.withType(tk)); else typeArrayDecl(ctx,list,withType,p);
      case _:typeArrayDecl(ctx,list,withType,p);
     }
     case _:typeArrayDecl(ctx,list,withType,p);
    }
   case EVars(vl):typeVars(ctx,vl,p);
   case EFor(it,e2):ForLoop.typeForLoop(ctx,TyperDisplay.handleDisplay,it,e2,NoForcedUnroll,p);
   case ETernary(e1,e2,e3):typeIf(ctx,e1,e2,e3,withType,true,p);
   case EIf(e,e1,e2):typeIf(ctx,e,e1,e2,withType,false,p);
   case EWhile(cond,body,NormalWhile):
    var old=ctx.e.inLoop,condition=typeExpr(ctx,cond,WithTypeTools.value); condition=AbstractCast.castOrUnify(ctx,ctx.t.tbool,condition,p); ctx.e.inLoop=true;
    var e=typeExpr(ctx,Expr.ensureBlock(body),NoValue); ctx.e.inLoop=old; mk(TWhile(condition,e,NormalWhile),ctx.t.tvoid,p);
   case EWhile(cond,body,DoWhile):
    var old=ctx.e.inLoop; ctx.e.inLoop=true; var e=typeExpr(ctx,Expr.ensureBlock(body),NoValue); ctx.e.inLoop=old;
    var condition=typeExpr(ctx,cond,WithTypeTools.value); condition=AbstractCast.castOrUnify(ctx,ctx.t.tbool,condition,condition.epos); mk(TWhile(condition,e,DoWhile),ctx.t.tvoid,p);
   case ESwitch(e1,cases,def):var result=Matcher.Match.matchExpr(ctx,e1,cases,def,withType,false,p); mk(TMeta({meta:MetaTag.Ast,exprs:[syntax],pos:p},result),result.etype,result.epos);
   case EReturn(e):
    if(!TyperManager.isFunctionContext(ctx)) {displayError(ctx.com,"Return outside function",p); e==null?Texpr.Builder.makeNull(terminatorType(ctx,withType,p),p):typeExpr(ctx,e,WithTypeTools.value);} else typeReturn(ctx,e,withType,p);
   case EBreak:if(!ctx.e.inLoop) displayError(ctx.com,"Break outside loop",p); mk(TBreak,terminatorType(ctx,withType,p),p);
   case EContinue:if(!ctx.e.inLoop) displayError(ctx.com,"Continue outside loop",p); mk(TContinue,terminatorType(ctx,withType,p),p);
   case ETry(e1,[]):typeExpr(ctx,e1,withType);
   case ETry(e1,catches):typeTry(ctx,e1,catches,withType,p);
   case EThrow(e):var value:Dynamic; try value=typeExpr(ctx,e,WithTypeTools.value) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some(err)):checkError(ctx,err); value=Texpr.Builder.makeNull(tDynamic,p); case _:throw exc;}} mk(TThrow(value),terminatorType(ctx,withType,p),p);
   case ENew(t,el):typeNew(ctx,t,el,withType,false,p);
   case EUnop(op,flag,e):typeUnop(ctx,op,flag,e,withType,p);
   case EFunction(kind,f):typeLocalFunction(ctx,kind,f,withType,false,p);
   case EUntyped(inner):
    var old=ctx.f.isUntyped; ctx.f.isUntyped=true;
    if(!Meta.has(MetaTag.HasUntyped,ctx.f.curfield.cfMeta)) ctx.f.curfield.cfMeta.unshift({meta:MetaTag.HasUntyped,exprs:[],pos:mkZeroRangePos(p)});
    var value=typeExpr(ctx,inner,withType); ctx.f.isUntyped=old; mk(value.eexpr,mkMono(),value.epos);
   case ECast(inner,null):var value=typeExpr(ctx,inner,WithTypeTools.value); mk(TCast(value,null),spawnMonomorph(ctx,p),p);
   case ECast(inner,t):typeCast(ctx,inner,t,p);
   case EDisplay(inner,dk):TyperDisplay.handleEdisplay(ctx,inner,dk,mode,withType);
   case ECheckType(inner,hint):var t=Typeload.loadComplexType(ctx,true,LoadAny,hint),value=typeExpr(ctx,inner,WithTypeTools.withType(t)); value=AbstractCast.castOrUnify(ctx,t,value,p); value.etype==t?value:mk(TCast(value,null),t,p);
   case EMeta(m,inner):typeMeta(ctx,m,inner,withType,p,mode);
   case EIs(inner,hint):switch hint.type {
    case CTPath(tp):
     if(tp.path.tparams.length>0) displayError(ctx.com,"Type parameters are not supported for the `is` operator",hint.pos);
     var value=typeExpr(ctx,inner,WithTypeTools.value),mt=Typeload.loadTypeDef(ctx,hint.pos,tp.path);
     if(ctx.f.inDisplay&&DisplayPosition.displayPosition.enclosedIn(hint.pos)) DisplayEmitter.displayModuleType(ctx,mt,hint.pos);
     var typeValue=TyperBase.typeModuleType(ctx,mt,hint.pos); Texpr.Builder.resolveAndMakeStaticCall(ctx.com.std,"isOfType",[value,typeValue],p);
    case _:displayError(ctx.com,"Unsupported type for `is` operator",hint.pos); Texpr.Builder.makeBool(ctx.com.basic,false,p);
   }
  };
 }
 static function __init__():Void {
  unifyMinRef=unifyMin; unifyMinForTypeSourceRef=unifyMinForTypeSource; makeCallRef=Calls.makeCall;
  TyperBase.typeCallTargetRef=typeCallTarget; TyperBase.typeAccessRef=typeAccess; typeBlockRef=typeBlock; typeExprRef=typeExpr;
 }
}
