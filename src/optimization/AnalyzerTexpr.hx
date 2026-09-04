package optimization;
import core.Ast;
import core.Globals;
import core.TType;
import core.TFunctions.*;
import core.TUnification.*;
import core.TFunctions.TypeExit;
import core.Texpr;
import core.Texpr.*;
import core.Meta;
import optimization.AnalyzerTypes;
import optimization.OptimizerTexpr.*;
import context.PurityState;
import optimization.AnalyzerConfig;
// haxe/src/optimization/analyzerTexpr.ml — mechanical draft; not compiled or validated.
class AnalyzerTexpr {
 public static function sExprPretty(e:TExpr):String return core.TPrinting.sExprPretty(false,"",false,core.TPrinting.sType.bind(core.TPrinting.printContext()),e);
 public static function isStackAllocated(c:TClass):Bool return Meta.has(StructAccess,c.clMeta);
 public static function mapValues(f:TExpr->TExpr,e:TExpr,allowControlFlow:Bool = true):{expr:TExpr,finalExpr:Null<TExpr>} {
  var branching = false; var finalExpr = null;
  function value(e:TExpr):TExpr {if (branching) return f(e); finalExpr = e; return mk(TConst(TNull),e.etype,e.epos);}
  function loop(complex:Bool,e:TExpr):TExpr return switch e.eexpr {
   case TIf(e1,e2,e3) if (e3 != null):branching = true; var e2 = loop(true,e2); var e3 = loop(true,e3); withExpr(e,TIf(e1,e2,e3));
   case TSwitch(s):branching = true; var cases = s.switchCases.map(c -> {casePatterns:c.casePatterns,caseExpr:loop(true,c.caseExpr)}); var def = s.switchDefault == null ? null : loop(true,s.switchDefault); withExpr(e,TSwitch(mkSwitch(s.switchSubject,cases,def,s.switchExhaustive)));
   case TBlock([e1]):loop(complex,e1);
   case TBlock(el):if (el.length > 0) {var last = loop(true,el[el.length - 1]); var block = withExpr(e,TBlock(el.slice(0,el.length - 1).concat([last]))); withExpr(block,TMeta({meta:core.MetaList.StrictMeta.MergeBlock,exprs:[],pos:block.epos},block));} else {if (!complex) throw new TypeExit(); value(e);}
   case TTry(e1,catches):branching = true; var e1 = loop(true,e1); withExpr(e,TTry(e1,catches.map(c -> {variable:c.variable,expr:loop(true,c.expr)})));
   case TMeta(m,e1):withExpr(e,TMeta(m,loop(complex,e1))); case TParenthesis(e1):withExpr(e,TParenthesis(loop(complex,e1)));
   case TBreak | TContinue | TThrow(_) | TReturn(_):if (!allowControlFlow) throw new TypeExit(); e;
   case _:if (!complex) throw new TypeExit(); value(e);
  }; var result = loop(false,e); return {expr:result,finalExpr:finalExpr};
 }
 public static function canThrow(e:TExpr):Bool return switch e.eexpr {case TConst(_) | TLocal(_) | TTypeExpr(_) | TFunction(_) | TBlock(_):false; case TCall(_,_) | TNew(_,_,_) | TThrow(_) | TField(_,_) | TArray(_,_):true; case TCast(_,mt) if (mt != null):true; case _:checkExpr(canThrow,e);};
 public static function canBeInlined(e:TExpr):Bool return switch e.eexpr {case TConst(_):true; case TParenthesis(e1) | TMeta(_,e1):canBeInlined(e1); case _:false;};
 public static function targetHandlesUnops(com:Dynamic):Bool return switch com.platform {case Lua | Python:false; case _:true;};
 public static function targetHandlesAssignOps(com:Dynamic,e2:TExpr):Bool return switch com.platform {case Php:!hasSideEffect(e2); case Lua:false; case Cpp if (!core.Define.defined(com.defines,core.Define.Cppia)):!hasSideEffect(e2); case _:true;};
 public static function targetHandlesSideEffectOrder(com:Dynamic):Bool return switch com.platform {case Cpp:core.Define.defined(com.defines,core.Define.Cppia); case Php:false; case _:true;};
 public static function canBeUsedAsValue(com:Dynamic,e:TExpr):Bool {
  function loop(e:TExpr):Bool return switch e.eexpr {case TBlock([e]):loop(e); case TBlock(_) | TSwitch(_) | TTry(_,_) | TReturn(_) | TThrow(_) | TBreak | TContinue:false; case TCall({eexpr:TConst(TString("phi"))},_):false; case TUnop(Increment | Decrement,_,_) if (!targetHandlesUnops(com)):false; case TFunction(_):true; case _:!checkExpr(e -> !loop(e),e);};
  switch [com.platform,e.eexpr] {case [Cpp | Jvm | Flash | Lua,TConst(TNull)]:return false; case _:} return loop(e);
 }
 public static function wrapMeta(s:String,e:TExpr):TExpr return mk(TMeta({meta:core.MetaList.StrictMeta.Custom(s),exprs:[],pos:e.epos},e),e.etype,e.epos);
 public static function isReallyUnbound(s:String):Bool return s != "`trace" && s != "__int__";
 static var r = ~/^[A-Za-z0-9_]+$/;
 public static function isUnboundCallThatMightHaveSideEffects(s:String,el:Array<TExpr>):Bool return switch [s,el] {case ["__js__",[{eexpr:TConst(TString(code))}]] if (r.match(code)):false; case _:true;};
 public static function maybeInheritVarName(v:TVar,alias:TVar):Void if (v.vName != alias.vName) switch [alias.vKind,v.vKind] {case [VUser(_),VUser(_)]:case [VUser(_),_]:v.vName = alias.vName; case _:}
 public static function typeChangeOk(com:Dynamic,t1:T,t2:T):Bool {
  if (t1 == t2) return true; function map(t:T):T return switch t {case TMono(r):r.tmType == null ? tDynamic : map(r.tmType); case _:core.TFunctions.map(map,t);}; t1 = map(t1); t2 = map(t2);
  function nullable(t:T):Bool return switch t {case TMono(r):r.tmType != null && nullable(r.tmType); case TAbstract({aPath:{pack:[],name:"Null"}},[_]):true; case TLazy(f):nullable(lazyType(f)); case TType(t,tl):nullable(applyTypedef(t,tl)); case TFun(_) | TInst({clKind:KTypeParameter(_)},_):false; case TAbstract(a,_) if (Meta.has(CoreType,a.aMeta)):!Meta.has(NotNull,a.aMeta); case TAbstract(a,tl):!Meta.has(NotNull,a.aMeta) && nullable(applyParams(a.aParams,tl,a.aThis)); case _:true;};
  if (t1 == t2) return true; return switch [follow(t1),follow(t2)] {case [TDynamic(_),_] | [_,TDynamic(_)]:false; case _:com.platformConfig.pfStatic && nullable(t1) != nullable(t2) ? false : typeIseq(t1,t2);};
 }
 public static function dynarrayMap<A>(f:A->A,d:Array<A>):Void for (i in 0...d.length) d[i] = f(d[i]);
 public static function dynarrayMapi<A>(f:Int->A->A,d:Array<A>):Void for (i in 0...d.length) d[i] = f(i,d[i]);
}
class TexprFilter {
 public static function apply(com:Dynamic,e:TExpr):TExpr {
  function loop(e:TExpr):TExpr return switch e.eexpr {
   case TBinop(op = OpBoolAnd | OpBoolOr,e1,e2):var cond = op == OpBoolOr ? mk(TUnop(Not,Prefix,e1),com.basic.tbool,e.epos) : e1; var otherwise = mk(TConst(TBool(op == OpBoolOr)),com.basic.tbool,e.epos); loop(mk(TIf(cond,e2,otherwise),e.etype,e.epos));
   case TBinop(OpAssignOp(op),e1 = {eexpr:TLocal(_)},e2):var inner = withExpr(e,TBinop(op,e1,e2)); loop(withExpr(inner,TBinop(OpAssign,e1,inner)));
   case TUnop(op = Increment | Decrement,flag,e1 = {eexpr:TLocal(_)}):var one = mk(TConst(TInt(1)),com.basic.tint,e1.epos); var assign = withExpr(e,TBinop(OpAssignOp(op == Increment ? OpAdd : OpSub),e1,one)); loop(flag == Prefix ? assign : mk(TBlock([assign,withExpr(assign,TBinop(op == Increment ? OpSub : OpAdd,e1,one))]),assign.etype,assign.epos));
   case TWhile(e1,e2,DoWhile) if (isTrueExpr(e1)):loop(withExpr(e,TWhile(e1,e2,NormalWhile)));
   case TWhile(e1,e2,flag) if (!isTrueExpr(e1)):
    var p = e.epos; var br = mk(TBreak,tDynamic,p); var not = mk(TUnop(Not,Prefix,Texpr.Builder.mkParent(e1)),e1.etype,e1.epos); function makeIf(eo:Null<TExpr>):TExpr return mk(TIf(not,br,eo),com.basic.tvoid,p);
    function mapContinue(e:TExpr):TExpr return switch e.eexpr {case TContinue:duplicateTvars(eIdentity,makeIf(e)); case TWhile(_,_,_):e; case _:mapExpr(mapContinue,e);};
    if (flag != NormalWhile) e2 = mapContinue(e2); var condition = makeIf(null); var block = flag == NormalWhile ? concat(condition,e2) : concat(e2,condition); var yes = Texpr.Builder.mkParent(mk(TConst(TBool(true)),com.basic.tbool,p)); loop(mk(TWhile(yes,block,NormalWhile),e.etype,p));
   case _:mapExpr(loop,e);
  }; return loop(e);
 }
}
typedef InterferenceReportData = {var irVarReads:haxe.ds.IntMap<Bool>; var irVarWrites:haxe.ds.IntMap<Bool>; var irFieldReads:haxe.ds.StringMap<Bool>; var irFieldWrites:haxe.ds.StringMap<Bool>; var irStateRead:Bool; var irStateWrite:Bool;}
class InterferenceReport {
 public static function create():InterferenceReportData return {irVarReads:new haxe.ds.IntMap(),irVarWrites:new haxe.ds.IntMap(),irFieldReads:new haxe.ds.StringMap(),irFieldWrites:new haxe.ds.StringMap(),irStateRead:false,irStateWrite:false};
 public static function setVarRead(ir:InterferenceReportData,v:TVar):Void ir.irVarReads.set(v.vId,true);
 public static function setVarWrite(ir:InterferenceReportData,v:TVar):Void ir.irVarWrites.set(v.vId,true);
 public static function setFieldRead(ir:InterferenceReportData,s:String):Void ir.irFieldReads.set(s,true);
 public static function setFieldWrite(ir:InterferenceReportData,s:String):Void ir.irFieldWrites.set(s,true);
 public static function setStateRead(ir:InterferenceReportData):Void ir.irStateRead = true;
 public static function setStateWrite(ir:InterferenceReportData):Void ir.irStateWrite = true;
 public static function hasVarRead(ir:InterferenceReportData,v:TVar):Bool return ir.irVarReads.exists(v.vId);
 public static function hasVarWrite(ir:InterferenceReportData,v:TVar):Bool return ir.irVarWrites.exists(v.vId);
 public static function hasFieldRead(ir:InterferenceReportData,s:String):Bool return ir.irFieldReads.exists(s);
 public static function hasFieldWrite(ir:InterferenceReportData,s:String):Bool return ir.irFieldWrites.exists(s);
 public static function hasStateRead(ir:InterferenceReportData):Bool return ir.irStateRead;
 public static function hasStateWrite(ir:InterferenceReportData):Bool return ir.irStateWrite;
 public static function hasAnyFieldRead(ir:InterferenceReportData):Bool return ir.irFieldReads.iterator().hasNext();
 public static function hasAnyFieldWrite(ir:InterferenceReportData):Bool return ir.irFieldWrites.iterator().hasNext();
 public static function hasAnyVarRead(ir:InterferenceReportData):Bool return ir.irVarReads.iterator().hasNext();
 public static function hasAnyVarWrite(ir:InterferenceReportData):Bool return ir.irVarWrites.iterator().hasNext();
 public static function fromTexpr(e:TExpr):InterferenceReportData {
  var ir = create(); function loop(e:TExpr):Void switch e.eexpr {
   case TLocal(v):setVarRead(ir,v); if (hasVarFlag(v,VCaptured)) setStateRead(ir);
   case TBinop(OpAssign,{eexpr:TLocal(v)},e2):setVarWrite(ir,v); if (hasVarFlag(v,VCaptured)) setStateWrite(ir); loop(e2);
   case TBinop(OpAssignOp(_),{eexpr:TLocal(v)},e2):setVarRead(ir,v); setVarWrite(ir,v); if (hasVarFlag(v,VCaptured)) {setStateRead(ir); setStateWrite(ir);} loop(e2);
   case TUnop(Increment | Decrement,_,{eexpr:TLocal(v)}):setVarRead(ir,v); setVarWrite(ir,v);
   case TField(e1,fa):loop(e1); if (!isReadOnlyFieldAccess(e1,fa)) setFieldRead(ir,fieldName(fa));
   case TBinop(OpAssign,{eexpr:TField(e1,fa)},e2):setFieldWrite(ir,fieldName(fa)); loop(e1); loop(e2);
   case TBinop(OpAssignOp(_),{eexpr:TField(e1,fa)},e2):var name = fieldName(fa); setFieldRead(ir,name); setFieldWrite(ir,name); loop(e1); loop(e2);
   case TUnop(Increment | Decrement,_,{eexpr:TField(e1,fa)}):var name = fieldName(fa); setFieldRead(ir,name); setFieldWrite(ir,name); loop(e1);
   case TArray(e1,e2):setStateRead(ir); loop(e1); loop(e2);
   case TBinop(OpAssign,{eexpr:TArray(e1,e2)},e3):setStateWrite(ir); loop(e1); loop(e2); loop(e3);
   case TBinop(OpAssignOp(_),{eexpr:TArray(e1,e2)},e3):setStateRead(ir); setStateWrite(ir); loop(e1); loop(e2); loop(e3);
   case TUnop(Increment | Decrement,_,{eexpr:TArray(e1,e2)}):setStateRead(ir); setStateWrite(ir); loop(e1); loop(e2);
   case TCall({eexpr:TIdent(s)},el) if (!AnalyzerTexpr.isUnboundCallThatMightHaveSideEffects(s,el)):for (e in el) loop(e);
   case TNew(c,_,el) if (c.clConstructor != null && PurityStateTools.isPure(c,c.clConstructor)):setStateRead(ir); for (e in el) loop(e);
   case TCall({eexpr:TField(e1,FEnum(_,_))},el):loop(e1); for (e in el) loop(e);
   case TCall({eexpr:TField(e1,fa)},el) if (PurityStateTools.isPureFieldAccess(fa)):setStateRead(ir); loop(e1); for (e in el) loop(e);
   case TCall(e1,el):setStateRead(ir); setStateWrite(ir); loop(e1); for (e in el) loop(e);
   case TNew(_,_,el):setStateRead(ir); setStateWrite(ir); for (e in el) loop(e);
   case TBinop(OpAssign,e1,e2):setStateWrite(ir); loop(e1); loop(e2);
   case TBinop(OpAssignOp(_),e1,e2):setStateRead(ir); setStateWrite(ir); loop(e1); loop(e2);
   case TUnop(Increment | Decrement,_,e1):setStateRead(ir); setStateWrite(ir); loop(e1);
   case _:iter(loop,e);
  } loop(e); return ir;
 }
 public static function toString(ir:InterferenceReportData):String {
  function ints(map:haxe.ds.IntMap<Bool>):String {var keys = [for (k in map.keys()) k]; keys.sort((a,b) -> b - a); return keys.map(Std.string).join(", ");}
  function strings(map:haxe.ds.StringMap<Bool>):String {var keys = [for (k in map.keys()) k]; keys.sort((a,b) -> Reflect.compare(b,a)); return keys.join(", ");}
  return core.TPrinting.Printer.sRecordFields("",[{name:"ir_var_reads",value:ints(ir.irVarReads)},{name:"ir_var_writes",value:ints(ir.irVarWrites)},{name:"ir_field_reads",value:strings(ir.irFieldReads)},{name:"ir_field_writes",value:strings(ir.irFieldWrites)},{name:"ir_state_read",value:Std.string(ir.irStateRead)},{name:"ir_state_write",value:Std.string(ir.irStateWrite)}]);
 }
}
class FusionState {
 var changed = false; var varReads = new haxe.ds.IntMap<Int>(); var varWrites = new haxe.ds.IntMap<Int>();
 public function new() {}
 function change(map:haxe.ds.IntMap<Int>,v:TVar,delta:Int):Void map.set(v.vId,(map.exists(v.vId) ? map.get(v.vId) : 0) + delta);
 public function incReads(v:TVar):Void change(varReads,v,1); public function decReads(v:TVar):Void change(varReads,v,-1);
 public function incWrites(v:TVar):Void change(varWrites,v,1); public function decWrites(v:TVar):Void change(varWrites,v,-1);
 public function getReads(v:TVar):Int return varReads.exists(v.vId) ? varReads.get(v.vId) : 0; public function getWrites(v:TVar):Int return varWrites.exists(v.vId) ? varWrites.get(v.vId) : 0;
 public function changeWrites(v:TVar,delta:Int):Void change(varWrites,v,delta); public function markChanged():Void changed = true; public function reset():Void changed = false; public function didChange():Bool return changed;
 public function inferFromTexpr(e:TExpr):Void {function loop(e:TExpr):Void switch e.eexpr {case TLocal(v):incReads(v); case TBinop(OpAssign,{eexpr:TLocal(v)},e2):incWrites(v); loop(e2); case _:iter(loop,e);} loop(e);}
}
class Fusion {
 public static function isAssignOp(op:Binop):Bool return switch op {case OpAdd | OpMult | OpDiv | OpSub | OpAnd | OpOr | OpXor | OpShl | OpShr | OpUShr | OpMod:true; case OpAssign | OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte | OpBoolAnd | OpBoolOr | OpAssignOp(_) | OpInterval | OpIn | OpNullCoal | OpArrow:false;};
 public static function useAssignOp(com:Dynamic,op:Binop,e1:TExpr,e2:TExpr,e3:TExpr):Bool {if (com.platform == Eval) {e1 = Texpr.skip(e1); e2 = Texpr.skip(e2);} return isAssignOp(op) && AnalyzerTexpr.targetHandlesAssignOps(com,e3) && Texpr.equal(e1,e2) && !hasSideEffect(e1);}
 public static function handleAssignedLocal(actx:AnalyzerContext,v1:TVar,value:TExpr,el:Array<TExpr>):Null<Array<TExpr>> {
  var config = actx.config; var com = actx.com; var found = false; var blocked = false; var ir = InterferenceReport.fromTexpr(value);
  if (config.fusionDebug) Sys.println("INTERFERENCE: " + InterferenceReport.toString(ir) + "\nINTO: " + core.TPrinting.sExprPretty(true,"",false,core.TPrinting.sType.bind(core.TPrinting.printContext()),mk(TBlock(el),tDynamic,Globals.nullPos)));
  function replace(e:TExpr):TExpr {
   function explore(e:TExpr):TExpr {var old = blocked; blocked = true; var e = replace(e); blocked = old; return e;}
   function handleEl(el:Array<TExpr>):Array<TExpr> {
    if (AnalyzerTexpr.targetHandlesSideEffectOrder(com)) return el.map(replace);
    var reallyFound = found; var el = el.map(e -> {found = false; var e = replace(e); if (found) reallyFound = true; return e;}); found = reallyFound; return el;
   }
   function handleCall(e:TExpr,el:Array<TExpr>):{expr:TExpr,args:Array<TExpr>} return switch com.platform {case Neko:var el = el.map(replace); var e = replace(e); {expr:e,args:el}; case Cpp:var e = replace(e); {expr:e,args:handleEl(el)}; case _:var e = replace(e); {expr:e,args:el.map(replace)};};
   if (found) return e;
   return switch e.eexpr {
    case TWhile(_,_,_) | TTry(_,_):throw new TypeExit();
    case TFunction(_):e;
    case TIf(e1,e2,eo):var e1 = replace(e1); if (!found && (ir.irStateWrite || InterferenceReport.hasAnyFieldWrite(ir) || InterferenceReport.hasAnyVarWrite(ir))) throw new TypeExit(); var e2 = replace(e2); withExpr(e,TIf(e1,e2,eo == null ? null : replace(eo)));
    case TSwitch(s):var subject = switch com.platform {case Lua | Python:explore(s.switchSubject); case _:replace(s.switchSubject);}; if (!found) throw new TypeExit(); withExpr(e,TSwitch(mkSwitch(subject,s.switchCases,s.switchDefault,s.switchExhaustive)));
    case TLocal(v2) if (v1 == v2 && !blocked):found = true; AnalyzerTexpr.typeChangeOk(com,v1.vType,value.etype) ? value : mk(TCast(value,null),v1.vType,e.epos);
    case TLocal(v):if (ir.irVarWrites.exists(v.vId) || (hasVarFlag(v,VCaptured) || core.TOther.ExtType.hasReferenceSemantics(v.vType)) && ir.irStateWrite) throw new TypeExit(); e;
    case TBinop(OpAssign,e1 = {eexpr:TLocal(v)},e2):var e2 = replace(e2); if (!found && ir.irVarReads.exists(v.vId)) throw new TypeExit(); withExpr(e,TBinop(OpAssign,e1,e2));
    case TBinop(OpAssignOp(_),{eexpr:TLocal(v)},_) | TUnop(Increment | Decrement,_,{eexpr:TLocal(v)}) if (v1 == v):throw new TypeExit();
    case TBinop(op = OpAssignOp(_),e1 = {eexpr:TLocal(v)},e2):var e2 = replace(e2); if (!found && (ir.irVarReads.exists(v.vId) || ir.irVarWrites.exists(v.vId))) throw new TypeExit(); withExpr(e,TBinop(op,e1,e2));
    case TUnop(Increment | Decrement,_,{eexpr:TLocal(v)}) if (ir.irVarReads.exists(v.vId) || ir.irVarWrites.exists(v.vId)):throw new TypeExit();
    case TField(e1,fa):var e1 = replace(e1); if (!found && !isReadOnlyFieldAccess(e1,fa) && (ir.irFieldWrites.exists(fieldName(fa)) || ir.irStateWrite)) throw new TypeExit(); withExpr(e,TField(e1,fa));
    case TBinop(OpAssign,ef = {eexpr:TField(e1,fa)},e2):var e1 = replace(e1); var e2 = replace(e2); if (!found && (ir.irFieldReads.exists(fieldName(fa)) || ir.irStateRead)) throw new TypeExit(); withExpr(e,TBinop(OpAssign,withExpr(ef,TField(e1,fa)),e2));
    case TBinop(op = OpAssignOp(_),ef = {eexpr:TField(e1,fa)},e2):var e1 = replace(e1); var name = fieldName(fa); if (!found && (ir.irFieldWrites.exists(name) || ir.irStateWrite)) throw new TypeExit(); var e2 = replace(e2); if (!found && (ir.irFieldReads.exists(name) || ir.irStateRead)) throw new TypeExit(); withExpr(e,TBinop(op,withExpr(ef,TField(e1,fa)),e2));
    case TUnop(Increment | Decrement,_,{eexpr:TField(_,fa)}) if (ir.irFieldReads.exists(fieldName(fa)) || ir.irStateRead || ir.irFieldWrites.exists(fieldName(fa)) || ir.irStateWrite):throw new TypeExit();
    case TArray(e1,e2):var e1 = replace(e1); var e2 = replace(e2); if (!found && ir.irStateWrite) throw new TypeExit(); withExpr(e,TArray(e1,e2));
    case TBinop(OpAssign,ef = {eexpr:TArray(e1,e2)},e3):var e1 = replace(e1); var e2 = replace(e2); var e3 = replace(e3); if (!found && ir.irStateRead) throw new TypeExit(); withExpr(e,TBinop(OpAssign,withExpr(ef,TArray(e1,e2)),e3));
    case TBinop(op = OpAssignOp(_),ef = {eexpr:TArray(e1,e2)},e3):var e1 = replace(e1); var e2 = replace(e2); if (!found && ir.irStateWrite) throw new TypeExit(); var e3 = replace(e3); if (!found && ir.irStateRead) throw new TypeExit(); withExpr(e,TBinop(op,withExpr(ef,TArray(e1,e2)),e3));
    case TUnop(Increment | Decrement,_,{eexpr:TArray(_,_)}) if (ir.irStateRead || ir.irStateWrite):throw new TypeExit();
    case TCall({eexpr:TIdent(s)},el) if (!AnalyzerTexpr.isUnboundCallThatMightHaveSideEffects(s,el)):e;
    case TNew(c,tl,el) if (c.clConstructor != null && PurityStateTools.isPure(c,c.clConstructor)):var el = handleEl(el); if (!found && (ir.irStateWrite || InterferenceReport.hasAnyFieldWrite(ir))) throw new TypeExit(); withExpr(e,TNew(c,tl,el));
    case TNew(c,tl,el):var el = handleEl(el); if (!found && (ir.irStateWrite || ir.irStateRead || InterferenceReport.hasAnyFieldRead(ir) || InterferenceReport.hasAnyFieldWrite(ir))) throw new TypeExit(); withExpr(e,TNew(c,tl,el));
    case TCall(ef = {eexpr:TField(_,FEnum(_,_))},el):withExpr(e,TCall(ef,handleEl(el)));
    case TCall(ef = {eexpr:TField(_,fa)},el) if (PurityStateTools.isPureFieldAccess(fa)):var r = handleCall(ef,el); if (!found && (ir.irStateWrite || InterferenceReport.hasAnyFieldWrite(ir))) throw new TypeExit(); withExpr(e,TCall(r.expr,r.args));
    case TCall(e1,el):var r = switch e1.eexpr {case TIdent(s) if (s != "`trace" && s != "__int__"):{expr:e1,args:el}; case _:handleCall(e1,el);}; if (!found && (ir.irStateRead || InterferenceReport.hasAnyFieldRead(ir) || ir.irStateWrite || InterferenceReport.hasAnyFieldWrite(ir))) throw new TypeExit(); withExpr(e,TCall(r.expr,r.args));
    case TObjectDecl(fl):var el = handleEl(fl.map(f -> f.expr)); if (!found && (ir.irStateWrite || InterferenceReport.hasAnyFieldWrite(ir))) throw new TypeExit(); if (fl.length != el.length) throw "Invalid_argument: List.map2"; withExpr(e,TObjectDecl([for (i in 0...fl.length) {key:fl[i].key,expr:el[i]}]));
    case TArrayDecl(el):withExpr(e,TArrayDecl(handleEl(el)));
    case TBinop(op,e1,e2) if (com.platform == Cpp):var e1 = replace(e1); var temp = found; found = false; var e2 = replace(e2); found = found || temp; withExpr(e,TBinop(op,e1,e2));
    case _:mapExpr(replace,e);
   };
  }
  try {var out = []; for (i in 0...el.length) {var mapped:TExpr = actx.withTimer(["<-","fusion","fuse","replace"],function() return replace(el[i])); out.push(mapped); if (found) {out = out.concat(el.slice(i + 1)); break;}} if (!found) throw new TypeExit(); if (config.fusionDebug) Sys.println("YES: " + AnalyzerTexpr.sExprPretty(mk(TBlock(out),tDynamic,Globals.nullPos))); return out;}
  catch (_:TypeExit) {if (config.fusionDebug) Sys.println("NO: " + haxe.CallStack.toString(haxe.CallStack.exceptionStack())); return null;}
 }
 public static function blockElement(config:AnalyzerConfigData,state:FusionState,loopBottom:Bool,acc:Array<TExpr>,el:Array<TExpr>):Array<TExpr> {
  function loop(acc:Array<TExpr>,el:Array<TExpr>):Array<TExpr> {
   if (el.length == 0) return acc; var e = el[0]; var rest = el.slice(1); return switch e.eexpr {
    case TBinop(OpAssign,{eexpr:TLocal(v1)},{eexpr:TLocal(v2)}) if (v1 == v2):loop(acc,rest);
    case TBinop(OpAssign | OpAssignOp(_),_,_) | TUnop(Increment | Decrement,_,_):loop([e].concat(acc),rest);
    case TLocal(_) if (!config.localDce):loop([e].concat(acc),rest);
    case TLocal(v):state.decReads(v); loop(acc,rest);
    case TField(_,fa) if (PurityStateTools.isExplicitlyImpure(fa)):loop([e].concat(acc),rest);
    case TFunction(_) | TConst(_) | TTypeExpr(_):loop(acc,rest);
    case TMeta(meta = {meta:core.MetaList.StrictMeta.Pure},_) if (PurityStateTools.getPurityFromMeta([meta]) == Pure):loop(acc,rest);
    case TCall({eexpr:TField(e1,fa)},args) if (PurityStateTools.isPureFieldAccess(fa) && config.localDce):loop(acc,[e1].concat(args).concat(rest));
    case TNew(c,tl,args) if (c.clConstructor != null && PurityStateTools.isPure(c,c.clConstructor) && config.localDce):loop(acc,args.concat(rest));
    case TIf({eexpr:TConst(TBool(t))},a,b):loop(acc,t ? [a].concat(rest) : b == null ? rest : [b].concat(rest));
    case TSwitch(s):var folded = Optimizer.checkConstantSwitch(s); folded == null ? loop([e].concat(acc),rest) : loop(acc,[folded].concat(rest));
    case TParenthesis(e1) | TMeta(_,e1) | TCast(e1,null) | TField(e1,_) | TUnop(_,_,e1) | TEnumIndex(e1) | TEnumParameter(e1,_,_):loop(acc,[e1].concat(rest));
    case TArray(e1,e2) | TBinop(_,e1,e2):loop(acc,[e1,e2].concat(rest));
    case TArrayDecl(args) | TCall({eexpr:TField(_,FEnum(_,_))},args):loop(acc,args.concat(rest));
    case TObjectDecl(fl):loop(acc,fl.map(f -> f.expr).concat(rest));
    case TIf(e1,e2,null) if (!hasSideEffect(e2)):loop(acc,[e1].concat(rest));
    case TIf(e1,e2,e3) if (e3 != null && !hasSideEffect(e2) && !hasSideEffect(e3)):loop(acc,[e1].concat(rest));
    case TBlock([e1]):loop(acc,[e1].concat(rest)); case TBlock([]):loop(acc,rest);
    case TContinue if (loopBottom):loop([],rest);
    case _:loop([e].concat(acc),rest);
   };
  } return loop(acc,el);
 }
 public static function apply(actx:AnalyzerContext,e:TExpr):TExpr {
  var config = actx.config; var com = actx.com; var state = new FusionState(); actx.withTimer(["<-","fusion","infer_from_texpr"],function() state.inferFromTexpr(e));
  function blockElementTimed(bottom:Bool,acc:Array<TExpr>,el:Array<TExpr>):Array<TExpr> return actx.withTimer(["<-","fusion","block_element"],function() return blockElement(config,state,bottom,acc,el));
  function canBeFused(v:TVar,e:TExpr):Bool {
   var uses = state.getReads(v); var writes = state.getWrites(v); var asValue = AnalyzerTexpr.canBeUsedAsValue(com,e); var generated = switch v.vKind {case VUser(_) | VInlined | VInlinedConstructorVariable(_):false; case _:true;}; var typeParams = v.vExtra != null && v.vExtra.vParams.length > 0;
   function impure(e:TExpr):Bool return switch e.eexpr {case TField(_,FStatic(cl,cf) | FInstance(cl,_,cf)) if (hasClassFlag(cl,CExtern)):!(Meta.has(CoreApi,cl.clMeta) || PurityStateTools.isPure(cl,cf)); case _:checkExpr(impure,e);};
   var impureExtern = impure(e); var variableSemantics = core.TOther.ExtType.hasVariableSemantics(v.vType); var variableExpr = switch e.eexpr {case TLocal({vKind:VUser(_)}):false; case _:true;};
   var b = uses <= 1 && writes == 0 && asValue && !(variableSemantics && variableExpr) && (generated || config.optimize && config.fusion && config.userVarFusion && !typeParams && !impureExtern);
   if (config.fusionDebug) {Sys.println('\nFUSION: $b\n\tvar ${v.vName}<${v.vId}> = ' + AnalyzerTexpr.sExprPretty(e)); Sys.println('CONDITION:\n\tnum_uses:$uses <= 1 && num_writes:$writes = 0 && can_be_used_as_value:$asValue && not (has_variable_semantics:$variableSemantics && e.eexpr=TLocal:$variableExpr) (is_compiler_generated:$generated || config.optimize:${config.optimize} && config.fusion:${config.fusion} && config.user_var_fusion:${config.userVarFusion} && not has_type_params:$typeParams && not is_impuare_extern:$impureExtern)');} return b;
  }
  function fuse(acc:Array<TExpr>,el:Array<TExpr>):Array<TExpr> {
   if (el.length == 0) return acc; var first = el[0]; var rest = el.slice(1);
   switch first.eexpr {
    case TVar(v1,null) if (rest.length > 0):switch rest[0].eexpr {case TBinop(OpAssign,{eexpr:TLocal(v2)},e2) if (v1 == v2):state.markChanged(); state.decWrites(v1); return fuse([withExpr(first,TVar(v1,e2))].concat(acc),rest.slice(1)); case _:}
    case _:
   }
   switch first.eexpr {
    case TIf(_,_,eelse) if (eelse != null && AnalyzerTexpr.canBeUsedAsValue(com,first) && !core.TOther.ExtType.isVoid(first.etype) && !(com.platform == Cpp && !core.Define.defined(com.defines,core.Define.Cppia))):
     try {var count = 0; var lhs:Null<TExpr> = null; var wrap:TExpr->TExpr = null; function checkAssign(e:TExpr):TExpr return switch e.eexpr {case TBinop(OpAssign,e1,e2):count++; if (lhs == null) {lhs = e1; wrap = other -> withExpr(e,TBinop(OpAssign,e1,other)); e2;} else if (Texpr.equal(lhs,e1)) e2; else throw new TypeExit(); case _:throw new TypeExit();}; var result = AnalyzerTexpr.mapValues(checkAssign,first).expr; if (lhs == null) throw "AnalyzerTexpr.fuse missing assignment"; switch lhs.eexpr {case TLocal(v):state.changeWrites(v,-count + 1); case _:} result = wrap(result); state.markChanged(); return fuse([result].concat(acc),rest);} catch (_:TypeExit) return fuse([first].concat(acc),rest);
    case TVar(v,e1) if (e1 != null && config.optimize && config.localDce && state.getReads(v) == 0 && state.getWrites(v) == 0):return fuse(acc,[e1].concat(rest));
    case TVar(v1,null) if (!hasVarFlag(v1,VCaptured)):
     var found = false; function replace(deep:Bool,e:TExpr):TExpr return switch e.eexpr {case TBinop(OpAssign,{eexpr:TLocal(v2)},e2) if (v1 == v2):if (deep) throw new TypeExit(); found = true; withExpr(first,TVar(v1,e2)); case TLocal(v2) if (v1 == v2):throw new TypeExit(); case _:mapExpr(e -> replace(true,e),e);};
     try {var out = []; for (i in 0...rest.length) {out.push(replace(false,rest[i])); if (found) {out = out.concat(rest.slice(i + 1)); break;}} if (!found) throw new TypeExit(); state.markChanged(); state.decWrites(v1); return fuse(acc,out);} catch (_:TypeExit) return fuse([first].concat(acc),rest);
    case TVar(v1,e1) if (e1 != null && canBeFused(v1,e1)):
     if (rest.length > 0) switch rest[0].eexpr {
      // v2 intentionally shadows the declaration variable, as upstream's pattern does.
      case TUnop(op = Increment | Decrement,Prefix,{eexpr:TLocal(v2)}):var found = false; function replace(e:TExpr):TExpr return switch e.eexpr {case TLocal(v) if (v2 == v):if (found) throw new TypeExit(); found = true; withExpr(e,TUnop(op,Postfix,e)); case TIf(_,_,_) | TSwitch(_) | TTry(_,_) | TWhile(_,_,_):throw new TypeExit(); case _:mapExpr(replace,e);};
       try {var ev = replace(first); if (!found) throw new TypeExit(); state.markChanged(); return fuse(acc,[ev].concat(rest.slice(1)));} catch (_:TypeExit) return fuse([first].concat(acc),rest);
      case _:
     }
     var result = handleAssignedLocal(actx,v1,e1,rest); if (result != null) {state.markChanged(); state.decReads(v1); return fuse(acc,result);} return fuse([first].concat(acc),rest);
    case TUnop(op = Increment | Decrement,Prefix,ev = {eexpr:TLocal(v)}) if (rest.length > 0):
     try {var second = rest[0]; var inner:TExpr; var wrap:TExpr->TExpr; switch second.eexpr {case TReturn(e2) if (e2 != null):inner = e2; wrap = e -> withExpr(e2,TReturn(e)); case TVar(v,e2) if (e2 != null):inner = e2; wrap = e -> withExpr(e2,TVar(v,e)); case _:throw new TypeExit();}
      var replacement = switch inner.eexpr {case TBinop(op2,{eexpr:TLocal(v2)},{eexpr:TConst(TInt(1))}) if (v == v2 && (op == Increment && op2 == OpSub || op == Decrement && op2 == OpAdd)):state.markChanged(); state.decReads(v2); wrap(withExpr(first,TUnop(op,Postfix,ev))); case TLocal(v2) if (v == v2):state.markChanged(); state.decReads(v2); wrap(withExpr(first,TUnop(op,Prefix,ev))); case _:throw new TypeExit();}; return fuse([replacement].concat(acc),rest.slice(1));
     } catch (_:TypeExit) return fuse([first].concat(acc),rest);
    case TBinop(OpAssign,e1,{eexpr:TBinop(op,e2,e3)}) if (useAssignOp(com,op,e1,e2,e3)):function reads(e:TExpr):Void switch e.eexpr {case TLocal(v):state.decReads(v); case _:iter(reads,e);} reads(e1); state.markChanged(); return fuse(acc,[withExpr(first,TBinop(OpAssignOp(op),e1,e3))].concat(rest));
    case TBinop(OpAssignOp(_),e1,_) if (rest.length > 0):switch rest[0].eexpr {case TVar(v,e2) if (e2 != null && Texpr.equal(e1,e2)):state.markChanged(); return fuse([withExpr(rest[0],TVar(v,first))].concat(acc),rest.slice(1)); case _:}
    case _:
   } return fuse([first].concat(acc),rest);
  }
  function timedFuse(el:Array<TExpr>):Array<TExpr> return actx.withTimer(["<-","fusion","fuse"],function() return fuse([],el));
  var loop:TExpr->TExpr = null;
  function block(bottom:Bool,el:Array<TExpr>,t:T,p:Pos):TExpr {
   el = el.map(loop); el.reverse(); el = blockElementTimed(bottom,[],el); el = timedFuse(el); el = blockElementTimed(false,[],el);
   while (true) {state.reset(); el = timedFuse(el); el = blockElementTimed(false,[],el); if (!state.didChange()) break;} return mk(TBlock(el),t,p);
  }
  loop = function(e:TExpr):TExpr return switch e.eexpr {case TWhile(cond,{eexpr:TBlock(el),etype:t,epos:p},flag):var cond = loop(cond); var body = block(true,el,t,p); withExpr(e,TWhile(cond,body,flag)); case TBlock(el):block(false,el,e.etype,e.epos); case TCall({eexpr:TIdent(s)},_) if (AnalyzerTexpr.isReallyUnbound(s)):e; case _:mapExpr(loop,e);}; return loop(e);
 }
}
class Cleanup {
 public static function apply(scom:Dynamic,e:TExpr):TExpr {
  function ifOrOp(e:TExpr,e1:TExpr,e2:TExpr,e3:TExpr):TExpr return switch [Texpr.skip(e1).eexpr,Texpr.skip(e2).eexpr,Texpr.skip(e3).eexpr] {
   case [_,TReturn(b),TReturn({eexpr:TConst(TBool(false))})] if (b != null):var binop = optimizeBinop(scom,withExpr(e,TBinop(OpBoolAnd,e1,b)),OpBoolAnd,e1,b); withExpr(e,TReturn(binop));
   case [TUnop(Not,Prefix,inner),TReturn(b),TReturn({eexpr:TConst(TBool(true))})] if (b != null):var binop = optimizeBinop(scom,withExpr(e,TBinop(OpBoolOr,inner,b)),OpBoolOr,inner,b); withExpr(e,TReturn(binop));
   case [TUnop(Not,Prefix,inner),_,TConst(TBool(true))]:optimizeBinop(scom,withExpr(e,TBinop(OpBoolOr,inner,e2)),OpBoolOr,inner,e2);
   case [_,_,TConst(TBool(false))]:optimizeBinop(scom,withExpr(e,TBinop(OpBoolAnd,e1,e2)),OpBoolAnd,e1,e2);
   case [_,_,TBlock([])]:withExpr(e,TIf(e1,e2,null));
   case _:switch Texpr.skip(e2).eexpr {case TBlock([]):var not = mk(TUnop(Not,Prefix,e1),e1.etype,e1.epos); not = optimizeUnop(not,Not,Prefix,e1); withExpr(e,TIf(not,e3,null)); case _:withExpr(e,TIf(e1,e2,e3));}
  };
  function loop(e:TExpr):TExpr return switch e.eexpr {
   case TIf(e1,e2,e3) if (e3 != null):var e1 = loop(e1); var e2 = loop(e2); var e3 = loop(e3); ifOrOp(e,e1,e2,e3);
   case TUnop(Increment | Decrement,_,e1) if (switch Texpr.skip(e1).eexpr {case TConst(_):true; case _:false;}):loop(e1);
   case TCall({eexpr:TIdent(s)},_) if (AnalyzerTexpr.isReallyUnbound(s)):e;
   case TBlock(el):withExpr(e,TBlock(el.map(e -> {var e = loop(e); return switch e.eexpr {case TIf(_,_,_):{eexpr:e.eexpr,etype:scom.basic.tvoid,epos:e.epos}; case _:e;};})));
   case TWhile(e1,e2,NormalWhile):
    var e1 = loop(e1); var e2 = loop(e2); function hasContinue(e:TExpr):Bool return switch e.eexpr {case TContinue:true; case _:checkExpr(hasContinue,e);}; var continues = hasContinue(e2);
    switch e2.eexpr {
     case TBlock(el) if (el.length > 0 && switch el[0].eexpr {case TIf(_, {eexpr:TBlock([{eexpr:TBreak}])},null):true; case _:false;}):
      switch el[0].eexpr {case TIf(cond,eb,null):var cond = Texpr.skip(cond); cond = switch cond.eexpr {case TUnop(_,_,inner):inner; case _:withExpr(cond,TUnop(Not,Prefix,cond));}; withExpr(e,TWhile(cond,withExpr(eb,TBlock(el.slice(1))),NormalWhile)); case _:throw "AnalyzerTexpr.cleanup loop header";}
     case TBlock(el):var doWhile = null; var locals = new haxe.ds.IntMap<Bool>();
      function collectVars(e:TExpr):Void switch e.eexpr {case TVar(v,e1):locals.set(v.vId,true); if (e1 != null) collectVars(e1); case _:iter(collectVars,e);}
      function referencesLocal(e:TExpr):Bool return switch e.eexpr {case TLocal(v) if (locals.exists(v.vId)):true; case _:checkExpr(referencesLocal,e);};
      function loop2(el:Array<TExpr>):Array<TExpr> return switch el {
       case [{eexpr:TBreak}] if (isTrueExpr(e1) && !continues):doWhile = Texpr.Builder.makeBool(scom.basic,true,e1.epos); [];
       case [{eexpr:TIf(cond,{eexpr:TBlock([{eexpr:TBreak}])},null)}] if (isTrueExpr(e1) && !referencesLocal(cond) && !continues):doWhile = cond; [];
       case []:[];
       case _:var first = el[0]; switch first.eexpr {case TBreak | TContinue | TReturn(_) | TThrow(_):[first]; case _:collectVars(first); [first].concat(loop2(el.slice(1)));}
      }; var el = loop2(el); doWhile == null ? withExpr(e,TWhile(e1,withExpr(e2,TBlock(el)),NormalWhile)) : withExpr(e,TWhile(withExpr(doWhile,TUnop(Not,Prefix,doWhile)),withExpr(e2,TBlock(el)),DoWhile));
     case _:withExpr(e,TWhile(e1,e2,NormalWhile));
    }
   case TField(e1,FAnon({cfName:s}) | FDynamic(s)):var e1 = loop(e1); withExpr(e,TField(e1,quickFieldDynamic(e1.etype,s)));
   case TField({eexpr:TTypeExpr(_)},_):e; case TTypeExpr(TClassDecl(_)):e;
   case TMeta({meta:core.MetaList.StrictMeta.Ast},e1) if (switch e1.eexpr {case TSwitch(_):false; case _:true;}):loop(e1);
   case _:mapExpr(loop,e);
  }; return loop(e);
 }
}
typedef PurityNode = {var pnClass:TClass; var pnField:TClassField; var pnPurity:PurityState; var pnDependents:Array<PurityNode>;}
class PurityConflict {public var node:PurityNode; public var pos:Pos; public function new(node:PurityNode,pos:Pos) {this.node = node; this.pos = pos;}}
class Purity {
 public static var nodeLut = new haxe.ds.StringMap<PurityNode>();
 public static function getFieldId(c:TClass,cf:TClassField):String return Globals.sTypePath(c.clPath) + "." + cf.cfName;
 public static function getNode(c:TClass,cf:TClassField):PurityNode {var id = getFieldId(c,cf); if (nodeLut.exists(id)) return nodeLut.get(id); var node:PurityNode = {pnClass:c,pnField:cf,pnPurity:PurityStateTools.getPurity(c,cf),pnDependents:[]}; nodeLut.set(id,node); return node;}
 public static function taint(node:PurityNode):Void switch node.pnPurity {
  case Impure:
  case ExpectPure(p):throw new PurityConflict(node,p);
  case MaybePure | Pure | InferredPure:
   node.pnPurity = Impure; for (n in node.pnDependents) taint(n); var c = node.pnClass;
   while (c.clSuper != null) {c = c.clSuper.cls; var cf = c.clFields.get(node.pnField.cfName); if (cf != null) taint(getNode(c,cf));}
 }
 public static function taintRaise(node:PurityNode):Dynamic {taint(node); throw new TypeExit();}
 public static function applyToField(isCtor:Bool,isStatic:Bool,c:TClass,cf:TClassField):Void {
  var node = getNode(c,cf);
  function checkField(c:TClass,cf:TClassField):Void {var other = getNode(c,cf); switch other.pnPurity {case Pure | InferredPure | ExpectPure(_):case Impure:taintRaise(node); case MaybePure:other.pnDependents.unshift(node);}}
  function checkWrite(e:TExpr):Void switch e.eexpr {case TLocal(v):if (core.TOther.ExtType.hasReferenceSemantics(v.vType)) taintRaise(node); case TField({eexpr:TConst(TThis)},_) if (isCtor):case _:taintRaise(node);}
  function loop(e:TExpr):Void switch e.eexpr {
   case TMeta(m = {meta:core.MetaList.StrictMeta.Pure},_):if (PurityStateTools.getPurityFromMeta([m]) == Impure) taintRaise(node);
   case TThrow(_):taintRaise(node);
   case TBinop(OpAssign | OpAssignOp(_),e1,e2):checkWrite(e1); loop(e2);
   case TUnop(Increment | Decrement,_,e1):checkWrite(e1);
   case TCall({eexpr:TField(_,FStatic(c,cf))},el):for (e in el) loop(e); checkField(c,cf);
   case TNew(c,_,el):for (e in el) loop(e); if (c.clConstructor != null) checkField(c,c.clConstructor); else taintRaise(node);
   case TCall({eexpr:TConst(TSuper)},el):if (c.clSuper != null && c.clSuper.cls.clConstructor != null) {checkField(c.clSuper.cls,c.clSuper.cls.clConstructor); for (e in el) loop(e);} else taintRaise(node);
   case TCall({eexpr:TIdent(s)},el) if (!AnalyzerTexpr.isUnboundCallThatMightHaveSideEffects(s,el)):for (e in el) loop(e);
   case TCall(_,_):taintRaise(node);
   case _:iter(loop,e);
  }
  switch cf.cfKind {
   case Method(MethDynamic) | Var(_):taint(node);
   case Method(MethNormal) if (!(isStatic || isCtor || hasClassFieldFlag(cf,CfFinal))):taint(node);
   case _:
    if (cf.cfExpr == null) {if (!PurityStateTools.isPure(c,cf)) taint(node);}
    else if (hasClassFieldFlag(cf,CfExtern) || Meta.has(FunctionCode,cf.cfMeta) || Meta.has(HlNative,cf.cfMeta) || Meta.has(HlNative,c.clMeta)) {if (!PurityStateTools.isPure(c,cf)) taint(node);}
    else try {switch node.pnPurity {case Impure:taintRaise(node); case Pure:throw new TypeExit(); case _:loop(cf.cfExpr);}} catch (_:TypeExit) {}
  }
 }
 public static function applyToClass(c:TClass):Void {for (cf in c.clOrderedFields) applyToField(false,false,c,cf); for (cf in c.clOrderedStatics) applyToField(false,true,c,cf); if (c.clConstructor != null) applyToField(true,false,c,c.clConstructor);}
 public static function infer(types:Array<ModuleType>):Void {
  nodeLut.clear(); for (mt in types) switch mt {case TClassDecl(c):try applyToClass(c) catch (conflict:PurityConflict) {core.Error.raiseTypingErrorExt(core.Error.makeError(core.Error.ErrorMsg.Custom("Impure field overrides/implements field which was explicitly marked as @:pure"),conflict.node.pnField.cfPos,[core.Error.makeError(core.Error.ErrorMsg.Custom(core.Error.complMsg("Pure field is here")),conflict.pos)]));} case _:}
  for (node in nodeLut) switch node.pnPurity {case Pure | MaybePure if (!exists(m -> m.meta == core.MetaList.StrictMeta.Pure,node.pnField.cfMeta)):var p = Globals.mkZeroRangePos(node.pnField.cfPos); node.pnField.cfMeta.unshift({meta:core.MetaList.StrictMeta.Pure,exprs:[{expr:EConst(Ident("inferredPure")),pos:p}],pos:p}); case _:}
 }
}
