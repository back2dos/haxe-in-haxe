package unit;

import core.ClassPath.ClassPathScope;
import core.ClassPath.DirectoryClassPath;
import core.ClassPaths;

class ClassPathsTest {
	public static function main():Void {
		var paths = new ClassPaths();
		paths.push(new DirectoryClassPath("haxe/src/", User));
		var resolved = paths.findFile("compiler/Args.hx");
		if (resolved.file != "haxe/src/compiler/Args.hx" || resolved.classPath.path != "haxe/src/") throw "Class path resolution failed";
		if (paths.findFileNoRaise("compiler/Missing.hx") != null) throw "Missing file resolution failed";
		if (paths.asStringList().join(",") != "haxe/src/" || paths.getStdPaths().length != 0) throw "Class path collection metadata failed";
		paths.add(new DirectoryClassPath("haxe/upstream/std/", Std));
		if (paths.getStdPaths().length != 1 || paths.asStringList()[0] != "haxe/upstream/std/") throw "Class path ordering failed";
		if (paths.findFile("StdTypes.hx").file != "haxe/upstream/std/StdTypes.hx") throw "Root-level standard module resolution failed";
	}
}
