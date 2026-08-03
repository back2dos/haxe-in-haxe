package haxe;

import compiler.Args;
import compiler.ParsedArg;
import compiler.hxb.HxbWriter;
import core.ClassPath.ClassPathScope;
import core.ClassPath.DirectoryClassPath;
import core.ClassPaths;
import core.Define;
import core.Globals.GlobalTypePath;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import typing.TypeloadModule;

/**
 * Bootstrap entry point for the Haxe implementation of the compiler.
 *
 * Compiler subsystems will be ported from haxe/src in small, traceable steps.
 */
class Main {
	static function main():Void {
		run(Sys.args());
	}

	/**
		The deliberately narrow batch entry point currently supported by the
		port: source class paths, raw defines, one main module and an HXB output.
		Keeping this separate from Args lets the latter remain a faithful CLI
		parser while unsupported compiler phases fail before any compilation work.
	**/
	public static function run(arguments:Array<String>):Void {
		var classPaths = new ClassPaths();
		var defines = Define.emptyDefines();
		var main:Null<GlobalTypePath> = null;
		var output:Null<String> = null;
		for (argument in Args.parseArgs(arguments)) {
			switch argument {
				case AddClassPath(path): classPaths.push(new DirectoryClassPath(classPathPath(path), User));
				case Define(key, value): Define.rawDefineValue(defines, key, value == null ? "1" : value);
				case SetMain(path):
					if (main != null) unsupported("multiple --main options");
					main = typePath(path, "--main");
				case SetHxbOut(file):
					if (output != null) unsupported("multiple --hxb options");
					output = file;
				case _:
					unsupported(Type.enumConstructor(argument));
			}
		}
		if (main == null) throw "Batch HXB compilation requires --main";
		if (output == null) throw "Batch HXB compilation requires --hxb";
		var module = new TypeloadModule(classPaths, defines).loadModule(main);
		var writer = new HxbWriter();
		writer.writeModule(module);
		ensureOutputDirectory(output);
		File.saveBytes(output, writer.exportModule());
	}

	static function typePath(parts:Array<String>, option:String):GlobalTypePath {
		if (parts.length == 0 || parts[parts.length - 1] == "") throw 'Invalid type path for $option';
		return {pack: parts.slice(0, parts.length - 1), name: parts[parts.length - 1]};
	}

	static function classPathPath(path:String):String {
		return path.length == 0 || StringTools.endsWith(path, "/") || StringTools.endsWith(path, "\\") ? path : path + "/";
	}

	static function ensureOutputDirectory(file:String):Void {
		var directory = Path.directory(file);
		if (directory != "." && !FileSystem.exists(directory)) FileSystem.createDirectory(directory);
	}

	static function unsupported(option:String):Void {
		throw 'Unsupported batch HXB compiler option: $option';
	}
}
