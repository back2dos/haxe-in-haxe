package unit;

import core.Json.JsonValue;
import core.data.JsonDataApi.JsonReaderApi;

class JsonDataApiTest {
	public static function main():Void {
		var data:JsonValue = JObject([
			{name: "name", value: JString("compiler")},
			{name: "enabled", value: JBool(true)},
			{name: "version", value: JInt(1)},
			{name: "items", value: JArray([JString("hxb")])}
		]);
		var fields = JsonReaderApi.readObject(data);
		if (fields.length != 4 || JsonReaderApi.readString(fields[0].value) != "compiler") throw "JSON object reading failed";
		if (!JsonReaderApi.readBool(fields[1].value) || JsonReaderApi.readInt(fields[2].value) != 1) throw "JSON scalar reading failed";
		if (JsonReaderApi.readString(JsonReaderApi.readArray(fields[3].value)[0]) != "hxb") throw "JSON array reading failed";
		var called = false;
		JsonReaderApi.readOptional(JNull, function(_) called = true);
		if (called) throw "JNull must be skipped";
		try {
			JsonReaderApi.readBool(JString("true"));
			throw "Expected boolean reading failure";
		} catch (_:core.Error.TypingError) {}
	}
}
