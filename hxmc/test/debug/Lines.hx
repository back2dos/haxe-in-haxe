// The program hxmc/test/DebugCheck.hx debugs: built with -debug, a debugger
// stops at the line marked `break here`, and its backtrace names the Haxe
// functions with the lines of the calls it passes (marked `frame:`).
class Lines {
	static var seen:Array<Int> = [];

	static function inner(depth:Int):Int {
		if (depth > 0)
			return inner(depth - 1) + 1; // frame: Lines.inner
		seen.push(depth); // break here
		return seen.length;
	}

	// (a try: not inlined into main; inner through a closure: not inlined here)
	static function outer(n:Int):Int {
		var total = 0;
		var f = inner;
		for (i in 0...n) {
			try {
				total += f(2); // frame: Lines.outer
			} catch (e:String) {
				total = -1;
			}
		}
		return total;
	}

	static function main() {
		var t = outer(3); // frame: Lines.main
		Sys.println("total " + t);
	}
}
