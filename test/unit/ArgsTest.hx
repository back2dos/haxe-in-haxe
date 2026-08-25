package unit;

import compiler.Args;
import compiler.ParsedArg;

class ArgsTest {
	public static function main():Void {
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
		switch Args.parseArgs(["-x", "app.Main"])[0] { case RunX("app.Main"): case _: throw "Expected -x run root"; }

		var advanced = Args.parseArgs(["-custom", "wasm=out", "--java-lib", "lib.jar", "--remap", "old:new", "lowercase", "--help-metas", "ignored"]);
		assertCustomTarget(advanced[0]);
		assertJavaLib(advanced[1]);
		assertRemap(advanced[2]);
		assertIncludedModule(advanced[3]);
		switch (advanced[4]) {
			case ShowHelpMetas:
			case _: throw "Expected help metas";
		}
		if (advanced.length != 5) throw "Early-exit help must consume remaining arguments";

		var expanded = Args.expandHxml(Args.parseArgs(["test/unit/args/root.hxml", "--hxb", "out.hxb"]));
		if (expanded.length != 3) throw "Unexpected expanded HXML argument count";
		switch expanded[0] { case AddClassPath("test"): case _: throw "Expected HXML class path"; }
		switch expanded[1] { case Define("nested", "yes"): case _: throw "Expected nested HXML define"; }
		switch expanded[2] { case SetHxbOut("out.hxb"): case _: throw "Expected trailing HXB output"; }
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

	static function assertCustomTarget(argument:ParsedArg):Void switch (argument) {
		case SetCustomTarget("wasm", "out"):
		case _: throw "Expected custom target";
	}

	static function assertJavaLib(argument:ParsedArg):Void switch (argument) {
		case AddNativeLib({libFile: "lib.jar", libExtern: false, libKind: JavaLib}):
		case _: throw "Expected Java native library";
	}

	static function assertRemap(argument:ParsedArg):Void switch (argument) {
		case Remap("old", "new"):
		case _: throw "Expected package remap";
	}

	static function assertIncludedModule(argument:ParsedArg):Void switch (argument) {
		case IncludeModule("lowercase"):
		case _: throw "Expected included module";
	}
}
