package hxmc.rt.wasm;

import hxmc.I64;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// Linear memory for WebAssembly (docs/hxmc.md, "WebAssembly"): what the C
// library and mmap provide on the native targets. Regions (the nursery, the
// old space's semispaces, the shadow stack, malloc's arenas) come from the
// top of memory, which grows (memory.grow) and never shrinks; freed regions
// are kept in a list and reused first (sizes are 64-bit: merged free regions
// may exceed 2 GB of the 4 GB). malloc/free: size classes of powers
// of two (16 bytes to 1 MB) with free lists, carved from 1 MB arenas;
// larger blocks are regions. One thread: no locks. Also -D hxmc.wasm-gc's
// (@:hxmc.anyHeap): its linear memory holds what hxmc.unsafe works on.
@:hxmc.wasm @:hxmc.anyHeap @:keep
class Heap {
	static inline var PAGE = 65536;
	static inline var MAX_FREE = 256;
	static inline var MIN_CLASS = 4; // 16 bytes
	static inline var MAX_CLASS = 20; // 1 MB
	static inline var ARENA = 1 << 20;

	static var top:Ptr; // the end of the regions handed out
	static var memEnd:Ptr; // the end of linear memory
	static var freeTab:Ptr; // MAX_FREE (start, size) pairs, then the size classes' free lists
	static var nfree:Int;
	static var arena:Ptr;
	static var arenaEnd:Ptr;

	@:hxmc.noGc static function init() {
		if (!top.isNull()) return;
		top = Mem.sym("__heap_base");
		memEnd = new Ptr((Wasm.wasm_memory_size() : I64) * PAGE);
		// the free-region table, outside any region
		var bytes = 16 * MAX_FREE + 8 * (MAX_CLASS + 1);
		freeTab = top;
		top = top.add((bytes + 15) & ~15);
		ensure(top);
		Wasm.memset(freeTab, 0, bytes);
	}

	// memory up to p (grows it): false when it cannot grow so far
	@:hxmc.noGc static function tryEnsure(p:Ptr):Bool {
		if (!memEnd.ult(p)) return true;
		var need = p.diff(memEnd);
		if (need > ((1 : I64) << 32)) return false;
		var pages = ((need + (PAGE - 1)) >>> 16).toInt();
		if (Wasm.wasm_memory_grow(pages) < 0) return false;
		memEnd = memEnd.add(pages * PAGE);
		return true;
	}

	@:hxmc.noGc static function ensure(p:Ptr) {
		if (!tryEnsure(p)) outOfMemory();
	}

	// (Wasi.exit: with no current handler, the pads of the frames below do not
	// take proc_exit's host exception for a Haxe exception and run on)
	@:hxmc.noGc public static function outOfMemory() {
		#if (hxmc.wasm_gc)
		throw "out of memory";
		#else
		Wasi.writeLit(2, "out of memory\n");
		Wasi.exit(2);
		#end
	}

	// the size of linear memory in bytes
	@:hxmc.noGc public static function memoryBytes():I64
		return memEnd.toI64();

	// a region of `bytes` (16-aligned, not zeroed when reused)
	@:hxmc.noGc public static function region(bytes:Int):Ptr {
		var p = tryRegion(bytes);
		if (p.isNull()) outOfMemory();
		return p;
	}

	// the same, or null when memory cannot grow so far
	@:hxmc.noGc public static function tryRegion(bytes:Int):Ptr {
		init();
		bytes = (bytes + 15) & ~15;
		for (i in 0...nfree) {
			var size = Mem.getI64(freeTab, 16 * i + 8);
			if (size >= (bytes : I64)) {
				var p = Mem.getPtr(freeTab, 16 * i);
				if (size == (bytes : I64)) removeFree(i) else {
					Mem.setPtr(freeTab, 16 * i, p.add(bytes));
					Mem.setI64(freeTab, 16 * i + 8, size - bytes);
				}
				return p;
			}
		}
		var p = top;
		if (!tryEnsure(top.add(bytes))) return Ptr.nil();
		top = top.add(bytes);
		return p;
	}

	// a region of `bytes` starting at a multiple of `align` (a power of two),
	// or null when memory cannot grow so far; what alignment skips stays free
	@:hxmc.noGc public static function tryRegionAligned(bytes:Int, align:Int):Ptr {
		init();
		bytes = (bytes + 15) & ~15;
		var mask:I64 = align - 1;
		for (i in 0...nfree) {
			var q = Mem.getPtr(freeTab, 16 * i);
			var size = Mem.getI64(freeTab, 16 * i + 8);
			var a = new Ptr((q.toI64() + mask) & ~mask);
			var skip = a.diff(q);
			if (skip + bytes <= size) {
				var rest = size - skip - bytes;
				if (skip > 0) Mem.setI64(freeTab, 16 * i + 8, skip) else removeFree(i);
				if (rest > 0) addFree(a.add(bytes), rest);
				return a;
			}
		}
		var a = new Ptr((top.toI64() + mask) & ~mask);
		if (!tryEnsure(a.add(bytes))) return Ptr.nil();
		var gap = a.diff(top);
		var q = top;
		top = a.add(bytes);
		if (gap > 0) addFree(q, gap);
		return a;
	}

