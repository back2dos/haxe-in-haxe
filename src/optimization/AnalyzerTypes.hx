package optimization;

import core.Globals;
import core.Ast;
import core.TType;
import core.TFunctions.*;
import core.TFunctions.NotFound;
import core.TPrinting;
import context.SafeCom;
import optimization.AnalyzerConfig;

// haxe/src/optimization/analyzerTypes.ml — mechanical draft; not compiled or validated.
enum BlockKind { BKRoot; BKNormal; BKFunctionBegin(tf:TFunc); BKFunctionEnd; BKSub; BKConditional; BKLoopHead; BKException; BKUnreachable; BKCatch(v:TVar); }
enum FlagBlock { BlockDce; }
enum CfgEdgeFlag { FlagExecutable; FlagDce; FlagCopyPropagation; }
enum CfgEdgeKind { CFGGoto; CFGFunction; CFGMaybeThrow; CFGCondBranch(e:TExpr); CFGCondElse; }
typedef CfgEdge = {var cfgFrom:BasicBlockData; var cfgTo:BasicBlockData; var cfgKind:CfgEdgeKind; var cfgFlags:Array<CfgEdgeFlag>;}
enum SyntaxEdge {
 SEIfThen(bbThen:BasicBlockData,bbNext:BasicBlockData,p:Pos);
 SEIfThenElse(bbThen:BasicBlockData,bbElse:BasicBlockData,bbNext:BasicBlockData,t:T,p:Pos);
 SESwitch(ss:SyntaxSwitch);
 SETry(bbTry:BasicBlockData,bbExc:BasicBlockData,catches:Array<{v:TVar,bb:BasicBlockData}>,bbNext:BasicBlockData,p:Pos);
 SEWhile(bbBody:BasicBlockData,bbNext:BasicBlockData,p:Pos);
 SESubBlock(bbSub:BasicBlockData,bbNext:BasicBlockData);
 SEMerge(bb:BasicBlockData); SENone;
}
typedef SyntaxSwitch = {var ssCases:Array<{values:Array<TExpr>,bb:BasicBlockData}>; var ssDefault:Null<BasicBlockData>; var ssNext:BasicBlockData; var ssPos:Pos; var ssExhaustive:Bool;}
enum TerminatorKind { TermNone; TermCondBranch(e:TExpr); TermReturn(p:Pos); TermReturnValue(e:TExpr,p:Pos); TermBreak(p:Pos); TermContinue(p:Pos); TermThrow(e:TExpr,p:Pos); }
typedef BasicBlockData = {
 var bbId:Int; var bbType:T; var bbPos:Pos; var bbKind:BlockKind; var bbClosed:Bool; var bbFlags:Int;
 var bbEl:Array<TExpr>; var bbPhi:Array<TExpr>; var bbTerminator:TerminatorKind;
 var bbOutgoing:Array<CfgEdge>; var bbIncoming:Array<CfgEdge>; var bbDominator:BasicBlockData;
 var bbDominated:Array<BasicBlockData>; var bbDf:Array<BasicBlockData>; var bbSyntaxEdge:SyntaxEdge;
 var bbLoopGroups:Array<Int>; var bbScopes:Array<Int>; var bbVarWrites:Array<TVar>;
}
enum TExprLookupTarget { LUPhi(i:Int); LUEl(i:Int); LUTerm; }
class BasicBlock {
 public static function intOfBlockFlag(flag:FlagBlock):Int return std.Type.enumIndex(flag);
 public static function addBlockFlag(bb:BasicBlockData,flag:FlagBlock) bb.bbFlags = setFlag(bb.bbFlags,intOfBlockFlag(flag));
 public static function removeBlockFlag(bb:BasicBlockData,flag:FlagBlock) bb.bbFlags = unsetFlag(bb.bbFlags,intOfBlockFlag(flag));
 public static function hasBlockFlag(bb:BasicBlockData,flag:FlagBlock):Bool return core.TFunctions.hasFlag(bb.bbFlags,intOfBlockFlag(flag));
 public static function sBlockKind(kind:BlockKind):String return switch kind {
  case BKRoot:"BKRoot"; case BKNormal:"BKNormal"; case BKFunctionBegin(_):"BKFunctionBegin"; case BKFunctionEnd:"BKFunctionEnd";
  case BKSub:"BKSub"; case BKConditional:"BKConditional"; case BKLoopHead:"BKLoopHead"; case BKException:"BKException"; case BKUnreachable:"BKUnreachable"; case BKCatch(_):"BKCatch";
 };
 public static function sCfgEdgeKind(kind:CfgEdgeKind):String return switch kind {
  case CFGGoto:"CFGGoto"; case CFGFunction:"CFGFunction"; case CFGMaybeThrow:"CFGMaybeThrow";
  case CFGCondBranch(e):"CFGCondBranch " + TPrinting.sExprPretty(false,"",false,TPrinting.sType.bind(TPrinting.printContext()),e);
  case CFGCondElse:"CFGCondElse";
 };
 public static function hasFlag(edge:CfgEdge,flag:CfgEdgeFlag):Bool return edge.cfgFlags.contains(flag);
 public static function addTexpr(bb:BasicBlockData,e:TExpr) bb.bbEl.push(e);
 public static function getTexpr(bb:BasicBlockData,luk:TExprLookupTarget):TExpr return switch luk {
  case LUPhi(i):bb.bbPhi[i]; case LUEl(i):bb.bbEl[i]; case LUTerm:switch bb.bbTerminator {
   case TermCondBranch(e) | TermReturnValue(e,_) | TermThrow(e,_):e;
   case TermNone | TermReturn(_) | TermBreak(_) | TermContinue(_):throw "AnalyzerTypes.getTexpr";
  }
 };
 public static function setSyntaxEdge(bb:BasicBlockData,se:SyntaxEdge) bb.bbSyntaxEdge = se;
 public static function addCfgEdge(from:BasicBlockData,to:BasicBlockData,kind:CfgEdgeKind) {
  if (from.bbKind != BKUnreachable) {var edge:CfgEdge = {cfgFrom:from,cfgTo:to,cfgKind:kind,cfgFlags:[]}; from.bbOutgoing.unshift(edge); to.bbIncoming.unshift(edge);}
 }
 public static function create(id:Int,kind:BlockKind,t:T,p:Pos):BasicBlockData {
  var bb:BasicBlockData = {bbKind:kind,bbId:id,bbType:t,bbPos:p,bbClosed:false,bbFlags:0,bbEl:[],bbPhi:[],bbTerminator:TermNone,bbOutgoing:[],bbIncoming:[],bbDominator:null,bbDominated:[],bbDf:[],bbSyntaxEdge:SENone,bbLoopGroups:[],bbVarWrites:[],bbScopes:[]}; bb.bbDominator = bb; return bb;
 }
 public static function inScope(bb:BasicBlockData,other:BasicBlockData):Bool {
  if (other.bbScopes.length == 0) core.Error.abort("Scope-less block (kind: " + sBlockKind(other.bbKind) + ")",other.bbPos);
  return bb.bbScopes.contains(other.bbScopes[0]);
 }
 public static function terminatorMap(f:TExpr->TExpr,term:TerminatorKind):TerminatorKind return switch term {
  case TermCondBranch(e):TermCondBranch(f(e)); case TermReturnValue(e,p):TermReturnValue(f(e),p); case TermThrow(e,p):TermThrow(f(e),p);
  case TermNone | TermReturn(_) | TermBreak(_) | TermContinue(_):term;
 };
 public static function terminatorIter(f:TExpr->Void,term:TerminatorKind):Void switch term {
  case TermCondBranch(e) | TermReturnValue(e,_) | TermThrow(e,_):f(e);
  case TermNone | TermReturn(_) | TermBreak(_) | TermContinue(_):
 }
}
typedef TFuncInfo = {var bb:BasicBlockData; var type:T; var pos:Pos; var tf:TFunc;}
typedef TExprLookup = {var bb:BasicBlockData; var target:TExprLookupTarget;}
typedef VarInfo = {var viVar:TVar; var viExtra:Null<TVarExtra>; var viBbDeclare:BasicBlockData; var viOrigin:TVar; var viWrites:Array<BasicBlockData>; var viValue:Null<TExprLookup>; var viSsaEdges:Array<TExprLookup>; var viReachingDef:Null<TVar>;}
typedef GraphData = {var gRoot:BasicBlockData; var gExit:BasicBlockData; var gUnreachable:BasicBlockData; var gFunctions:haxe.ds.IntMap<TFuncInfo>; var gNodes:Array<BasicBlockData>; var gVarInfos:Array<VarInfo>; var gLoops:haxe.ds.IntMap<BasicBlockData>;}
private typedef DomBbInfo = {var bb:BasicBlockData; var parent:DomBbInfo; var idom:DomBbInfo; var semi:Int; var label:DomBbInfo; var ancestor:DomBbInfo; var bucket:Array<DomBbInfo>;}
class Graph {
 public static function createVarInfo(g:GraphData,bb:BasicBlockData,v:TVar):VarInfo {
  var vi:VarInfo = {viVar:v,viExtra:v.vExtra,viBbDeclare:bb,viOrigin:v,viWrites:[],viValue:null,viSsaEdges:[],viReachingDef:null};
  g.gVarInfos.push(vi); var i = g.gVarInfos.length - 1; v.vExtra = varExtra([],mk(TConst(TInt(i)),tDynamic,Globals.nullPos)); return vi;
 }
 public static function getVarInfo(g:GraphData,v:TVar):VarInfo return switch v.vExtra {
  case {vExpr:{eexpr:TConst(TInt(i))}}:g.gVarInfos[i];
  case _:Sys.println("Unbound variable, please report this"); Sys.println(TPrinting.Printer.sTvar(v)); createVarInfo(g,g.gUnreachable,v);
 };
 public static function declareVar(g:GraphData,v:TVar,bb:BasicBlockData):Void {createVarInfo(g,bb,v);}
 public static function addVarDef(g:GraphData,bb:BasicBlockData,v:TVar):Void if (bb.bbId > 0) {bb.bbVarWrites.unshift(v); getVarInfo(g,v).viWrites.unshift(bb);}
 public static function setVarValue(g:GraphData,v:TVar,bb:BasicBlockData,luk:TExprLookupTarget) getVarInfo(g,v).viValue = {bb:bb,target:luk};
 public static function getVarValue(g:GraphData,v:TVar):TExpr {
  var value = getVarInfo(g,v).viValue; if (value == null) throw new NotFound();
  return switch BasicBlock.getTexpr(value.bb,value.target).eexpr {case TVar(_,e) if (e != null):e; case TBinop(OpAssign,_,e):e; case _:throw "AnalyzerTypes.getVarValue";};
 }
 public static function addVarOrigin(g:GraphData,v:TVar,origin:TVar) getVarInfo(g,v).viOrigin = origin;
 public static function getVarOrigin(g:GraphData,v:TVar):TVar return getVarInfo(g,v).viOrigin;
 public static function addSsaEdge(g:GraphData,v:TVar,bb:BasicBlockData,luk:TExprLookupTarget) getVarInfo(g,v).viSsaEdges.unshift({bb:bb,target:luk});
 public static function addFunction(g:GraphData,tf:TFunc,t:T,p:Pos,bb:BasicBlockData) g.gFunctions.set(bb.bbId,{bb:bb,type:t,pos:p,tf:tf});
 static var nextId = 1;
 static final idMutex = new sys.thread.Mutex();
 public static function allocId():Int {idMutex.acquire(); var id = ++nextId; idMutex.release(); return id;}
 public static function createNode(g:GraphData,kind:BlockKind,t:T,p:Pos):BasicBlockData {var bb = BasicBlock.create(allocId(),kind,t,p); g.gNodes.unshift(bb); return bb;}
 public static function closeNode(bb:BasicBlockData):Void if (bb.bbId > 0) {if (bb.bbClosed) throw "assert: block already closed"; bb.bbClosed = true;}
 public static function iterDomTreeFrom(g:GraphData,bb:BasicBlockData,f:BasicBlockData->Void):Void {f(bb); for (child in bb.bbDominated) iterDomTreeFrom(g,child,f);}
 public static function iterDomTree(g:GraphData,f:BasicBlockData->Void):Void iterDomTreeFrom(g,g.gRoot,f);
 public static function iterEdgesFrom(g:GraphData,bb:BasicBlockData,f:CfgEdge->Void):Void iterDomTreeFrom(g,bb,function(bb) {for (edge in bb.bbOutgoing) f(edge);});
 public static function iterEdges(g:GraphData,f:CfgEdge->Void):Void iterEdgesFrom(g,g.gRoot,f);
 public static function create(t:T,p:Pos):GraphData {var root = BasicBlock.create(1,BKRoot,t,p); var unreachable = BasicBlock.create(0,BKUnreachable,tDynamic,Globals.nullPos); return {gRoot:root,gExit:unreachable,gUnreachable:unreachable,gFunctions:new haxe.ds.IntMap(),gNodes:[root],gVarInfos:[],gLoops:new haxe.ds.IntMap()};}
 public static function checkIntegrity(g:GraphData):Void for (bb in g.gNodes) {
  for (edge in bb.bbOutgoing) if (edge.cfgTo == g.gUnreachable) Sys.println('Outgoing edge from ${bb.bbId} to the unreachable block'); else if (!edge.cfgTo.bbIncoming.contains(edge)) Sys.println('Outgoing edge ${edge.cfgFrom.bbId} -> ${edge.cfgTo.bbId} has no matching incoming edge');
  for (edge in bb.bbIncoming) if (edge.cfgFrom == g.gUnreachable) Sys.println('Incoming edge to ${bb.bbId} from the unreachable block'); else if (!edge.cfgFrom.bbOutgoing.contains(edge)) Sys.println('Incoming edge ${edge.cfgTo.bbId} <- ${edge.cfgFrom.bbId} has no matching outgoing edge');
 }
 public static function inferImmediateDominators(g:GraphData):Void {
  var info = new haxe.ds.IntMap<DomBbInfo>(); var nodes:Array<DomBbInfo> = [];
  function addInfo(bb:BasicBlockData,parent:BasicBlockData):Void {
   var bbi:DomBbInfo = {bb:bb,parent:null,idom:null,semi:nodes.length,label:null,ancestor:null,bucket:[]}; bbi.parent = bbi; bbi.idom = bbi; bbi.label = bbi; bbi.ancestor = bbi;
   // The OCaml record update keeps the original self-references for a non-root node.
   if (bb != parent) {var copy:DomBbInfo = Reflect.copy(bbi); copy.parent = info.get(parent.bbId); bbi = copy;}
   info.set(bb.bbId,bbi); nodes.push(bbi);
  }
  function visit(parent:BasicBlockData,bb:BasicBlockData):Void {bb.bbDominated = []; addInfo(bb,parent); for (edge in bb.bbOutgoing) if (!info.exists(edge.cfgTo.bbId)) visit(bb,edge.cfgTo);}
  visit(g.gRoot,g.gRoot);
  function compress(bbi:DomBbInfo):Void {
   var worklist = [bbi]; var ancestor = bbi.ancestor; while (ancestor.ancestor != ancestor) {worklist.unshift(ancestor); ancestor = ancestor.ancestor;}
   if (worklist.length == 0) throw "AnalyzerTypes.compress";
   var a = worklist.shift(); var minSemi = a.label.semi;
   for (desc in worklist) {var label = desc.label; if (label.semi > minSemi) desc.label = a.label; else minSemi = label.semi; a = desc;}
  }
  function eval(id:Int):DomBbInfo {var bbi = info.get(id); if (bbi.ancestor != bbi) {compress(bbi); return bbi.label;} return bbi;}
  var i = nodes.length - 1;
  while (i > 0) {
   var w = nodes[i--]; var semi = w.semi; for (edge in w.bb.bbIncoming) semi = Std.int(Math.min(semi,eval(edge.cfgFrom.bbId).semi));
   w.semi = semi; nodes[semi].bucket.unshift(w); var parent = w.parent; w.ancestor = parent;
   for (v in parent.bucket) {var u = eval(v.bb.bbId); v.idom = u.semi < v.semi ? u : parent;} parent.bucket = [];
  }
  if (nodes.length == 0) throw "AnalyzerTypes.inferImmediateDominators";
  for (w in nodes.slice(1)) if (w.idom != nodes[w.semi]) w.idom = w.idom.idom;
  for (bbi in nodes) if (bbi.idom != bbi) {var bb = bbi.bb; var other = bbi.idom.bb; if (bb != other) {bb.bbDominator = other; other.bbDominated.unshift(bb);}}
 }
 public static function inferDominanceFrontier(g:GraphData):Void iterEdges(g,function(edge) {
  var bb = edge.cfgFrom;
  while (bb != g.gUnreachable && bb != edge.cfgTo && bb != edge.cfgTo.bbDominator) {if (edge.cfgTo != g.gExit) bb.bbDf.unshift(edge.cfgTo); if (bb.bbDominator == bb) break; bb = bb.bbDominator;}
 });
 public static function inferVarWrites(g:GraphData):Void iterDomTree(g,function(bb) {
  switch bb.bbKind {case BKCatch(v):declareVar(g,v,bb); addVarDef(g,bb,v); case BKFunctionBegin(tf):for (arg in tf.tfArgs) {declareVar(g,arg.v,bb); addVarDef(g,bb,arg.v);} case _:}
  function infer(e:TExpr):Void switch e.eexpr {case TVar(v,eo):declareVar(g,v,bb); if (eo != null) addVarDef(g,bb,v); case TBinop(OpAssign,{eexpr:TLocal(v)},_):addVarDef(g,bb,v); case _:}
  for (e in bb.bbEl) infer(e); BasicBlock.terminatorIter(infer,bb.bbTerminator);
 });
 public static function inferScopes(g:GraphData):Void {
  var nextScopeId = 0; function nextScope(scopes:Array<Int>):Array<Int> return [++nextScopeId].concat(scopes);
  function loop(scopes:Array<Int>,bb:BasicBlockData):Void {
   bb.bbScopes = scopes;
   switch bb.bbSyntaxEdge {
    case SEIfThen(bt,bn,_):loop(nextScope(scopes),bt); loop(scopes,bn);
    case SEIfThenElse(bt,be,bn,_,_):loop(nextScope(scopes),bt); loop(nextScope(scopes),be); loop(scopes,bn);
    case SESwitch(ss):for (c in ss.ssCases) loop(nextScope(scopes),c.bb); if (ss.ssDefault != null) loop(nextScope(scopes),ss.ssDefault); loop(scopes,ss.ssNext);
    case SETry(bt,bx,catches,bn,_):var inner = nextScope(scopes); loop(inner,bt); loop(inner,bx); for (c in catches) loop(nextScope(scopes),c.bb); loop(scopes,bn);
    case SEWhile(body,next,_):loop(nextScope(scopes),body); loop(scopes,next);
    case SESubBlock(sub,next):loop(nextScope(scopes),sub); loop(scopes,next);
    case SEMerge(other):loop(scopes,other);
    case SENone:
   }
  }
  for (fn in g.gFunctions) loop([0],fn.bb);
 }
}
typedef AnalyzerContext = {
 var com:Dynamic; var config:AnalyzerConfigData; var graph:GraphData; var tempVarName:String; var withTimer:Dynamic; var identifier:String;
 var entry:BasicBlockData; var hasUnbound:Bool; var loopCounter:Int; var loopStack:Array<Int>; var debugExprs:Array<{name:String,expr:TExpr}>; var nameStack:Array<String>; var didOptimize:Bool;
}
class AnalyzerTypes {}
