package syntax;
import core.Globals;
import context.Common;
// Draft mechanical translation of haxe/src/syntax/parserConfig.ml; unvalidated.
class ParserConfig {
	public static function defaultConfig(defines:Dynamic):Dynamic return Parser.createConfig(defines,false,false,DMNone,false,null);
	public static function fileParserConfig(com:Dynamic, file:String):Dynamic {
		var displayPosition = DisplayPosition.displayPosition;
		var inDisplay = displayPosition.get() != Globals.nullPos;
		var inDisplayFile = inDisplay && displayPosition.isInFile(core.Path.UniqueKey.create(file));
		return Parser.createConfig(com.defines,inDisplay,inDisplayFile,com.display.dmsKind,com.partScope.parserState.wasAutoTriggered,com.partScope.parserState.specialIdentifierFiles);
	}
}
