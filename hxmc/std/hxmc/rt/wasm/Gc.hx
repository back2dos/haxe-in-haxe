package hxmc.rt.wasm;

import hxmc.I64;
import hxmc.rt.Types.*;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The collector and allocator of WebAssembly programs: hxmc/rt/rt.c's
// generational copying collector with one thread, in Haxe over linear
// memory (hxmc/README.md, "WebAssembly"). Same objects, nursery, promotion
// and depth-first copying as rt.c (whose comments explain them); the
// differences: regions come from Heap (memory grows, it is never given
// back: freed semispaces are reused), no thread handshake (one thread,
// thread-locals are globals), no native handles (no C resources), and
// finalisers are registered but never run. Every function here is
// @:hxmc.noGc: it runs while objects move, with raw addresses.
@:hxmc.wasm @:keep
class Gc {
	static inline var K_FWD = 15;
	static inline var MINOR_MAX = 32 << 20;
	static inline var MIN_OLD = 16 << 20;
	static inline var SHADOW = 64 << 20;

	static var nurseryBase:Ptr; // MINOR_MAX reserved
	static var youngStart:Ptr;
	static var youngEnd:Ptr;
	static var minorSize:Int;
	static var minorFixed:Bool;
	static var oldRegion:Ptr; // the current semispace (a Heap region)
	static var oldRegionSize:Int;
	static var oldStart:Ptr;
	static var oldPtr:Ptr;
	static var oldEnd:Ptr;
	static var fromStart:Ptr;
	static var fromEnd:Ptr;
	static var stackBase:Ptr; // the shadow stack
	static var nglobals:Int;
	static var major:Bool; // which forwarding (minor or major) runs
	static var stats:Bool;
	static var minors:Int;
	static var majors:Int;
	// the remembered set: slots, and objects scanned whole
	static var rem:Ptr;
	static var remLen:Int;
	static var remCap:Int;
	static var robjs:Ptr;
	static var robjsLen:Int;
	static var robjsCap:Int;
	static var robjsRecent:Ptr; // 256 entries
	// the depth-first copy's stack: (object, next slot) pairs
	static var gcStack:Ptr;
	static var gcTop:Int;
	static var gcCap:Int;
	// nursery growth (rt.c's adapt_nursery)
	static var grownFrom:Int;
	static var survivedBefore:Int;
	static var growthOff:Bool;

	static inline function hdrLo(p:Ptr):Int
		return Mem.getI32(p, -8);

	static inline function nslotsOf(p:Ptr):Int
		return hdrLo(p) & 0x0FFFFFFF;

	static inline function kindOf(p:Ptr):Int
		return (hdrLo(p) >>> 28) & 15;

	static inline function tindexOf(p:Ptr):Int
		return Mem.getU16(p, -4);

	static inline function objBytes(p:Ptr):Int
		return 8 * (nslotsOf(p) + 1);

	static inline function inYoung(p:Ptr):Bool
		return !p.ult(youngStart) && p.ult(youngEnd);

	static inline function inFrom(p:Ptr):Bool
		return !p.ult(fromStart) && p.ult(fromEnd);

	// ---- startup

	@:hxmc.export("rt_init") @:hxmc.noGc static function init(ng:Int, argc:Int, argv:Ptr):Void {
		Heap.malloc(0); // (the heap's tables)
		Wasi.init();
		var m = Wasi.envInt("RT_MINOR_KB", -1);
		minorFixed = m >= 0;
		minorSize = (m >= 0 ? m : 4096) << 10;
		if (minorSize < 4096) minorSize = 4096;
		if (minorSize > MINOR_MAX) minorSize = MINOR_MAX;
		stats = Wasi.envInt("RT_STATS", -1) >= 0;
		verifying = Wasi.envInt("RT_VERIFY", -1) >= 0;
		nurseryBase = Heap.regionZero(MINOR_MAX);
		youngStart = nurseryBase;
		setYoungEnd(youngStart.add(minorSize));
		Mem.setPtr(Mem.sym("rt_young_start"), 0, youngStart);
		Mem.tlsSet("rt_young_ptr", youngStart);
		Mem.tlsSet("rt_young_limit", youngEnd);
		var om = Wasi.envInt("RT_OLD_MB", 32);
		oldRegionSize = om << 20;
		oldRegion = Heap.region(oldRegionSize);
		oldStart = oldRegion;
		oldPtr = oldStart;
		oldEnd = oldStart.add(oldRegionSize);
		stackBase = Heap.regionZero(SHADOW);
		Mem.tlsSet("rt_sp", stackBase);
		Mem.tlsSet("rt_sp_hw", stackBase);
		nglobals = ng;
		Mem.setPtr(Mem.sym("rt_globals"), 0, Heap.calloc(ng + 1, 8));
		remCap = 4096;
		rem = Heap.malloc(8 * remCap);
		robjsCap = 256;
		robjs = Heap.malloc(8 * robjsCap);
		robjsRecent = Heap.calloc(256, 8);
		gcCap = 4096;
		gcStack = Heap.malloc(16 * gcCap);
		Boxes.init();
		// the type objects (rt_type_objs: two words each, DataGen)
		var nt = Mem.getI32(Mem.sym("rt_ntypes"), 0);
		var to = Mem.sym("rt_type_objs");
		for (t in 0...nt) {
			Mem.setI64(to, 16 * t, mkhdr(1, K_RAW, T_TYPEOBJ));
			Mem.setI64(to, 16 * t + 8, t);
		}
	}

