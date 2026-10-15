package hxmc;

// The hxmc target's initialization (`--custom-target hxmc=<out>` calls
// hxmc.Init.init() first): hxmc's std, next to this std, given last.
class Init {
	public static function init() {
		#if macro
		var std = haxe.io.Path.directory(haxe.io.Path.directory(haxe.macro.Context.resolvePath("hxmc/Init.hx")));
		haxe.macro.Compiler.addClassPath(haxe.io.Path.directory(std) + "/hxmc-std");
		#end
	}
}
