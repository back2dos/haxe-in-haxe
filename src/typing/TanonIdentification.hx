package typing;
import core.TType;
import core.TFunctions.*;
import core.TOther.*;
import core.Globals.*;
// haxe/src/typing/tanon_identification.ml — mechanical draft; not compile-validated.
typedef PathFieldMapping<A>={var pfmPath:Dynamic;var pfmParams:TypeParams;var pfmFields:Dynamic;var pfmConverted:Null<Array<{name:String,value:A}>>;var pfmArity:Int;}
class AnonIdMode {
 public static var defaultMode:Dynamic={...defaultUnificationContext(),nullFollowMode:NeverFollow};
 public static var strict:Dynamic={allowTransitiveCast:false,allowAbstractCast:false,allowDynamicToCast:false,allowArgNameMismatch:false,allowOptionalMismatch:false,equalityKind:EqStricter,equalityUnderlying:false,strictFieldKind:true,opaqueFieldParams:false,allowFinalInvariance:false,typeParamMode:TpDefault,nullFollowMode:NeverFollow,unifyStack:newRecStack(),eqStack:newRecStack(),varianceStack:newRecStack(),abstractCastStack:newRecStack(),unifyNewMonos:newRecStack(),applyParamsStack:[]};
}
class TanonIdentification<A> {
 var pfms:Dynamic=new Hashtbl();var pfmMutex=new sys.thread.Mutex();var pfmByArity:Array<Array<PathFieldMapping<A>>>=[];var addPfmMutex=new sys.thread.Mutex();var num=0;
 public function new() {}
 public static function replaceMono(asDynamic:Bool,t:T):T {var visited=[];function loop(t:T):T return switch t{case TMono({tmType:null}):asDynamic?tDynamic:t;case TAnon(an):if(visited.indexOf(an)>=0)t;else{visited.unshift(an);map(loop,t);}case _:map(loop,t);};return loop(t);}
 public static function countFields(pm:Dynamic):Int {var i=0;for(_ in (pm.keys():Iterator<String>))i++;return i;}
 public static function pfmOfTypedef<A>(td:Dynamic):PathFieldMapping<A> return switch follow(td.tType){case TAnon(an):{pfmPath:td.tPath,pfmParams:td.tParams,pfmFields:an.aFields,pfmConverted:null,pfmArity:countFields(an.aFields)};case _:throw "assert";};
 public function getPfms():Dynamic return pfms;
 public function addPfm(path:Dynamic,pfm:PathFieldMapping<A>):Void {addPfmMutex.acquire();while(pfmByArity.length<=pfm.pfmArity)pfmByArity.push([]);pfmByArity[pfm.pfmArity].push(pfm);pfms.replace(path,pfm);addPfmMutex.release();}
 public function unify(uctx:Dynamic,tc:T,pfm:PathFieldMapping<A>):Void {
  function pairs(fields:Dynamic):Array<Dynamic> {var acc=[];var names=[for(n in (pfm.pfmFields.keys():Iterator<String>))n];names.sort(Reflect.compare);for(n in names){var cf=pfm.pfmFields.get(n);var other=fields.get(cf.cfName);if(other==null)throw new NotFound();acc.unshift({cf:cf,other:other});}return acc;}
  function fieldType(cf:TClassField):T return uctx.opaqueFieldParams?cf.cfType:monomorphs(cf.cfParams,cf.cfType);
  try {
   var monos:Array<T>=switch follow(tc) {
    case TInst(c,tl):var ps=pairs(c.clFields);var ms=pfm.pfmParams.map(function(_)return mkMono());for(pair in ps){if(!unifyKind(uctx,pair.other.cfKind,pair.cf.cfKind))throw new UnifyError([UnifyCustom("kind mismatch")]);core.Type.unify(applyParams(c.clParams,tl,fieldType(pair.other)),applyParams(pfm.pfmParams,ms,fieldType(pair.cf)));}ms;
    case TAnon(an):var fields=an.aFields.copy();var ps=pairs(an.aFields);var ms=pfm.pfmParams.map(function(_)return mkMono());for(pair in ps){if(!uctx.allowOptionalMismatch&&core.Meta.has(core.Meta.Optional,pair.cf.cfMeta)!=core.Meta.has(core.Meta.Optional,pair.other.cfMeta))throw new UnifyError([UnifyCustom("optional mismatch")]);if(!unifyKind(uctx,pair.other.cfKind,pair.cf.cfKind))throw new UnifyError([UnifyCustom("kind mismatch")]);fields.remove(pair.cf.cfName);typeEqCustom(uctx,fieldType(pair.other),applyParams(pfm.pfmParams,ms,fieldType(pair.cf)));}if(countFields(fields)>0)throw new UnifyError([UnifyCustom("not enough fields")]);ms;
    case _:throw new UnifyError([UnifyCustom("bad type")]);
   };for(t in monos)switch follow(t){case TMono(r):Monomorph.bind(r,tDynamic);case t:if(ExtType.isVoid(t))throw new UnifyError([UnifyCustom("return mono")]);}
  }catch(e:NotFound){throw new UnifyError([]);}
 }
 public function findCompatible(uctx:Dynamic,arity:Int,tc:T):PathFieldMapping<A> {if(arity>=pfmByArity.length)throw new NotFound();for(pfm in pfmByArity[arity])try{unify(uctx,tc,pfm);return pfm;}catch(e:UnifyError){}throw new NotFound();}
 public function identifyTypedef(td:Dynamic):Void {function loop(t:T):Void switch t{case TAnon(an) if((an.aStatus==Closed||an.aStatus==Const)&&countFields(an.aFields)>0):addPfm(td.tPath,pfmOfTypedef(td));case TMono({tmType:t}) if(t!=null):loop(t);case TLazy(f):loop(lazyType(f));case _:};loop(td.tType);}
 function protect<B>(f:Void->B):B {pfmMutex.acquire();try{var r=f();pfmMutex.release();return r;}catch(e:Dynamic){pfmMutex.release();throw e;}}
 public function identifyAnon(uctx:Dynamic,an:Dynamic):PathFieldMapping<A> {
  function makePfm(path:Dynamic):PathFieldMapping<A> return {pfmPath:path,pfmParams:[],pfmFields:an.aFields,pfmConverted:null,pfmArity:countFields(an.aFields)};
  var path:Dynamic=switch an.aStatus{case ClassStatics(c):c.clPath;case EnumStatics(e):e.ePath;case AbstractStatics(a):a.aPath;case _:null;};
  if(path!=null)return protect(function(){try{return pfms.find(path);}catch(e:NotFound){var pfm=makePfm(path);addPfm(path,pfm);return pfm;}});
  var arity=0;var fields=an.aFields.copy();var names=[for(n in (an.aFields.keys():Iterator<String>))n];names.sort(Reflect.compare);for(n in names){var cf=an.aFields.get(n);arity++;fields.set(cf.cfName,{...cf,cfType:replaceMono(uctx.equalityKind!=EqStricter,cf.cfType)});}an={aFields:fields,aStatus:an.aStatus};
  return protect(function(){try{return findCompatible(uctx,arity,TAnon(an));}catch(e:NotFound){var id=num++;var path={pack:["haxe","generated"],name:'Anon$id'};var pfm=makePfm(path);addPfm(path,pfm);return pfm;}});
 }
 public function identify(uctx:Dynamic,acceptAnons:Bool,t:T):Null<PathFieldMapping<A>> {
  function loop(t:T):Null<PathFieldMapping<A>> return switch t {
   case TType(td,tl):try{protect(function()return pfms.find(td.tPath));}catch(e:NotFound){loop(applyTypedef(td,tl));}
   case TMono({tmType:t}) if(t!=null):loop(t);
   case TAbstract(a,tl) if(!core.Meta.has(core.Meta.CoreType,a.aMeta)):loop(core.Abstract.getUnderlyingType(a,tl));
   case TAbstract({aPath:{pack:[],name:"Null"}},[t]):loop(t);
   case TLazy(f):loop(lazyType(f));case TAnon(an) if(acceptAnons&&countFields(an.aFields)>0):identifyAnon(uctx,an);case _:null;
  };return loop(t);
 }
}