	public static inline function mkhdr(nslots:Int, kind:Int, tindex:Int):I64
		return ((tindex : I64) << 32) | ((((kind << 28) | nslots) : I64) & ((((1 : I64) << 32) - 1)));

	@:hxmc.noGc static function setYoungEnd(e:Ptr) {
		youngEnd = e;
		Mem.setPtr(Mem.sym("rt_young_end"), 0, e);
	}

	// ---- allocation

	@:hxmc.export("hxmc_alloc_slow") @:hxmc.collects static function allocSlowParts(lo:Int, tindex:Int, bytes:Int):Ptr
		return allocSlow(((tindex : I64) << 32) | ((lo : I64) & ((((1 : I64) << 32) - 1))), bytes);

	@:hxmc.export("rt_alloc_slow") @:hxmc.collects static function allocSlow(header:I64, bytes:Int):Ptr {
		var p:Ptr;
		if (bytes > minorSize >> 2) {
			// large objects go straight to the old space
			if (oldEnd.diff(oldPtr) < (bytes : I64)) collect(true, bytes);
			p = oldPtr;
			oldPtr = oldPtr.add(bytes);
		} else {
			var yp = Mem.tlsGet("rt_young_ptr");
			if (Mem.tlsGet("rt_young_limit").diff(yp) < (bytes : I64)) {
				collect(false, 0);
				yp = Mem.tlsGet("rt_young_ptr");
			}
			p = yp;
			Mem.tlsSet("rt_young_ptr", yp.add(bytes));
		}
		Mem.setI64(p, 0, header);
		Wasm.memset(p.add(8), 0, bytes - 8);
		return p.add(8);
	}

	// ---- the write barrier

	@:hxmc.export("hxmc_barrier_slow") @:hxmc.noGc static function barrierSlow(obj:Ptr, slot:Ptr, v:Ptr, prev:Ptr):Void {
		if (inYoung(v) && !inYoung(prev)) remember(slot);
	}

	@:hxmc.export("rt_write_barrier") @:hxmc.noGc static function writeBarrier(obj:Ptr, slot:Ptr, v:Ptr):Void
		remember(slot);

	@:hxmc.noGc static function remember(slot:Ptr) {
		if (remLen == remCap) {
			remCap *= 2;
			rem = Heap.realloc(rem, 8 * remCap);
		}
		Mem.setPtr(rem, 8 * remLen, slot);
		remLen++;
	}

	@:hxmc.noGc static function rememberObj(o:Ptr) {
		var h = (o.toI64() >> 4).toInt() & 255;
		if (Mem.getPtr(robjsRecent, 8 * h) == o) return;
		Mem.setPtr(robjsRecent, 8 * h, o);
		if (robjsLen == robjsCap) {
			robjsCap *= 2;
			robjs = Heap.realloc(robjs, 8 * robjsCap);
		}
		Mem.setPtr(robjs, 8 * robjsLen, o);
		robjsLen++;
	}

	@:hxmc.export("rt_barrier_range") @:hxmc.noGc static function barrierRange(obj:Ptr, from:Ptr, n:Int):Void {
		if (inYoung(obj)) return;
		if (n > 16) {
			rememberObj(obj);
			return;
		}
		for (i in 0...n)
			if (inYoung(Mem.getPtr(from, 8 * i))) remember(from.add(8 * i));
	}

	// ---- collection

	@:hxmc.noGc static function copyTo(dst:Ptr, obj:Ptr):Ptr {
		var words = nslotsOf(obj) + 1;
		var s = obj.add(-8);
		if (words <= 8) {
			for (i in 0...words)
				Mem.setI64(dst, 8 * i, Mem.getI64(s, 8 * i));
		} else
			Wasm.memcpy(dst, s, 8 * words);
		return dst.add(8);
	}

