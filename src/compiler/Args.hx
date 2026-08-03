package compiler;

import compiler.ParsedArg;

// Port of the parse_args portion of haxe/src/compiler/args.ml.
class Args {
	public static function parseArgs(arguments:Array<String>):Array<ParsedArg> {
		var parsed:Array<ParsedArg> = [];
		var index = 0;
		while (index < arguments.length) {
			var argument = arguments[index++];
			switch (argument) {
				case "--next", "-next": parsed.push(Next);
				case "--each", "-each": parsed.push(Each);
				case "--cwd", "-C": parsed.push(Cwd(requiredArgument(argument, arguments, index++)));
				case "--js", "-js": parsed.push(SetPlatform(Js, requiredArgument(argument, arguments, index++)));
				case "--lua", "-lua": parsed.push(SetPlatform(Lua, requiredArgument(argument, arguments, index++)));
				case "--swf", "-swf": parsed.push(SetPlatform(Flash, requiredArgument(argument, arguments, index++)));
				case "--neko", "-neko": parsed.push(SetPlatform(Neko, requiredArgument(argument, arguments, index++)));
				case "--php", "-php": parsed.push(SetPlatform(Php, requiredArgument(argument, arguments, index++)));
				case "--cpp", "-cpp": parsed.push(SetPlatform(Cpp, requiredArgument(argument, arguments, index++)));
				case "--jvm", "-jvm":
					parsed.push(SetPlatform(Jvm, requiredArgument(argument, arguments, index++)));
					parsed.push(AddLib("hxjava"));
				case "--python", "-python": parsed.push(SetPlatform(Python, requiredArgument(argument, arguments, index++)));
				case "--hl", "-hl": parsed.push(SetPlatform(Hl, requiredArgument(argument, arguments, index++)));
				case "--custom-target", "-custom":
					var target = requiredArgument(argument, arguments, index++);
					var equals = target.indexOf("=");
					parsed.push(equals < 0 ? SetCustomTarget(target, "") : SetCustomTarget(target.substr(0, equals), target.substr(equals + 1)));
				case "--cppia", "-cppia": parsed.push(SetCppiaTarget(requiredArgument(argument, arguments, index++)));
				case "-x": parsed.push(RunX(requiredArgument(argument, arguments, index++)));
				case "--interp": parsed.push(Interp);
				case "--run":
					var path = requiredArgument(argument, arguments, index++);
					parsed.push(Run(path, arguments.slice(index)));
					return parsed;
				case "--class-path", "-p", "-cp": parsed.push(AddClassPath(requiredArgument(argument, arguments, index++)));
				case "-libcp": parsed.push(AddLibClassPath(requiredArgument(argument, arguments, index++)));
				case "--hxb-lib", "-hxb-lib": parsed.push(AddHxbLib(requiredArgument(argument, arguments, index++)));
				case "--main", "-m", "-main": parsed.push(SetMain(parseTypePath(requiredArgument(argument, arguments, index++))));
				case "--library", "-L", "-lib": parsed.push(AddLib(requiredArgument(argument, arguments, index++)));
				case "--define", "-D":
					var define = requiredArgument(argument, arguments, index++);
					var equals = define.indexOf("=");
					parsed.push(equals < 0 ? Define(define, null) : Define(define.substr(0, equals), define.substr(equals + 1)));
				case "--undefine": parsed.push(Undefine(requiredArgument(argument, arguments, index++)));
				case "--verbose", "-v": parsed.push(SetVerbose);
				case "--debug", "-debug": parsed.push(SetDebug);
				case "--version", "-version":
					parsed.push(ShowVersion);
					return parsed;
				case "--help", "-h", "-help":
					parsed.push(ShowHelp);
					return parsed;
				case "--help-defines":
					parsed.push(ShowHelpDefines);
					return parsed;
				case "--help-metas":
					parsed.push(ShowHelpMetas);
					return parsed;
				case "--help-user-defines":
					parsed.push(ShowHelpUserDefines);
					return parsed;
				case "--help-user-metas":
					parsed.push(ShowHelpUserMetas);
					return parsed;
				case "--dce", "-dce": parsed.push(SetDce(requiredArgument(argument, arguments, index++)));
				case "--swf-version", "-swf-version":
					var version = Std.parseFloat(requiredArgument(argument, arguments, index++));
					if (!Math.isNaN(version)) parsed.push(SetSwfVersion(version));
				case "--swf-lib", "-swf-lib": parsed.push(AddNativeLib(nativeLib(requiredArgument(argument, arguments, index++), false, SwfLib)));
				case "--swf-lib-extern", "-swf-lib-extern": parsed.push(AddNativeLib(nativeLib(requiredArgument(argument, arguments, index++), true, SwfLib)));
				case "--java-lib", "-java-lib": parsed.push(AddNativeLib(nativeLib(requiredArgument(argument, arguments, index++), false, JavaLib)));
				case "--java-lib-extern": parsed.push(AddNativeLib(nativeLib(requiredArgument(argument, arguments, index++), true, JavaLib)));
				case "--neko-lib-path": parsed.push(AddNekoLibPath(requiredArgument(argument, arguments, index++)));
				case "--resource", "-r", "-resource":
					var resource = requiredArgument(argument, arguments, index++);
					var at = resource.indexOf("@");
					parsed.push(at < 0 ? AddResource(resource, resource) : AddResource(resource.substr(0, at), resource.substr(at + 1)));
			case "--cmd", "-cmd": parsed.push(RunCmd(Helper.unquote(requiredArgument(argument, arguments, index++))));
				case "--prompt", "-prompt": parsed.push(SetPrompt);
				case "--display": parsed.push(SetDisplayArg(requiredArgument(argument, arguments, index++)));
				case "--xml", "-xml": parsed.push(SetXmlOut(requiredArgument(argument, arguments, index++)));
				case "--json": parsed.push(SetJsonOut(requiredArgument(argument, arguments, index++)));
				case "--hxb": parsed.push(SetHxbOut(requiredArgument(argument, arguments, index++)));
				case "--no-output": parsed.push(SetNoOutput);
				case "--times": parsed.push(SetMeasureTimes);
				case "--macro", "-macro": parsed.push(AddMacro(requiredArgument(argument, arguments, index++)));
				case "--remap", "-remap":
					var remap = requiredArgument(argument, arguments, index++);
					var colon = remap.indexOf(":");
					if (colon >= 0) parsed.push(Remap(remap.substr(0, colon), remap.substr(colon + 1)));
				case "--custom-extension": parsed.push(SetCustomExtension(requiredArgument(argument, arguments, index++)));
				case "--server-listen", "--wait": parsed.push(ServerListen(requiredArgument(argument, arguments, index++)));
				case "--server-connect": parsed.push(ServerConnect(requiredArgument(argument, arguments, index++)));
				case "--connect": parsed.push(Connect(requiredArgument(argument, arguments, index++)));
				case "--haxelib-global": parsed.push(HaxelibGlobal);
				case "-w": parsed.push(AddWarning(requiredArgument(argument, arguments, index++)));
				default:
					if (StringTools.endsWith(argument, ".hxml")) parsed.push(HxmlFile(argument));
					else if (isClassPath(argument)) parsed.push(AddClass(parseTypePath(argument)));
					else parsed.push(IncludeModule(argument));
			}
		}
		return parsed;
	}

	static function requiredArgument(option:String, arguments:Array<String>, index:Int):String {
		if (index >= arguments.length) throw 'Missing argument for $option';
		return arguments[index];
	}

	static function parseTypePath(path:String):Array<String> {
		return path.split(".");
	}

	static function isClassPath(path:String):Bool {
		var parts = parseTypePath(path);
		var name = parts[parts.length - 1];
		return name.length > 0 && name.charCodeAt(0) >= "A".code && name.charCodeAt(0) <= "Z".code;
	}

	static function nativeLib(file:String, isExtern:Bool, kind:NativeLibKind):NativeLibArg {
		return {libFile: file, libExtern: isExtern, libKind: kind};
	}

}
