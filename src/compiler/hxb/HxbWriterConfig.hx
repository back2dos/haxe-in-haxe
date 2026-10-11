package compiler.hxb;

import core.Globals.nullPos;
import core.data.DataReaderApi;
import core.data.DataWriterApi;

class WriterTargetConfig {
	public var generate:Bool;
	public var exclude:Array<Array<String>>;
	public var include:Array<Array<String>>;
	public var hxbVersion:Int;
	public var generateDocs:Bool;

	// port: create_target_config
	public function new() {
		generate = true;
		exclude = [];
		include = [];
		hxbVersion = HxbData.VERSION;
		generateDocs = true;
	}
}

// port: the record type t; `new` is create.
class HxbWriterConfig {
	public var archivePath:String;
	public final targetConfig:WriterTargetConfig;
	public final macroConfig:WriterTargetConfig;

	public function new() {
		archivePath = "";
		targetConfig = new WriterTargetConfig();
		macroConfig = new WriterTargetConfig();
	}

	static function error(s:String):Dynamic {
		return core.Error.raiseTypingError(s, nullPos);
	}

	// port: ExtString.String.nsplit (an empty string has no parts).
	static function nsplit(s:String, sep:String):Array<String> return s == "" ? [] : s.split(sep);

	// port: module WriterConfigReader (API : DataReaderApi.DataReaderApi), with the API as an argument.
	public static function readTargetConfig<Data>(api:DataReaderApi<Data>, config:WriterTargetConfig, fl:Array<{name:String, value:Data}>):Void {
		for (f in fl) {
			var data = f.value;
			switch f.name {
				case "generate":
					config.generate = api.readBool(data);
				case "exclude":
					api.readOptional(data, function(data) {
						var l = api.readArray(data);
						config.exclude = l.map(data -> nsplit(api.readString(data), "."));
					});
				case "include":
					api.readOptional(data, function(data) {
						var l = api.readArray(data);
						config.include = l.map(data -> nsplit(api.readString(data), "."));
					});
				case "hxbVersion":
					config.hxbVersion = api.readInt(data);
				case "generateDocumentation":
					config.generateDocs = api.readBool(data);
				case s:
					error("Unknown key for target config: " + s);
			}
		}
	}

	public static function readWriterConfig<Data>(api:DataReaderApi<Data>, config:HxbWriterConfig, data:Data):Void {
		function read(data:Data) {
			var fl = api.readObject(data);
			for (f in fl) {
				var data = f.value;
				switch f.name {
					case "archivePath":
						config.archivePath = api.readString(data);
					case "targetConfig":
						api.readOptional(data, data -> readTargetConfig(api, config.targetConfig, api.readObject(data)));
					case "macroConfig":
						api.readOptional(data, data -> readTargetConfig(api, config.macroConfig, api.readObject(data)));
					case s:
						error("Unknown key for writer config: " + s);
				}
			}
		}
		api.readOptional(data, read);
	}

	// port: module WriterConfigWriter (API : DataWriterApi.DataWriterApi), with the API as an argument.
	public static function writeTargetConfig<Data>(api:DataWriterApi<Data>, config:WriterTargetConfig):Data {
		return api.writeObject([
			{name: "generate", value: api.writeBool(config.generate)},
			{name: "exclude", value: api.writeArray(config.exclude.map(sl -> api.writeString(sl.join("."))))},
			{name: "include", value: api.writeArray(config.include.map(sl -> api.writeString(sl.join("."))))},
			{name: "hxbVersion", value: api.writeInt(config.hxbVersion)},
			{name: "generateDocumentation", value: api.writeBool(config.generateDocs)},
		]);
	}

	public static function writeWriterConfig<Data>(api:DataWriterApi<Data>, config:HxbWriterConfig):Data {
		return api.writeObject([
			{name: "archivePath", value: api.writeString(config.archivePath)},
			{name: "targetConfig", value: writeTargetConfig(api, config.targetConfig)},
			{name: "macroConfig", value: writeTargetConfig(api, config.macroConfig)},
		]);
	}

	// port: module WriterConfigReaderJson = WriterConfigReader(JsonDataApi.JsonReaderApi)
	static final jsonReaderApi:DataReaderApi<Dynamic> = new DataReaderApi<Dynamic>(core.data.JsonDataApi.JsonReaderApi.readOptional,
		data -> core.data.JsonDataApi.JsonReaderApi.readObject(data).map(f -> {name: f.name, value: f.value}),
		core.data.JsonDataApi.JsonReaderApi.readArray, core.data.JsonDataApi.JsonReaderApi.readString,
		core.data.JsonDataApi.JsonReaderApi.readIdent, core.data.JsonDataApi.JsonReaderApi.readBool,
		core.data.JsonDataApi.JsonReaderApi.readInt, core.data.JsonDataApi.JsonReaderApi.dataToString);

	public static function processJson(config:HxbWriterConfig, json:Dynamic):Void {
		readWriterConfig(jsonReaderApi, config, json);
	}

	public static function parse(config:HxbWriterConfig, input:String):Void {
		// port: Json.Reader.read_json over a Sedlex buffer; haxe.Json.parse builds the same values.
		var json = haxe.Json.parse(input);
		processJson(config, json);
	}

	public static function processArgument(file:String):HxbWriterConfig {
		var config = new HxbWriterConfig();
		switch core.Path.fileExtension(file) {
			case "json":
				var data = try sys.io.File.getContent(file) catch (exc:Dynamic) {
					// port: Printexc.to_string of the Sys_error raised by open_in.
					var exc = if (!sys.FileSystem.exists(file)) "Sys_error(\"" + file + ": No such file or directory\")" else Std.string(exc);
					error("Could not open file " + file + ": " + exc);
				}
				parse(config, data);
			case _:
				config.archivePath = file;
		}
		// port: `Some config`
		return config;
	}
}
