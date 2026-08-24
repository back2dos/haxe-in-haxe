import syntax.Grammar;

/**
	A breadth probe over the pinned upstream unit sources. This is parser
	coverage, not compiler conformance: many files require macros, libraries,
	target defines, or intentionally exercise compiler failures.
**/
class UpstreamParserCorpus {
	static final expectedFileCount = 1366;
	static final minimumParsedCount = 808;

	static function main():Void {
		var root = "haxe/tests/unit/src";
		var files:Array<String> = [];
		collect(root, files);
		files.sort(Reflect.compare);
		if (files.length != expectedFileCount) throw 'Pinned upstream parser corpus changed: expected $expectedFileCount files, found ${files.length}';

		var parsed = 0;
		for (file in files) try {
			Grammar.parse(sys.io.File.getContent(file), core.Define.emptyDefines(), file);
			parsed++;
		} catch (_:Dynamic) {}

		if (parsed < minimumParsedCount) throw 'Upstream parser coverage regressed: parsed $parsed/${files.length}, expected at least $minimumParsedCount';
		Sys.println('Upstream parser corpus: parsed $parsed/${files.length} (floor $minimumParsedCount)');
	}

	static function collect(path:String, files:Array<String>):Void for (name in sys.FileSystem.readDirectory(path)) {
		var child = path + "/" + name;
		if (sys.FileSystem.isDirectory(child)) collect(child, files);
		else if (StringTools.endsWith(name, ".hx")) files.push(child);
	}
}
