package hxmc.rt;

import hxmc.rt.C;
import hxmc.unsafe.Atomic;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The haxe.atomic cells (hxmc.NativeAtomic, formerly in rt_thread.c),
// sequentially consistent: an Int cell is a T_NATIVE K_RAW object (the low
// 4 bytes of slot 0), an object cell a one-slot K_PARR the collector scans.
// A reference stored into an object cell is remembered afterwards when the
// cell is old and the reference young (rt_barrier_range of the slot).
@:keep
class Atomics {
	static inline var T_NATIVE = 16;
	static inline var T_ADATA_P = 6;
	static inline var K_RAW = 2;
	static inline var K_PARR = 1;

	@:hxmc.host("hxmc_NativeAtomic_intNew") static function intNew(v:Int):Dynamic {
		var a = Mem.allocRaw(1, T_NATIVE, K_RAW);
		Mem.setI32(Mem.addr(a), 0, v);
		return a;
	}

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intLoad") static function intLoad(a:Dynamic):Int
		return Atomic.load32(Mem.addr(a));

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intStore") static function intStore(a:Dynamic, v:Int):Int {
		Atomic.store32(Mem.addr(a), v);
		return v;
	}

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intExchange") static function intExchange(a:Dynamic, v:Int):Int
		return Atomic.exchange32(Mem.addr(a), v);

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intCompareExchange") static function intCompareExchange(a:Dynamic, e:Int, r:Int):Int
		return Atomic.cas32(Mem.addr(a), e, r);

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intAdd") static function intAdd(a:Dynamic, v:Int):Int
		return Atomic.add32(Mem.addr(a), v);

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intSub") static function intSub(a:Dynamic, v:Int):Int
		return Atomic.add32(Mem.addr(a), -v);

	// the bitwise operations: a compare-exchange loop (op 0 and, 1 or, 2 xor)
	@:hxmc.noGc static function bitwise(a:Dynamic, v:Int, op:Int):Int {
		var p = Mem.addr(a);
		var o = Atomic.load32(p);
		while (true) {
			var n = op == 0 ? o & v : op == 1 ? o | v : o ^ v;
			var seen = Atomic.cas32(p, o, n);
			if (seen == o) return o;
			o = seen;
		}
	}

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intAnd") static function intAnd(a:Dynamic, v:Int):Int
		return bitwise(a, v, 0);

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intOr") static function intOr(a:Dynamic, v:Int):Int
		return bitwise(a, v, 1);

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_intXor") static function intXor(a:Dynamic, v:Int):Int
		return bitwise(a, v, 2);

	@:hxmc.host("hxmc_NativeAtomic_objNew") static function objNew(v:Dynamic):Dynamic {
		var a = Mem.alloc(1, T_ADATA_P, K_PARR);
		Mem.setRef(Mem.addr(a), 0, v); // a is young
		return a;
	}

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_objLoad") static function objLoad(a:Dynamic):Dynamic
		return Mem.obj(Ptr.ofI64(Atomic.load64(Mem.addr(a))));

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_objStore") static function objStore(a:Dynamic, v:Dynamic):Dynamic {
		var p = Mem.addr(a);
		Atomic.store64(p, Mem.addr(v).toI64());
		Leaf.rt_barrier_range(a, p, 1);
		return v;
	}

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_objExchange") static function objExchange(a:Dynamic, v:Dynamic):Dynamic {
		var p = Mem.addr(a);
		var o = Atomic.exchange64(p, Mem.addr(v).toI64());
		Leaf.rt_barrier_range(a, p, 1);
		return Mem.obj(Ptr.ofI64(o));
	}

	@:hxmc.noGc @:hxmc.host("hxmc_NativeAtomic_objCompareExchange") static function objCompareExchange(a:Dynamic, e:Dynamic, r:Dynamic):Dynamic {
		var p = Mem.addr(a);
		var ei = Mem.addr(e).toI64();
		var o = Atomic.cas64(p, ei, Mem.addr(r).toI64());
		if (Ptr.ofI64(o) == Ptr.ofI64(ei)) Leaf.rt_barrier_range(a, p, 1);
		return Mem.obj(Ptr.ofI64(o));
	}
}
