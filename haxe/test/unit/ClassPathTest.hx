package unit;

import core.ClassPath.ClassPathScope;
import core.ClassPath.DirectoryClassPath;

class ClassPathTest {
	public static function main():Void {
		var path = new DirectoryClassPath("haxe/src/", User);
		var listing = path.getUncachedDirListing("compiler/Args.hx");
		if (listing == null || listing.directory != "haxe/src/compiler" || listing.files.indexOf("Args.hx") < 0) throw "Class path directory listing failed";
		if (path.getUncachedDirListing("compiler/Args.hx") != null) throw "Directory listing cache failed";
		path.clearCache();
		if (path.getUncachedDirListing("compiler/Args.hx") == null) throw "Class path cache clearing failed";
		if (path.isStdPath() || path.scopeString() != "User" || path.clone().path != "haxe/src/") throw "Class path metadata failed";
	}
}
