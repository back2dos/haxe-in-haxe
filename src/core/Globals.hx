package core;

// Port of the foundational definitions in haxe/src/core/globals.ml.

typedef Pos = {
	var pfile:String;
	var pmin:Int;
	var pmax:Int;
}

typedef GlobalTypePath = {
	var pack:Array<String>;
	var name:String;
}

typedef CompilerVersion = {
	var version:Int;
	var major:Int;
	var minor:Int;
	var revision:Int;
	var pre:Null<String>;
	var extra:Null<{name:String, build:String}>;
}

enum Platform {
	Cross;
	Js;
	Lua;
	Neko;
	Flash;
	Php;
	Cpp;
	Jvm;
	Python;
	Hl;
	Eval;
	CustomTarget(name:String);
}

class Globals {
	public static final version = 5000;
	public static final versionMajor = Std.int(version / 1000);
	public static final versionMinor = Std.int((version % 1000) / 100);
	public static final versionRevision = version % 100;
	public static final versionPre:Null<String> = "preview.1";

	public static final isWindows = Sys.systemName() == "Windows" || Sys.systemName() == "Cygwin";
	public static final maxCustomTargetLen = 16;
	public static final platforms:Array<Platform> = [Js, Lua, Neko, Flash, Php, Cpp, Jvm, Python, Hl, Eval];
	public static final sVersion = versionToString();

	static function versionToString():String {
		return versionMajor + "." + versionMinor + "." + versionRevision + (versionPre == null ? "" : "-" + versionPre);
	}

	public static function filePos(file:String):Pos return {pfile: file, pmin: 0, pmax: 0};
	public static function fakePos(file:String):Pos return {pfile: file, pmin: -1, pmax: -1};
	public static final nullPos:Pos = fakePos("?");

	public static function platformName(platform:Platform):String {
		return switch (platform) {
			case Cross: "cross";
			case Js: "js";
			case Lua: "lua";
			case Neko: "neko";
			case Flash: "flash";
			case Php: "php";
			case Cpp: "cpp";
			case Jvm: "jvm";
			case Python: "python";
			case Hl: "hl";
			case Eval: "eval";
			case CustomTarget(name): name;
		};
	}

	public static function parsePlatform(name:String):Platform {
		return switch (name) {
			case "cross": Cross;
			case "js": Js;
			case "lua": Lua;
			case "neko": Neko;
			case "flash": Flash;
			case "php": Php;
			case "cpp": Cpp;
			case "jvm": Jvm;
			case "python": Python;
			case "hl": Hl;
			case "eval": Eval;
			case _: CustomTarget(name);
		};
	}

	public static function platformListHelp(platforms:Array<Platform>):String {
		return switch (platforms.length) {
			case 0: "";
			case 1: " (" + platformName(platforms[0]) + " only)";
			case _: " (for " + [for (platform in platforms) platformName(platform)].join(",") + ")";
		};
	}

	public static function mkZeroRangePos(pos:Pos):Pos return {pfile: pos.pfile, pmin: pos.pmin, pmax: pos.pmin};
	public static function sTypePath(path:GlobalTypePath):String return path.pack.length == 0 ? path.name : path.pack.join(".") + "." + path.name;
	public static function startsWith(value:String, char:String):Bool return value.length > 0 && value.charAt(0) == char;
	public static function patchStringPos(pos:Pos, value:String):Pos return {pfile: pos.pfile, pmin: pos.pmax - value.length, pmax: pos.pmax};

	// Like globals.ml, this only appends the build portion of the supplied version.
	public static function sVersionFull(version:CompilerVersion):String return version.extra == null ? sVersion : sVersion + "+" + version.extra.build;
}
