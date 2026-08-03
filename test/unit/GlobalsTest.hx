package unit;

import core.Globals;
import core.Globals.Platform;

class GlobalsTest {
	public static function main():Void {
		var file = Globals.filePos("Main.hx");
		if (file.pfile != "Main.hx" || file.pmin != 0 || file.pmax != 0) throw "filePos";
		var fake = Globals.fakePos("-D debug");
		if (fake.pmin != -1 || fake.pmax != -1) throw "fakePos";
		var zero = Globals.mkZeroRangePos({pfile: "Main.hx", pmin: 3, pmax: 8});
		if (zero.pmin != 3 || zero.pmax != 3) throw "mkZeroRangePos";
		var patch = Globals.patchStringPos({pfile: "Main.hx", pmin: 0, pmax: 8}, "name");
		if (patch.pmin != 4 || patch.pmax != 8) throw "patchStringPos";

		for (platform in Globals.platforms) if (Globals.parsePlatform(Globals.platformName(platform)) != platform) throw "platform round trip";
		if (Globals.platformName(Globals.parsePlatform("wasm")) != "wasm") throw "custom platform";
		if (Globals.platformListHelp([]) != "") throw "empty platform help";
		if (Globals.platformListHelp([Js]) != " (js only)") throw "single platform help";
		if (Globals.platformListHelp([Js, Cpp]) != " (for js,cpp)") throw "multiple platform help";
		if (Globals.sTypePath({pack: ["foo", "bar"], name: "Baz"}) != "foo.bar.Baz") throw "sTypePath";
		if (!Globals.startsWith("$value", "$") || Globals.startsWith("", "$")) throw "startsWith";
		if (Globals.sVersion != "5.0.0-preview.1") throw "sVersion";
		if (Globals.sVersionFull({version: 1234, major: 1, minor: 2, revision: 3, pre: null, extra: {name: "build", build: "abc"}}) != "5.0.0-preview.1+abc") throw "sVersionFull";
	}
}
