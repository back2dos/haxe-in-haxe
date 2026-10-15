package core.data;

import core.Json;
import core.Json.JsonValue;
import core.Json.JsonField;

class JsonDataApi {
	public static function error(s:String):Dynamic {
		/* TODO: should this raise something else? */
		return core.Error.raiseTypingError(s, core.Globals.nullPos);
	}
}

// port: module JsonReaderApi (`type data = Json.t`)
class JsonReaderApi {
	public static function readOptional(json:JsonValue, f:JsonValue->Void):Void {
		switch json {
			case JNull:
			case _:
				f(json);
		}
	}

	public static function readObject(json:JsonValue):Array<JsonField> {
		return switch json {
			case JObject(fl): fl;
			case _: JsonDataApi.error('Expected JObject, found ${Json.stringOfJson(json)}');
		}
	}

	public static function readArray(json:JsonValue):Array<JsonValue> {
		return switch json {
			case JArray(l): l;
			case _: JsonDataApi.error('Expected JArray, found ${Json.stringOfJson(json)}');
		}
	}

	public static function readString(json:JsonValue):String {
		return switch json {
			case JString(s): s;
			case _: JsonDataApi.error('Expected JString, found ${Json.stringOfJson(json)}');
		}
	}

	public static function readInt(json:JsonValue):Int {
		return switch json {
			case JInt(i): i;
			case _: JsonDataApi.error('Expected JInt, found ${Json.stringOfJson(json)}');
		}
	}

	public static function readIdent(json:JsonValue):String {
		return switch json {
			case JString(s): s;
			case _: JsonDataApi.error('Expected identifier string, found ${Json.stringOfJson(json)}');
		}
	}

	public static function readBool(json:JsonValue):Bool {
		return switch json {
			case JBool(b): b;
			case _: JsonDataApi.error('Expected JBool, found ${Json.stringOfJson(json)}');
		}
	}

	public static function dataToString(json:JsonValue):String {
		return Json.stringOfJson(json);
	}
}
