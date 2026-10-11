package compiler;

// port: the platforms a target flag selects (upstream uses Globals.platform).
enum Platform {
	Js;
	Lua;
	Flash;
	Neko;
	Php;
	Cpp;
	Jvm;
	Python;
	Hl;
}

enum NativeLibKind {
	JavaLib;
	SwfLib;
	HxbLib;
}

@:structInit class NativeLibArg {
	public var libFile:String;
	public var libKind:NativeLibKind;
	public var libExtern:Bool;

	public inline function new(libFile:String, libKind:NativeLibKind, libExtern:Bool) {
		this.libFile = libFile;
		this.libKind = libKind;
		this.libExtern = libExtern;
	}

	public inline function clone():NativeLibArg return new NativeLibArg(libFile, libKind, libExtern);
}

enum ExpandingArgFunction {
	AddLibs(libs:Array<String>, cwd:String);
}

enum ExpandingArgState {
	NotYetExpanded(f:ExpandingArgFunction);
	AlreadyExpanded(args:Array<ParsedArg>);
}

class ExpandingArg {
	public final original:Array<ParsedArg>;
	public var state:ExpandingArgState;

	public function new(original:Array<ParsedArg>, state:ExpandingArgState) {
		this.original = original;
		this.state = state;
	}
}

enum ParsedArg {
	// Targets
	SetPlatform(platform:Platform, output:String);
	SetCustomTarget(name:String, path:String);
	/** --cppia: cpp target with cppia define */
	SetCppiaTarget(output:String);
	// Compilation
	AddClassPath(path:String);
	AddLibClassPath(path:String);
	AddHxbLib(file:String);
	SetMain(path:Array<String>);
	AddLib(name:String);
	HaxelibGlobal;
	Define(flag:String, value:Null<String>);
	Undefine(flag:String);
	SetVerbose;
	SetDebug;
	/** --interp: eval target + interp flag */
	Interp;
	/** --run: path + runtime args (terminal; rest becomes argv) */
	Run(path:String, arguments:Array<String>);
	/** -x: shorthand run (non-terminal; subsequent args are still build args) */
	RunX(path:String);
	AddResource(file:String, name:String);
	RunCmd(command:String);
	SetSwfVersion(version:Float);
	SetDce(mode:String);
	AddNativeLib(library:NativeLibArg);
	AddNekoLibPath(path:String);
	Remap(pack:String, target:String);
	SetCustomExtension(extension:String);
	AddMacro(expression:String);
	SetDisplayArg(input:String);
	SetXmlOut(file:String);
	SetJsonOut(file:String);
	SetHxbOut(file:String);
	SetNoOutput;
	SetMeasureTimes;
	AddWarning(setting:String);

	AddClass(path:Array<String>);
	IncludeModule(module:String);
	SetPrompt;
	// Batch
	Next;
	Each;
	Expand(ex:ExpandingArg);
	// Server
	ServerListen(hostPort:String);
	ServerConnect(hostPort:String);
	Connect(hostPort:String);
	// Working directory - applied eagerly for hxml resolution
	Cwd(path:String);
	// Hxml file reference - expanded lazily in process_params
	HxmlFile(file:String);
	// Early-exit helpers (raise HelpMessage when processed)
	ShowVersion;
	ShowHelp;
	ShowHelpDefines;
	ShowHelpMetas;
	ShowHelpUserDefines;
	ShowHelpUserMetas;
}
