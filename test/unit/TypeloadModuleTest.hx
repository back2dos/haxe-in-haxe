package unit;

import core.ClassPath.ClassPathScope;
import core.ClassPath.DirectoryClassPath;
import core.ClassPaths;
import core.Define;
import core.TType.ModuleType;
import typing.TypeloadModule;

class TypeloadModuleTest {
	public static function main():Void {
		var paths = new ClassPaths();
		paths.push(new DirectoryClassPath("test/", User));
		var loader = new TypeloadModule(paths, Define.emptyDefines());
		var module = loader.loadModule({pack:["unit", "moduleload"], name:"Example"});
		if (module.mId != 0 || module.mTypes.length != 4 || module.mExtra.mFile != "test/unit/moduleload/Example.hx") throw "Module loading failed";
		if (loader.loadModule({pack:["unit", "moduleload"], name:"Example"}) != module) throw "Module cache failed";
		var names = [for (type in module.mTypes) switch type { case TClassDecl(value): value.clPath.name; case TEnumDecl(value): value.ePath.name; case TTypeDecl(value): value.tPath.name; case TAbstractDecl(value): value.aPath.name; }];
		if (names.join(",") != "Example,Choice,Alias,Count") throw "Module shells failed";
	}
}
