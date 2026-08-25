package unit;

import core.Ast;
import core.Define;
import syntax.Preprocessor;

class PreprocessorTest {
	public static function main():Void {
		var defines = Define.emptyDefines();
		Define.rawDefineValue(defines, "feature", "2");
		Define.rawDefineValue(defines, "platform.js", "1");
		assertNames('#if feature >= 2\nclass Selected {}\n#elseif feature\nclass Wrong {}\n#else\nclass Fallback {}\n#end', defines, ["Selected"]);
		assertNames('#if missing\nclass Wrong {}\n#else\n#if platform.js\nclass Nested {}\n#end\n#end', defines, ["Nested"]);
		assertNames('#if version("4.3.0") > "4.2.9"\nclass Versioned {}\n#end', defines, ["Versioned"]);
		assertNames('#if (/* note */ feature)\nclass Commented {}\n#end', defines, ["Commented"]);
		var documented = Preprocessor.process('/** Kept. */ class Documented {} // discarded', defines, "Test.hx");
		if (!Lambda.exists(documented, function(item) return switch item.token { case Comment(value): value == "* Kept. "; case _: false; })) throw "Documentation comment was discarded";
		if (Lambda.exists(documented, function(item) return switch item.token { case CommentLine(_): true; case _: false; })) throw "Line comment was preserved";
		assertThrows('#end', defines, InvalidEnd);
		assertThrows('#if feature\nclass Open {}', defines, UnclosedConditional);
	}

	static function assertNames(source:String, defines, expected:Array<String>):Void {
		var names = [for (item in Preprocessor.process(source, defines, "Test.hx")) switch item.token { case Const(Ident(value)): value; case _: null; }].filter(function(value) return value != null);
		if (names.join(",") != expected.join(",")) throw 'Expected ${expected.join(",")}, got ${names.join(",")}';
	}
	static function assertThrows(source:String, defines, expected:PreprocessorErrorMsg):Void {
		try Preprocessor.process(source, defines, "Test.hx") catch (error:PreprocessorError) {
			if (Type.enumEq(error.message, expected)) return;
			throw 'Unexpected preprocessor error';
		}
		throw "Expected preprocessor error";
	}
}
