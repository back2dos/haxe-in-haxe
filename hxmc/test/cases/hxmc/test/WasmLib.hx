package hxmc.test;

// (WasmImports: a C function declared in a package named hxmc, of a library,
// is an import of the program's as well, as those of packages/os and
// packages/gfx)
@:hxmc.c @:hxmc.lib("host") extern class WasmLib {
	static function h_lib(v:Int):Int;
}
