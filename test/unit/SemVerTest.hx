package unit;

import syntax.SemVer.SemVerTools;

class SemVerTest {
	public static function main():Void {
		if (SemVerTools.toString(SemVerTools.parseVersion("1.2.3-alpha.1+build.23")) != "1.2.3-alpha.1") throw "Build metadata must be removed";
		if (SemVerTools.compareVersion(SemVerTools.parseVersion("1.2.3-alpha.2"), SemVerTools.parseVersion("1.2.3-alpha.10")) >= 0) throw "Numeric pre-release ordering failed";
		if (SemVerTools.compareVersion(SemVerTools.parseVersion("1.2.3-alpha"), SemVerTools.parseVersion("1.2.3-1")) <= 0) throw "String pre-release must follow numeric pre-release";
		if (SemVerTools.compareVersion(SemVerTools.parseVersion("1.2.3"), SemVerTools.parseVersion("1.2.3-rc.1")) <= 0) throw "Release must follow pre-release";
		assertInvalid("1.2");
		assertInvalid("1.2.3-");
	}

	static function assertInvalid(version:String):Void {
		try {
			SemVerTools.parseVersion(version);
			throw 'Expected invalid version: $version';
		} catch (error:Dynamic) {
			if (Std.string(error).indexOf("Invalid version string") < 0) throw error;
		}
	}
}
