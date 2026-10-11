package context;

import core.Globals.GlobalTypePath;
import core.Globals.Pos;
import core.Ast;

enum NativeLibFlags {
	FlagIsStd;
	FlagIsExtern;
}

class NativeLibraryBase {
	var flags:Array<NativeLibFlags> = [];
	final name:String;
	final filePath:String;

	public function new(name:String, filePath:String) {
		this.name = name;
		this.filePath = filePath;
	}

	public function addFlag(flag:NativeLibFlags):Void flags.unshift(flag);

	public function hasFlag(flag:NativeLibFlags):Bool return flags.contains(flag);

	public function getName():String return name;

	public function getFilePath():String return filePath;
}

interface NativeLibrary<A, Data> {
	public function addFlag(flag:NativeLibFlags):Void;
	public function hasFlag(flag:NativeLibFlags):Bool;
	public function getName():String;
	public function getFilePath():String;
	public function build(path:GlobalTypePath, pos:Pos):Null<Package>;
	public function close():Void;
	public function listModules():Array<GlobalTypePath>;
	public function load():Void;
	public function lookup(path:GlobalTypePath):A;
	public function getData():Data;
}

// port: JClass.jclass is opaque here (the JVM loader's lookup always answers None).
interface JavaClassData {}
typedef JavaLibType = Null<{cls:JavaClassData, source:String, library:String}>;
typedef SwfLibType = Null<libs.swflib.As3hl.HlClass>;

typedef NativeLibrariesData = {
	var javaLibs:Array<NativeLibrary<JavaLibType, Void>>;
	var swfLibs:Array<NativeLibrary<SwfLibType, libs.swflib.Swf.SwfData>>;
	var allLibs:Array<String>;
}

class NativeLibraries {
	public static function createNativeLibs():NativeLibrariesData return {javaLibs: [], swfLibs: [], allLibs: []};
}
