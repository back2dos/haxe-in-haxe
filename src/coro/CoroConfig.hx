package coro;
// haxe/src/coro/coroConfig.ml — mechanical draft; not compile-validated.
typedef CoroAssert = {var numStates:Null<Int>; var numHoisted:Null<Int>;}
typedef CoroOutcome = {var noSuspend:Bool; var noReturn:Bool; var noThrow:Bool;}
typedef CoroConfigData = {var debug:Bool; var transformed:Bool; var assertConfig:Null<CoroAssert>; var outcome:CoroOutcome;}
class CoroConfigReader {
 var api:Dynamic;
 public function new(api:Dynamic) this.api=api;
 public function readCoroAssert(config:CoroAssert,data:Dynamic):Void {
  for (field in (api.readObject(data):Array<Dynamic>)) switch field.name {
   case "numStates": config.numStates=api.readInt(field.data);
   case "numHoisted": config.numHoisted=api.readInt(field.data);
   case s: Error.raiseTypingError('Unknown key for coroutine assert config: $s',core.Globals.nullPos);
  }
 }
 public function readCoroOutcome(outcome:CoroOutcome,data:Dynamic):Void {
  for (field in (api.readObject(data):Array<Dynamic>)) switch field.name {
   case "noSuspend": outcome.noSuspend=api.readBool(field.data);
   case "noReturn": outcome.noReturn=api.readBool(field.data);
   case "noThrow": outcome.noThrow=api.readBool(field.data);
   case s: Error.raiseTypingError('Unknown key for coroutine outcome config: $s',core.Globals.nullPos);
  }
 }
 public function readCoroConfig(config:CoroConfigData,data:Dynamic):Void api.readOptional(data,function(data) {
  for (field in (api.readObject(data):Array<Dynamic>)) switch field.name {
   case "debug": config.debug=api.readBool(field.data);
   case "transformed": config.transformed=api.readBool(field.data);
   case "assert": var assertion:CoroAssert={numStates:null,numHoisted:null}; readCoroAssert(assertion,field.data); config.assertConfig=assertion;
   case "outcome": readCoroOutcome(config.outcome,field.data);
   case s: Error.raiseTypingError('Unknown key for coroutine config: $s',core.Globals.nullPos);
  }
 });
}
class CoroConfig {
 public static function defaultOutcome():CoroOutcome return {noSuspend:false,noReturn:false,noThrow:false};
 public static function create():CoroConfigData return {debug:false,transformed:false,assertConfig:null,outcome:defaultOutcome()};
 public static function ofMetadataEntry(entry:Dynamic):CoroConfigData {
  var config=create(); new CoroConfigReader(MetaDataApi.MetaReaderApi).readCoroConfig(config,MetaDataApi.ofMetadataEntry(entry)); return config;
 }
 public static function ofMetaList(meta:Dynamic):CoroConfigData {
  var entry; try {entry=core.Meta.get(core.Meta.Coroutine,meta);} catch(e:NotFound) {return create();} return ofMetadataEntry(entry);
 }
 public static function getCoroutineConfig(meta:Dynamic):Null<CoroConfigData> {var config=ofMetaList(meta); return config.transformed?null:config;}
}
