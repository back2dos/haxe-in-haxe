package coro;
// haxe/src/coro/coroScopeConfig.ml — mechanical draft; not compile-validated.
typedef CoroScopeConfigData = {var restrictedSuspension:Bool;}
class CoroScopeConfigReader {
 var api:Dynamic; public function new(api:Dynamic) this.api=api;
 public function readCoroScopeConfig(config:CoroScopeConfigData,data:Dynamic):Void api.readOptional(data,function(data) {
  for(field in (api.readObject(data):Array<Dynamic>)) switch field.name {
   case "restrictedSuspension": config.restrictedSuspension=api.readBool(field.data);
   case s: Error.raiseTypingError('Unknown key for coroutine scope config: $s',core.Globals.nullPos);
  }
 });
}
class CoroScopeConfig {
 public static function create():CoroScopeConfigData return {restrictedSuspension:false};
 public static function ofMetaList(meta:Dynamic):Null<CoroScopeConfigData> {
  var entry; try {entry=core.Meta.get(core.Meta.CoroutineScope,meta);} catch(e:NotFound) {return null;}
  var config=create(); new CoroScopeConfigReader(MetaDataApi.MetaReaderApi).readCoroScopeConfig(config,MetaDataApi.ofMetadataEntry(entry)); return config;
 }
}
