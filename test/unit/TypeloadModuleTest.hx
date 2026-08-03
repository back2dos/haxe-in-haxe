package unit;

import core.ClassPath.ClassPathScope;
import core.ClassPath.DirectoryClassPath;
import core.ClassPaths;
import core.Define;
import core.TType.ModuleType;
import core.TType.T;
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
		var cls = switch module.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected class"; };
		if (cls.clOrderedFields.length != 3 || cls.clOrderedStatics.length != 1 || cls.clConstructor != null) throw "Class field population failed";
		if (cls.clStatics.get("value").cfName != "value" || cls.clFields.get("choice").cfName != "choice") throw "Class field maps failed";
		switch cls.clFields.get("choice").cfType { case TEnum(en, _): if (en.ePath.name != "Choice") throw "Named enum hint failed"; case _: throw "Expected enum field type"; }
		switch cls.clFields.get("alias").cfType { case TType(def, _): if (def.tPath.name != "Alias") throw "Named typedef hint failed"; case _: throw "Expected typedef field type"; }
		var choice = switch module.mTypes[1] { case TEnumDecl(value): value; case _: throw "Expected enum"; };
		if (choice.eNames.join(",") != "One,Many" || choice.eConstrs.get("Many").efIndex != 1) throw "Enum constructor population failed";
		switch choice.eConstrs.get("Many").efType { case TFun(signature): if (signature.args.length != 2) throw "Enum constructor arguments failed"; case _: throw "Expected enum constructor function"; }
	}
}
