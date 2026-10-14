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
	// the image base: x86-64 a fixed 0x400000 (addresses are kept absolute);
	// arm64 0x140000000, relocatable (addresses are kept as RVAs, BASE 0, and
	// the base is added where a 64-bit absolute address is written)
	var BASE = 0x400000;
	var imgLo = 0;
	var imgHi = 0;
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
		if (arm && !diag("lowbase")) {
			BASE = 0;
			imgLo = 0x40000000;
			imgHi = 1;
		}
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

	// HXMC_PE_DIAG=<flag,...>: variants of the output for bisecting a loader's
	// refusal (development)
	static var diags:Null<Array<String>>;

	static function diag(f:String):Bool {
		if (diags == null) {
			var e = Sys.getEnv("HXMC_PE_DIAG");
			diags = e == null ? [] : e.split(",");
		}
		return diags.indexOf(f) >= 0;
	}

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
				if (arm) {
					// adrp x16, slot; ldr x16, [x16, :lo12:slot]; br x16
					thunks.buf.u32(0x90000010);
					thunks.buf.u32(0xF9400210);
					thunks.buf.u32(0xD61F0200);
					thunks.buf.u32(0xD503201F);
				} else {
					thunks.buf.u8(0xff);
					thunks.buf.u8(0x25);
					thunks.buf.u32(0);
					thunks.buf.u16(0x9090);
				}
			}
		// __CTOR_LIST__ / __DTOR_LIST__ (MinGW's __do_global_ctors): -1, the
		// objects' .ctors/.dtors sections (constructors of the C library, e.g.
		// winpthreads' initialization), 0; kept together by their names in .data
		var extra = new Obj();
		extra.sections.push(thunks);
		var listHead = new Map<String, Section>();
		for (l in ["ctor", "dtor"]) {
			var head = new Section(".data$hxmc_" + l + "0", Data, 8);
			head.buf.u64(-1, -1);
			var tail = new Section(".data$hxmc_" + l + "2", Data, 8);
			tail.buf.u64(0, 0);
			extra.sections.push(head);
			extra.sections.push(tail);
			listHead.set(l, head);
		}
		for (o in objs)
			for (sec in o.sections)
				for (l in ["ctor", "dtor"])
					if (sec.name == "." + l + "s" || StringTools.startsWith(sec.name, "." + l + "s.")) {
						sec.name = ".data$hxmc_" + l + "1" + sec.name;
						sec.kind = Data;
					}
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
			{name: ".reloc", chars: 0x42000040, secs: []},
		];
		for (o in objs)
			for (s in o.sections) {
				// (.CRT$X?A ... .CRT$X?Z: arrays of pointers, read-only or not,
				// kept together in .data in name order)
				var g = StringTools.startsWith(s.name, ".CRT$") ? 3 : switch s.kind {
					case Text: 0;
					case RoData: StringTools.startsWith(s.name, ".pdata") ? 2 : 1;
					case Data | InitArray | FiniArray: 3;
					case Tdata | Tbss: 4;
					case Bss: diag("bssdata") ? 3 : 6;
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
		var relocatable = arm && !diag("fixed");
		var baseRelocs:Array<{rva:Int, type:Int}> = [];
		var defined = new Map<String, Int>();
		defined.set("__CTOR_LIST__", addr.get(listHead.get("ctor")));
		defined.set("__DTOR_LIST__", addr.get(listHead.get("dtor")));
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
		// HXMC_MAP=<file>: the address of every code symbol (debugging; no
		// symbol table is written in PE files)
		var mapFile = Sys.getEnv("HXMC_MAP");
		if (mapFile != null) {
			var m = new StringBuf();
			for (o in objs)
				for (s in o.symbols)
					if (s.section != null && s.section.kind == Text && addr.exists(s.section))
						m.add(StringTools.hex(addr.get(s.section) + s.offset, 8) + " " + s.name + "\n");
			sys.io.File.saveContent(mapFile, m.toString());
		}
		function isAbs(sym:Symbol):Bool {
			var t = target(sym);
			// (linker-defined: addresses, but for the zero of an undefined weak symbol)
			return t != null ? t.abs : sym.name != "__ImageBase" && symAddr(sym) == 0;
		}
		// the thunks: jmp [rip + IAT slot] (arm64: adrp, ldr, br)
		for (k => off in thunkOf) {
			if (arm) {
				var p = addr.get(thunks) + off;
				A64Reloc.adrp(thunks.buf, off, iatAddr(k), p);
				A64Reloc.imm12(thunks.buf, off + 4, (iatAddr(k) & 0xfff) >> 3);
				continue;
			}
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
							if (isAbs(r.sym)) s.buf.set64(r.offset, v, v < 0 ? -1 : 0) else {
								s.buf.set64(r.offset, v + imgLo, imgHi);
								if (relocatable) baseRelocs.push({rva: P - BASE, type: 10});
							}
						case RAbs32 | RAbs32S:
							s.buf.set32(r.offset, S + A);
							if (!isAbs(r.sym)) {
								if (imgHi != 0) throw "hxmc: link: a 32-bit absolute address of " + r.sym.name + " (an image above 4 GB)";
								if (relocatable) baseRelocs.push({rva: P - BASE, type: 3});
							}
						case RPc32 | RCall32:
							s.buf.set32(r.offset, S + A - P);
						case RImgRel32:
							s.buf.set32(r.offset, S == 0 ? 0 : S + A - BASE);
						case RSecRel32:
							var t = target(r.sym);
							var sec = t != null && t.section != null ? outOf.get(t.section) : -1;
							s.buf.set32(r.offset, S + A - BASE - (sec >= 0 ? starts[sec] : 0));
						case RA64SecRelHi12 | RA64SecRelLo12A | RA64SecRelLo12L:
							var t = target(r.sym);
							var sec = t != null && t.section != null ? outOf.get(t.section) : -1;
							A64Reloc.apply(s.buf, r.offset, r.kind, S + A - BASE - (sec >= 0 ? starts[sec] : 0), P, r.sym.name);
						case _:
							if (!arm || !A64Reloc.apply(s.buf, r.offset, r.kind, S + A, P, r.sym.name))
								throw "hxmc: link: relocation " + r.kind + " on Windows";
					}
				}
			}
		// base relocations (arm64 images must be relocatable): a block per page
		var relocBuf = new Buf(4096);
		if (relocatable && baseRelocs.length > 0) {
			baseRelocs.sort((a, b) -> a.rva - b.rva);
			var k = 0;
			while (k < baseRelocs.length) {
				var page = baseRelocs[k].rva & ~0xfff;
				var at = relocBuf.len;
				relocBuf.u32(page);
				relocBuf.u32(0);
				while (k < baseRelocs.length && (baseRelocs[k].rva & ~0xfff) == page) {
					relocBuf.u16((baseRelocs[k].type << 12) | (baseRelocs[k].rva & 0xfff));
					k++;
				}
				if ((relocBuf.len & 3) != 0) relocBuf.u16(0);
				relocBuf.set32(at + 4, relocBuf.len - at);
			}
			sizes[7] = relocBuf.len;
			imageSize = starts[7] + align(relocBuf.len, SECT);
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
			if (g.name == ".idata") out.b.blit(at, idata.b, 0, idata.len) else if (g.name == ".reloc") out.b.blit(at, relocBuf.b, 0, relocBuf.len) else
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
		h.u16(relocatable ? 0x0022 : 0x0023); // (RELOCS_STRIPPED |) EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE
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
		h.u64(BASE + imgLo, imgHi); // ImageBase
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
		// NX_COMPAT | TERMINAL_SERVER_AWARE (x86-64: no DYNAMIC_BASE, a fixed
		// image; arm64: DYNAMIC_BASE, with base relocations)
		h.u16(relocatable ? (imgHi != 0 ? 0x8160 : 0x8140) : 0x8100); // (| HIGH_ENTROPY_VA above 4 GB)
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
		if (sizes[2] > 0 && !diag("nopdata")) dirs[3] = [starts[2], sizes[2]];
		if (sizes[7] > 0) dirs[5] = [starts[7], sizes[7]];
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
