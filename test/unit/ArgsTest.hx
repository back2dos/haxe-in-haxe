package unit;

import compiler.Args;
import compiler.ParsedArg;

class ArgsTest {
	static function main():Void {
		var arguments = Args.parseArgs(["-cp", "src", "-D", "feature=value", "--hxb", "output.hxb", "-m", "app.Main"]);
		if (arguments.length != 4) throw "Unexpected parsed argument count";
		assertClassPath(arguments[0]);
		assertDefine(arguments[1]);
		assertHxbOutput(arguments[2]);
		assertMain(arguments[3]);

		var run = Args.parseArgs(["--run", "app.Main", "one", "two"]);
		switch (run[0]) {
			case Run(path, values) if (path == "app.Main" && values.join(",") == "one,two"):
			case _: throw "--run must consume remaining arguments";
		}
	}

	static function assertClassPath(argument:ParsedArg):Void switch (argument) {
		case AddClassPath("src"):
		case _: throw "Expected class path";
	}

	static function assertDefine(argument:ParsedArg):Void switch (argument) {
		case Define("feature", "value"):
		case _: throw "Expected define";
	}

	static function assertHxbOutput(argument:ParsedArg):Void switch (argument) {
		case SetHxbOut("output.hxb"):
		case _: throw "Expected HXB output";
	}

	static function assertMain(argument:ParsedArg):Void switch (argument) {
		case SetMain(["app", "Main"]):
		case _: throw "Expected main path";
	}
}
