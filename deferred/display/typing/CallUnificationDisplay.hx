// Deferred haxe/src/typing/callUnification.ml: raise_augmented_display.
// Exact draft body preserved until display-service integration.
package typing;
class CallUnificationDisplay {
 function raiseAugmentedDisplay(cf:Dynamic,de:Dynamic):Dynamic {
   var text=genDocTextOpt(cf.cfDoc); if(text==null) throw DisplayException(de); var doc=new Javadoc(text);
   switch de {
    case DisplayHover(hover):switch hover.hexpected {
     case WithType(t,si) if(si!=null):
      var next=switch si {
       case FunctionArgument(info) if(info.siDoc==null):var copy=Reflect.copy(info); copy.siDoc=doc.getParamInfo(info.siName); FunctionArgument(copy);
       case StructureField(info) if(info.siDoc==null):var copy=Reflect.copy(info); copy.siDoc=doc.getParamInfo(info.siName); StructureField(copy);
       case _:si;
      };
      return DisplayException.raiseHover(hover.hitem,WithType(t,next),hover.hpos);
     case _:throw DisplayException(de);
    }
    case _:throw DisplayException(de);
   }
  }
}

/* The corresponding attempt/make catch, restored with display services:
try typed=unifyCallArgs(ctx,el,split.remaining,ret,p,isInline,forced,inOverload,fa.faFieldPos) catch(exc:Dynamic) {switch exc {case DisplayException(de):typed=raiseAugmentedDisplay(cf,de); case _:throw exc;}}
*/
