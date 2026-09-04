package coro;
import core.TType;
import core.Globals.Pos;
import coro.CoroConfig;
import coro.CoroElsewhere.TexprBuilder;
// haxe/src/coro/coroTypes.ml — mechanical draft; not compile-validated.
enum CoroFor { LocalFunc(tf:TFunc,v:TVar); ClassField(c:TClass,cf:TClassField,tf:TFunc,p:Pos); }
enum SuspendExpr { SusBlock; SusResult; }
typedef CoroBlock = { var cbId:Int; var cbEl:Array<TExpr>; var cbTypepos:Null<{t:T,p:Pos}>; var cbCatch:Null<CoroBlock>; var cbNext:CoroNext; var cbFlags:Int; var cbStackValue:Null<TExpr>; }
typedef CoroBlockNext = Null<CoroBlock>;
enum CoroNext {
 NextUnknown; NextReturnVoid; NextReturn(e:TExpr); NextThrow(e:TExpr);
 NextIfThen(e:TExpr,thenBlock:CoroBlock,next:CoroBlock);
 NextIfThenElse(e:TExpr,thenBlock:CoroBlock,elseBlock:CoroBlock,next:CoroBlockNext);
 NextSwitch(s:CoroSwitch,next:CoroBlockNext); NextWhile(e:TExpr,body:CoroBlock,next:CoroBlockNext);
 NextTry(body:CoroBlock,catches:CoroCatch,next:CoroBlockNext); NextSuspend(s:CoroSuspend,next:CoroBlockNext);
 NextBreak(next:CoroBlock); NextContinue(next:CoroBlock); NextFallThrough(next:CoroBlock); NextGoto(next:CoroBlock);
}
typedef CoroSwitch = { var csSubject:TExpr; var csCases:Array<{el:Array<TExpr>,cb:CoroBlock}>; var csDefault:Null<CoroBlock>; var csExhaustive:Bool; }
typedef CoroCatch = {var ccCb:CoroBlock; var ccCatches:Array<{v:TVar,cb:CoroBlock}>;}
typedef CoroSuspend = {var csFun:TExpr; var csArgs:Array<TExpr>; var csPos:Pos; var csResult:SuspendExpr; var csKind:CoroOutcome;}
typedef CoroDeferredApi = {var makeInlineReturn:Null<TExpr>->Pos->TExpr; var makeInlineTailCall:CoroSuspend->TExpr; var makeSyncCall:CoroSuspend->Null<TExpr>->TExpr; var makeThis:TExpr->TExpr; var makeSuperField:TExpr->TExpr;}
typedef CoroCtx = {
 var builder:TexprBuilder; var typer:Dynamic; var config:CoroConfigData; var coroType:CoroFor; var classNamePos:Pos;
 var deferredExprs:Map<Int,Void->TExpr>; var hasCaptureVars:Bool; var capturesThis:Bool; var nextBlockId:Int;
 var currentCatch:Null<CoroBlock>; var hasCatch:Bool; var numStates:Int;
}
enum abstract CbFlag(Int) to Int {var CbGenerated=0; var CbSuspendState=1; var CbResumeState=2;}
typedef CoroScope = {var scopeVar:TVar; var restrictedSuspension:Bool;}
enum CoroGenMode {GenThunk(cf:TClassField); GenInline(field:Null<{e:TExpr,cf:TClassField}>);}
