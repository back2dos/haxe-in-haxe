package unit;

import core.Ast;
import core.Define;

/** Conditional compilation in the translated parser (`parserEntry.ml`). */
class PreprocessorTest {
	public static function main():Void {
		var defines = Define.emptyDefines();
		Define.rawDefineValue(defines, "feature", "2");
		Define.rawDefineValue(defines, "platform.js", "1");
		assertNames('#if (feature >= 2)\nclass Selected {}\n#elseif feature\nclass Wrong {}\n#else\nclass Fallback {}\n#end', defines, ["Selected"]);
		assertNames('#if missing\nclass Wrong {}\n#else\n#if platform.js\nclass Nested {}\n#end\n#end', defines, ["Nested"]);
		assertNames('#if (version("4.3.0") > "4.2.9")\nclass Versioned {}\n#end', defines, ["Versioned"]);
		assertNames('#if (/* note */ feature)\nclass Commented {}\n#end', defines, ["Commented"]);
		var documented = GrammarTest.parse('/** Kept. */ class Documented {} // discarded', defines, "Test.hx");
		switch documented.declarations[0].definition {
			case EClass({doc: {docOwn: " Kept. "}}):
			case _: throw "Documentation comment was discarded";
		}
		assertThrows('#end', defines);
		// Like upstream, only a skipped block reaching the end of the file is reported as unclosed.
		assertThrows('#if missing\nclass Open {}', defines);
	}

	static function assertNames(source:String, defines, expected:Array<String>):Void {
		var names = [for (decl in GrammarTest.parse(source, defines, "Test.hx").declarations) switch decl.definition {
			case EClass(c): c.name.name;
			case _: null;
		}].filter(function(value) return value != null);
		if (names.join(",") != expected.join(",")) throw 'Expected ${expected.join(",")}, got ${names.join(",")}';
	}

	static function assertThrows(source:String, defines):Void {
		try GrammarTest.parse(source, defines, "Test.hx") catch (_:String) return;
		throw "Expected preprocessor error";
	}
}
