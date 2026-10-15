package unit;

import core.StringError;

class StringErrorTest {
	public static function main():Void {
		if (StringError.levenshtein("kitten", "sitting") != 3) throw "Levenshtein distance failed";
		if (StringError.getSimilar("strng", ["string", "strong", "unrelated"]).join(",") != "string,strong") throw "Similar-string filtering failed";
		if (StringError.stringError("strng", ["string"], "Unknown type") != "Unknown type (Suggestion: string)") throw "Single suggestion failed";
		if (StringError.stringError("zzz", ["string"], "Unknown type") != "Unknown type") throw "No suggestion must preserve message";
	}
}
