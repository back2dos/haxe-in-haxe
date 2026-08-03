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
				case "--dce", "-dce": parsed.push(SetDce(requiredArgument(argument, arguments, index++)));
				case "--resource", "-r", "-resource":
					var resource = requiredArgument(argument, arguments, index++);
					var at = resource.indexOf("@");
					parsed.push(at < 0 ? AddResource(resource, resource) : AddResource(resource.substr(0, at), resource.substr(at + 1)));
				case "--cmd", "-cmd": parsed.push(RunCmd(unquote(requiredArgument(argument, arguments, index++))));
				case "--display": parsed.push(SetDisplayArg(requiredArgument(argument, arguments, index++)));
				case "--xml", "-xml": parsed.push(SetXmlOut(requiredArgument(argument, arguments, index++)));
				case "--json": parsed.push(SetJsonOut(requiredArgument(argument, arguments, index++)));
				case "--hxb": parsed.push(SetHxbOut(requiredArgument(argument, arguments, index++)));
				case "--no-output": parsed.push(SetNoOutput);
				case "--times": parsed.push(SetMeasureTimes);
				case "--macro", "-macro": parsed.push(AddMacro(requiredArgument(argument, arguments, index++)));
				case "-w": parsed.push(AddWarning(requiredArgument(argument, arguments, index++)));
				default:
					if (StringTools.endsWith(argument, ".hxml")) parsed.push(HxmlFile(argument));
					else parsed.push(AddClass(parseTypePath(argument)));
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

	static function unquote(value:String):String {
		if (value.length > 1) {
			var first = value.charAt(0);
			var last = value.charAt(value.length - 1);
			if ((first == '"' && last == '"') || (first == "'" && last == "'")) return value.substr(1, value.length - 2);
		}
		return value;
	}
}
