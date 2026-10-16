// A C function of a shared library in a static Linux executable (the default musl mode).
// target: linux-x86_64
// expect: the C function cos of the shared library libm.so.6 (@:hxmc.lib)
// expect: shared libraries need the dynamic glibc mode (-D hxmc.libc=glibc)
@:hxmc.c @:hxmc.lib("libm.so.6") extern class M {
	static function cos(x:Float):Float;
}

class SharedStatic {
	static function main()
		trace(M.cos(0.0));
}
