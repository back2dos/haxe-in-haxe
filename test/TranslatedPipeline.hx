// Runs the translated compiler (haxe.Main). Without arguments it compiles the
// Basic fixture and checks that the archive contains the typed root module.
class TranslatedPipeline {
	static function main():Void {
		var output = "test/generated/testing/translated-basic.hxb";
		var arguments = Sys.args();
		var defaultCase = arguments.length == 0;
		if (defaultCase) {
			sys.FileSystem.createDirectory("test/generated/testing");
			if (sys.FileSystem.exists(output)) sys.FileSystem.deleteFile(output);
			arguments = ["-cp", "test/conformance", "--main", "unit.moduleload.Basic", "--interp", "--no-output", "--hxb", output];
		}
		var code = haxe.Main.run(arguments);
		var request = haxe.Main.lastRequest;
		if (code == 0 && defaultCase) {
			if (request.stats.sModulesTyped == 0 || !sys.FileSystem.exists(output)) throw "Pipeline reported success without typing modules and writing HXB";
			var input = sys.io.File.read(output, true), entries = haxe.zip.Reader.readZip(input);
			input.close();
			var basic = false;
			for (entry in entries) if (entry.fileName == "eval/unit/moduleload/Basic.hxb" && entry.fileSize > 0) basic = true;
			if (!basic) throw "HXB archive is missing the typed Basic module";
		}
		if (request != null) Sys.println("Translated pipeline exit=" + code + " parsed=" + request.stats.sFilesParsed + " typed=" + request.stats.sModulesTyped + " methods=" + request.stats.sMethodsTyped);
		Sys.exit(code);
	}
}
