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
import context.AbstractCast;
import context.TyperManager;
import typing.FieldAccess.*;

// haxe/src/typing/typerBase.ml — mechanical draft; not compile-validated.
enum AccessKind {
 AKNo(access:AccessKind,pos:Dynamic);
 AKExpr(e:Dynamic);
 AKSafeNav(sn:SafeNavAccess);
 AKField(fa:Dynamic);
 AKAccessor(fa:Dynamic);
 AKUsingField(sea:Dynamic);
 AKUsingAccessor(sea:Dynamic);
 AKAccess(a:Dynamic,params:Array<Dynamic>,c:Dynamic,e1:Dynamic,e2:Dynamic);
 AKResolve(sea:Dynamic,name:String);
}
typedef SafeNavAccess={var snPos:Dynamic; var snBase:Dynamic; var snTempVar:Dynamic; var snAccess:AccessKind;}
enum ObjectDeclKind {ODKWithStructure(a:Dynamic); ODKWithClass(c:Dynamic,params:Array<Dynamic>); ODKPlain; ODKFailed;}
enum FromKind {FromType; FromField;}
class MetaConfig {
 public static function asBool(e:Dynamic):Bool return switch e.expr {case EConst(Ident("true")):true; case EConst(Ident("false")):false; case _:throw InvalidArgument("bool");};
 public static function readArgConfig(meta:Dynamic,f:Dynamic->Void,l:Array<Dynamic>):Void {
  for(m in l) if(m.meta==meta) for(e in (cast m.exprs:Array<Dynamic>)) switch e.expr {
   case EConst(Ident(s)): f({name:s,expr:{expr:EConst(Ident("true")),pos:Globals.nullPos}});
   case EBinop(OpAssign,{expr:EConst(Ident(s))},e2): f({name:s,expr:e2});
   case _:
  }
 }
}
class AbstractFromConfig {
 public var ignoredByInference=false;
 public function new() {}
 public static function make():AbstractFromConfig return new AbstractFromConfig();
 public static function updateConfigFromMeta(config:AbstractFromConfig,ml:Array<Dynamic>):AbstractFromConfig {
  MetaConfig.readArgConfig(Meta.From,function(arg) {
   if(arg.name=="ignoredByInference") try config.ignoredByInference=MetaConfig.asBool(arg.expr) catch(e:Dynamic) {switch e {case InvalidArgument(_): case _:throw e;}}
  },ml); return config;
 }
}
class ValueReference {
 final ctx:Dynamic;
 final vars:Array<Dynamic>=[];
 public function new(ctx:Dynamic) {this.ctx=ctx;}
 public function getVars():Array<Dynamic> return vars.copy();
 public function asVar(name:String,e:Dynamic):Dynamic {var v=allocVar(VGenerated,name,e.etype,e.epos); vars.push({variable:v,expr:e}); return mk(TLocal(v),v.vType,v.vPos);}
 function getExprAux(depth:Int,name:String,e:Dynamic):Dynamic return switch Texpr.skip(e).eexpr {
  case TLocal(_) | TTypeExpr(_) | TConst(_): e;
  case TField(ef,fa) if(depth==0): mk(TField(getExprAux(depth+1,"fh",ef),fa),e.etype,e.epos);
  case TArray(e1,e2) if(depth==0): var e1=getExprAux(depth+1,"base",e1); var e2=getExprAux(depth+1,"index",e2); mk(TArray(e1,e2),e.etype,e.epos);
  case _: asVar(name,e);
 };
 public function getExpr(name:String,e:Dynamic):Dynamic return getExprAux(0,name,e);
 public function getExprPart(name:String,e:Dynamic):Dynamic return getExprAux(1,name,e);
 public function toTexpr(e:Dynamic):Dynamic {
  if(vars.length==0) return e;
  var el=vars.map(pair -> mk(TVar(pair.variable,pair.expr),ctx.t.tvoid,pair.variable.vPos));
  var block=mk(TBlock(el.concat([e])),e.etype,e.epos);
  return mk(TMeta({meta:Meta.MergeBlock,exprs:[],pos:Globals.nullPos},block),block.etype,block.epos);
 }
 public function toTexprEl(el:Array<Dynamic>,e:Dynamic):Dynamic {
  var declarations=vars.map(pair -> mk(TVar(pair.variable,pair.expr),ctx.t.tvoid,pair.variable.vPos));
  var block=mk(TBlock(declarations.concat(el).concat([e])),e.etype,e.epos);
  return mk(TMeta({meta:Meta.MergeBlock,exprs:[],pos:Globals.nullPos},block),block.etype,block.epos);
 }
}
class TyperBase {
 public static var typeCallTargetRef:Dynamic=function(_:Dynamic,_:Dynamic,_:Dynamic,_:Dynamic,_:Dynamic):Dynamic {throw "Uninitialized typeCallTargetRef";};
 public static var typeAccessRef:Dynamic=function(_:Dynamic,_:Dynamic,_:Dynamic,_:Dynamic,_:Dynamic):Dynamic {throw "Uninitialized typeAccessRef";};
 public static function isLowerIdent(s:String,p:Dynamic):Bool {try return Ast.isLowerIdent(s) catch(e:Dynamic) {switch e {case InvalidArgument(msg): return raiseTypingError(msg,p); case _:throw e;}}}
 public static function getThis(ctx:Dynamic,p:Dynamic):Dynamic return switch ctx.e.curfun {
  case FunStatic: raiseTypingError("Cannot access this from a static function",p);
  case FunMemberClassLocal | FunMemberAbstractLocal:
   var v=ctx.f.vthis;
   if(v==null) {
    if(ctx.e.curfun==FunMemberAbstractLocal) {v=ctx.f.locals.get("this"); if(v==null) throw "Not_found"; addVarFlag(v,VUsedByTyper);}
    else v=addLocal(ctx,VGenerated,genLocalPrefix+"this",ctx.c.tthis,p);
    ctx.f.vthis=v;
   } else ctx.f.locals.set(v.vName,v);
   mk(TLocal(v),ctx.c.tthis,p);
  case FunMemberAbstract:
   var v=ctx.f.locals.get("this"); if(v==null) raiseTypingError("Cannot reference this abstract here",p); mk(TLocal(v),v.vType,p);
  case FunConstructor | FunMember if(TyperManager.isCoroutineContext(ctx)):
   var v=ctx.f.vthis;
   if(v==null) {v=addLocal(ctx,VGenerated,genLocalPrefix+"this",ctx.c.tthis,p); ctx.f.vthis=v;}
   mk(TLocal(v),ctx.c.tthis,p);
  case FunConstructor | FunMember: mk(TConst(TThis),ctx.c.tthis,p);
 };
 public static function getStoredTypedExpr(ctx:Dynamic,id:Int):Dynamic return Texpr.duplicateTvars(e -> getThis(ctx,e.epos),ctx.com.partScope.storedTypedExprs.find(id));
 public static function typeStoredExpr(ctx:Dynamic,e1:Dynamic):Dynamic {var id=switch e1.expr {case EConst(Int(s,_)):Std.parseInt(s); case _:throw "Invalid stored expression id";}; return getStoredTypedExpr(ctx,id);}
 public static function assignToThisIsAllowed(ctx:Dynamic):Bool return switch ctx.c.curclass.clKind {
  case KAbstractImpl(_): switch ctx.f.curfield.cfKind {case Method(MethInline):true; case Method(_) if(hasClassFieldFlag(ctx.f.curfield,CfAbstractConstructor)):true; case _:false;}
  case _:false;
 };
 public static function typeModuleTypeSimple(mt:Dynamic,p:Dynamic):Dynamic return switch mt {
  case TClassDecl(c): mk(TTypeExpr(TClassDecl(c)),c.clType,p);
  case TEnumDecl(e): mk(TTypeExpr(TEnumDecl(e)),e.eType,p);
  case TTypeDecl(s):
   var t=applyTypedef(s,(cast s.tParams:Array<Dynamic>).map(_ -> mkMono()));
   switch follow(t) {case TEnum(e,_):typeModuleTypeSimple(TEnumDecl(e),p); case TInst(c,_):typeModuleTypeSimple(TClassDecl(c),p); case TAbstract(a,_):typeModuleTypeSimple(TAbstractDecl(a),p); case _:throw "Invalid simple module type";}
  case TAbstractDecl(a) if(a.aImpl!=null):typeModuleTypeSimple(TClassDecl(a.aImpl),p);
  case TAbstractDecl(a):var tmp=abstractModuleType(a,[]); mk(TTypeExpr(TAbstractDecl(a)),TType(tmp,[]),p);
 };
 public static function typeModuleType(ctx:Dynamic,t:Dynamic,p:Dynamic):Dynamic {
  function loop(t:Dynamic,tparams:Dynamic):Dynamic return switch t {
   case TClassDecl({clKind:KGenericBuild(_)}):
    var info=InstanceBuilder.getBuildInfo(ctx,t,p);
    var t1=info.buildApply(tparams==null?[]:tparams);
    var mt:Dynamic;
    try mt=moduleTypeOfType(t1) catch(e:Dynamic) {if(e!="Exit") throw e; if(follow(t1)==tDynamic) mt=Typeload.loadTypeDef(ctx,p,mkTypePath({pack:[],name:"Dynamic"})); else mt=raiseTypingError("Invalid module type",p);}
    loop(mt,null);
   case TClassDecl(c):mk(TTypeExpr(TClassDecl(c)),c.clType,p);
   case TEnumDecl(e):mk(TTypeExpr(TEnumDecl(e)),e.eType,p);
   case TTypeDecl(s):
    var t1=applyTypedef(s,(cast s.tParams:Array<Dynamic>).map(_ -> spawnMonomorph(ctx,p)));
    DeprecationCheck.checkTypedef(createDeprecationContext(ctx),s,p);
    switch follow(t1) {case TEnum(e,params):loop(TEnumDecl(e),params); case TInst(c,params):loop(TClassDecl(c),params); case TAbstract(a,params):loop(TAbstractDecl(a),params); case _:raiseTypingError(Globals.sTypePath(s.tPath)+" is not a value",p);}
   case TAbstractDecl(a) if(a.aImpl!=null):loop(TClassDecl(a.aImpl),tparams);
   case TAbstractDecl(a):
    if(!Meta.has(Meta.RuntimeValue,a.aMeta)) raiseTypingError(Globals.sTypePath(a.aPath)+" is not a value",p);
    var tmp=abstractModuleType(a,[]); mk(TTypeExpr(TAbstractDecl(a)),TType(tmp,[]),p);
  };
  return loop(t,null);
 }
 public static function mkModuleTypeAccess(ctx:Dynamic,t:Dynamic,p:Dynamic):AccessKind return AKExpr(typeModuleType(ctx,t,p));
 public static function sFieldAccess(tabs:String,fa:Dynamic):String {
  var host=switch fa.faHost {case FHStatic(c):"FHStatic("+Globals.sTypePath(c.clPath)+")"; case FHInstance(c,tl):"FHInstance("+Globals.sTypePath(c.clPath)+", "+sTypes(tl)+")"; case FHAbstract(a,tl,c):"FHAbstract("+Globals.sTypePath(a.aPath)+", "+sTypes(tl)+", "+Globals.sTypePath(c.clPath)+")"; case FHAnon:"FHAnon";};
  return Printer.sRecordFields(tabs,[{name:"fa_on",value:pretty(fa.faOn)},{name:"fa_field",value:fa.faField.cfName},{name:"fa_host",value:host},{name:"fa_inline",value:Std.string(fa.faInline)},{name:"fa_pos",value:position(fa.faPos)}]);
 }
 static function pretty(e:Dynamic):String return sExprPretty(true,"",false,t -> sType(printContext(),t),e);
 static function position(p:Dynamic):String return p.pfile+"("+p.pmin+"-"+p.pmax+")";
 public static function sStaticExtensionAccess(sea:Dynamic):String return Printer.sRecordFields("",[{name:"se_this",value:pretty(sea.seThis)},{name:"se_access",value:sFieldAccess("\t",sea.seAccess)}]);
 public static function sAccessKind(acc:AccessKind):String return switch acc {
  case AKNo(a,_):"AKNo "+sAccessKind(a);
  case AKExpr(e):"AKExpr "+pretty(e);
  case AKSafeNav(sn):"AKSafeNav("+sSafeNavAccess(sn)+")";
  case AKField(fa):"AKField("+sFieldAccess("",fa)+")";
  case AKAccessor(fa):"AKAccessor("+sFieldAccess("",fa)+")";
  case AKUsingField(sea):"AKUsingField("+sStaticExtensionAccess(sea)+")";
  case AKUsingAccessor(sea):"AKUsingAccessor("+sStaticExtensionAccess(sea)+")";
  case AKAccess(a,tl,c,e1,e2):"AKAccess("+Globals.sTypePath(a.aPath)+", ["+tl.map(t -> sType(printContext(),t)).join(", ")+"], "+Globals.sTypePath(c.clPath)+", "+pretty(e1)+", "+pretty(e2)+")";
  case AKResolve(sea,name):"AKResolve("+sStaticExtensionAccess(sea)+", "+name+")";
 };
 public static function sSafeNavAccess(sn:SafeNavAccess):String return Printer.sRecordFields("",[{name:"sn_base",value:pretty(sn.snBase)},{name:"sn_temp_var",value:sn.snTempVar==null?"None":"Some "+pretty(sn.snTempVar)},{name:"sn_access",value:sAccessKind(sn.snAccess)}]);
 public static function sDotPathPart(part:Dynamic):String return Printer.sRecordFields("",[{name:"name",value:part.name},{name:"case",value:part.letterCase==PUppercase?"PUppercase":"PLowercase"},{name:"pos",value:position(part.pos)}]);
 public static function getConstructibleConstraint(ctx:Dynamic,tl:Array<Dynamic>,p:Dynamic):Dynamic {
  function extract(t:Dynamic):Dynamic return switch follow(t) {case TFun(tl,tr):{args:tl,ret:tr}; case _:raiseTypingError("Constructible type parameter should be function",p);};
  for(t in tl) switch follow(t) {
   case TAnon(a): if(a.aFields.exists("new")) return extract(a.aFields.get("new").cfType);
   case TAbstract({aPath:{pack:["haxe"],name:"Constructible"}},[t1]):return extract(t1);
   case TInst({clKind:KTypeParameter(ttp)},_):var result=getConstructibleConstraint(ctx,getConstraints(ttp),p); if(result!=null) return result;
   case _:
  }
  return null;
 }
 public static function unifyStaticExtension(ctx:Dynamic,e:Dynamic,t:Dynamic,p:Dynamic):Dynamic {
  function check(t:Dynamic):Bool return switch follow(t) {case TAbstract(a,_) if(Meta.has(Meta.MultiType,a.aMeta)):true; case _:false;};
  if(check(e.etype)||check(t)) return AbstractCast.castOrUnifyRaise(ctx,t,e,p);
  var config=defaultUnificationContext(); config.allowDynamicToCast=false; Type.unifyCustom(config,e.etype,t); return e;
 }
 public static function getAbstractFroms(ctx:Dynamic,a:Dynamic,pl:Array<Dynamic>):Array<Dynamic> {
  var l=(cast a.aFrom:Array<Dynamic>).map(t -> {kind:FromType,type:applyParams(a.aParams,pl,t)});
  for(pair in (cast a.aFromField:Array<Dynamic>)) {
   var f=pair.field;
   if(f==ctx.f.curfield || AbstractFromConfig.updateConfigFromMeta(AbstractFromConfig.make(),f.cfMeta).ignoredByInference) continue;
   switch follow(Type.fieldType(f)) {
    case TFun([{type:v}],t): try {typeEq(EqStrict,t,TAbstract(a,pl.map(duplicate))); l.unshift({kind:FromField,type:v});} catch(e:Dynamic) {switch e {case UnifyError(_): case _:throw e;}}
    case _:
   }
  }
  return l;
 }
 public static function safeNavBranch(ctx:Dynamic,sn:SafeNavAccess,fThen:Void->Dynamic):Dynamic {
  var eobj=sn.snBase, enull=Builder.makeNull(eobj.etype,sn.snPos);
  var eneq=Builder.binop(OpNotEq,eobj,enull,ctx.t.tbool,sn.snPos);
  var ethen=fThen(), tnull=ctx.t.tnull(ethen.etype);
  if(!isNullable(ethen.etype)) ethen=mk(TCast(ethen,null),tnull,ethen.epos);
  var eelse=Builder.makeNull(tnull,sn.snPos), eif=mk(TIf(eneq,ethen,eelse),tnull,sn.snPos);
  return sn.snTempVar==null?eif:mk(TBlock([sn.snTempVar,eif]),eif.etype,eif.epos);
 }
 public static function getSafeNavBase(ctx:Dynamic,eobj:Dynamic):Dynamic return switch Texpr.skip(eobj).eexpr {
  case TLocal(_) | TTypeExpr(_) | TConst(_): {base:eobj,tempVar:null};
  case _:var v=allocVar(VGenerated,"tmp",eobj.etype,eobj.epos); var temp=mk(TVar(v,eobj),ctx.t.tvoid,v.vPos); {base:mk(TLocal(v),v.vType,v.vPos),tempVar:temp};
 };
}
