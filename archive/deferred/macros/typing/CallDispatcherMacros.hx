// Deferred haxe/src/typing/callUnification.ml: call_dispatcher#macro_call.
// Exact draft body preserved until macro-runtime integration.
package typing;
class CallDispatcherMacros {
 function macroCall(ethis:Dynamic,cf:Dynamic,el:Array<Expr>):Dynamic {
  if(ctx.e.macroDepth>300) raiseTypingError("Stack overflow",p); ctx.e.macroDepth++; ctx.e.withTypeStack.unshift(withType);
  var ethisF:Void->Void=function() {};
  function macroInMacro():Void->Dynamic return function() return typeExpr(ctx,{expr:EThrow({expr:EConst(String("macro-in-macro",SDoubleQuotes)),pos:p}),pos:p},withType,mode);
  function handle(result:Dynamic,merge:Bool):Void->Dynamic return switch result {
   case MError:function() return typeExpr(ctx,{expr:EConst(Ident("null")),pos:p},WithTypeTools.value,mode);
   case MSuccess({expr:EMeta({meta:MetaTag.MergeBlock},{expr:EBlock(el)})}) if(merge):function() {var e=typeBlockRef(ctx,el,withType,p); return mk(TMeta({meta:MetaTag.MergeBlock,exprs:[],pos:p},e),e.etype,e.epos);};
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
}
