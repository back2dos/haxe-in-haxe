package unit;

import compiler.hxb.HxbWriterConfig;

class HxbWriterConfigTest {
	public static function main():Void {
		var config = new HxbWriterConfig();
		HxbWriterConfig.parse(config, '{"archivePath":"out.zip","targetConfig":{"generate":false,"exclude":["internal.debug"],"include":["api.Public"],"hxbVersion":2,"generateDocumentation":false},"macroConfig":null}');
		if (config.archivePath != "out.zip") throw "Archive path was not parsed";
		if (config.targetConfig.generate || config.targetConfig.generateDocumentation || config.targetConfig.hxbVersion != 2) throw "Target flags were not parsed";
		if (config.targetConfig.exclude[0].join(".") != "internal.debug" || config.targetConfig.include[0].join(".") != "api.Public") throw "Target paths were not parsed";

		var encoded = HxbWriterConfig.toJson(config);
		var roundTrip = new HxbWriterConfig();
		HxbWriterConfig.parse(roundTrip, encoded);
		if (roundTrip.archivePath != "out.zip" || roundTrip.targetConfig.exclude[0].join(".") != "internal.debug") throw "Writer config round-trip failed";

		assertFailure('{"unknown":true}', "Unknown key for writer config: unknown");
		assertFailure('{"targetConfig":{"generate":"no"}}', "Expected boolean");
	}

	static function assertFailure(input:String, expected:String):Void {
		try {
			HxbWriterConfig.parse(new HxbWriterConfig(), input);
			throw "Expected writer config failure";
		} catch (error:Dynamic) {
			if (Std.string(error).indexOf(expected) < 0) throw error;
		}
	}
}