	@:hxmc.noGc static function forwardTo(p:Ptr, n:Ptr) {
		Mem.setI32(p, -8, (hdrLo(p) & 0x0FFFFFFF) | (K_FWD << 28));
		Mem.setPtr(p, 0, n);
	}

	@:hxmc.noGc static function fwd(p:Ptr):Ptr {
		if (!inYoung(p) && !(major && inFrom(p))) return p;
		if (kindOf(p) == K_FWD) return Mem.getPtr(p, 0);
		var bytes = objBytes(p);
		var n = copyTo(oldPtr, p);
		oldPtr = oldPtr.add(bytes);
		forwardTo(p, n);
		return n;
	}

	@:hxmc.noGc static function push(o:Ptr) {
		if (gcTop == gcCap) {
			gcCap *= 2;
			gcStack = Heap.realloc(gcStack, 16 * gcCap);
		}
		Mem.setPtr(gcStack, 16 * gcTop, o);
		Mem.setI64(gcStack, 16 * gcTop + 8, 0);
		gcTop++;
	}

	@:hxmc.noGc static function drain() {
		while (gcTop > 0) {
			var f = gcStack.add(16 * (gcTop - 1));
			var o = Mem.getPtr(f, 0);
			var n = nslotsOf(o), k = kindOf(o);
			var pm = k == K_OBJ ? Mem.getPtr(Mem.sym("rt_types"), 112 * tindexOf(o) + 24) : Ptr.nil();
			if (k == K_RAW || (k == K_OBJ && pm.isNull())) {
				gcTop--;
				continue;
			}
			var i = Mem.getI64(f, 8).toInt();
			var pushed = false;
			while (i < n) {
				if (!pm.isNull() && ((Mem.getI32(pm, 4 * (i >> 5)) >>> (i & 31)) & 1) == 0) {
					i++;
					continue;
				}
				var v = Mem.getPtr(o, 8 * i);
				if (v.isNull()) {
					i++;
					continue;
				}
				var before = oldPtr;
				var nv = fwd(v);
				Mem.setPtr(o, 8 * i, nv);
				i++;
				if (oldPtr != before) {
					// copied just now: its subtree next
					Mem.setI64(f, 8, i);
					push(nv);
					pushed = true;
					break;
				}
			}
			if (!pushed) gcTop--;
		}
	}

	@:hxmc.noGc static function fwdRoot(p:Ptr):Ptr {
		var before = oldPtr;
		var n = fwd(p);
		if (oldPtr != before) {
			push(n);
			drain();
		}
		return n;
	}

	@:hxmc.noGc static function rootAt(slot:Ptr) {
		var v = Mem.getPtr(slot, 0);
		if (!v.isNull()) Mem.setPtr(slot, 0, fwdRoot(v));
	}

	@:hxmc.noGc static function scanObject(o:Ptr) {
		var n = nslotsOf(o);
		switch kindOf(o) {
			case K_OBJ:
				var pm = Mem.getPtr(Mem.sym("rt_types"), 112 * tindexOf(o) + 24);
				if (pm.isNull()) return;
				for (i in 0...n)
					if (((Mem.getI32(pm, 4 * (i >> 5)) >>> (i & 31)) & 1) != 0) rootAt(o.add(8 * i));
			case K_PARR:
				for (i in 0...n)
					rootAt(o.add(8 * i));
			case _:
		}
	}

	@:hxmc.noGc static function scanRoots() {
		var sp = Mem.tlsGet("rt_sp");
		var s = stackBase;
		while (s.ult(sp)) {
			rootAt(s);
			s = s.add(8);
		}
		var g = Mem.getPtr(Mem.sym("rt_globals"), 0);
		for (i in 0...nglobals)
			rootAt(g.add(8 * i));
		var e = Mem.tlsGet("rt_exn");
		if (!e.isNull()) Mem.tlsSet("rt_exn", fwdRoot(e));
	}

	@:hxmc.noGc static function minorGc() {
		var used = Mem.tlsGet("rt_young_ptr").diff(youngStart).toInt();
		if (oldEnd.diff(oldPtr) < ((used + 64) : I64)) {
			majorGc(0);
			return;
		}
		minors++;
		major = false;
		scanRoots();
		for (i in 0...remLen)
			rootAt(Mem.getPtr(rem, 8 * i));
		remLen = 0;
		for (i in 0...robjsLen)
			scanObject(Mem.getPtr(robjs, 8 * i));
		robjsLen = 0;
		Wasm.memset(robjsRecent, 0, 8 * 256);
	}

