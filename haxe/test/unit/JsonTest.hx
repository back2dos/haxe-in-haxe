package unit;

import core.Json;
import core.Json.JsonValue;
import core.Json.JsonValue.*;
import core.Json.Reader;

class JsonTest {
	public static function main():Void {
		var value = Reader.readJson('{"name":"Haxe\\ncompiler","count":42,"fraction":1.5,"ok":true,"none":null,"items":["x",-1]}');
		switch (value) {
			case JObject(fields):
				if (fields.length != 6 || fields[0].name != "name") throw "Object parsing failed";
				switch (fields[1].value) { case JInt(42): case _: throw "Integer parsing failed"; }
				switch (fields[2].value) { case JFloat(1.5): case _: throw "Float parsing failed"; }
			case _: throw "Expected object";
		}
		if (Json.stringOfJson(JObject([{name: "\t", value: JString('"\\\n' + String.fromCharCode(1))}, {name: "array", value: JArray([JBool(false), JNull])}])) != '{"\\t":"\\"\\\\\\n\\u0001","array":[false,null]}') throw "JSON writing failed";
		switch (Reader.readJson('"\\uD83D\\uDE00"')) { case JString("😀"): case _: throw "Surrogate pair parsing failed"; }
		switch (Reader.readJson("1 trailing")) { case JInt(1): case _: throw "Trailing input behavior changed"; }
		switch (Reader.readJson("2147483648")) { case JFloat(2147483648.0): case _: throw "Integer overflow handling failed"; }
		assertThrows(function() Reader.readJson('"\\uD83D"'));
		assertThrows(function() Reader.readJson("[1,]"));
		assertThrows(function() Json.stringOfJson(JFloat(Math.NaN)));
	}

	static function assertThrows(callback:Void->Void):Void {
		try callback() catch (_:Dynamic) return;
		throw "Expected JSON failure";
	}
}
