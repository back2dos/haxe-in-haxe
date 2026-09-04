package context;
import core.Define;
import core.Define.DefineContext;
// Draft mechanical translation of haxe/src/context/dumpConfig.ml; unvalidated.
enum DumpMode { NoDump; Ast; Pretty; Record; Position; }
enum DumpStage { AfterTyping; AfterCasting; AfterInlining; AfterAnalyzing; AfterSanitizing; AfterDce; }
typedef DumpConfiguration = {
	var dumpMode:DumpMode;
	var dumpPath:String;
	var dumpStage:DumpStage;
	var dumpPrintIds:Bool;
	var dumpDependencies:Bool;
}
class DumpConfig {
	public static function createDefault():DumpConfiguration return {
		dumpMode:NoDump, dumpPath:"dump", dumpStage:AfterDce,
		dumpPrintIds:false, dumpDependencies:false
	};
	public static function updateFromDefines(conf:DumpConfiguration, def:DefineContext):Void {
		conf.dumpMode = switch Define.rawDefinedValueSafe(def, "dump") {
			case "1": Ast;
			case "pretty": Pretty;
			case "record": Record;
			case "position": Position;
			case _: NoDump;
		};
		conf.dumpPath = Define.rawDefinedValueSafe(def, "dump-path", "dump");
		conf.dumpStage = switch Define.rawDefinedValueSafe(def, "dump-stage") {
			case "typing": AfterTyping;
			case "casting": AfterCasting;
			case "inlining": AfterInlining;
			case "analyzing": AfterAnalyzing;
			case "sanitizing": AfterSanitizing;
			case "dce": AfterDce;
			case _: AfterDce;
		};
		conf.dumpPrintIds = !Define.rawDefined(def, "dump-ignore-var-ids");
		conf.dumpDependencies = Define.rawDefined(def, "dump-dependencies");
	}
	public static function stringOfDumpStage(stage:DumpStage):String return switch stage {
		case AfterTyping: "AfterTyping";
		case AfterCasting: "AfterCasting";
		case AfterInlining: "AfterInlining";
		case AfterAnalyzing: "AfterAnalyzing";
		case AfterSanitizing: "AfterSanitizing";
		case AfterDce: "AfterDce";
	};
}
