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
import typing.TypeloadCheck.*;

// haxe/src/typing/typeloadCheck.ml — mechanical draft; not compile-validated.
class BuildCanceled extends haxe.Exception {
 public final state:Dynamic;
 public function new(state:Dynamic) {super("Build canceled"); this.state=state;}
}
typedef RedefinitionContext={var cNew:Dynamic; var cfNew:Dynamic; var cOld:Dynamic; var cfOld:Dynamic; var map:Dynamic->Dynamic; var tOld:Dynamic;}
enum CheckOverrideKind {NothingToDo; NormalOverride(ctx:RedefinitionContext); OverloadOverride(f:Void->Void);}
class TypeloadCheck {
 public static function isGenericParameter(ctx:Dynamic,c:Dynamic):Bool {
  var name=c.clPath.name;
  try {lookupParam(name,ctx.f.curfield.cfParams); return hasClassFieldFlag(ctx.f.curfield,CfGeneric);} catch(e:Dynamic) {if(e!="Not_found") throw e;}
  try {lookupParam(name,ctx.typeParams); return switch ctx.c.curclass.clKind {case KGeneric:true; case _:false;};} catch(e:Dynamic) {if(e!="Not_found") throw e; return false;}
 }
 public static function validRedefinition(com:Dynamic,map1:Dynamic->Dynamic,map2:Dynamic->Dynamic,f1:Dynamic,t1:Dynamic,f2:Dynamic,t2:Dynamic):Void {
  var tctx:Dynamic={typeParamPairs:[],knownTypeParams:f1.cfParams};
  var uctx=defaultUnificationContext(); uctx.typeParamMode=TpDefinition(tctx);
  function valid(a:Dynamic,b:Dynamic):Void {unifyCustom(uctx,a,b); if(isNull(a)!=isNull(b)||(follow(a)==tDynamic && follow(b)!=tDynamic)) throw UnifyError([CannotUnify(a,b)]);}
  switch [PurityState.getPurityFromMeta(f2.cfMeta),PurityState.getPurityFromMeta(f1.cfMeta)] {
   case [Pure,MaybePure]:f1.cfMeta.unshift({meta:Meta.Pure,exprs:[{expr:EConst(Ident("expect")),pos:mkZeroRangePos(f2.cfPos)}],pos:Globals.nullPos});
   case [ExpectPure(p),MaybePure]:f1.cfMeta.unshift({meta:Meta.Pure,exprs:[{expr:EConst(Ident("expect")),pos:p}],pos:Globals.nullPos});
   case _:
  }
  switch [f1.cfKind,f2.cfKind] {
   case [Method(m1),Method(m2)] if(m1!=MethDynamic && m2!=MethDynamic):
    switch [followWithCoro(t1),followWithCoro(t2)] {
     case [Coro(_),NotCoro(_)]:throw UnifyError([UnifyCustom("Method should be coroutine")]);
     case [NotCoro(_),Coro(_)]:throw UnifyError([UnifyCustom("Method should not be coroutine")]);
     case [NotCoro(TFun(args1,r1)),NotCoro(TFun(args2,r2))] | [Coro(args1,r1),Coro(args2,r2)]:
      if(args1.length!=args2.length) throw UnifyError([UnifyCustom("Different number of function arguments")]);
      var i=0;
      try {
       valid(r1,r2);
       for(index in 0...args1.length) {
        var a1=args1[index],a2=args2[index]; i++;
        if(a1.optional!=a2.optional) throw UnifyError([CannotUnify(a2.type,a1.type),NotMatchingOptional(a2.optional,a1.optional,a1.name)]);
        try valid(a2.type,a1.type) catch(e:Dynamic) {switch e {case UnifyError(_):throw UnifyError([CannotUnifyImplementation(a1.type,a2.type)]); case _:throw e;}}
       }
      } catch(e:Dynamic) {switch e {case UnifyError(l):var msg=i==0?InvalidReturnType:InvalidFunctionArgument(i,args1.length); throw UnifyError([CannotUnify(t1,t2),msg].concat(l)); case _:throw e;}}
     case _:displayError(com,"Unexpected types when checking redefinition of "+f1.cfName+":\n\tf1: "+sTypeKind(t1)+"\n\tf2: "+sTypeKind(t2),f1.cfPos);
    }
   case [_,Var({vWrite:AccNo | AccNever})]:valid(t1,t2);
   case [_,Var({vRead:AccNo | AccNever})]:valid(t2,t1);
   case [_,_] if(hasClassFieldFlag(f2,CfFinal)):valid(t1,t2);
   case _:typeEq(EqStrict,t1,t2); if(isNull(t1)!=isNull(t2)) throw UnifyError([CannotUnify(t1,t2)]);
  }
  function assignTtp(ttp1:Dynamic,ttp2:Dynamic):Void {
   var ct1:Array<Dynamic>=getConstraints(ttp1),ct2:Array<Dynamic>=getConstraints(ttp2);
   function fail(t:Dynamic):Void {throw UnifyError([UnifyCustom("Constraint unsatisfied for type parameter "+ttp2.ttpName+": "+sType(printContext(),t))]);}
   if(ct2.length==0) return;
   if(ct1.length==0) fail(ct2[0]);
   for(t2 in ct2) {
    var mapped=map2(t2), found=false;
    for(t1 in ct1) try {Type.unifyCustom(uctx,map1(t1),mapped); found=true; break;} catch(e:Dynamic) {switch e {case UnifyError(_): case _:throw e;}}
    if(!found) fail(mapped);
   }
  }
  for(pair in (cast tctx.typeParamPairs:Array<Dynamic>)) assignTtp(pair.second,pair.first);
 }
 public static function copyMeta(source:Array<Dynamic>,target:Array<Dynamic>,selected:Array<Dynamic>):Array<Dynamic> {var result=target.copy(); for(m in source) if(selected.contains(m.meta)) result.unshift(m); return result;}
 public static function checkNativeNameOverride(ctx:Dynamic,child:Dynamic,base:Dynamic):Void {
  function error(bp:Dynamic,cp:Dynamic):Void displayErrorExt(ctx.com,makeError(Custom("Field "+child.cfName+" has different @:native value than in superclass"),cp,[makeError(Custom(complMsg("Base field is defined here")),bp)]));
  try {var cn=Native.getNativeName(child.cfMeta); try {var bn=Native.getNativeName(base.cfMeta); if(bn.name!=cn.name) error(bn.pos,cn.pos);} catch(e:Dynamic) {if(e!="Not_found") throw e; error(base.cfNamePos,cn.pos);}}
  catch(e:Dynamic) {if(e!="Not_found") throw e;}
 }
 public static function checkOverrideField(ctx:Dynamic,p:Dynamic,r:RedefinitionContext):Void {
  var i=r.cfNew.cfName, hasOverride=hasClassFieldFlag(r.cfNew,CfOverride);
  checkNativeNameOverride(ctx,r.cfNew,r.cfOld);
  switch r.cfNew.cfKind {case Var({vRead:AccRequire(_)}):throw "Not_found"; case _:}
  if(hasClassFieldFlag(r.cfOld,CfAbstract)) {
   if(hasOverride) displayError(ctx.com,"Field "+i+" is declared 'override' but parent field "+i+" is 'abstract' and does not provide any implementation to override",p);
   else addClassFieldFlag(r.cfNew,CfOverride);
  }
  if(hasClassFieldFlag(r.cfOld,CfOverload)&&!hasClassFieldFlag(r.cfNew,CfOverload)) displayError(ctx.com,"Field "+i+" should be declared with overload since it was already declared as overload in superclass",p);
  else if(!hasOverride&&!hasClassFieldFlag(r.cfOld,CfAbstract)) {if(hasClassFlag(r.cNew,CExtern)) addClassFieldFlag(r.cfNew,CfOverride); else displayError(ctx.com,"Field "+i+" should be declared with 'override' since it is inherited from superclass "+Globals.sTypePath(r.cOld.clPath),p);}
  else if(!hasClassFieldFlag(r.cfNew,CfPublic)&&hasClassFieldFlag(r.cfOld,CfPublic)) displayError(ctx.com,"Field "+i+" has less visibility (public/private) than superclass one",p);
  else switch [r.cfNew.cfKind,r.cfOld.cfKind] {
   case [_,Method(MethInline)]:displayError(ctx.com,"Field "+i+" is inlined and cannot be overridden",p);
   case [a,b] if(a==b):
   case [Method(MethInline),Method(MethNormal)]:
   case _:displayError(ctx.com,"Field "+i+" has different property access than in superclass",p);
  }
  if(hasClassFieldFlag(r.cfOld,CfFinal)) displayError(ctx.com,"Cannot override final method "+i,p);
  try validRedefinition(ctx.com,r.map,r.map,r.cfNew,r.cfNew.cfType,r.cfOld,r.tOld) catch(e:Dynamic) {switch e {
   case UnifyError(l):displayErrorExt(ctx.com,makeError(Custom("Field "+i+" overrides parent class with different or incomplete type"),p,[makeError(Custom(complMsg(errorMsg(Unify(l)))),p),makeError(Custom(complMsg("Base field is defined here")),r.cfOld.cfNamePos)]));
   case _:throw e;
  }}
 }
 public static function findOverrideField(ctx:Dynamic,cNew:Dynamic,cfNew:Dynamic,cOld:Dynamic,tl:Array<Dynamic>,getSuperField:Dynamic,isOverload:Bool,p:Dynamic):Null<RedefinitionContext> {
  var i=cfNew.cfName;
  try {
   if(isOverload&&!hasClassFieldFlag(cfNew,CfOverload)) displayError(ctx.com,"Missing overload declaration for field "+i,p);
   var sup=getSuperField(cOld,i), map=TClass.getMapFunction(cOld,tl);
   return {cNew:cNew,cfNew:cfNew,cOld:cOld,cfOld:sup.field,map:map,tOld:map(sup.type)};
  } catch(e:Dynamic) {
   if(e!="Not_found") throw e;
   if(hasClassFieldFlag(cfNew,CfOverride)) {
    var msg:String;
    if(isOverload) msg="Field "+i+" is declared 'override' but no compatible overload was found";
    else {
     var fields=[];
     for(pair in TClass.getAllSuperFields(cNew)) switch pair.field.cfKind {case Method(MethNormal) if(!hasClassFieldFlag(pair.field,CfFinal)):fields.unshift(pair.field.cfName); case _:}
     msg=StringError.stringError(i,fields,"Field "+i+" is declared 'override' but doesn't override any field");
    }
    displayError(ctx.com,msg,p);
   }
   return null;
  }
 }
 public static function hasSuperCall(name:String,e:Dynamic):Bool return switch e.eexpr {case TCall({eexpr:TField({eexpr:TConst(TSuper)},FInstance(_,_,cf))},_) if(cf.cfName==name):true; case _:checkExpr(e -> hasSuperCall(name,e),e);};
 public static function checkCallSuper(com:Dynamic,r:RedefinitionContext,e:Dynamic):Void {
  var name=r.cfOld.cfName;
  function active(c:Dynamic,cf:Dynamic):Bool {
   if(hasClassFieldFlag(r.cfOld,CfAbstract)) return false;
   try {var m=Meta.get(Meta.CallSuper,cf.cfMeta); return switch m.exprs {case [{expr:EConst(Ident("false"))}]:false; case _:true;};}
   catch(e:Dynamic) {if(e!="Not_found") throw e; var sup=c.clSuper; if(sup==null||!sup.c.clFields.exists(name)) return false; return active(sup.c,sup.c.clFields.get(name));}
  }
  if(active(r.cOld,r.cfOld)&&!hasSuperCall(name,e)) displayError(com,"Missing call to super."+name+"()",r.cfNew.cfNamePos);
 }
 public static function checkOverriding(ctx:Dynamic,c:Dynamic,f:Dynamic):CheckOverrideKind {
  var sup=c.clSuper;
  if(sup==null) {if(hasClassFieldFlag(f,CfOverride)) displayError(ctx.com,"Field "+f.cfName+" is declared 'override' but doesn't override any field",f.cfPos); return NothingToDo;}
  var csup=sup.c,params=sup.params,p=f.cfNamePos,i=f.cfName;
  if(hasClassFieldFlag(f,CfOverload)) {
   var overloads:Array<Dynamic>=getOverloads(ctx.com,csup,i);
   for(pair in overloads) switch pair.field.cfKind {case Var(_):displayError(ctx.com,"A variable named '"+pair.field.cfName+"' was already declared in a superclass",f.cfPos); case _:}
   return OverloadOverride(function() {
    var r=findOverrideField(ctx,c,f,csup,params,function(csup:Dynamic,i:String):Dynamic {for(pair in overloads) if(Overloads.sameOverloadArgs(f.cfType,applyParams(csup.clParams,params,pair.type),f,pair.field)) return pair; throw "Not_found";},true,p);
    if(r!=null) checkOverrideField(ctx,p,r);
   });
  }
  var r=findOverrideField(ctx,c,f,csup,params,function(csup:Dynamic,i:String):Dynamic {var raw=rawClassField(f -> f.cfType,csup,params,i); return {type:raw.type,field:raw.field};},false,p);
  return r==null?NothingToDo:NormalOverride(r);
 }
 public static function classFieldNoInterf(c:Dynamic,i:String):Dynamic {
  if(c.clFields.exists(i)) {var f=c.clFields.get(i); return {map:function(t:Dynamic) return t,type:f.cfType,field:f};}
  var sup=c.clSuper; if(sup==null) throw "Not_found";
  var raw=rawClassField(f -> f.cfType,sup.c,sup.params,i),map=TClass.getMapFunction(sup.c,sup.params);
  return {map:map,type:applyParams(sup.c.clParams,sup.params,raw.type),field:raw.field};
 }
 public static function returnFlow(ctx:Dynamic,e:Dynamic):Void {
  function error():Void {displayError(ctx.com,"Missing return: "+sType(printContext(),ctx.e.ret),e.epos); throw "Exit";}
  switch e.eexpr {
   case TReturn(_) | TThrow(_):
   case TParenthesis(e) | TMeta(_,e):returnFlow(ctx,e);
   case TBlock(el):
    if(el.length==0) error();
    for(i in 0...el.length) {if(i==el.length-1) returnFlow(ctx,el[i]); else if(DeadEnd.hasDeadEnd(el[i])) return;}
   case TIf(_,e1,e2) if(e2!=null):returnFlow(ctx,e1); returnFlow(ctx,e2);
   case TSwitch(s) if(s.switchDefault!=null):for(c in (cast s.switchCases:Array<Dynamic>)) returnFlow(ctx,c.caseExpr); returnFlow(ctx,s.switchDefault);
   case TSwitch(s) if(s.switchExhaustive):for(c in (cast s.switchCases:Array<Dynamic>)) returnFlow(ctx,c.caseExpr);
   case TTry(e,cases):returnFlow(ctx,e); for(c in (cast cases:Array<Dynamic>)) returnFlow(ctx,c.expr);
   case TWhile({eexpr:TConst(TBool(true))},body,_):
    function loop(e:Dynamic):Void switch e.eexpr {case TWhile(_): case TBreak:error(); case _:iter(loop,e);}
    loop(body);
   case _:if(!DeadEnd.hasDeadEnd(e)) error();
  }
 }
 public static function checkGlobalMetadata(ctx:Dynamic,meta:Dynamic,fAdd:Dynamic->Void,mpath:Dynamic,tpath:Dynamic,so:Null<String>):Void {
  var sl1=fullDotPath2(mpath,tpath), fieldMode=so!=null; if(fieldMode) sl1=sl1.concat([so]);
  for(entry in (cast ctx.com.globalMetadata:Array<Dynamic>)) if(((fieldMode&&entry.toFields)||(!fieldMode&&entry.toTypes))&&matchPath(entry.recursive,sl1,entry.path)) fAdd(entry.meta);
  if(ctx.m.isDisplayFile) delay(ctx.g,PCheckConstraint,function() DisplayEmitter.checkDisplayMetadata(ctx,meta));
 }
 public static function checkFinalVars(ctx:Dynamic,e:Dynamic):Void {
  var finalVars=new Map<String,Bool>(),ordered=[];
  function loop(c:Dynamic):Void {
   for(cf in (cast c.clOrderedFields:Array<Dynamic>)) switch cf.cfKind {case Var(_) if(hasClassFieldFlag(cf,CfFinal)&&cf.cfExpr==null&&!finalVars.exists(cf.cfName)):finalVars.set(cf.cfName,false); ordered.push({c:c,field:cf}); case _:}
   var sup=c.clSuper; if(sup!=null && hasClassFlag(sup.c,CAbstract)&&!hasConstructor(sup.c)) loop(sup.c);
  }
  loop(ctx.c.curclass);
  if(finalVars.iterator().hasNext()) {
   function findInits(e:Dynamic):Void switch e.eexpr {case TBinop(OpAssign,{eexpr:TField({eexpr:TConst(TThis)},fa)},e2):finalVars.remove(fieldName(fa)); findInits(e2); case _:iter(findInits,e);}
   findInits(e);
   if(finalVars.iterator().hasNext()) {var sub=ordered.filter(pair -> finalVars.exists(pair.field.cfName)).map(pair -> makeError(Custom("Uninitialized field"),pair.field.cfNamePos)); sub.reverse(); displayErrorExt(ctx.com,makeError(Custom("Some final fields are uninitialized in this class"),ctx.c.curclass.clNamePos,sub));}
  }
 }
}
class Inheritance {
 public static function isBasicClassPath(path:Dynamic):Bool return path.pack.length==0 && ["Array","String","Date","Xml"].contains(path.name);
 public static function checkExtends(ctx:Dynamic,c:Dynamic,t:Dynamic,p:Dynamic):Dynamic return switch follow(t) {
  case TInst(csup,params):
   if(isBasicClassPath(csup.clPath)&&!(hasClassFlag(c,CExtern)&&hasClassFlag(csup,CExtern))) raiseTypingError("Cannot extend basic class",p);
   if(extendsClass(csup,c)) raiseTypingError("Recursive class",p);
   switch csup.clKind {case KTypeParameter(_):if(TypeloadCheck.isGenericParameter(ctx,csup)) raiseTypingError("Extending generic type parameters is no longer allowed in Haxe 4",p); raiseTypingError("Cannot extend type parameters",p); case _:{c:csup,params:params};}
  case t:raiseTypingError("Should extend by using a class, found "+sTypeKind(t),p);
 };
 public static function checkInterface(com:Dynamic,g:Dynamic,missing:Array<Dynamic>,c:Dynamic,intf:Dynamic,params:Array<Dynamic>):Void {
  var uctx=defaultUnificationContext();
  for(pair in (cast intf.clImplements:Array<Dynamic>)) checkInterface(com,g,missing,c,pair.c,pair.params.map(t -> applyParams(intf.clParams,params,t)));
  var p=c.clNamePos;
  function checkField(f:Dynamic):Void {
   var t=applyParams(intf.clParams,params,f.cfType), isOverload=false;
   function implicitField():Dynamic {
    var cf=Reflect.copy(f); cf.cfOverloads=[]; cf.cfType=applyParams(intf.clParams,params,f.cfType);
    if(c.clFields.exists(cf.cfName)) {var previous=c.clFields.get(cf.cfName); com.overloadCache.remove({path:c.clPath,name:f.cfName}); previous.cfOverloads.unshift(cf);} else TClass.addField(c,cf);
    return cf;
   }
   function isMethod():Bool return switch f.cfKind {case Method(_):true; case Var(_):false;};
   try {
    var previous=TypeloadCheck.classFieldNoInterf(c,f.cfName),map2=previous.map,t2=previous.type,f2=previous.field;
    if(f2.cfOverloads.length!=0 || hasClassFieldFlag(f2,CfOverload)) {
     var overloads:Array<Dynamic>=getOverloads(com,c,f.cfName); isOverload=true; var found=false;
     for(pair in overloads) if(Overloads.sameOverloadArgs(t,pair.type,f,pair.field)) {t2=pair.type; f2=pair.field; found=true; break;}
     if(!found) throw "Not_found";
    }
    delay(g,PForce,function() {
     follow(f2.cfType); var p=f2.cfNamePos;
     function mkind(m:Dynamic):Int return switch m {case MethNormal|MethInline:0; case MethDynamic:1; case MethMacro:2;};
     var sameKind=switch [f.cfKind,f2.cfKind] {case [Var(_),Var(_)]:true; case [Method(m1),Method(m2)]:mkind(m1)==mkind(m2); case _:false;};
     if(hasClassFieldFlag(f,CfPublic)&&!hasClassFieldFlag(f2,CfPublic)&&!Meta.has(Meta.CompilerGenerated,f.cfMeta)) displayError(com,"Field "+f.cfName+" should be public as requested by "+Globals.sTypePath(intf.clPath),p);
     else if(!unifyKind(uctx,f2.cfKind,f.cfKind)||!sameKind) displayError(com,"Field "+f.cfName+" has different property access than in "+Globals.sTypePath(intf.clPath)+": "+sKind(f2.cfKind)+" should be "+sKind(f.cfKind),p);
     else try TypeloadCheck.validRedefinition(com,TClass.getMapFunction(intf,params),map2,f2,t2,f,applyParams(intf.clParams,params,f.cfType)) catch(e:Dynamic) {switch e {
      case UnifyError(l):if(!hasClassFlag(c,CExtern)) displayErrorExt(com,makeError(Custom("Field "+f.cfName+" has different type than in "+Globals.sTypePath(intf.clPath)),p,[makeError(Custom(complMsg(errorMsg(Unify(l)))),p),makeError(Custom(complMsg("Interface field is defined here")),f.cfNamePos)]));
      case _:throw e;
     }}
    });
   } catch(e:Dynamic) {
    if(e!="Not_found") throw e;
    if(hasClassFlag(c,CAbstract)&&isMethod()) addClassFieldFlag(implicitField(),CfAbstract);
    else if(hasClassFieldFlag(f,CfDefault)) {var cf=implicitField(); cf.cfExpr=null; addClassFieldFlag(cf,CfExtern); addClassFieldFlag(cf,CfOverride);}
    else if(!hasClassFlag(c,CInterface)) {
     if(Diagnostics.errorInDiagnosticsRun(com,c.clPos)) missing.push({field:f,type:t});
     else {
      var msg:String;
      if(isOverload) {var pc=printContext(); var args=switch follow(f.cfType) {case TFun(args,_):args.map(a -> (a.optional?"?":"")+a.name+" : "+sType(pc,a.type)).join(", "); case _:throw "Invalid overload type";}; msg="No suitable overload for "+f.cfName+"( "+args+" ), as needed by "+Globals.sTypePath(intf.clPath)+" was found";}
      else msg="Field "+f.cfName+" needed by "+Globals.sTypePath(intf.clPath)+" is missing";
      displayError(com,msg,p);
     }
    }
   }
  }
  // Ordered-map traversal is retained through the upstream map adapter.
  intf.clFields.iter(function(_:String,cf:Dynamic) {checkField(cf); if(hasClassFieldFlag(cf,CfOverload)) {var list:Array<Dynamic>=cf.cfOverloads.copy(); list.reverse(); for(overload in list) checkField(overload);}});
 }
 public static function checkInterfaces(ctx:Dynamic,c:Dynamic):Void {
  for(pair in (cast c.clImplements:Array<Dynamic>)) {
   var missing=[]; checkInterface(ctx.com,ctx.g,missing,c,pair.c,pair.params);
   if(missing.length>0) {
    var diag={mfPos:c.clNamePos,mfOn:TClassDecl(c),mfFields:missing.map(p -> {field:p.field,type:p.type,completion:CompletionType.fromType(Display.getImportStatus(ctx),p.type)}),mfCause:ImplementedInterface(pair.c,pair.params)};
    CompilerMessage.addModuleDiagnostic(ctx.com,c.clModule,DiagnosticsPrinter.makeMissingFieldsMessage(diag));
   }
  }
 }
 public static function checkAbstractClass(ctx:Dynamic,c:Dynamic,csup:Dynamic,params:Array<Dynamic>):Void {
  var missing:Array<Dynamic>=[],map=t -> applyParams(csup.clParams,params,t);
  function checkField(cf1:Dynamic,t1:Dynamic):Void {
   var found=false;
   if(c.clFields.exists(cf1.cfName)) {var cf2=c.clFields.get(cf1.cfName); for(cf in ([cf2].concat(cf2.cfOverloads):Array<Dynamic>)) if(Overloads.sameOverloadArgs(t1,cf.cfType,cf1,cf)) {found=true; break;}}
   if(!found) missing.unshift({field:cf1,type:t1});
  }
  TClass.getAllFields(csup,params).iter(function(_:String,pair:Dynamic) {for(overload in (cast Overloads.collectOverloads(map,csup,pair.field.cfName):Array<Dynamic>)) if(hasClassFieldFlag(overload.field,CfAbstract)) checkField(overload.field,overload.type);});
  if(missing.length==0) return;
  if(Diagnostics.errorInDiagnosticsRun(ctx.com,c.clPos)) {
   var fields=missing.map(pair -> {field:pair.field,type:pair.type,completion:CompletionType.fromType(Display.getImportStatus(ctx),pair.type)}); fields.reverse();
   var diag={mfPos:c.clNamePos,mfOn:TClassDecl(c),mfFields:fields,mfCause:AbstractParent(csup,params)};
   CompilerMessage.addModuleDiagnostic(ctx.com,c.clModule,DiagnosticsPrinter.makeMissingFieldsMessage(diag));
  } else {
   var pctx=printContext(),sub=missing.map(function(pair) {var cf=pair.field; var s=switch follow(cf.cfType) {case TFun(tl,_):tl.map(arg -> arg.name+":"+sType(pctx,arg.type)).join(", "); case t:sType(pctx,t);}; return makeError(Custom(complMsg(cf.cfName+"("+s+")")),cf.cfNamePos);});
   var singular=missing.length==1;
   var wrapped=[makeError(Custom("Implement "+(singular?"it":"them")+" or make "+Globals.sTypePath(c.clPath)+" abstract as well"),c.clNamePos,sub)];
   displayErrorExt(ctx.com,makeError(Custom("This class extends abstract class "+Globals.sTypePath(csup.clPath)+" but doesn't implement the following method"+(singular?"":"s")),c.clNamePos,wrapped));
  }
 }
 public static function setHeritance(ctx:Dynamic,c:Dynamic,herits:Array<Dynamic>,p:Dynamic):Array<Void->Void> {
  var isLib=Meta.has(Meta.LibType,c.clMeta),oldMeta=c.clMeta,hasInterf=false;
  function processMeta(csup:Dynamic):Void {
   var list:Array<Dynamic>=csup.clMeta.copy(); list.reverse();
   for(m in list) if(m.meta==Meta.AutoBuild) c.clMeta=[{meta:Meta.Build,exprs:m.exprs,pos:mkZeroRangePos(c.clPos)},m].concat(c.clMeta);
   var isParam=switch c.clKind {case KTypeParameter(_):true; case _:false;};
   if(hasClassFlag(csup,CFinal)&&!((hasClassFlag(csup,CExtern)&&Meta.has(Meta.Hack,c.clMeta))||isParam)) raiseTypingError("Cannot extend a final "+(hasClassFlag(c,CInterface)?"interface":"class"),p);
  }
  function checkCancelBuild(csup:Dynamic):Void {var state=csup.clBuild(); if(state!=Built) {c.clMeta=oldMeta; throw new BuildCanceled(state);}}
  function checkHerit(t:Dynamic,isExtends:Bool,p:Dynamic):Void->Void {
   function checkInterfacesOrDelay():Void switch c.clBuild() {
    case BuildMacro(pending):pending.value.unshift(function() delay(ctx.g,PConnectField,checkInterfacesOrDelay));
    case _ if(ctx.com.display.dmsFullTyping):checkInterfaces(ctx,c);
    case _:
   }
   if(isExtends) {
    if(c.clSuper!=null) raiseTypingError("Cannot extend several classes",p);
    var sup=checkExtends(ctx,c,t,p),csup=sup.c,params=sup.params;
    if(hasClassFlag(c,CInterface)) {
     if(!hasClassFlag(csup,CInterface)) raiseTypingError("Cannot extend by using a class ("+Globals.sTypePath(c.clPath)+" extends "+Globals.sTypePath(csup.clPath)+")",p);
     c.clImplements.unshift({c:csup,params:params});
     if(!hasInterf) {if(!isLib) delay(ctx.g,PConnectField,checkInterfacesOrDelay); hasInterf=true;}
    } else {if(hasClassFlag(csup,CInterface)) raiseTypingError("Cannot extend by using an interface ("+Globals.sTypePath(c.clPath)+" extends "+Globals.sTypePath(csup.clPath)+")",p); c.clSuper={c:csup,params:params};}
    return function() {checkCancelBuild(csup); processMeta(csup);};
   }
   return switch follow(t) {
    case TInst(({clPath:{pack:[],name:"ArrayAccess"}} => ca),[t]) if(hasClassFlag(ca,CExtern)):
     if(c.clArrayAccess!=null) raiseTypingError("Duplicate array access",p); c.clArrayAccess=t; function() {};
    case TInst(intf,params):
     if(extendsClass(intf,c)) raiseTypingError("Recursive class",p);
     if(hasClassFlag(c,CInterface)) raiseTypingError("Interfaces cannot implement another interface (use extends instead)",p);
     if(!hasClassFlag(intf,CInterface)) raiseTypingError("You can only implement an interface",p);
     c.clImplements.unshift({c:intf,params:params});
     if(!hasInterf&&!isLib&&!Meta.has(Meta.Custom("$do_not_check_interf"),c.clMeta)) {delay(ctx.g,PConnectField,checkInterfacesOrDelay); hasInterf=true;}
     function() {checkCancelBuild(intf); processMeta(intf);};
    case TDynamic(t):
     if(c.clDynamic!=null) raiseTypingError("Cannot have several dynamics",p);
     if(!hasClassFlag(c,CExtern)) displayError(ctx.com,"In haxe 4, implements Dynamic is only supported on externs",p);
     c.clDynamic=t==null?tDynamic:t; function() {};
    case _:raiseTypingError("Should implement by using an interface",p);
   };
  }
  var selected=[];
  for(h in herits) switch h {case HExtends(t):selected.push({isExtends:true,type:t}); case HImplements(t):selected.push({isExtends:false,type:t}); case _:}
  var fl=[];
  for(h in selected) try {
   var t:Dynamic;
   try t=Typeload.loadInstance(ctx,h.type,ParamNormal,LoadNormal,true) catch(e:Dynamic) {switch e {
    case DisplayException(DisplayFields(({fkind:CRTypeHint} => r))):
     if(!h.isExtends&&hasClassFlag(c,CInterface)) raiseFields([],CRImplements,r.fsubject);
     var l=(cast r.fitems:Array<Dynamic>).filter(function(item) return switch item.ciKind {
      case ITType(({kind:Interface} => cm),_):(!h.isExtends||hasClassFlag(c,CInterface))&&CompletionModuleType.getPath(cm)!=c.clPath;
      case ITType(({kind:Class} => cm),_):h.isExtends&&!hasClassFlag(c,CInterface)&&CompletionModuleType.getPath(cm)!=c.clPath&&(!cm.isFinal||Meta.has(Meta.Hack,c.clMeta))&&(!isBasicClassPath({pack:cm.pack,name:cm.name})||(hasClassFlag(c,CExtern)&&cm.isExtern));
      case _:false;
     });
     t=raiseFields(l,h.isExtends?CRExtends:CRImplements,r.fsubject);
    case _:throw e;
   }}
   fl.push(checkHerit(t,h.isExtends,h.type.posFull));
  } catch(e:Dynamic) {switch e {
   case Error({errMessage:ModuleNotFound({pack:[],name:name}),errPos:p}) if(ctx.com.display.dmsKind!=DMNone):if(Diagnostics.errorInDiagnosticsRun(ctx.com,p)) DisplayToplevel.handleUnresolvedIdentifier(ctx,name,p,true);
   case _:throw e;
  }}
  return fl;
 }
}
