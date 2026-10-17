import hxmc.unsafe.*;

// Loads Lib's shared library (its path: the first argument) and calls its
// export lib_run (SharedCheck).
@:hxmc.c extern class Ind {
	@:hxmc.indirect static function run(f:Ptr, arg:Int):Int;
}

class Host {
	static function main() {
		var path = Sys.args()[0];
		var lib = Arena.scopedValue(a -> Posix.dlopen(a.cstring(path), 2));
		if (lib.isNull()) {
			Sys.println("host: dlopen: " + ((cast Posix.dlerror() : CString).toString()));
			Sys.exit(1);
		}
		var f = Posix.dlsym(lib, Mem.cstr("lib_run"));
		Sys.println("host: lib_run " + (f.isNull() ? "missing" : "found") + ", main " + (Posix.dlsym(lib, Mem.cstr("main")).isNull() ? "hidden" : "exported"));
		Sys.println("host: lib_run returned " + Ind.run(f, 7));
	}
}
