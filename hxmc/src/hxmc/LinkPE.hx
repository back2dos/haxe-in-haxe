package hxmc;

import haxe.io.Bytes;
import hxmc.Obj;

// hxmc's linker for Windows: objects (the program's, the runtime object of
// MkRt) -> a PE32+ executable at a fixed base (no base relocations), with
// its import directory written directly from the runtime's import list
// (.hxmc.imports: which DLL exports what), call thunks for imported code,
// the TLS directory of the C runtime (_tls_used) and the exception
// directory (.pdata).
class LinkPE {
	static inline var BASE = 0x400000;
	static inline var SECT = 0x1000;
	static inline var FILE = 0x200;

	var objs:Array<Obj>;
	var arm:Bool;
	var globals = new Map<String, Symbol>();
	var imports = new Map<String, {dll:String, name:String, code:Bool}>();
	var addr = new Map<Section, Int>();
	var outOf = new Map<Section, Int>(); // section -> output section index

	public function new(objs:Array<Obj>, arm:Bool) {
		this.objs = objs;
		this.arm = arm;
	}

	function readImports() {
		for (o in objs) {
			var keep = [];
			for (s in o.sections)
				if (s.name == ".hxmc.imports") {
					for (l in s.buf.toBytes().toString().split("\n")) {
						var f = l.split("\t");
						if (f.length >= 4) imports.set(f[1], {dll: f[0], name: f[2], code: f[3] == "code"});
					}
				} else keep.push(s);
			o.sections = keep;
		}
	}

	function resolve() {
		for (o in objs)
			for (s in o.symbols) {
				if (!s.global || (s.section == null && !s.abs)) continue;
				var prev = globals.get(s.name);
				if (prev == null || prev.weak && !s.weak) globals.set(s.name, s);
				else if (!prev.weak && !s.weak) throw 'hxmc: link: ${s.name} defined twice';
			}
	}

	inline function target(s:Symbol):Null<Symbol>
		return (s.section != null || s.abs) ? s : globals.get(s.name);

	static inline function align(v:Int, a:Int):Int
		return a <= 1 ? v : (v + a - 1) & ~(a - 1);

