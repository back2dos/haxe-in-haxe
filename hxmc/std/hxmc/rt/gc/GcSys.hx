package hxmc.rt.gc;

// -D hxmc.wasm-gc: the system functions, over the host (hxmc/bootstrap/wasmgc.mjs)
@:keep @:hxmc.wasmgc
class GcSys {
	public static function print(s:String)
		W.write(1, s);

	public static function printErr(s:String)
		W.write(2, s);
}
