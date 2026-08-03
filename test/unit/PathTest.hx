package unit;

import core.Path;
import core.Path.FilePath;
import core.Path.UniqueKey;

class PathTest {
	public static function main():Void {
		var source = Path.parsePath("foo\\bar/Baz.hx");
		if (source.pack.join(".") != "foo.bar" || source.name != "Baz") throw "Path parsing failed";
		var std = Path.parseTypePath("foo._std.Bar");
		if (std.pack.join(".") != "foo" || std.name != "Bar") throw "_std path parsing failed";
		var invalid = false;
		try Path.parsePath("Foo.Bar") catch (error:Dynamic) invalid = Std.string(error).indexOf("Could not process argument Foo.Bar") == 0;
		if (!invalid) throw "Invalid package path was accepted";
		if (Path.normalizePath("./foo//bar") != "foo/bar" || Path.normalizePath("/foo/../bar") != "/bar") throw "Path normalization failed";
		if (!Path.isAbsolutePath("/foo") || Path.isAbsolutePath("foo/bar")) throw "Absolute path detection failed";
		if (Path.addTrailingSlash("foo") != "foo/" || Path.removeTrailingSlash("foo//") != "foo") throw "Trailing slash helpers failed";
		if (Path.flatPath({pack: ["foo_bar", "baz"], name: "Qux_Type"}) != "foo_$bar_baz_Qux_$Type") throw "Flat path failed";
		if (Path.makeValidFilename("foo/bar: baz") != "foo_bar__baz") throw "Filename sanitizing failed";
		if (Path.moduleNameOfFile("foo/bar/Baz.js.hx") != "Baz") throw "Module name parsing failed";
		var parsed = FilePath.parse("foo/bar.baz");
		if (parsed.directory != "foo" || parsed.fileName != "bar" || parsed.extension != "baz" || parsed.backslash || FilePath.nameAndExtension(parsed) != "bar.baz") throw "File path parsing failed";
		var key = UniqueKey.createLazy(".");
		if (UniqueKey.lazyPath(key) != "." || UniqueKey.lazyKey(key) != UniqueKey.lazyKey(key) || !UniqueKey.startsWith(UniqueKey.toString(UniqueKey.lazyKey(key)), "/")) throw "Unique key failed";
	}
}