	@:hxmc.noGc static function addFree(p:Ptr, bytes:I64) {
		if (nfree == MAX_FREE) return; // (lost: the table is full)
		Mem.setPtr(freeTab, 16 * nfree, p);
		Mem.setI64(freeTab, 16 * nfree + 8, bytes);
		nfree++;
	}

	// a region of `bytes`, zeroed
	@:hxmc.noGc public static function regionZero(bytes:Int):Ptr {
		var p = region(bytes);
		Wasm.memset(p, 0, (bytes + 15) & ~15);
		return p;
	}

	@:hxmc.noGc static function removeFree(i:Int) {
		nfree--;
		if (i < nfree) {
			Mem.setPtr(freeTab, 16 * i, Mem.getPtr(freeTab, 16 * nfree));
			Mem.setI64(freeTab, 16 * i + 8, Mem.getI64(freeTab, 16 * nfree + 8));
		}
	}

	// returns a region; neighbours merge, and one at the top lowers it
	@:hxmc.noGc public static function release(p:Ptr, size:Int) {
		var bytes:I64 = (size + 15) & ~15;
		var merged = true;
		while (merged) {
			merged = false;
			for (i in 0...nfree) {
				var q = Mem.getPtr(freeTab, 16 * i);
				var qs = Mem.getI64(freeTab, 16 * i + 8);
				if (q.addL(qs) == p) {
					p = q;
					bytes += qs;
					removeFree(i);
					merged = true;
					break;
				}
				if (p.addL(bytes) == q) {
					bytes += qs;
					removeFree(i);
					merged = true;
					break;
				}
			}
		}
		if (p.addL(bytes) == top) {
			top = p;
			return;
		}
		addFree(p, bytes);
	}

	// ---- malloc

	static inline function classHead(c:Int):Ptr
		return freeTab.add(16 * MAX_FREE + 8 * c);

	@:hxmc.noGc static function classOf(n:Int):Int {
		var c = MIN_CLASS;
		while ((1 << c) < n + 8)
			c++;
		return c;
	}

	// the block's header (8 bytes before it): twice its class (even), or for a region
	// (larger than the largest class) its size + 1
	@:hxmc.export("malloc") @:hxmc.noGc public static function malloc(n:I64):Ptr {
		init();
		var size = n.toInt();
		if (size < 0 || n > (0x7fff0000 : I64)) return Ptr.nil();
		if (size + 8 > (1 << MAX_CLASS)) {
			var r = region(size + 16);
			Mem.setI64(r, 8, ((size + 16 + 15) & ~15) + 1);
			return r.add(16);
		}
		var c = classOf(size);
		var h = classHead(c);
		var b = Mem.getPtr(h, 0);
		if (!b.isNull()) {
			Mem.setPtr(h, 0, Mem.getPtr(b, 0));
			return b;
		}
		var bs = 1 << c;
		if (arenaEnd.diff(arena) < (bs : I64)) {
			arena = region(ARENA);
			arenaEnd = arena.add(ARENA);
		}
		var blk = arena;
		arena = arena.add(bs);
		Mem.setI64(blk, 0, 2 * c);
		return blk.add(8);
	}

	@:hxmc.export("free") @:hxmc.noGc public static function free(p:Ptr):Void {
		if (p.isNull()) return;
		var hdr = Mem.getI64(p, -8).toInt();
		if ((hdr & 1) != 0) {
			release(p.add(-16), hdr - 1);
			return;
		}
		var h = classHead(hdr >> 1);
		Mem.setPtr(p, 0, Mem.getPtr(h, 0));
		Mem.setPtr(h, 0, p);
	}

	@:hxmc.noGc static function usable(p:Ptr):Int {
		var hdr = Mem.getI64(p, -8).toInt();
		return (hdr & 1) != 0 ? hdr - 1 - 16 : (1 << (hdr >> 1)) - 8;
	}

	@:hxmc.export("realloc") @:hxmc.noGc public static function realloc(p:Ptr, n:I64):Ptr {
		if (p.isNull()) return malloc(n);
		var have = usable(p);
		if (n <= (have : I64)) return p;
		var q = malloc(n);
		if (q.isNull()) return q;
		Wasm.memcpy(q, p, have);
		free(p);
		return q;
	}

	@:hxmc.export("calloc") @:hxmc.noGc public static function calloc(n:I64, size:I64):Ptr {
		var bytes = n * size;
		var p = malloc(bytes);
		if (!p.isNull()) Wasm.memset(p, 0, bytes);
		return p;
	}

	// ---- C strings

	@:hxmc.export("strlen") @:hxmc.noGc public static function strlen(s:Ptr):I64 {
		var n = 0;
		while (Mem.getU8(s, n) != 0)
			n++;
		return n;
	}

	@:hxmc.export("strcmp") @:hxmc.noGc public static function strcmp(a:Ptr, b:Ptr):Int {
		var i = 0;
		while (true) {
			var x = Mem.getU8(a, i), y = Mem.getU8(b, i);
			if (x != y) return x - y;
			if (x == 0) return 0;
			i++;
		}
	}

	@:hxmc.export("memcmp") @:hxmc.noGc public static function memcmp(a:Ptr, b:Ptr, n:I64):Int
		return hxmc.rt.MemOps.compare(a, b, n);

	@:hxmc.export("strdup") @:hxmc.noGc public static function strdup(s:Ptr):Ptr {
		var n = strlen(s);
		var p = malloc(n + 1);
		Wasm.memcpy(p, s, n + 1);
		return p;
	}
}
