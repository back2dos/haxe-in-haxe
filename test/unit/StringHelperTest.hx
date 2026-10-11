package unit;

import core.StringHelper;

class StringHelperTest {
	public static function main():Void {
		if (StringHelper.uppercase("Haxe-abc") != "HAXE-ABC" || StringHelper.capitalize("haxe") != "Haxe") throw "ASCII case conversion failed";
		if (!StringHelper.startsUppercaseIdentifier("__Main") || StringHelper.startsUppercaseIdentifier("_main")) throw "Identifier case detection failed";
		if (StringHelper.sEscape("a\n\"\\") != "a\\n\\\"\\\\") throw "String escaping failed";
		if (StringHelper.escapeResName("a b!", ["!"]) != "a-x32b!") throw "Resource name escaping failed";
		if (StringHelper.removeExtension("Main.hx") != "Main" || StringHelper.extension("Main") != "Main") throw "Extension helpers failed";
		if (StringHelper.urlEncodeString("a b/é") != "a%20b%2F%C3%A9") throw "URL encoding failed";
		var utf16 = StringHelper.utf8ToUtf16("A😀", true);
		if ([for (i in 0...utf16.length) utf16.charCodeAt(i)].join(",") != "65,0,61,216,0,222,0,0") throw "UTF-16 conversion failed";
		// Like upstream, only ASCII round-trips: the high byte of other units is copied as is.
		if (StringHelper.utf16ToUtf8(StringHelper.utf8ToUtf16("Ab", false)) != "Ab") throw "UTF-16 to UTF-8 conversion failed";
	}
}
