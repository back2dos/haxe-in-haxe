package unit;

import core.data.JsonDataApi.JsonReaderApi;
import core.data.JsonDataApi.JsonWriterApi;

class JsonDataApiTest {
	public static function main():Void {
		var data = haxe.Json.parse('{"name":"compiler","enabled":true,"version":1,"items":["hxb"]}');
		var fields = JsonReaderApi.readObject(data);
		if (fields.length != 4 || JsonReaderApi.readString(Reflect.field(data, "name")) != "compiler") throw "JSON object reading failed";
		if (!JsonReaderApi.readBool(Reflect.field(data, "enabled")) || JsonReaderApi.readInt(Reflect.field(data, "version")) != 1) throw "JSON scalar reading failed";
		if (JsonReaderApi.readArray(Reflect.field(data, "items"))[0] != "hxb") throw "JSON array reading failed";

		var written = JsonWriterApi.writeObject([{name: "answer", value: JsonWriterApi.writeInt(42)}]);
		if (haxe.Json.stringify(written) != '{"answer":42}') throw "JSON object writing failed";
		try {
			JsonReaderApi.readBool("true");
			throw "Expected boolean reading failure";
		} catch (error:Dynamic) {
			if (Std.string(error).indexOf("Expected JBool") < 0) throw error;
		}
	}
}