	@:hxmc.noGc static function majorGc(need:Int) {
		majors++;
		var used = Mem.tlsGet("rt_young_ptr").diff(youngStart).toInt();
		var live = oldPtr.diff(oldStart).toInt();
		fromStart = oldStart;
		fromEnd = oldPtr;
		var fromRegion = oldRegion, fromSize = oldRegionSize;
		// the to-space: room for everything and for growth after it (twice
		// what may be live: a wasm32 memory has 4 GB), else for everything
		var want = clampSize(2.0 * (live + used) + 4.0 * minorSize + need);
		var least = clampSize(1.0 * live + used + need + 65536);
		if (want < MIN_OLD) want = MIN_OLD;
		var size = want;
		oldRegion = Heap.tryRegion(size);
		if (oldRegion.isNull()) {
			size = least;
			oldRegion = Heap.tryRegion(size);
			if (oldRegion.isNull()) Heap.outOfMemory();
		}
		oldRegionSize = size;
		oldStart = oldRegion;
		oldPtr = oldStart;
		major = true;
		scanRoots();
		remLen = 0;
		robjsLen = 0;
		Wasm.memset(robjsRecent, 0, 8 * 256);
		major = false;
		Heap.release(fromRegion, fromSize);
		var nowLive = oldPtr.diff(oldStart).toInt();
		var limit = clampSize(2.0 * nowLive + 4.0 * minorSize + need);
		if (limit < MIN_OLD) limit = MIN_OLD;
		if (limit > oldRegionSize) limit = oldRegionSize;
		oldEnd = oldStart.add(limit);
		if (stats) Wasi.statLine("gc: major ", majors, nowLive >> 20, limit >> 20);
	}

	// a size in bytes as an Int, at most a little under 2 GB
	@:hxmc.noGc static function clampSize(v:Float):Int
		return v > 2147418112.0 ? 2147418112 : Std.int(v);

	@:hxmc.noGc static function adaptNursery(survived:Int) {
		if (grownFrom > 0) {
			if (survived > survivedBefore + (survivedBefore >> 1)) {
				resizeNursery(grownFrom);
				growthOff = true;
			}
			grownFrom = 0;
		} else if (!growthOff && minorSize < MINOR_MAX && survived * 8 > minorSize) {
			grownFrom = minorSize;
			survivedBefore = survived;
			resizeNursery(minorSize * 2);
		}
	}

	@:hxmc.noGc static function resizeNursery(size:Int) {
		minorSize = size;
		setYoungEnd(youngStart.add(size));
	}

	@:hxmc.noGc static function collect(full:Bool, need:Int) {
		if (verifying) verify(false);
		if (verifying) checkRemembered();
		if (full) majorGc(need) else {
			var before = oldPtr;
			var m0 = majors;
			minorGc();
			if (!minorFixed && majors == m0) adaptNursery(oldPtr.diff(before).toInt());
		}
		Mem.tlsSet("rt_young_ptr", youngStart);
		Mem.tlsSet("rt_young_limit", youngEnd);
		if (verifying) verify(true);
		// the slots the frames left above the stack top (rt_sp_hw)
		var sp = Mem.tlsGet("rt_sp"), hw = Mem.tlsGet("rt_sp_hw");
		if (sp.ult(hw)) Wasm.memset(sp, 0, hw.diff(sp));
		Mem.tlsSet("rt_sp_hw", sp);
	}

	// RT_VERIFY=1: before and after each collection, the old space is checked
	// object by object (sane headers; after it, references to nothing young)
	static var verifying:Bool;

	@:hxmc.noGc static function verify(after:Bool) {
		var nt = Mem.getI32(Mem.sym("rt_ntypes"), 0);
		var p = oldStart;
		var count = 0;
		while (p.ult(oldPtr)) {
			var o = p.add(8);
			var n = nslotsOf(o), k = kindOf(o), t = tindexOf(o);
			if (k > 2 || t >= nt || oldPtr.diff(o) < ((8 * n) : I64)) bad("gc: verify: bad header (minor, offset, used) ", minors, o.diff(oldStart).toInt(), oldPtr.diff(oldStart).toInt());
			var pm = k == K_OBJ ? Mem.getPtr(Mem.sym("rt_types"), 112 * t + 24) : Ptr.nil();
			if (k == K_PARR || !pm.isNull())
				for (i in 0...n) {
					if (k == K_OBJ && ((Mem.getI32(pm, 4 * (i >> 5)) >>> (i & 31)) & 1) == 0) continue;
					var v = Mem.getPtr(o, 8 * i);
					if (v.isNull()) continue;
					if (after && inYoung(v)) bad("gc: verify: young reference after a collection (object, slot, type) ", count, i, t);
					if (!v.ult(oldStart) && v.ult(oldPtr) && kindOf(v) > 2) bad("gc: verify: reference to a bad header (object, slot, type) ", count, i, t);
				}
			p = p.add(8 * (n + 1));
			count++;
		}
	}