	public function link(entry:String):Bytes {
		readImports();
		resolve();
		// the imports the objects use: IAT slots (and thunks for code)
		var used = new Map<String, Bool>(); // imported name keys (the symbol names of the list)
		for (o in objs)
			for (s in o.sections)
				for (r in s.relocs)
					if (target(r.sym) == null && imports.exists(r.sym.name)) used.set(r.sym.name, true);
		// one IAT slot per (dll, name)
		var dlls:Array<String> = [];
		var byDll = new Map<String, Array<String>>(); // dll -> imported names
		var slotKey = new Map<String, String>(); // symbol -> dll + name
		var keys = [for (k in used.keys()) k];
		keys.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		for (k in keys) {
			var i = imports.get(k);
			var dll = i.dll;
			if (!byDll.exists(dll)) {
				byDll.set(dll, []);
				dlls.push(dll);
			}
			var names = byDll.get(dll);
			if (names.indexOf(i.name) < 0) names.push(i.name);
			slotKey.set(k, dll + "\t" + i.name);
		}
		// synthesized sections: thunks, the import data, constructor lists
		var thunks = new Section(".text$hxmc_thunks", Text, 16);
		var thunkOf = new Map<String, Int>();
		for (k in keys)
			if (!StringTools.startsWith(k, "__imp_")) {
				thunkOf.set(k, thunks.buf.len);
				thunks.buf.u8(0xff);
				thunks.buf.u8(0x25);
				thunks.buf.u32(0);
				thunks.buf.u16(0x9090);
			}
		var lists = new Section(".rdata$hxmc_ctors", RoData, 8);
		// __CTOR_LIST__ / __DTOR_LIST__ (MinGW): -1, then nothing, then 0
		lists.buf.u64(-1, -1);
		lists.buf.u64(0, 0);
		lists.buf.u64(-1, -1);
		lists.buf.u64(0, 0);
		var extra = new Obj();
		extra.sections.push(thunks);
		extra.sections.push(lists);
		objs.push(extra);
		// output sections
		var groups:Array<{name:String, chars:Int, secs:Array<Section>}> = [
			{name: ".text", chars: 0x60000020, secs: []},
			{name: ".rdata", chars: 0x40000040, secs: []},
			{name: ".pdata", chars: 0x40000040, secs: []},
			{name: ".data", chars: 0xC0000040, secs: []},
			{name: ".tls", chars: 0xC0000040, secs: []},
			{name: ".idata", chars: 0xC0000040, secs: []},
			{name: ".bss", chars: 0xC0000080, secs: []},
		];
		for (o in objs)
			for (s in o.sections) {
				var g = switch s.kind {
					case Text: 0;
					case RoData: StringTools.startsWith(s.name, ".pdata") ? 2 : 1;
					case Data | InitArray | FiniArray: 3;
					case Tdata | Tbss: 4;
					case Bss: 6;
				};
				groups[g].secs.push(s);
			}
		// within a group, by name: grouped sections ("name$suffix") in suffix order
		for (g in groups) {
			var idx = new Map<Section, Int>();
			for (i in 0...g.secs.length)
				idx.set(g.secs[i], i);
			g.secs.sort((a, b) -> a.name < b.name ? -1 : a.name > b.name ? 1 : idx.get(a) - idx.get(b));
		}
		var nsec = groups.length;
		var headers = align(64 + 4 + 20 + 240 + 40 * nsec, FILE);
		var rva = align(headers, SECT);
		var starts = [], sizes = [];
		var idata:Buf = null;
		var idataLayout = null;
		for (gi in 0...groups.length) {
			var g = groups[gi];
			starts.push(rva);
			var pos = rva;
			if (g.name == ".idata") {
				idataLayout = importData(dlls, byDll, rva);
				idata = idataLayout.buf;
				pos += idata.len;
			} else
				for (s in g.secs) {
					pos = align(pos, s.align);
					addr.set(s, BASE + pos);
					outOf.set(s, gi);
					pos += s.size();
				}
			sizes.push(pos - rva);
			rva = align(pos, SECT);
		}
		var imageSize = rva;
		var defined = new Map<String, Int>();
		defined.set("__CTOR_LIST__", addr.get(lists));
		defined.set("__DTOR_LIST__", addr.get(lists) + 16);
		defined.set("__ImageBase", BASE);
		defined.set("WinMain", 0);
		var iatAddr = (k:String) -> BASE + idataLayout.iat.get(slotKey.get(k));
		var symAddr = function(s:Symbol):Int {
			var t = target(s);
			if (t == null) {
				var n = s.name;
				if (imports.exists(n)) return StringTools.startsWith(n, "__imp_") ? iatAddr(n) : addr.get(thunks) + thunkOf.get(n);
				var d = defined.get(n);
				if (d != null) return d;
				if (s.weak) return 0;
				throw 'hxmc: link: undefined symbol $n';
			}
			if (t.abs) return t.offset;
			return addr.get(t.section) + t.offset;
		};
		// the thunks: jmp [rip + IAT slot]
		for (k => off in thunkOf) {
			var p = addr.get(thunks) + off + 6;
			thunks.buf.set32(off + 2, iatAddr(k) - p);
		}
		// relocations
		var tlsStart = BASE + starts[4];
		for (g in groups)
			for (s in g.secs) {
				if (s.kind == Bss || s.kind == Tbss) continue;
				var base = addr.get(s);
				for (r in s.relocs) {
					var S = symAddr(r.sym);
					var A = r.addend;
					var P = base + r.offset;
					switch r.kind {
						case RAbs64:
							var v = S + A;
							s.buf.set64(r.offset, v, v < 0 ? -1 : 0);
						case RAbs32 | RAbs32S:
							s.buf.set32(r.offset, S + A);
						case RPc32 | RCall32:
							s.buf.set32(r.offset, S + A - P);
						case RImgRel32:
							s.buf.set32(r.offset, S == 0 ? 0 : S + A - BASE);
						case RSecRel32:
							var t = target(r.sym);
							var sec = t != null && t.section != null ? outOf.get(t.section) : -1;
							s.buf.set32(r.offset, S + A - BASE - (sec >= 0 ? starts[sec] : 0));
						case _:
							throw "hxmc: link: relocation " + r.kind + " on Windows";
					}
				}
			}
		// the file
		var out = new Buf(1 << 20);
		out.zeros(headers);
		var rawPos = [], rawSize = [];
		for (gi in 0...groups.length) {
			var g = groups[gi];
			if (g.name == ".bss" || sizes[gi] == 0) {
				rawPos.push(0);
				rawSize.push(0);
				continue;
			}
			out.align(FILE);
			var at = out.len;
			rawPos.push(at);
			out.zeros(align(sizes[gi], FILE));
			rawSize.push(align(sizes[gi], FILE));
			if (g.name == ".idata") out.b.blit(at, idata.b, 0, idata.len) else
				for (s in g.secs)
					if (s.kind != Bss && s.kind != Tbss) out.b.blit(at + addr.get(s) - BASE - starts[gi], s.buf.b, 0, s.buf.len);
		}
		// headers
		var h = new Buf(headers);
		h.u16(0x5a4d); // MZ
		h.zeros(58);
		h.u32(64); // e_lfanew
		h.u32(0x4550); // PE\0\0
		h.u16(arm ? 0xaa64 : 0x8664);
		var present = [for (gi in 0...groups.length) if (sizes[gi] > 0) gi];
		h.u16(present.length);
		h.u32(0);
		h.u32(0);
		h.u32(0);
		h.u16(240);
		h.u16(0x0023); // RELOCS_STRIPPED | EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE
		h.u16(0x20b); // PE32+
		h.u8(14);
		h.u8(0);
		h.u32(rawSize[0]); // SizeOfCode
		h.u32(rawSize[1] + rawSize[2] + rawSize[3] + rawSize[4] + rawSize[5]); // SizeOfInitializedData
		h.u32(sizes[6]); // SizeOfUninitializedData
		var e = globals.get(entry);
		if (e == null) throw "hxmc: link: no entry point " + entry;
		h.u32(symAddr(e) - BASE);
		h.u32(starts[0]); // BaseOfCode
		h.u64(BASE, 0); // ImageBase
		h.u32(SECT);
		h.u32(FILE);
		h.u16(6);
		h.u16(0); // OS version
		h.u16(0);
		h.u16(0); // image version
		h.u16(6);
		h.u16(0); // subsystem version
		h.u32(0);
		h.u32(imageSize);
		h.u32(headers);
		h.u32(0); // checksum
		h.u16(3); // console
		h.u16(0x8100); // NX_COMPAT | TERMINAL_SERVER_AWARE (no DYNAMIC_BASE: a fixed image)
		h.u64(0x1000000, 0); // stack reserve
		h.u64(0x1000, 0);
		h.u64(0x100000, 0); // heap
		h.u64(0x1000, 0);
		h.u32(0);
		h.u32(16);
		// data directories
		var dirs = [for (_ in 0...16) [0, 0]];
		if (dlls.length > 0) {
			dirs[1] = [starts[5] + idataLayout.dir, 20 * (dlls.length + 1)];
			dirs[12] = [starts[5] + idataLayout.iatStart, idataLayout.iatSize];
		}
		if (sizes[2] > 0) dirs[3] = [starts[2], sizes[2]];
		var tlsUsed = globals.get("_tls_used");
		if (tlsUsed != null) dirs[9] = [symAddr(tlsUsed) - BASE, 40];
		for (d in dirs) {
			h.u32(d[0]);
			h.u32(d[1]);
		}
		// section table
		for (gi in present) {
			var g = groups[gi];
			var nm = Bytes.alloc(8);
			nm.fill(0, 8, 0);
			nm.blit(0, Bytes.ofString(g.name), 0, g.name.length);
			h.bytes(nm);
			h.u32(sizes[gi]);
			h.u32(starts[gi]);
			h.u32(rawSize[gi]);
			h.u32(rawPos[gi]);
			h.u32(0);
			h.u32(0);
			h.u16(0);
			h.u16(0);
			h.u32(g.chars);
		}
		out.b.blit(0, h.b, 0, h.len);
		return out.toBytes();
	}

