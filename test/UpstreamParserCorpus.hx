import syntax.Grammar;
import syntax.Lexer;
import syntax.Parser;
import syntax.ParserEntry;

/**
	A breadth probe over the pinned upstream unit sources. This is parser
	coverage, not compiler conformance: many files require macros, libraries,
	target defines, or intentionally exercise compiler failures.
**/
class UpstreamParserCorpus {
	static final expectedFileCount = 1366;
	static final minimumParsedCount = 1355;

	static function main():Void {
		var root = "haxe/tests/unit/src";
		var files:Array<String> = [];
		collect(root, files);
		files.sort(Reflect.compare);
		if (files.length != expectedFileCount) throw 'Pinned upstream parser corpus changed: expected $expectedFileCount files, found ${files.length}';

		var parsed = 0;
		var reportFailures = Sys.getEnv("HAXE_PARSER_REPORT_FAILURES") == "1";
		for (file in files) try {
			var config = Parser.createConfig(core.Define.emptyDefines(), false, false, DMNone, false, null);
			switch ParserEntry.parse(config, Grammar.parseFileStream, Lexer.createTempCtx(file), new Lexer(sys.io.File.getContent(file), file), file) {
				case ParseSuccess(_, _): parsed++;
				case ParseError(_, error, _): throw new ParserError(error.message, error.pos);
			}
		} catch (error:Dynamic) {
			if (reportFailures) Sys.println('$file: ${formatError(error)}');
		}

		if (parsed < minimumParsedCount) throw 'Upstream parser coverage regressed: parsed $parsed/${files.length}, expected at least $minimumParsedCount';
		Sys.println('Upstream parser corpus: parsed $parsed/${files.length} (floor $minimumParsedCount)');
	}

	static function formatError(error:Dynamic):String {
		if (Std.isOfType(error, ParserError)) return Parser.errorMsg((error:ParserError).error) + " at " + (error:ParserError).pos.pfile + ":" + (error:ParserError).pos.pmin;
		var message = Reflect.hasField(error, "message") ? Std.string(Reflect.field(error, "message")) : Std.string(error);
		var pos:Dynamic = Reflect.field(error, "pos");
		return pos == null ? message : '$message at ${pos.pfile}:${pos.pmin}';
	}

	static function collect(path:String, files:Array<String>):Void for (name in sys.FileSystem.readDirectory(path)) {
		var child = path + "/" + name;
		if (sys.FileSystem.isDirectory(child)) collect(child, files);
		else if (StringTools.endsWith(name, ".hx")) files.push(child);
	}
}
