package haxe;

import compiler.Args;
import compiler.ParsedArg;
import compiler.hxb.HxbWriter;
import compiler.hxb.HxbWriterConfig;
import core.ClassPath.ClassPathScope;
import core.ClassPath.DirectoryClassPath;
import core.ClassPaths;
import core.Define;
import core.Globals.GlobalTypePath;
import core.TType.ModuleType;
import core.ZipOutput;
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
		if (arguments.length > 0 && arguments[0] == "--") arguments = arguments.slice(1);
		var classPaths = new ClassPaths();
		var stdPath = "haxe/std/";
		if (!FileSystem.exists(stdPath)) throw "Pinned standard library not found at " + stdPath;
		classPaths.push(new DirectoryClassPath(stdPath, Std));
		var defines = Define.emptyDefines();
		// The HXB target is a cross-target compiler artifact. Std.hx uses this
		// target define to permit loading the shared standard library.
		Define.rawDefineValue(defines, "cross", "1");
		var main:Null<GlobalTypePath> = null;
		var hxbArgument:Null<String> = null;
		for (argument in Args.parseArgs(arguments)) {
			switch argument {
				case AddClassPath(path): classPaths.add(new DirectoryClassPath(classPathPath(path), User));
				case Define(key, value): Define.rawDefineValue(defines, key, value == null ? "1" : value);
				case SetMain(path):
					if (main != null) unsupported("multiple --main options");
					main = typePath(path, "--main");
				case SetHxbOut(file):
					if (hxbArgument != null) unsupported("multiple --hxb options");
					hxbArgument = file;
				case _:
					unsupported(Type.enumConstructor(argument));
			}
		}
		if (main == null) throw "Batch HXB compilation requires --main";
		if (hxbArgument == null) throw "Batch HXB compilation requires --hxb";
		var config = HxbWriterConfig.processArgument(hxbArgument);
		if (config.targetConfig.hxbVersion != compiler.hxb.HxbData.VERSION) throw 'Unsupported HXB version: ${config.targetConfig.hxbVersion}';
		ensureOutputDirectory(config.archivePath);
		var loader = new TypeloadModule(classPaths, defines);
		loader.loadStdBootstrap();
		var mainModule = loader.loadModule(main);
		markMainKept(mainModule);
		var zip = new ZipOutput(config.archivePath, 0);
		try {
			if (config.targetConfig.generate) for (module in loader.loadedModules()) {
				var path = module.mPath.pack.concat([module.mPath.name]);
				if (shouldExport(path, config.targetConfig)) {
					var writer = new HxbWriter();
					writer.writeModule(module);
					zip.addBytesEntry(writer.exportModule(), "cross/" + path.join("/") + ".hxb");
				}
			}
		} catch (error:Dynamic) {
			zip.close();
			throw error;
		}
		zip.close();
	}

	static function markMainKept(module:core.TType.ModuleDef):Void {
		for (type in module.mTypes) switch type {
			case TClassDecl(cls):
				var field = cls.clStatics.get("main");
				if (field != null && field.cfMeta.length == 0) {
					field.cfMeta.unshift({meta:":keep", exprs:[], pos:{pfile:field.cfPos.pfile, pmin:field.cfPos.pmin, pmax:field.cfPos.pmin}});
					field.cfFlags |= 1 << core.TType.TType.flagTClassFieldNames.indexOf("CfPostProcessed");
				}
			case _:
		}
		if (module.mStatics != null) {
			var field = module.mStatics.clStatics.get("main");
			if (field != null && field.cfMeta.length == 0) {
				field.cfMeta.unshift({meta:":keep", exprs:[], pos:{pfile:field.cfPos.pfile, pmin:field.cfPos.pmin, pmax:field.cfPos.pmin}});
				field.cfFlags |= 1 << core.TType.TType.flagTClassFieldNames.indexOf("CfPostProcessed");
			}
		}
	}

	static function shouldExport(path:Array<String>, config:compiler.hxb.HxbWriterConfig.WriterTargetConfig):Bool {
		for (pattern in config.include) if (matchesPath(path, pattern)) return true;
		for (pattern in config.exclude) if (matchesPath(path, pattern)) return false;
		return true;
	}

	// Direct port of Ast.match_path true for HXB include/exclude patterns.
	static function matchesPath(path:Array<String>, pattern:Array<String>):Bool {
		function lowerIdentifier(value:String):Bool return value.length > 0 && value.charCodeAt(0) >= "a".code && value.charCodeAt(0) <= "z".code;
		function loop(top:Bool, pathIndex:Int, patternIndex:Int):Bool {
			if (patternIndex == pattern.length) return pathIndex == path.length || !top;
			var part = pattern[patternIndex];
			if (part == "**") return patternIndex + 1 == pattern.length || loop(false, pathIndex, patternIndex + 1) || (pathIndex < path.length && loop(false, pathIndex + 1, patternIndex));
			if (pathIndex == path.length) return false;
			if (patternIndex + 1 == pattern.length && pathIndex + 1 < path.length && lowerIdentifier(part) && !lowerIdentifier(path[pathIndex + 1])) return path[pathIndex] == part;
			return (part == "*" || path[pathIndex] == part) && loop(false, pathIndex + 1, patternIndex + 1);
		}
		return loop(true, 0, 0);
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
