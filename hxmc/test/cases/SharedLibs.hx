import hxmc.unsafe.*;

// The dynamic glibc mode (-D hxmc.libc=glibc, the corpus's --libc glibc):
// C functions of the system's shared libraries, imported (@:hxmc.lib: a
// DT_NEEDED entry and an import bound at load time) and looked up at run time
// (Posix.dlopen and dlsym, as a graphics back end loads its drivers).
@:hxmc.c @:hxmc.lib("libm.so.6") extern class M {
	static function cos(x:Float):Float;
	static function pow(a:Float, b:Float):Float;
	static function hypot(a:Float, b:Float):Float;
}

@:hxmc.c extern class Ind {
	@:hxmc.indirect static function strlen(f:Ptr, s:Ptr):Int64;
	@:hxmc.indirect static function atan2(f:Ptr, a:Float, b:Float):Float;
}

class SharedLibs {
	static function main() {
		trace(M.cos(0.0), M.pow(2, 10), M.hypot(3, 4));
		var libc = Posix.dlopen(Mem.cstr("libc.so.6"), 2);
		trace(libc.isNull());
		var f = Posix.dlsym(libc, Mem.cstr("strlen"));
		trace(f.isNull(), haxe.Int64.toStr(Ind.strlen(f, Mem.cstr("hello, world"))));
		var libm = Posix.dlopen(Mem.cstr("libm.so.6"), 1);
		var g = Posix.dlsym(libm, Mem.cstr("atan2"));
		trace(Math.round(Ind.atan2(g, 1, 1) * 4e6) / 1e6);
		trace(Posix.dlsym(libc, Mem.cstr("hxmc_no_such_function")).isNull());
		var none = Posix.dlopen(Mem.cstr("libhxmc-none.so"), 2);
		trace(none.isNull(), !Posix.dlerror().isNull());
		trace(Posix.dlclose(libm), Posix.dlclose(libc));
	}
}