	// RT_VERIFY=1, before each collection: every young reference in the old
	// space is in a remembered slot or object (the write barrier missed none)
	@:hxmc.noGc static function checkRemembered() {
		var cap = 1;
		while (cap < 2 * (remLen + robjsLen) + 16)
			cap <<= 1;
		var tab = Heap.calloc(cap, 8);
		inline function add(p:Ptr) {
			var h = (p.toI64() >> 3).toInt() & (cap - 1);
			while (!Mem.getPtr(tab, 8 * h).isNull() && Mem.getPtr(tab, 8 * h) != p)
				h = (h + 1) & (cap - 1);
			Mem.setPtr(tab, 8 * h, p);
		}
		inline function has(p:Ptr):Bool {
			var h = (p.toI64() >> 3).toInt() & (cap - 1);
			var r = false;
			while (!Mem.getPtr(tab, 8 * h).isNull()) {
				if (Mem.getPtr(tab, 8 * h) == p) {
					r = true;
					break;
				}
				h = (h + 1) & (cap - 1);
			}
			return r;
		}
		for (i in 0...remLen)
			add(Mem.getPtr(rem, 8 * i));
		for (i in 0...robjsLen)
			add(Mem.getPtr(robjs, 8 * i));
		var p = oldStart;
		var count = 0;
		while (p.ult(oldPtr)) {
			var o = p.add(8);
			var n = nslotsOf(o), k = kindOf(o), t = tindexOf(o);
			var pm = k == K_OBJ ? Mem.getPtr(Mem.sym("rt_types"), 112 * t + 24) : Ptr.nil();
			if (k == K_PARR || !pm.isNull()) {
				if (!has(o))
					for (i in 0...n) {
						if (k == K_OBJ && ((Mem.getI32(pm, 4 * (i >> 5)) >>> (i & 31)) & 1) == 0) continue;
						var v = Mem.getPtr(o, 8 * i);
						if (!v.isNull() && inYoung(v) && !has(o.add(8 * i))) bad("gc: verify: unremembered young reference (object, slot, type) ", count, i, t);
					}
			}
			p = p.add(8 * (n + 1));
			count++;
		}
		Heap.free(tab);
	}

	@:hxmc.noGc static function bad(lit:String, a:Int, b:Int, c:Int) {
		Wasi.writeLit(2, lit);
		Wasi.writeInt(2, a);
		Wasi.writeLit(2, " ");
		Wasi.writeInt(2, b);
		Wasi.writeLit(2, " ");
		Wasi.writeInt(2, c);
		Wasi.writeLit(2, "\n");
		WasiApi.proc_exit(99);
	}

	// ---- hxmc.NativeGc

	@:hxmc.export("hxmc_NativeGc_collect") @:hxmc.collects static function gcCollect(full:Bool):Void
		collect(full, 0);

	// (finalisers never run: WebAssembly programs have no resources to free behind values)
	@:hxmc.export("hxmc_NativeGc_finalise") @:hxmc.noGc static function gcFinalise(fn:Dynamic->Void, v:Dynamic):Void {}

	@:hxmc.export("hxmc_NativeGc_runFinalisers") @:hxmc.noGc static function gcRunFinalisers():Void {}

	@:hxmc.export("hxmc_NativeGc_heapBytes") @:hxmc.noGc static function gcHeapBytes():Float {
		var b:Float = cast oldEnd.diff(oldStart);
		return b + minorSize;
	}

	@:hxmc.export("hxmc_NativeGc_reached") @:hxmc.noGc static function gcReached():Bool
		return false;

	// (no object sizes: 0)
	// (no census of the heap on WebAssembly)
	@:hxmc.export("hxmc_NativeGc_objsize") static function gcObjsize(v:Dynamic, exclude:Array<Dynamic>, out:Array<Dynamic>):Float {
		hxmc.rt.C.Rt.rt_throw("Gc.objsize is not supported on WebAssembly");
		return 0;
	}
}
