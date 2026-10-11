// Original draft includes deferred display/cache branches.
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

// haxe/src/typing/typeload.ml — mechanical draft; not compile-validated.
enum LoadInstanceParamMode {ParamNormal; ParamSpawnMonos; ParamCustom(f:Dynamic->Null<Array<Dynamic>>->Array<Dynamic>);}
enum LoadInstanceMode {LoadNormal; LoadReturn; LoadAny;}
class Typeload {
 public static var typeFunctionParamsRef:Dynamic=function(_:Dynamic,_:Dynamic,_:Dynamic,_:Dynamic):Dynamic {throw "Uninitialized typeFunctionParamsRef";};
 public static function checkFieldAccess(ctx:Dynamic,cff:Dynamic):Dynamic {
  var displayed:Dynamic=null,acc:Array<Dynamic>=[],p0=Reflect.copy(cff.cffPos); p0.pmax=p0.pmin;
  function checkDisplay(p1:Dynamic):Void {var pmid=Reflect.copy(p0); pmid.pmin=p0.pmax; pmid.pmax=p1.pmin; if(DisplayPosition.displayPosition.enclosedIn(pmid)&&acc.length>0) displayed=acc[0];}
  for(entry in (cast cff.cffAccess:Array<Dynamic>)) {
   var access=entry.access,p1=entry.pos; checkDisplay(p1);
   var prior:Dynamic=null;
   for(a in acc) if(a.access==access) {prior=a; break;}
   if(prior!=null) {
    if(p1!=Globals.nullPos&&prior.pos!=Globals.nullPos) displayErrorExt(ctx.com,makeError(Custom("Duplicate access modifier "+Ast.sAccess(access)),p1,[makeError(Custom(complMsg("Previously defined here")),prior.pos)]));
    p0=p1; continue;
   }
   switch access {
    case APublic|APrivate:
     for(a in acc) if(a.access==APublic||a.access==APrivate) {prior=a; break;}
     if(prior!=null) displayErrorExt(ctx.com,makeError(Custom("Conflicting access modifier "+Ast.sAccess(access)),p1,[makeError(Custom(complMsg("Conflicts with this")),prior.pos)]));
     else acc.unshift(entry);
    case _:acc.unshift(entry);
   }
   p0=p1;
  }
  checkDisplay(cff.cffName.pos); return displayed;
 }
 public static function findTypeInModule(m:Dynamic,name:String):Dynamic {for(mt in (cast m.mTypes:Array<Dynamic>)) {var info=tInfos(mt); if(!info.mtPrivate&&info.mtPath.name==name) return mt;} throw "Not_found";}
 public static function findTypeInModuleRaise(ctx:Dynamic,m:Dynamic,name:String,p:Dynamic):Dynamic {
  for(mt in (cast m.mTypes:Array<Dynamic>)) {var info=tInfos(mt); if(info.mtPath.name==name) {if(ctx.m.curmod!=info.mtModule&&info.mtPrivate) raiseTypingErrorExt(makeError(TypeNotFound(m.mPath,name,PrivateType),p)); return mt;}}
  return raiseTypingErrorExt(makeError(TypeNotFound(m.mPath,name,NotDefined),p));
 }
 public static function findTypeInCurrentModuleContext(ctx:Dynamic,pack:Array<String>,name:String):Dynamic {
  if(pack.length==0) {
   for(mt in (cast ctx.m.curmod.mTypes:Array<Dynamic>)) if(tName(mt)==name) return mt;
   var found=ctx.m.importResolution.findTypeImport(name); ImportHandling.markImportPosition(ctx,found.pos); return found.type;
  }
  for(mt in (cast ctx.m.curmod.mTypes:Array<Dynamic>)) if(tPath(mt)=={pack:pack,name:name}) return mt;
  throw "Not_found";
 }
 public static function findInWildcardImports(ctx:Dynamic,mname:String,p:Dynamic,f:Dynamic->Dynamic):Dynamic {
  for(entry in (cast ctx.m.importResolution.extractWildcardPackages():Array<Dynamic>)) try {
   var path={pack:entry.pack,name:mname},m:Dynamic;
   try m=ctx.g.doLoadModule(ctx,path,p) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some({errMessage:ModuleNotFound(mpath)})) if(mpath==path):throw "Not_found"; case _:throw exc;}}
   var result=f(m); ImportHandling.markImportPosition(ctx,entry.pos); return result;
  } catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
  throw "Not_found";
 }
 public static function findInModulesStartingFromCurrentPackage(ctx:Dynamic,mname:String,p:Dynamic,f:Dynamic->Dynamic):Dynamic {
  var pack:Array<String>=ctx.m.curmod.mPath.pack.copy(),m:Dynamic;
  while(true) {
   var path={pack:pack,name:mname};
   try {m=ctx.g.doLoadModule(ctx,path,p); break;} catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some({errMessage:ModuleNotFound(mpath)})) if(mpath==path):if(pack.length==0) throw "Not_found"; pack=pack.slice(0,pack.length-1); case _:throw exc;}}
  }
  return f(m);
 }
 public static function findInUnqualifiedModules(ctx:Dynamic,name:String,p:Dynamic,f:Dynamic->Dynamic):Dynamic {try return findInWildcardImports(ctx,name,p,f) catch(exc:Dynamic) {if(exc!="Not_found") throw exc; return findInModulesStartingFromCurrentPackage(ctx,name,p,f);}}
 public static function loadUnqualifiedTypeDef(ctx:Dynamic,mname:String,tname:String,p:Dynamic):Dynamic {try return findInUnqualifiedModules(ctx,mname,p,m -> findTypeInModuleRaise(ctx,m,tname,p)) catch(exc:Dynamic) {if(exc!="Not_found") throw exc; return raiseErrorMsg(ModuleNotFound({pack:[],name:mname}),p);}}
 public static function loadModule(ctx:Dynamic,path:Dynamic,p:Dynamic):Dynamic {
  try return ctx.g.doLoadModule(ctx,path,p) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some({errMessage:ModuleNotFound(mpath)})) if(mpath==path&&path.pack.length>0&&path.pack[0]=="std"):return ctx.g.doLoadModule(ctx,{pack:path.pack.slice(1),name:path.name},p); case _:throw exc;}}
 }
 public static function loadQualifiedTypeDef(ctx:Dynamic,pack:Array<String>,mname:String,tname:String,p:Dynamic):Dynamic return findTypeInModuleRaise(ctx,loadModule(ctx,{pack:pack,name:mname},p),tname,p);
 public static function loadTypeDefPrime(ctx:Dynamic,pack:Array<String>,mname:String,tname:String,p:Dynamic):Dynamic return pack.length==0?loadUnqualifiedTypeDef(ctx,mname,tname,p):loadQualifiedTypeDef(ctx,pack,mname,tname,p);
 public static function loadTypeDef(ctx:Dynamic,p:Dynamic,t:Dynamic):Dynamic {
  if(t==Parser.magicTypePath) raiseFields(DisplayToplevel.collect(ctx,TKType,NoValue,true),CRTypeHint,DisplayTypes.makeSubject(null,p));
  var name=t.tsub==null?t.tname:t.tsub;
  try {if(t.tsub!=null) throw "Not_found"; return findTypeInCurrentModuleContext(ctx,t.tpackage,name);} catch(exc:Dynamic) {if(exc!="Not_found") throw exc; return loadTypeDefPrime(ctx,t.tpackage,t.tname,name,p);}
 }
 public static function generateArgsMeta(com:Dynamic,cls:Dynamic,addMeta:Dynamic->Void,args:Array<Dynamic>):Void {
  var values=[];
  for(arg in args) if(arg.expr!=null) values.unshift({name:{name:arg.name.name,pos:arg.name.pos,quotes:NoQuotes},expr:arg.expr});
  if(values.length>0) addMeta({meta:MetaTag.Value,exprs:[{expr:EObjectDecl(values),pos:Globals.nullPos}],pos:Globals.nullPos});
  if(args.exists(arg -> arg.meta.length>0)) addMeta({meta:MetaTag.HaxeArguments,exprs:[{expr:EFunction(FKAnonymous,{fParams:[],fArgs:args,fType:null,fExpr:null}),pos:Globals.nullPos}],pos:Globals.nullPos});
 }
 public static function isRedefined(ctx:Dynamic,cf1:Dynamic,fields:Dynamic,p:Dynamic):Bool {
  if(!fields.exists(cf1.cfName)) return false;
  var cf2=fields.get(cf1.cfName),pc=printContext();
  if(!typeIseq(cf1.cfType,cf2.cfType)) raiseTypingErrorExt(makeError(Custom("Cannot redefine field "+cf1.cfName+" with different type"),p,[makeError(Custom(complMsg("Second type was "+sType(pc,cf2.cfType))),cf2.cfPos),makeError(Custom(complMsg("First type was "+sType(pc,cf1.cfType))),cf1.cfPos)]));
  return true;
 }
 public static function makeExtensionType(ctx:Dynamic,tl:Array<Dynamic>):Dynamic {
  var fields=PMap.empty();
  for(pair in tl) switch follow(pair.type) {
   case TAnon(a):a.aFields.iter(function(_:String,cf:Dynamic) {if(!isRedefined(ctx,cf,fields,pair.pos)) fields=fields.add(cf.cfName,cf);});
   case _:displayError(ctx.com,"Can only extend structures",pair.pos); fields=PMap.empty();
  }
  return mkAnon({value:Extend(tl.map(pair -> pair.type))},fields);
 }
 public static function checkParamConstraints(ctx:Dynamic,t:Dynamic,map:Dynamic->Dynamic,ttp:Dynamic,p:Dynamic):Void {
  for(ti in (cast getConstraints(ttp):Array<Dynamic>)) {
   var mapped=map(ti);
   try unifyRaise(t,mapped,p) catch(exc:Dynamic) {switch exc {
    case (core.ds.ExceptionTools.typing(_) => Some(err)):switch err.errMessage {
     case Unify(l):
      function fail():Void {if(!ctx.f.isUntyped) {var copy=Reflect.copy(err); copy.errMessage=Unify([ConstraintFailure(Globals.sTypePath(ttp.ttpClass.clPath))].concat(l)); displayErrorExt(ctx.com,copy);}}
      switch follow(t) {
       case TInst({clKind:KExpr(e)},_):var local=TyperManager.cloneForTypeParameterExpression(ctx),e=typeExpr(local,e,WithTypeTools.withType(mapped)); try unifyRaise(e.etype,mapped,p) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.typing(_) => Some({errMessage:Unify(_)})):fail(); case _:throw exc;}}
       case _:fail();
      }
     case _:throw exc;
    }
    case _:throw exc;
   }}
  }
 }
 public static function maybeBuildInstance(ctx:Dynamic,t0:Dynamic,getParams:LoadInstanceParamMode,p:Dynamic):Dynamic {
  function loop(t:Dynamic):Dynamic return switch t {
   case TInst(({clKind:KGeneric} => c),tl):var info=ctx.g.getBuildInfo(ctx,TClassDecl(c),p); var params=switch getParams {case ParamNormal|ParamSpawnMonos:tl; case ParamCustom(f):f(info,tl);}; maybeBuildInstance(ctx,info.buildApply(params),getParams,p);
   case TType(td,tl):loop(applyTypedef(td,tl));
   case TMono(m) if(m.tmType!=null):loop(m.tmType);
   case _:t0;
  };
  return loop(t0);
 }
 public static function loadParams(ctx:Dynamic,info:Dynamic,params:Array<Dynamic>,p:Dynamic):Array<Dynamic> {
  var rest=info.buildKind==BuildGenericBuild&&info.buildParams.length==1&&info.buildParams[0].ttpName=="Rest",javaRest=ctx.com.platform==Jvm&&info.buildExtern; rest=rest||javaRest;
  function loadParam(param:Dynamic,ttp:Dynamic):Dynamic return switch param {
   case TPExpr(e):
    var name=switch e.expr {case EConst(String(s,_)):"S"+s; case EConst((Int(_) => c)):"I"+sConstant(c); case EConst((Float(_) => c)):"F"+sConstant(c); case EDisplay(_):typeExpr(ctx,e,WithTypeTools.value); "Expr"; case _:"Expr";};
    var c=mkClass(ctx.m.curmod,{pack:[],name:name},p,e.pos); c.clKind=KExpr(e); {type:TInst(c,[]),pos:e.pos};
   case TPType({type:CTPath({path:{tpackage:["$"],tname:"_hx_default"}}),pos:p}):
    if(ttp!=null&&ttp.ttpDefault!=null) {type:ttp.ttpDefault,pos:p};
    else if(ttp!=null) raiseTypingError("Invalid default, type parameter "+ttp.ttpName+" has no default value",p);
    else if(rest) raiseTypingError("Cannot use default with rest type parameters",p);
    else raiseTypingError("Too many type parameters for "+Globals.sTypePath(info.buildPath),p);
   case TPType(t):{type:loadComplexType(ctx,true,LoadNormal,t),pos:t.pos};
  };
  var checks=[];
  function loop(inputs:Array<Dynamic>,expected:Array<Dynamic>,isRest:Bool):Array<Dynamic> {
   if(inputs.length>0&&expected.length>0) {
    var ttp=expected[0],name=ttp.ttpName,loaded=loadParam(inputs[0],ttp),t=loaded.type;
    var expression=switch t {case TInst({clKind:KExpr(_)},_):true; case _:false;},expects=name=="Const"||Meta.has(MetaTag.Const,ttp.ttpClass.clMeta),accepts=name=="Rest";
    if(expression) {if(!expects&&!accepts) raiseTypingError("Constant value unexpected here",p);} else if(expects) raiseTypingError("Type parameter is expected to be a constant value",p);
    isRest=isRest||(name=="Rest"&&info.buildKind==BuildGenericBuild);
    var generic=switch info.buildKind {case BuildGeneric(_):true; case _:false;};
    if(ttp.ttpConstraints!=null||generic) checks.push({type:t,param:ttp,pos:loaded.pos});
    return [t].concat(loop(inputs.slice(1),expected.slice(1),isRest));
   }
   if(inputs.length==0&&expected.length==0) return [];
   if(inputs.length==0) {
    if(expected.length==1&&expected[0].ttpName=="Rest"&&info.buildKind==BuildGenericBuild) return [];
    var ttp=expected[0],t:Dynamic;
    if(javaRest) t=tDynamic; else if(ttp.ttpDefault!=null) t=ttp.ttpDefault; else if(ignoreError(ctx.com)) t=ttp.ttpType; else return raiseTypingError("Not enough type parameters for "+Globals.sTypePath(info.buildPath),p);
    return [t].concat(loop([],expected.slice(1),isRest));
   }
   var loaded=loadParam(inputs[0],null);
   if(isRest) return [loaded.type].concat(loop(inputs.slice(1),[],true));
   if(ignoreError(ctx.com)) return [];
   return raiseTypingError("Too many type parameters for "+Globals.sTypePath(info.buildPath),loaded.pos);
  }
  var result=loop(params,info.buildParams,false);
  if(!rest) {
   function map(t:Dynamic):Dynamic return maybeBuildInstance(ctx,applyParams(info.buildParams,result,t),ParamNormal,p);
   delay(ctx.g,PCheckConstraint,function() {for(check in checks) checkParamConstraints(ctx,check.type,map,check.param,check.pos);});
  }
  return result;
 }
 public static function loadInstancePrime(ctx:Dynamic,ptp:Dynamic,getParams:LoadInstanceParamMode,mode:LoadInstanceMode):Dynamic {
  var t=ptp.path;
  try {
   if(t.tpackage.length!=0||t.tsub!=null) throw "Not_found";
   var pt=lookupParam(t.tname,ctx.typeParams); if(t.tparams.length!=0) raiseTypingError("Class type parameter "+t.tname+" can't have parameters",ptp.posFull); return pt;
  } catch(exc:Dynamic) {if(exc!="Not_found") throw exc;}
  var mt=loadTypeDef(ctx,ptp.posPath,t),info=ctx.g.getBuildInfo(ctx,mt,ptp.posFull);
  if(info.buildPath.pack.length==0&&info.buildPath.name=="Dynamic") return switch t.tparams {case []:tDynamic; case [TPType(t)]:TDynamic(loadComplexType(ctx,true,LoadNormal,t)); case _:raiseTypingError("Too many parameters for Dynamic",ptp.posFull);};
  if(info.buildParams.length==0) {
   if(t.tparams.length>0) {var pos=switch t.tparams[0] {case TPType(t):t.pos; case TPExpr(e):e.pos;}; displayError(ctx.com,"Too many type parameters for "+Globals.sTypePath(info.buildPath),pos);}
   return info.buildApply([]);
  }
  var rest=info.buildKind==BuildGenericBuild&&info.buildParams.length==1&&info.buildParams[0].ttpName=="Rest";
  var tl=if(t.tparams.length==0&&!rest) switch getParams {case ParamNormal:loadParams(ctx,info,t.tparams,ptp.posFull); case ParamSpawnMonos:Monomorph.spawnConstrainedMonos(t -> t,info.buildParams); case ParamCustom(f):f(info,null);} else loadParams(ctx,info,t.tparams,ptp.posFull);
  return maybeBuildInstance(ctx,info.buildApply(tl),getParams,ptp.posFull);
 }
 public static function loadInstance(ctx:Dynamic,ptp:Dynamic,getParams:LoadInstanceParamMode,mode:LoadInstanceMode,allowDisplay:Bool=false):Dynamic {
  try {var t=loadInstancePrime(ctx,ptp,getParams,mode); if(allowDisplay) DisplayEmitter.checkDisplayType(ctx,t,ptp); return t;}
  catch(exc:Dynamic) {switch exc {
   case (core.ds.ExceptionTools.typing(_) => Some({errMessage:ModuleNotFound(path)})) if(ctx.e.macroDepth<=0&&ctx.com.display.dmsKind==DMDefault&&DisplayPosition.displayPosition.enclosedIn(ptp.posPath)):return DisplayToplevel.collectAndRaise(ctx,TKType,NoValue,CRTypeHint,{name:Globals.sTypePath(path),pos:ptp.posFull},ptp.posPath);
   case _:throw exc;
  }}
 }
 static function structCompletion(e:Dynamic,intersection:Bool):Dynamic {
  switch e {case DisplayException(DisplayFields(({fkind:CRTypeHint} => r))):var items=(cast r.fitems:Array<Dynamic>).filter(item -> switch item.ciKind {case ITType({kind:Struct},_):true; case _:false;}); return raiseFields(items,CRStructExtension(intersection),r.fsubject); case _:throw e;}
 }
 public static function loadComplexTypePrime(ctx:Dynamic,allowDisplay:Bool,mode:LoadInstanceMode,hint:Dynamic):Dynamic {
  var p=hint.pos;
  return switch hint.type {
   case CTParent(t):loadComplexType(ctx,allowDisplay,mode,t);
   case CTPath({path:{tpackage:["$"],tname:"_hx_mono"}}):spawnMonomorph(ctx,p);
   case CTPath({path:{tpackage:["$"],tname:"_hx_default"}}):raiseTypingError("Invalid type : default",p);
   case CTPath(ptp):loadInstance(ctx,ptp,ParamNormal,mode,allowDisplay);
   case CTOptional(_):raiseTypingError("Optional type not allowed here",p);
   case CTNamed(_):raiseTypingError("Named type not allowed here",p);
   case CTIntersection(tl):
    var loaded=tl.map(function(t) {try return {type:loadComplexType(ctx,allowDisplay,LoadNormal,t),pos:t.pos} catch(e:Dynamic) return structCompletion(e,true);});
    var tr=Monomorph.create(),t=TMono(tr),r=makeLazy(ctx.g,t,function() {var ta=makeExtensionType(ctx,loaded); Monomorph.bind(tr,ta); return ta;},"constraint"); TLazy(r);
   case CTExtend(tl,fields):
    var ta=loadComplexType(ctx,allowDisplay,LoadNormal,{type:CTAnonymous(fields),pos:p});
    var a=switch ta {case TAnon(a):a; case _:throw "Invalid anonymous extension";};
    function extension(pair:Dynamic):Dynamic return switch follow(pair.type) {
     case TInst({clKind:KTypeParameter(_)},_):raiseTypingError("Cannot structurally extend type parameters",pair.pos);
     case TMono(_):raiseTypingError("Loop found in cascading signatures definitions. Please change order/import",pair.pos);
     case TAnon(a2):
      a.aFields.iter(function(_:String,cf:Dynamic) isRedefined(ctx,cf,a2.aFields,pair.pos));
      var fields=a2.aFields; a.aFields.iter(function(name:String,cf:Dynamic) {fields=fields.add(name,cf);}); mkAnon({value:Extend([pair.type])},fields);
     case _:raiseTypingError("Can only extend structures",pair.pos);
    };
    function merge(pair:Dynamic):Void switch follow(pair.type) {case TAnon(a2):a2.aFields.iter(function(name:String,cf:Dynamic) {if(!isRedefined(ctx,cf,a.aFields,pair.pos)) a.aFields=a.aFields.add(name,cf);}); case _:raiseTypingError("Can only extend structures",pair.pos);}
    var instances=tl.map(function(ptp) {try return {type:loadInstance(ctx,ptp,ParamNormal,LoadNormal,allowDisplay),pos:ptp.posFull} catch(e:Dynamic) return structCompletion(e,false);});
    var tr=Monomorph.create(),t=TMono(tr),r=makeLazy(ctx.g,t,function() {
     var result:Dynamic;
     if(instances.length==1) result=extension(instances[0]); else {for(instance in instances) merge(instance); a.aStatus.value=Extend(instances.map(pair -> pair.type)); result=ta;}
     Monomorph.bind(tr,result); return t;
    },"constraint"); TLazy(r);
   case CTAnonymous(list):
    var displayed:Dynamic=null,fields=PMap.empty();
    for(f in list) {
     var name=f.cffName.name,pf=f.cffName.pos,p=f.cffPos;
     if(fields.exists(name)) raiseTypingError("Duplicate field declaration : "+name,pf);
     function optionalType(mode:LoadInstanceMode,t:Dynamic):Dynamic {if(t==null) return raiseTypingError("Explicit type required for field "+name,p); return loadComplexType(ctx,allowDisplay,mode,t);}
     if(name=="new") warning(ctx,WDeprecated,"Structures with new are deprecated, use haxe.Constraints.Constructible instead",p);
     function noExpr(e:Dynamic):Void {if(e!=null) raiseTypingError("Expression not allowed here",e.pos);}
     var pub=true,dyn=false,params:Array<Dynamic>=[],isFinal=false;
     checkFieldAccess(ctx,f);
     for(access in (cast f.cffAccess:Array<Dynamic>)) switch access.access {
      case APublic:
      case APrivate:if(haxe.io.Path.withoutDirectory(access.pos.pfile)!="NativeIterable.hx") warning(ctx,WDeprecated,"private structure fields are deprecated",access.pos); pub=false;
      case ADynamic if(switch f.cffKind {case FFun(_):true; case _:false;}):dyn=true;
      case AFinal:isFinal=true;
      case a:raiseTypingError("Invalid access "+Ast.sAccess(a),p);
     }
     var t:Dynamic,kind:Dynamic;
     switch f.cffKind {
      case FVar(type,e) if(isFinal):noExpr(e); if(type==null) raiseTypingError("Type required for structure property",p); t=loadComplexType(ctx,allowDisplay,LoadNormal,type); kind=Var({vRead:AccNormal,vWrite:AccNever});
      case FVar({type:CTPath({path:{tpackage:[],tname:"Void"}})},_)|FProp(_,_,{type:CTPath({path:{tpackage:[],tname:"Void"}})},_):raiseTypingError("Fields of type Void are not allowed in structures",p);
      case FVar(type,e):noExpr(e); t=optionalType(LoadNormal,type); kind=Var({vRead:AccNormal,vWrite:AccNormal});
      case FFun(fd):
       params=typeFunctionParamsRef(ctx,fd,TPHAnonField,name); noExpr(fd.fExpr); var old=ctx.typeParams; ctx.typeParams=params.concat(old);
       var args=fd.fArgs.map(function(arg) {noExpr(arg.expr); return {name:arg.name.name,optional:arg.optional,type:optionalType(LoadNormal,arg.type)};});
       var ret=optionalType(LoadReturn,fd.fType); t=Meta.has(MetaTag.Coroutine,f.cffMeta)?AtomicLazy.force(ctx.t.tcoro.tcoro)(args,ret):TFun({args:args,ret:ret}); ctx.typeParams=old; kind=Method(dyn?MethDynamic:MethNormal);
      case FProp(i1,i2,type,e):
       noExpr(e);
       function property(part:Dynamic,get:Bool):Dynamic return switch part.name {
        case "null":AccNo; case "never":AccNever; case "default":AccNormal; case "dynamic":AccCall;
        case "get" if(get):AccCall; case "set" if(!get):AccCall; case "private get" if(get):AccPrivateCall; case "private set" if(!get):AccPrivateCall;
        case x if((get&&x=="get_"+name)||(!get&&x=="set_"+name)):AccCall;
        case _:raiseTypingError("Custom property access is no longer supported in Haxe 3",f.cffPos);
       };
       if(type==null) raiseTypingError("Type required for structure property",p);
       t=loadComplexType(ctx,allowDisplay,LoadNormal,type); kind=Var({vRead:property(i1,true),vWrite:property(i2,false)});
     }
     if(Meta.has(MetaTag.Optional,f.cffMeta)) t=ctx.t.tnull(t);
     var cf=mkField(name,t,p,f.cffName.pos,pub); cf.cfKind=kind; cf.cfParams=params; cf.cfDoc=f.cffDoc; cf.cfMeta=f.cffMeta;
     if(isFinal) addClassFieldFlag(cf,CfFinal); initMetaOverloads(ctx,null,cf);
     if(ctx.m.isDisplayFile) {DisplayEmitter.checkDisplayMetadata(ctx,cf.cfMeta); if(DisplayPosition.displayPosition.enclosedIn(cf.cfNamePos)) displayed=cf;}
     fields=fields.add(name,cf);
    }
    var a={aFields:fields,aStatus:{value:Closed}};
    if(displayed!=null) {var cf=displayed; delay(ctx.g,PBuildClass,function() DisplayEmitter.displayField(ctx,AnonymousStructure(a),CFSMember,cf,cf.cfNamePos));}
    TAnon(a);
   case CTFunction(args,ret):
    var voidArg=args.length==1&&switch args[0].type {case CTPath({path:{tpackage:[],tparams:[],tname:"Void"}}):true; case _:false;};
    if(voidArg) TFun({args:[],ret:loadComplexType(ctx,allowDisplay,LoadReturn,ret)});
    else {
     var typed=args.map(function(t) {
      var opt=false,name="";
      switch t.type {case CTOptional(inner)|CTParent({type:CTOptional(inner)}):t=inner; opt=true; case _:}
      switch t.type {case CTNamed(n,inner):name=n.name; t=inner; case _:}
      return {name:name,optional:opt,type:loadComplexType(ctx,allowDisplay,LoadNormal,t)};
     });
     TFun({args:typed,ret:loadComplexType(ctx,allowDisplay,LoadReturn,ret)});
    }
  };
 }
 public static function loadComplexType(ctx:Dynamic,allowDisplay:Bool,mode:LoadInstanceMode,hint:Dynamic):Dynamic {
  try return loadComplexTypePrime(ctx,allowDisplay,mode,hint) catch(exc:Dynamic) {switch exc {
   case (core.ds.ExceptionTools.typing(_) => Some(err)):switch err.errMessage {
    case ModuleNotFound({pack:[],name:name}) if(Diagnostics.errorInDiagnosticsRun(ctx.com,err.errPos)):delay(ctx.g,PForce,function() DisplayToplevel.handleUnresolvedIdentifier(ctx,name,err.errPos,true)); return tDynamic;
    case _:throw exc;
   }
   case _:throw exc;
  }}
 }
 public static function initMetaOverloads(ctx:Dynamic,co:Dynamic,cf:Dynamic):Void {
  var overloads=[],baseMeta=(cast cf.cfMeta:Array<Dynamic>).filter(m -> m.meta!=MetaTag.Overload&&m.meta!=MetaTag.Value),kept=[];
  for(m in (cast cf.cfMeta:Array<Dynamic>)) switch m {
   case {meta:MetaTag.Overload,exprs:[{expr:EFunction(kind,f),pos:p}]}:
    switch kind {case FKNamed(_):raiseTypingError("Function name must not be part of @:overload",p); case _:}
    switch f.fExpr {case {expr:EBlock([])}: case _:raiseTypingError("Overload must only declare an empty method body {}",p);}
    switch cf.cfKind {case Method(MethInline):raiseTypingError("Cannot @:overload inline function",p); case _:}
    var old=ctx.typeParams; if(cf.cfParams.length>0) ctx.typeParams=(cast ctx.typeParams:Array<Dynamic>).filter(ttp -> ttp.ttpHost!=TPHMethod);
    var params=typeFunctionParamsRef(ctx,f,TPHMethod,cf.cfName); ctx.typeParams=params.concat(ctx.typeParams);
    function optionalType(mode:LoadInstanceMode,t:Dynamic):Dynamic {if(t==null) return raiseTypingError("Explicit type required",p); return loadComplexType(ctx,true,mode,t);}
    var args=f.fArgs.map(function(arg) {var t=optionalType(LoadNormal,arg.type); if(arg.optional) t=ctx.t.tnull(t); return {name:arg.name.name,optional:arg.optional||arg.expr!=null,type:t};});
    var overloadField=Reflect.copy(cf); overloadField.cfType=TFun({args:args,ret:optionalType(LoadReturn,f.fType)}); overloadField.cfParams=params; overloadField.cfMeta=baseMeta.copy();
    generateArgsMeta(ctx.com,co,m -> overloadField.cfMeta.unshift(m),f.fArgs); overloads.unshift(overloadField); ctx.typeParams=old;
   case {meta:MetaTag.Overload,exprs:[]} if(ctx.com.config.pfOverload):
    addClassFieldFlag(cf,CfOverload);
    switch follow(cf.cfType) {case TFun({args:args,ret:_}):for(arg in args) switch arg.type {case TMono(t) if(t.tmType==null):raiseTypingError("Explicit type required for overload functions\n... For function argument '"+arg.name+"'",cf.cfPos); case _:} case _:}
    kept.push(m);
   case {meta:MetaTag.Overload,exprs:[],pos:p}:raiseTypingError("This platform does not support this kind of overload declaration. Try @:overload(function()... {}) instead",p);
   case {meta:MetaTag.Overload,pos:p}:raiseTypingError("Invalid @:overload metadata format",p);
   case _:kept.push(m);
  }
  cf.cfMeta=kept; overloads.reverse(); cf.cfOverloads=overloads;
 }
 public static function tIterator(ctx:Dynamic,p:Dynamic):Dynamic return switch loadQualifiedTypeDef(ctx,[],"StdTypes","Iterator",p) {case TTypeDecl(t):addDependency(ctx.m.curmod,t.tModule,MDepFromTyping); var pt=spawnMonomorph(ctx,p); {type:applyTypedef(t,[pt]),parameter:pt}; case _:throw "Iterator is not a typedef";};
 public static function loadTypeHint(ctx:Dynamic,pcur:Dynamic,mode:LoadInstanceMode,t:Dynamic,opt:Bool=false):Dynamic {var type=t==null?spawnMonomorph(ctx,pcur):loadComplexType(ctx,true,mode,t); return opt?ctx.t.tnull(type):type;}
 public static function typeTypeParam(ctx:Dynamic,host:Dynamic,path:Dynamic,tp:Dynamic):Dynamic {
  var name=tp.tpName.name,c=mkClass(ctx.m.curmod,{pack:path.pack.concat([path.name]),name:name},tp.tpName.pos,tp.tpName.pos);
  c.clParams=typeTypeParams(ctx,host,c.clPath,tp.tpParams); c.clMeta=tp.tpMeta; var ttp=mkTypeParam(c,host,null,null);
  if(ctx.m.isDisplayFile&&DisplayPosition.displayPosition.enclosedIn(tp.tpName.pos)) DisplayEmitter.displayType(ctx,ttp.ttpType,tp.tpName.pos); return ttp;
 }
 public static function typeTypeParams(ctx:Dynamic,host:Dynamic,path:Dynamic,tpl:Array<Dynamic>):Array<Dynamic> {
  var names:Array<String>=[],pairs=[];
  for(tp in tpl) {if(names.contains(tp.tpName.name)) displayError(ctx.com,"Duplicate type parameter name: "+tp.tpName.name,tp.tpName.pos); names.unshift(tp.tpName.name); pairs.push({syntax:tp,param:typeTypeParam(ctx,host,path,tp)});}
  var params=pairs.map(pair -> pair.param),local=TyperManager.cloneForTypeParams(ctx,params.concat(ctx.typeParams));
  for(pair in pairs) {
   var tp=pair.syntax,ttp=pair.param;
   if(tp.tpDefault!=null) {
    var ct=tp.tpDefault,r=makeLazy(local.g,ttp.ttpType,function() {
     var t=loadComplexType(local,true,LoadNormal,ct);
     switch host {case TPHType: case TPHConstructor|TPHMethod|TPHEnumConstructor|TPHAnonField|TPHLocal|TPHUnbound:displayError(local.com,"Default type parameters are only supported on types",ct.pos);}
     checkParamConstraints(local,t,t -> t,ttp,ct.pos); return t;
    },"default"); ttp.ttpDefault=TLazy(r);
   }
   if(tp.tpConstraints!=null) {
    var th=tp.tpConstraints,constraints=AtomicLazy.fromFun(function() {
     function load(th:Dynamic):Array<Dynamic> return switch th.type {case CTIntersection(tl):tl.map(t -> loadComplexType(local,true,LoadNormal,t)); case CTParent(ct):load(ct); case _:[loadComplexType(local,true,LoadNormal,th)];};
     var constr=load(th);
     function check(t:Dynamic):Void switch follow(t) {case TInst(c2,_) if(ttp.ttpClass==c2):raiseTypingError("Recursive constraint parameter is not allowed",th.pos); case TInst({clKind:KTypeParameter(param)},_):delay(local.g,PConnectField,function() {for(t in (cast getConstraints(param):Array<Dynamic>)) check(t);}); case _:}
     for(t in constr) check(t); return constr;
    });
    delay(local.g,PConnectField,function() {AtomicLazy.force(constraints);}); ttp.ttpConstraints=constraints;
   }
  }
  return params;
 }
 public static function loadCoreClass(ctx:Dynamic,c:Dynamic):Dynamic {
  var ctx2=ctx.g.coreApi;
  if(ctx2==null) {
   var com2=Common.clone(ctx.com,ctx.com.isMacroContext); enterStage(com2,CInitMacrosDone); com2.defines.values=PMap.empty();
   Common.define(com2,Define.CoreApi); Common.define(com2,Define.Sys); allowPackage(com2,"sys"); Define.rawDefineValue(com2.defines,"target.threaded","true");
   if(ctx.com.isMacroContext) Common.define(com2,Define.Macro);
   com2.classPaths.lockContext(ctx.com.customExt,platformNameMacro(ctx.com),true);
   com2.classPaths.modify(function(cp) return switch cp.scope {case Std:[cp.clone()]; case _:[];},ctx.com.classPaths.asList());
   if(com2.display.dmsCheckCoreApi) {var copy=Reflect.copy(com2.display); copy.dmsCheckCoreApi=false; com2.display=copy;}
   CommonCache.lockSignature(com2,"load_core_class"); CommonCache.getCache(ctx.com).addChild(CommonCache.getCacheSign(com2));
   ctx2=createContextRef(com2,ctx.g.macros); ctx.g.coreApi=ctx2;
  }
  var path=switch c.clKind {case KAbstractImpl(a):a.aPath; case _:c.clPath;};
  var t=loadTypeDefPrime(ctx2,c.clModule.mPath.pack,c.clModule.mPath.name,path.name,Globals.nullPos);
  flushPass(ctx2.g,PFinal,{name:"core_final",path:c.clPath.pack.concat([c.clPath.name])});
  return switch t {case TClassDecl(ccore):ccore; case TAbstractDecl(a) if(a.aImpl!=null):a.aImpl; case _:throw "Invalid core class";};
 }
 public static function initCoreApi(ctx:Dynamic,c:Dynamic):Void {
  var core=loadCoreClass(ctx,c),cp:Array<Dynamic>=core.clParams,params:Array<Dynamic>=c.clParams;
  if(cp.length!=params.length) raiseTypingError("Class must have the same number of type parameters as core type",c.clPos);
  for(i in 0...cp.length) {
   var a:Array<Dynamic>=getConstraints(cp[i]),b:Array<Dynamic>=getConstraints(params[i]);
   if(a.length!=b.length) raiseTypingError("Type parameters must have the same number of constraints as core type",c.clPos);
   try for(j in 0...a.length) typeEq(EqCoreType,b[j],a[j]) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.unification(_) => Some(l)):displayErrorExt(ctx.com,makeError(Custom("Type parameter "+params[i].ttpName+" has different constraint than in core type"),c.clPos,[makeError(Custom(complMsg(errorMsg(Unify(l)))),c.clPos)])); case _:throw exc;}}
  }
  if(c.clDoc==null) c.clDoc=core.clDoc;
  function compare(f:Dynamic,f2:Dynamic):Void {
   var p=f2.cfExpr==null?c.clPos:f2.cfExpr.epos;
   try typeEq(EqCoreType,applyParams(core.clParams,extractParamTypes(c.clParams),f.cfType),f2.cfType) catch(exc:Dynamic) {switch exc {case (core.ds.ExceptionTools.unification(_) => Some(l)):displayErrorExt(ctx.com,makeError(Custom("Field "+f.cfName+" has different type than in core type"),p,[makeError(Custom(complMsg(errorMsg(Unify(l)))),p)])); case _:throw exc;}}
   if(hasClassFieldFlag(f2,CfPublic)!=hasClassFieldFlag(f,CfPublic)) raiseTypingError("Field "+f.cfName+" has different visibility than core type",p);
   if(f2.cfDoc==null) f2.cfDoc=f.cfDoc;
   if(f2.cfKind!=f.cfKind) switch [f2.cfKind,f.cfKind] {case [Method(MethInline),Method(MethNormal)]|[Method(MethNormal),Method(MethInline)]: case _:raiseTypingError("Field "+f.cfName+" has different property access than core type",p);}
   switch [followWithCoro(f.cfType),followWithCoro(f2.cfType)] {
    case [Coro(_),NotCoro(_)]:raiseTypingError("Method should be coroutine",p);
    case [NotCoro(_),Coro(_)]:raiseTypingError("Method should not be coroutine",p);
    case [NotCoro(TFun({args:pl1,ret:_})),NotCoro(TFun({args:pl2,ret:_}))]|[Coro(pl1,_),Coro(pl2,_)]:
     if(pl1.length!=pl2.length) raiseTypingError("Argument count mismatch",p);
     for(i in 0...pl1.length) if(pl1[i].name!=pl2[i].name) raiseTypingError("Method parameter name '"+pl2[i].name+"' should be '"+pl1[i].name+"'",p);
    case _:
   }
  }
  function checkFields(expected:Dynamic,actual:Dynamic):Void {
   expected.iter(function(name:String,f:Dynamic) {if(hasClassFieldFlag(f,CfPublic)) {var f2=actual.get(f.cfName); if(f2==null) raiseTypingError("Missing field "+name+" required by core type",c.clPos); compare(f,f2);}});
   actual.iter(function(name:String,f:Dynamic) {var p=f.cfExpr==null?c.clPos:f.cfExpr.epos; if(hasClassFieldFlag(f,CfPublic)&&!Meta.has(MetaTag.Hack,f.cfMeta)&&!expected.exists(f.cfName)&&!hasClassFieldFlag(f,CfOverride)) raiseTypingError("Public field "+name+" is not part of core type",p);});
  }
  checkFields(core.clFields,c.clFields); checkFields(core.clStatics,c.clStatics);
  var a=core.clConstructor,b=c.clConstructor;
  if(a==null&&b==null) return;
  if(a!=null&&!hasClassFieldFlag(a,CfPublic)) return;
  if(a!=null&&b!=null) {compare(a,b); return;}
  if(a==null&&b!=null&&!hasClassFieldFlag(b,CfPublic)) return;
  raiseTypingError("Constructor differs from core type",c.clPos);
 }
}
