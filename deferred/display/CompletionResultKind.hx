package deferred.display;

import core.DisplayTypes;
import core.TFunctions.*;

// haxe/src/core/displayTypes.ml, CompletionResultKind.to_json.
// Preserved draft for deferred display services; requires CompletionItem and Genjson.
class CompletionResultKind {
 public static function toJson(ctx:Dynamic,kind:CompletionResultKindValue):Dynamic {
  function expectedTypeFields(t:Null<ExpectedTypeCompletion>):Array<Dynamic> return t==null?[]:[{name:"expectedType",value:CompletionItem.CompletionType.toJson(ctx,t.expectedType)},{name:"expectedTypeFollowed",value:CompletionItem.CompletionType.toJson(ctx,t.expectedTypeFollowed)},{name:"compatibleTypes",value:JArray(t.compatibleTypes.map(function(t) return CompletionItem.CompletionType.toJson(ctx,t)))}];
  var i:Int;var args:Dynamic=null;
  switch kind {
   case CRField(item,p,iterator,keyValueIterator):
    var type=CompletionItem.getType(item),converted:Dynamic=null;
    if (type!=null) try {
     var mt=moduleTypeOfType(type.type),context=Reflect.copy(ctx);context.generateAbstractImpl=true;
     var jmt=Genjson.generateModuleType(context,mt);var followed=type.type==follow(type.type)?JNull:Genjson.generateModuleType(context,moduleTypeOfType(follow(type.type)));
     converted={moduleType:jmt,followed:followed,type:CompletionItem.CompletionType.toJson(context,type.completion)};
    }catch (_:Dynamic) {}
    var fields:Array<Dynamic>=[{name:"item",value:CompletionItem.toJson(ctx,null,item)},{name:"range",value:Genjson.generatePosAsRange(p)},{name:"iterator",value:iterator==null?JNull:JObject([{name:"type",value:Genjson.generateType(ctx,iterator)}])},{name:"keyValueIterator",value:keyValueIterator==null?JNull:JObject([{name:"key",value:Genjson.generateType(ctx,keyValueIterator.key)},{name:"value",value:Genjson.generateType(ctx,keyValueIterator.value)}])}];
    if (converted!=null) fields=fields.concat([{name:"type",value:converted.type},{name:"moduleType",value:converted.moduleType},{name:"moduleTypeFollowed",value:converted.followed}]);i=0;args=JObject(fields);
   case CRStructureField:i=1;case CRToplevel(t):i=2;args=JObject(expectedTypeFields(t));case CRMetadata:i=3;case CRTypeHint:i=4;case CRExtends:i=5;case CRImplements:i=6;
   case CRStructExtension(intersection):i=7;args=JObject([{name:"isIntersectionType",value:JBool(intersection)}]);case CRImport:i=8;case CRUsing:i=9;case CRNew:i=10;
   case CRPattern(t,outermost):i=11;args=JObject([{name:"isOutermostPattern",value:JBool(outermost)}].concat(expectedTypeFields(t)));case CROverride:i=12;case CRTypeRelation:i=13;case CRTypeDecl:i=14;
  }
  return JObject([{name:"kind",value:JInt(i)}].concat(args==null?[]:[{name:"args",value:args}]));
 }
}