	// the import directory, ILTs, IATs, hint/name entries and DLL names of
	// .idata at `rva`; iat: (dll + name) -> RVA of its IAT slot
	function importData(dlls:Array<String>, byDll:Map<String, Array<String>>, rva:Int) {
		var b = new Buf(4096);
		var dir = 0;
		b.zeros(20 * (dlls.length + 1));
		var n = 0;
		for (d in dlls)
			n += byDll.get(d).length + 1;
		var ilt = b.len;
		b.zeros(8 * n);
		var iatStart = b.len;
		b.zeros(8 * n);
		var iat = new Map<String, Int>();
		var k = 0;
		for (di in 0...dlls.length) {
			var d = dlls[di];
			var names = byDll.get(d);
			var first = k;
			for (name in names) {
				b.align(2);
				var hn = b.len;
				b.u16(0);
				b.str(name);
				b.u8(0);
				b.set64(ilt + 8 * k, rva + hn, 0);
				b.set64(iatStart + 8 * k, rva + hn, 0);
				iat.set(d + "\t" + name, rva + iatStart + 8 * k);
				k++;
			}
			k++; // the terminating zero entry
			var dn = b.len;
			b.str(d);
			b.u8(0);
			var e = dir + 20 * di;
			b.set32(e, rva + ilt + 8 * first);
			b.set32(e + 12, rva + dn);
			b.set32(e + 16, rva + iatStart + 8 * first);
		}
		return {buf: b, dir: dir, iat: iat, iatStart: iatStart, iatSize: 8 * n};
	}
}
