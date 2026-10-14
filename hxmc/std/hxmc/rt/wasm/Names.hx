package hxmc.rt.wasm;

import hxmc.I64;
import hxmc.rt.Types.*;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// rt_dyn.c for WebAssembly (hxmc/README.md, "WebAssembly"): the table of
// field names (the generated table is sorted; names seen only at run time
// are appended, in malloc'ed memory, with a hash table), field names as
// immortal strings, the inline-cache miss (one thread: the entry is
// refilled), and the program's end and uncaught exceptions.
@:hxmc.wasm @:keep
class Names {
	static var extra:Ptr; // added names (C strings), by index
	static var nextra:Int;
	static var extraCap:Int;
	static var hash:Ptr; // int32 index + 1, open addressing
	static var hashCap:Int;
	static var strs:Ptr; // fid -> immortal String
	static var strsCap:Int;

	static inline function nstatic():Int
		return Mem.getI32(Mem.sym("rt_nfield_names"), 0);

	static inline function staticName(i:Int):Ptr
		return Mem.getPtr(Mem.sym("rt_field_names"), 8 * i);

	@:hxmc.noGc static function findStatic(name:Ptr):Int {
		var lo = 0, hi = nstatic() - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1;
			var c = Heap.strcmp(staticName(mid), name);
			if (c == 0) return mid;
			if (c < 0) lo = mid + 1 else hi = mid - 1;
		}
		return -1;
	}

	@:hxmc.noGc static function nameHash(s:Ptr):Int {
		var h = 0x811c9dc5;
		var i = 0;
		while (true) {
			var c = Mem.getU8(s, i);
			if (c == 0) return h;
			h = (h ^ c) * 16777619;
			i++;
		}
	}

	@:hxmc.noGc static function findExtra(name:Ptr):Int {
		if (hashCap == 0) return -1;
		var i = nameHash(name) & (hashCap - 1);
		while (true) {
			var e = Mem.getI32(hash, 4 * i);
			if (e == 0) return -1;
			if (Heap.strcmp(Mem.getPtr(extra, 8 * (e - 1)), name) == 0) return nstatic() + e - 1;
			i = (i + 1) & (hashCap - 1);
		}
	}

	@:hxmc.noGc static function hashIn(i:Int) {
		var j = nameHash(Mem.getPtr(extra, 8 * i)) & (hashCap - 1);
		while (Mem.getI32(hash, 4 * j) != 0)
			j = (j + 1) & (hashCap - 1);
		Mem.setI32(hash, 4 * j, i + 1);
	}

	@:hxmc.noGc static function intern(name:Ptr):Int {
		var f = findStatic(name);
		if (f >= 0) return f;
		f = findExtra(name);
		if (f >= 0) return f;
		if (nextra == extraCap) {
			extraCap = extraCap == 0 ? 1024 : extraCap * 2;
			extra = Heap.realloc(extra, 8 * extraCap);
		}
		Mem.setPtr(extra, 8 * nextra, Heap.strdup(name));
		nextra++;
		if (nextra * 2 > hashCap) {
			Heap.free(hash);
			hashCap = hashCap == 0 ? 1024 : hashCap * 2;
			hash = Heap.calloc(hashCap, 4);
			for (i in 0...nextra)
				hashIn(i);
		} else
			hashIn(nextra - 1);
		return nstatic() + nextra - 1;
	}

	@:hxmc.export("hx_fid_c") @:hxmc.noGc static function fidC(name:Ptr):Int {
		var f = findStatic(name);
		return f >= 0 ? f : findExtra(name);
	}

	@:hxmc.export("hx_fid_slow") @:hxmc.noGc static function fidSlow(name:String):Int {
		var u = hxmc.rt.Str.toUtf8(name);
		var f = intern(u);
		Heap.free(u);
		return f;
	}

	@:hxmc.export("hx_fid_find") @:hxmc.noGc static function fidFind(name:String):Int {
		var u = hxmc.rt.Str.toUtf8(name);
		var f = fidC(u);
		Heap.free(u);
		return f;
	}

	@:hxmc.export("hx_fid_name") @:hxmc.noGc static function fidName(f:Int):Ptr
		return f < nstatic() ? staticName(f) : Mem.getPtr(extra, 8 * (f - nstatic()));

	@:hxmc.export("hx_fid_str") static function fidStr(f:Int):String {
		if (f < strsCap) {
			var r = Mem.getPtr(strs, 8 * f);
			if (!r.isNull()) return Mem.obj(r);
		}
		var n = fidName(f);
		var s:String = hxmc.rt.Str.ofUtf8(n, Heap.strlen(n).toInt());
		return immortal(s, f);
	}

	// a copy of s outside the heap, laid out like the string literals
	@:hxmc.noGc static function immortal(s:String, f:Int):String {
		var bytes = 8 + 8 * nslots(s);
		var copy = Heap.malloc(bytes);
		Wasm.memcpy(copy, Mem.addr(s).add(-8), bytes);
		var r = copy.add(8);
		if (f >= strsCap) {
			var ncap = strsCap == 0 ? 1024 : strsCap;
			while (ncap <= f)
				ncap *= 2;
			strs = Heap.realloc(strs, 8 * ncap);
			Wasm.memset(strs.add(8 * strsCap), 0, 8 * (ncap - strsCap));
			strsCap = ncap;
		}
		Mem.setPtr(strs, 8 * f, r);
		return Mem.obj(r);
	}

	@:hxmc.export("rt_icache_miss") @:hxmc.noGc static function icacheMiss(o:Dynamic, fid:Int, c:Ptr):Ptr {
		icacheFill(o, fid, c);
		Mem.setI32(c, 0, tindex(o));
		return c;
	}

	@:hxmc.noGc static function icacheFill(o:Dynamic, fid:Int, c:Ptr):Void
		Fill.rt_icache_fill(o, fid, c);

	// ---- the program's end

	@:hxmc.export("rt_main_done") @:hxmc.noGc static function mainDone():Void
		Wasi.flush();

	// rt_throw without a handler (wasm.LinkWasm's rt_throw calls it)
	@:hxmc.export("hx_uncaught") static function uncaught(v:Dynamic):Void {
		var s:String = hxmc.rt.Dyn.stdString(v);
		Wasi.flush();
		Wasi.writeStr(2, "Uncaught exception: ");
		Wasi.writeStr(2, s);
		Wasi.writeStr(2, "\n");
		WasiApi.proc_exit(1);
	}
}

@:hxmc.c extern class Fill {
	static function rt_icache_fill(o:Dynamic, fid:Int, c:Ptr):Void;
}
