import hxmc.unsafe.*;

// Structs by value in calls of a WebAssembly module's imports, clang's C
// ABI for wasm32 (hxmc/src/hxmc/CAbi.hx): the host (WasmStruct.cjs) reads
// a struct argument at the address it gets, stores a result at the address
// given first; structs of one scalar travel as that scalar. WebAssembly only.
@:hxmc.struct @:publicFields class Pt {
	var x:Float;
	var y:Float;
}

@:hxmc.struct @:publicFields class OneF {
	var f:Float32;
}

@:hxmc.struct @:publicFields class OneL {
	var l:Int64;
}

@:hxmc.struct @:publicFields class Mix {
	var a:Int;
	var b:UInt8;
	var c:UInt16;
}

@:hxmc.lib("host") extern class Host {
	@:hxmc.c("w_pt_sum") static function ptSum(p:Pt):Float;
	@:hxmc.c("w_pt_make") static function ptMake(x:Float, y:Float):Pt;
	@:hxmc.c("w_pt_swap") static function ptSwap(p:Pt):Pt;
	@:hxmc.c("w_one_f") static function oneF(v:OneF, k:Float32):OneF;
	@:hxmc.c("w_one_l") static function oneL(v:OneL):OneL;
	@:hxmc.c("w_mix") static function mix(k:Int, m:Mix, z:Int):Int;
}

class WasmStruct {
	static function main() {
		var p = Host.ptMake(1.5, -2);
		var q = Host.ptSwap(p);
		trace(p.x, p.y, q.x, q.y, Host.ptSum(p), Host.ptSum(q));
		Arena.scoped(a -> {
			var f = a.make(OneF);
			f.value.f = 2.5;
			var g = Host.oneF(f.value, 4);
			var l = a.make(OneL);
			l.value.l = 7;
			var m = a.make(Mix);
			m.value.a = -5;
			m.value.b = 200;
			m.value.c = 3;
			trace(g.f, haxe.Int64.toStr(Host.oneL(l.value).l), Host.mix(1, m.value, 2));
		});
	}
}
