package compiler;

// Port of haxe/src/compiler/parsedArg.ml.

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

typedef NativeLibArg = {
	var libFile:String;
	var libKind:NativeLibKind;
	var libExtern:Bool;
}

/** The CLI representation is intentionally separate from compiler context mutation. */
enum ParsedArg {
	SetPlatform(platform:Platform, output:String);
	SetCppiaTarget(output:String);
	AddClassPath(path:String);
	AddLibClassPath(path:String);
	AddHxbLib(file:String);
	SetMain(path:Array<String>);
	AddLib(name:String);
	Define(flag:String, value:Null<String>);
	Undefine(flag:String);
	SetVerbose;
	SetDebug;
	Interp;
	Run(path:String, arguments:Array<String>);
	RunX(path:String);
	AddResource(file:String, name:String);
	RunCmd(command:String);
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
	Next;
	Each;
	Cwd(path:String);
	HxmlFile(file:String);
	ShowVersion;
	ShowHelp;
}
