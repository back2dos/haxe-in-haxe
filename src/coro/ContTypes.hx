package coro;
import core.TType;
// haxe/src/coro/contTypes.ml — mechanical draft; not compile-validated.
typedef ContinuationApi = {
 var baseContinuationClass:TClass; var suspensionState:T; var suspensionResult:T->T; var suspensionResultClass:TClass;
 var continuation:T; var state:TClassField; var result:TClassField; var error:TClassField; var completion:TClassField;
 var context:TClassField; var gotoLabel:TClassField; var suspended:TClassField;
}
class ContTypes {
 public static function createContinuationApi(baseContinuationClass:TClass,suspensionState:T,suspensionResultClass:TClass,continuation:T,suspended:TClassField,state:TClassField,result:TClassField,error:TClassField,completion:TClassField,context:TClassField,gotoLabel:TClassField):ContinuationApi return {
  baseContinuationClass:baseContinuationClass,suspensionState:suspensionState,suspensionResult:function(t) return TInst(suspensionResultClass,[t]),suspensionResultClass:suspensionResultClass,continuation:continuation,suspended:suspended,state:state,result:result,error:error,completion:completion,context:context,gotoLabel:gotoLabel
 };
}
