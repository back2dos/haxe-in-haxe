package unit;

import compiler.hxb.HxbWriterConfig;

class HxbWriterConfigTest {
	public static function main():Void {
		var config = new HxbWriterConfig();
		HxbWriterConfig.parse(config, '{"archivePath":"out.zip","targetConfig":{"generate":false,"exclude":["internal.debug"],"include":["api.Public"],"hxbVersion":2,"generateDocumentation":false},"macroConfig":null}');
		if (config.archivePath != "out.zip") throw "Archive path was not parsed";
		if (config.targetConfig.generate || config.targetConfig.generateDocs || config.targetConfig.hxbVersion != 2) throw "Target flags were not parsed";
		if (config.targetConfig.exclude[0].join(".") != "internal.debug" || config.targetConfig.include[0].join(".") != "api.Public") throw "Target paths were not parsed";

		assertFailure('{"unknown":true}', "Unknown key for writer config: unknown");
		assertFailure('{"targetConfig":{"generate":"no"}}', "Expected JBool");
	}

	static function assertFailure(input:String, expected:String):Void {
		try {
			HxbWriterConfig.parse(new HxbWriterConfig(), input);
			throw "Expected writer config failure";
		} catch (error:Dynamic) {
			var message = Std.isOfType(error, core.Error.TypingError) ? core.Error.errorMsg((error : core.Error.TypingError).error.errMessage) : Std.string(error);
			if (message.indexOf(expected) < 0) throw error;
		}
	}
}
