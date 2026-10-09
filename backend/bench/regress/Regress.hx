// Regressions found compiling haxe-formatter with hxc (bench/README.md, 2026-10-09):
//   haxe -lib hxc -cp backend/bench/regress -main Regress -dce full --custom-target hxc=bin/regress && bin/regress
// prints "ok" four times.
class Regress {
	static function main() {
		// -dce full removed haxe.Exception.caught/thrown, which only the backend calls
		// (the lowering crashed on the missing field)
		try {
			throw new haxe.Exception("ok");
		} catch (e:haxe.Exception) {
			Sys.println(e.message);
		}
		try {
			throw "ok";
		} catch (e:haxe.Exception) {
			Sys.println(e.message);
		}
		// StringTools.isEof was `false` (the std fallback for unknown targets) while
		// fastCodeAt returns 0 past the end, so EOF loops (hxjsonast's Parser) never ended
		var s = "ab", i = 0, n = 0;
		while (!StringTools.isEof(StringTools.fastCodeAt(s, i++)))
			n++;
		Sys.println(n == 2 ? "ok" : "isEof: " + n);
		Sys.println(StringTools.isEof(StringTools.fastCodeAt("", 0)) ? "ok" : "isEof past the end");
	}
}
