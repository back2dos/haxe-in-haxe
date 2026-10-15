package hxmc;

import haxe.io.Bytes;
import hxmc.Obj;
import hxmc.Abi;

// hxmc's linker for macOS: objects (the program's, the runtime object of
// MkRt.macho) -> a Mach-O executable (MH_EXECUTE, position-independent as
// arm64 macOS requires) that loads /usr/lib/libSystem.B.dylib, written
// without the SDK or ld64:
//   __PAGEZERO (4 GB), __TEXT (headers, code, import stubs, read-only data),
//   __DATA (import slots, data with pointers, thread-local descriptors and
//   templates, zero-fill), __LINKEDIT (dyld's rebase and bind opcodes, an
//   export trie, the symbol table of the imports, the code signature).
// Addresses are kept relative to the image (vm offset == file offset in
// __TEXT and __DATA); absolute pointers get BASE added and a rebase entry.
// Whatever the objects leave undefined is bound from libSystem (two-level
// namespace, ordinal 1) with its Mach-O name (`_` + the C name): calls go
// through a stub per function, address loads through slots in __got.
// arm64 executables must be signed: an ad-hoc, linker-signed code signature
// (a CodeDirectory of SHA-256 page hashes) ends __LINKEDIT.
// Thread-local variables: the runtime's descriptors (__thread_vars: thunk
// bound to _tlv_bootstrap, key, offset in the template) get their offsets
// here; generated code reaches a variable at its template offset from the
// thread's copy (hxmc_tls_base, through hxmc_tls_start, a descriptor of
// offset 0 defined here).
class LinkMachO {
	static inline var BASE_HI = 1; // the image at 0x100000000 (above __PAGEZERO)
	static inline var HEADER_RESERVE = 0x1000; // load commands (padded)

	var objs:Array<Obj>;
	var abi:Abi;
	var arm:Bool;
	var PAGE:Int;
	var globals = new Map<String, Symbol>();
	var addr = new Map<Section, Int>();

	public var symbols = false; // a symbol table of the code (profilers, debuggers)

	public function new(objs:Array<Obj>, abi:Abi) {
		this.objs = objs;
		this.abi = abi;
		arm = abi.arm;
		PAGE = abi.segAlign;
		if (abi.output != Executable) throw "hxmc: " + abi.output + " output is not supported yet on macOS";
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

	static function isGot(k:RelKind):Bool
		return k == RGotPcRel32 || k == RA64GotPage21 || k == RA64GotLo12;

	static function isBranch(k:RelKind):Bool
		return k == RCall32 || k == RA64Call26 || k == RA64Jump26;

	static function isTlvSection(s:Section):Bool
		return StringTools.endsWith(s.name, "__thread_vars");

	public function link(entry:String):Bytes {
		// __dso_handle (as ld64 defines it): the image's Mach-O header, the
		// start of __TEXT; libuv and mbedtls refer to it (atexit handlers).
		// Its section is not laid out: it is placed at 0 below.
		var header = new Section("__TEXT,__mach_header", RoData, 1);
		var dso = new Obj();
		dso.define("__dso_handle", header, 0, 0);
		objs.push(dso);
		resolve();
		// imports: what stays undefined (by name), and whether each is weak
		var importWeak = new Map<String, Bool>();
		var importOrder:Array<String> = [];
		function imported(s:Symbol):Bool {
			if (target(s) != null) return false;
			if (!importWeak.exists(s.name)) {
				importWeak.set(s.name, s.weak);
				importOrder.push(s.name);
			} else if (!s.weak) importWeak.set(s.name, false);
			return true;
		}
		// the template-start descriptor (hxmc_tls_start), and the first
		// thread-local section it points at
		var tls = [for (o in objs) for (s in o.sections) if (s.kind == Tdata) s].concat([for (o in objs) for (s in o.sections) if (s.kind == Tbss) s]);
		var extra = new Obj();
		var tlv0 = new Section("__DATA,__thread_vars", Data, 8);
		if (tls.length > 0) {
			var start = new Symbol(".Ltls_start");
			start.global = false;
			start.section = tls[0];
			tlv0.buf.zeros(24);
			tlv0.relocs.push(new Reloc(0, RAbs64, extra.sym("_tlv_bootstrap"), 0));
			tlv0.relocs.push(new Reloc(16, RAbs64, start, 0));
			extra.sections.push(tlv0);
			extra.define("hxmc_tls_start", tlv0, 0, 24);
		}
		var stubs = new Section("__TEXT,__stubs", Text, 16);
		var got = new Section("__DATA,__got", Data, 8);
		extra.sections.push(stubs);
		extra.sections.push(got);
		objs.push(extra);
		if (tls.length > 0) globals.set("hxmc_tls_start", extra.sym("hxmc_tls_start"));
		// slots (by target: a defined symbol, or an import's name) and stubs
		var gotSlot = new Map<String, Int>(); // key -> offset in got
		var gotKey = new Map<Int, Symbol>(); // offset -> the symbol it holds
		var stubOf = new Map<String, Int>();
		var localKeys = new Map<Symbol, String>();
		var nlocal = 0;
		function slotKey(s:Symbol):String {
			var t = target(s);
			if (t == null) return "imp:" + s.name;
			if (t.global) return "sym:" + t.name;
			var k = localKeys.get(t);
			if (k == null) localKeys.set(t, k = "loc:" + (nlocal++));
			return k;
		}
		function slot(s:Symbol):Int {
			var k = slotKey(s);
			var at = gotSlot.get(k);
			if (at == null) {
				at = got.buf.len;
				gotSlot.set(k, at);
				gotKey.set(at, s);
				got.buf.u64(0, 0);
			}
			return at;
		}
		function stub(name:String):Int {
			var at = stubOf.get(name);
			if (at != null) return at;
			at = stubs.buf.len;
			stubOf.set(name, at);
			// (patched once the slots have addresses)
			if (arm) {
				stubs.buf.u32(0x90000010); // adrp x16, slot
				stubs.buf.u32(0xF9400210); // ldr x16, [x16, :lo12:slot]
				stubs.buf.u32(0xD61F0200); // br x16
			} else {
				stubs.buf.u8(0xff); // jmp [rip + slot]
				stubs.buf.u8(0x25);
				stubs.buf.u32(0);
			}
			return at;
		}
		var stubSlot = new Map<String, Int>();
		for (o in objs)
			for (s in o.sections)
				for (r in s.relocs) {
					var imp = imported(r.sym);
					if (isGot(r.kind)) slot(r.sym);
					else if (imp && r.kind != RAbs64) {
						// code (a call, or an address taken pc-relatively): the stub
						stub(r.sym.name);
						if (!stubSlot.exists(r.sym.name)) stubSlot.set(r.sym.name, slot(r.sym));
					}
				}
		// ---- layout
		var text = [], ro = [], roData = [], data = [], init = [], fini = [], tlv = [], tdata = [], tbss = [], bss = [];
		for (o in objs)
			for (s in o.sections) {
				switch s.kind {
					case Text: if (s != stubs) text.push(s);
					case RoData:
						// read-only data with absolute addresses goes where dyld can write
						var abs = false;
						for (r in s.relocs)
							if (r.kind == RAbs64 || r.kind == RAbs32 || r.kind == RAbs32S) {
								var t = target(r.sym);
								if (t == null || !t.abs) abs = true;
							}
						if (abs) roData.push(s) else ro.push(s);
					case Data: if (isTlvSection(s)) tlv.push(s) else if (s != got) data.push(s);
					case InitArray: init.push(s);
					case FiniArray: fini.push(s);
					case Tdata: tdata.push(s);
					case Tbss: tbss.push(s);
					case Bss: bss.push(s);
				}
			}
		text.push(stubs);
		addr.set(header, 0);
		var pos = HEADER_RESERVE;
		function place(list:Array<Section>):{start:Int, end:Int} {
			if (list.length > 0) pos = align(pos, list[0].align);
			var start = pos;
			for (s in list) {
				pos = align(pos, s.align);
				addr.set(s, pos);
				pos += s.size();
			}
			return {start: start, end: pos};
		}
		// __TEXT
		pos = align(pos, 16);
		var oText = place(text);
		var oConst = place(ro);
		var textEnd = align(pos, PAGE);
		// __DATA
		pos = textEnd;
		var dataStart = pos;
		var oGot = place([got]);
		var oDConst = place(roData);
		var oData = place(data);
		var oInit = place(init);
		var oFini = place(fini);
		var oTlv = place(tlv);
		pos = align(pos, 16);
		var oTdata = place(tdata);
		var dataFileEnd = pos;
		var oTbss = place(tbss);
		var tlsStart = tdata.length > 0 ? addr.get(tdata[0]) : tbss.length > 0 ? addr.get(tbss[0]) : 0;
		var oBss = place(bss);
		var dataEnd = align(pos, PAGE);
		if (dataEnd == dataStart) dataEnd += PAGE;
		var stubAddr = addr.get(stubs);
		var gotAddr = addr.get(got);
		function symAddr(s:Symbol):Int {
			var t = target(s);
			if (t == null) {
				var st = stubOf.get(s.name);
				if (st != null) return stubAddr + st;
				if (s.weak) return 0;
				throw 'hxmc: link: undefined symbol ${s.name}';
			}
			if (t.abs) return t.offset;
			return addr.get(t.section) + t.offset;
		}
		// the stubs, now that slots have addresses
		for (name => at in stubOf) {
			var sl = gotAddr + stubSlot.get(name);
			if (arm) {
				A64Reloc.adrp(stubs.buf, at, sl, stubAddr + at);
				A64Reloc.imm12(stubs.buf, at + 4, (sl & 0xfff) >> 3);
			} else stubs.buf.set32(at + 2, sl - (stubAddr + at + 6));
		}
		// the thread-local template offset of a variable: its descriptor's
		// third word refers to its storage
		var descRel = new Map<Section, Map<Int, Reloc>>();
		for (s in tlv) {
			var m = new Map<Int, Reloc>();
			for (r in s.relocs)
				m.set(r.offset, r);
			descRel.set(s, m);
		}
		function tlsOffset(s:Symbol):Int {
			var t = target(s);
			if (t == null || t.section == null || !descRel.exists(t.section)) throw "hxmc: link: " + s.name + " is not a thread-local variable";
			var r = descRel.get(t.section).get(t.offset + 16);
			if (r == null) throw "hxmc: link: no storage for the thread-local variable " + s.name;
			return symAddr(r.sym) + r.addend - tlsStart;
		}
		// relocations; rebase and bind entries
		var rebases:Array<Int> = [];
		var binds:Array<{at:Int, name:String, addend:Int}> = [];
		// the slots
		for (at => s in gotKey) {
			var t = target(s);
			if (t == null) binds.push({at: gotAddr + at, name: s.name, addend: 0});
			else if (t.abs) got.buf.set64(at, t.offset, 0);
			else {
				got.buf.set64(at, symAddr(s), BASE_HI);
				rebases.push(gotAddr + at);
			}
		}
		var all = text.concat(ro).concat(roData).concat(data).concat(init).concat(fini).concat(tlv).concat(tdata);
		for (s in all) {
			var base = addr.get(s);
			var buf = s.buf;
			var inTlv = isTlvSection(s);
			for (r in s.relocs) {
				var P = base + r.offset;
				var A = r.addend;
				switch r.kind {
					case RAbs64:
						var t = target(r.sym);
						if (inTlv && r.offset % 24 == 16) {
							// a descriptor's offset in the template
							buf.set64(r.offset, symAddr(r.sym) + A - tlsStart, 0);
						} else if (t == null) {
							buf.set64(r.offset, 0, 0);
							binds.push({at: P, name: r.sym.name, addend: A});
						} else if (t.abs) {
							var v = t.offset + A;
							buf.set64(r.offset, v, v < 0 ? -1 : 0);
						} else {
							buf.set64(r.offset, symAddr(r.sym) + A, BASE_HI);
							rebases.push(P);
						}
					case RAbs32 | RAbs32S:
						var t = target(r.sym);
						if (t == null || !t.abs) throw "hxmc: link: a 32-bit absolute address of " + r.sym.name + " (position-independent output)";
						buf.set32(r.offset, t.offset + A);
					case RPc32 | RCall32:
						buf.set32(r.offset, symAddr(r.sym) + A - P);
					case RGotPcRel32:
						buf.set32(r.offset, gotAddr + slot(r.sym) + A - P);
					case RSecRel32:
						buf.set32(r.offset, tlsOffset(r.sym) + A);
					case RA64GotPage21:
						A64Reloc.adrp(buf, r.offset, gotAddr + slot(r.sym), P);
					case RA64GotLo12:
						A64Reloc.imm12(buf, r.offset, ((gotAddr + slot(r.sym)) & 0xfff) >> 3);
					case RA64SecRelHi12 | RA64SecRelLo12A | RA64SecRelLo12L:
						A64Reloc.apply(buf, r.offset, r.kind, tlsOffset(r.sym) + A, P, r.sym.name);
					case _:
						if (!arm || !A64Reloc.apply(buf, r.offset, r.kind, symAddr(r.sym) + A, P, r.sym.name))
							throw "hxmc: link: relocation " + r.kind + " on macOS";
				}
			}
		}
		// ---- __LINKEDIT
		var le = new Buf(1 << 16);
		// rebase opcodes: runs of adjacent pointers
		rebases.sort((a, b) -> a - b);
		var rebaseOff = le.len;
		if (rebases.length > 0) {
			le.u8(0x11); // REBASE_OPCODE_SET_TYPE_IMM pointer
			var k = 0;
			while (k < rebases.length) {
				var n = 1;
				while (k + n < rebases.length && rebases[k + n] == rebases[k] + 8 * n)
					n++;
				le.u8(0x20 | 2); // SET_SEGMENT_AND_OFFSET_ULEB __DATA
				uleb(le, rebases[k] - dataStart);
				le.u8(0x60); // DO_REBASE_ULEB_TIMES
				uleb(le, n);
				k += n;
			}
		}
		le.u8(0);
		le.align(8);
		var rebaseSize = le.len - rebaseOff;
		// bind opcodes (non-lazy: all at load)
		binds.sort((a, b) -> a.at - b.at);
		var bindOff = le.len;
		if (binds.length > 0) {
			le.u8(0x11); // BIND_OPCODE_SET_DYLIB_ORDINAL_IMM 1
			le.u8(0x51); // BIND_OPCODE_SET_TYPE_IMM pointer
			var cur = "";
			var curAddend = 0;
			for (b in binds) {
				if (b.name != cur) {
					le.u8(0x40 | (importWeak.get(b.name) ? 1 : 0)); // SET_SYMBOL_TRAILING_FLAGS_IMM
					le.str("_" + b.name);
					le.u8(0);
					cur = b.name;
				}
				if (b.addend != curAddend) {
					le.u8(0x60); // SET_ADDEND_SLEB
					sleb(le, b.addend);
					curAddend = b.addend;
				}
				le.u8(0x70 | 2); // SET_SEGMENT_AND_OFFSET_ULEB __DATA
				uleb(le, b.at - dataStart);
				le.u8(0x90); // DO_BIND
			}
		}
		le.u8(0);
		le.align(8);
		var bindSize = le.len - bindOff;
		// the export trie: __mh_execute_header at 0
		var exportOff = le.len;
		le.u8(0); // root: not terminal
		le.u8(1); // one edge
		le.str("__mh_execute_header");
		le.u8(0);
		le.u8(23); // the child's offset in the trie (just after this byte)
		le.u8(2); // terminal: 2 bytes of information
		le.u8(0); // flags: regular
		le.u8(0); // address 0
		le.u8(0); // no children
		le.align(8);
		var exportSize = le.len - exportOff;
		// the symbol table: (with `symbols`) the functions as locals, then the
		// imports (undefined, from ordinal 1)
		var strtab = new Buf(4096);
		strtab.u8(0x20);
		strtab.u8(0);
		var symtabOff = le.len;
		var nlocals = 0;
		if (symbols)
			for (o in objs)
				for (s in o.symbols) {
					var sec = s.section;
					if (sec == null || sec.kind != Text || !addr.exists(sec) || s.abs || s.name.length == 0 || StringTools.startsWith(s.name, ".L")) continue;
					le.u32(strtab.len);
					strtab.str("_" + s.name);
					strtab.u8(0);
					le.u8(0x0e); // N_SECT, local
					le.u8(1); // __text
					le.u16(0);
					le.u64(addr.get(sec) + s.offset, BASE_HI);
					nlocals++;
				}
		var nimports = 0;
		for (name in importOrder) {
			le.u32(strtab.len);
			strtab.str("_" + name);
			strtab.u8(0);
			le.u8(0x01); // N_UNDF | N_EXT
			le.u8(0);
			le.u16((1 << 8) | (importWeak.get(name) ? 0x40 : 0));
			le.u64(0, 0);
			nimports++;
		}
		var nsyms = nlocals + nimports;
		var strOff = le.len;
		le.buf(strtab);
		le.align(16);
		var sigOffInLe = le.len;
		// ---- the file
		var leFileOff = dataFileEnd > dataStart ? align(dataFileEnd, PAGE) : dataStart;
		var leVm = dataEnd;
		var cdIdent = "hxmc";
		var nPages = (leFileOff + sigOffInLe + 4095) >> 12;
		var cdHeader = 88;
		var cdLen = cdHeader + cdIdent.length + 1 + 32 * nPages;
		var sigLen = align(20 + cdLen, 16);
		var fileSize = leFileOff + sigOffInLe + sigLen;
		var out = new Buf(fileSize + 16);
		out.zeros(fileSize);
		for (s in text.concat(ro).concat(roData).concat(data).concat(init).concat(fini).concat(tlv).concat(tdata).concat([got]))
			out.b.blit(addr.get(s), s.buf.b, 0, s.buf.len);
		out.b.blit(leFileOff, le.b, 0, le.len);
		// load commands
		var h = new Buf(HEADER_RESERVE);
		h.u32(0xfeedfacf);
		h.u32(arm ? 0x0100000c : 0x01000007);
		h.u32(arm ? 0 : 3);
		h.u32(2); // MH_EXECUTE
		var ncmdsAt = h.len;
		h.u32(0);
		h.u32(0); // sizeofcmds
		// NOUNDEFS | DYLDLINK | TWOLEVEL | PIE (| HAS_TLV_DESCRIPTORS: dyld sets
		// up the descriptors of __thread_vars only with it)
		h.u32(0x00200085 | (tlv.length > 0 ? 0x00800000 : 0));
		h.u32(0);
		var ncmds = 0;
		function seg(name:String, vm:Int, vmsize:Int, fileoff:Int, filesize:Int, prot:Int, sects:Array<{name:String, start:Int, end:Int, flags:Int, zerofill:Bool, align:Int}>) {
			ncmds++;
			var live = [for (x in sects) if (x.end > x.start || x.name == "__text") x];
			h.u32(0x19);
			h.u32(72 + 80 * live.length);
			fixed(h, name, 16);
			h.u64(vm, name == "__PAGEZERO" ? 0 : BASE_HI);
			h.u64(vmsize, name == "__PAGEZERO" ? 1 : 0);
			h.u64(fileoff, 0);
			h.u64(filesize, 0);
			h.u32(prot);
			h.u32(prot);
			h.u32(live.length);
			h.u32(0);
			for (x in live) {
				fixed(h, x.name, 16);
				fixed(h, name, 16);
				h.u64(x.start, BASE_HI);
				h.u64(x.end - x.start, 0);
				h.u32(x.zerofill ? 0 : x.start);
				h.u32(log2(x.align));
				h.u32(0);
				h.u32(0);
				h.u32(x.flags);
				h.u32(0);
				h.u32(0);
				h.u32(0);
			}
		}
		inline function sec(name, o:{start:Int, end:Int}, flags, zerofill = false, al = 16)
			return {name: name, start: o.start, end: o.end, flags: flags, zerofill: zerofill, align: al};
		seg("__PAGEZERO", 0, 0, 0, 0, 0, []);
		seg("__TEXT", 0, textEnd, 0, textEnd, 5, [
			sec("__text", {start: oText.start, end: addr.get(stubs) + stubs.size()}, 0x80000400),
			sec("__const", oConst, 0)
		]);
		seg("__DATA", dataStart, dataEnd - dataStart, dataStart, dataFileEnd - dataStart, 3, [
			sec("__got", oGot, 0, false, 8),
			sec("__const", oDConst, 0),
			sec("__data", oData, 0),
			sec("__mod_init_func", oInit, 9, false, 8),
			sec("__mod_term_func", oFini, 0xa, false, 8),
			sec("__thread_vars", oTlv, 0x13, false, 8),
			sec("__thread_data", oTdata, 0x11),
			sec("__thread_bss", oTbss, 0x12, true),
			sec("__bss", oBss, 1, true)
		]);
		seg("__LINKEDIT", leVm, align(sigOffInLe + sigLen, PAGE), leFileOff, sigOffInLe + sigLen, 1, []);
		// dyld info
		ncmds++;
		h.u32(0x80000022);
		h.u32(48);
		h.u32(leFileOff + rebaseOff);
		h.u32(rebaseSize);
		h.u32(leFileOff + bindOff);
		h.u32(bindSize);
		h.u32(0);
		h.u32(0);
		h.u32(0);
		h.u32(0);
		h.u32(leFileOff + exportOff);
		h.u32(exportSize);
		// symbol tables
		ncmds++;
		h.u32(0x2);
		h.u32(24);
		h.u32(leFileOff + symtabOff);
		h.u32(nsyms);
		h.u32(leFileOff + strOff);
		h.u32(strtab.len);
		ncmds++;
		h.u32(0xb);
		h.u32(80);
		h.u32(0); // ilocalsym
		h.u32(nlocals);
		h.u32(nlocals); // iextdefsym
		h.u32(0);
		h.u32(nlocals); // iundefsym
		h.u32(nimports);
		for (_ in 0...12)
			h.u32(0);
		// the dynamic linker
		ncmds++;
		var dyld = "/usr/lib/dyld";
		var dl = align(12 + dyld.length + 1, 8);
		h.u32(0xe);
		h.u32(dl);
		h.u32(12);
		fixed(h, dyld, dl - 12);
		// UUID (filled below)
		ncmds++;
		h.u32(0x1b);
		h.u32(24);
		var uuidAt = h.len;
		h.zeros(16);
		// build version: macOS, minimum 11.0 (arm64) / 10.15 (x86-64)
		ncmds++;
		var minos = arm ? 0x000B0000 : 0x000A0F00;
		h.u32(0x32);
		h.u32(32);
		h.u32(1); // PLATFORM_MACOS
		h.u32(minos);
		h.u32(minos); // sdk
		h.u32(1);
		h.u32(3); // TOOL_LD
		h.u32(0x00010000);
		// main
		ncmds++;
		var e = target(entrySym(entry));
		h.u32(0x80000028);
		h.u32(24);
		h.u64(symAddr(e), 0);
		h.u64(0, 0);
		// libSystem
		ncmds++;
		var lib = "/usr/lib/libSystem.B.dylib";
		var ll = align(24 + lib.length + 1, 8);
		h.u32(0xc);
		h.u32(ll);
		h.u32(24);
		h.u32(2);
		h.u32(0x05276403); // current version 1319.100.3
		h.u32(0x00010000); // compatibility 1.0.0
		fixed(h, lib, ll - 24);
		// the code signature
		ncmds++;
		h.u32(0x1d);
		h.u32(16);
		h.u32(leFileOff + sigOffInLe);
		h.u32(sigLen);
		if (h.len > HEADER_RESERVE) throw "hxmc: link: Mach-O load commands too large";
		h.set32(ncmdsAt, ncmds);
		h.set32(ncmdsAt + 4, h.len - 32);
		out.b.blit(0, h.b, 0, h.len);
		// UUID: a digest of the file (with a zero UUID), as a version-4 UUID
		var digest = haxe.crypto.Md5.make(out.b.sub(0, leFileOff + sigOffInLe));
		digest.set(6, (digest.get(6) & 0x0f) | 0x40);
		digest.set(8, (digest.get(8) & 0x3f) | 0x80);
		out.b.blit(uuidAt, digest, 0, 16);
		// the signature: SuperBlob { CodeDirectory } (big-endian)
		var codeLimit = leFileOff + sigOffInLe;
		var sig = new BeBuf();
		sig.u32(0xfade0cc0);
		sig.u32(20 + cdLen);
		sig.u32(1);
		sig.u32(0); // CSSLOT_CODEDIRECTORY
		sig.u32(20);
		sig.u32(0xfade0c02);
		sig.u32(cdLen);
		sig.u32(0x20400);
		sig.u32(0x20002); // CS_ADHOC | CS_LINKER_SIGNED
		sig.u32(cdHeader + cdIdent.length + 1); // hashOffset
		sig.u32(cdHeader); // identOffset
		sig.u32(0); // nSpecialSlots
		sig.u32(nPages);
		sig.u32(codeLimit);
		sig.u8(32); // hashSize
		sig.u8(2); // CS_HASHTYPE_SHA256
		sig.u8(0); // platform
		sig.u8(12); // log2 page size
		sig.u32(0); // spare2
		sig.u32(0); // scatterOffset
		sig.u32(0); // teamOffset
		sig.u32(0); // spare3
		sig.u64(0); // codeLimit64
		sig.u64(0); // execSegBase
		sig.u64(textEnd); // execSegLimit
		sig.u64(1); // CS_EXECSEG_MAIN_BINARY
		sig.b.str(cdIdent);
		sig.u8(0);
		for (p in 0...nPages) {
			var off = p << 12;
			var n = codeLimit - off < 4096 ? codeLimit - off : 4096;
			sig.b.bytes(haxe.crypto.Sha256.make(out.b.sub(off, n)));
		}
		out.b.blit(codeLimit, sig.b.b, 0, sig.b.len);
		return out.toBytes();
	}

	function entrySym(name:String):Symbol {
		var s = globals.get(name);
		if (s == null) throw 'hxmc: link: no entry point $name';
		return s;
	}

	static function log2(v:Int):Int {
		var k = 0;
		while ((1 << k) < v)
			k++;
		return k;
	}

	static function fixed(h:Buf, s:String, n:Int) {
		var b = Bytes.ofString(s);
		if (b.length > n) throw "hxmc: link: name too long: " + s;
		h.bytes(b);
		h.zeros(n - b.length);
	}

	static function uleb(b:Buf, v:Int) {
		while (true) {
			var c = v & 0x7f;
			v >>>= 7;
			if (v != 0) b.u8(c | 0x80) else {
				b.u8(c);
				return;
			}
		}
	}

	static function sleb(b:Buf, v:Int) {
		while (true) {
			var c = v & 0x7f;
			v >>= 7;
			if ((v == 0 && (c & 0x40) == 0) || (v == -1 && (c & 0x40) != 0)) {
				b.u8(c);
				return;
			}
			b.u8(c | 0x80);
		}
	}
}

// big-endian words over a Buf (code signatures)
class BeBuf {
	public var b = new Buf(1 << 16);

	public function new() {}

	public inline function u8(v:Int)
		b.u8(v);

	public function u32(v:Int) {
		b.u8(v >>> 24);
		b.u8((v >> 16) & 0xff);
		b.u8((v >> 8) & 0xff);
		b.u8(v & 0xff);
	}

	public function u64(v:Int) {
		u32(v < 0 ? -1 : 0);
		u32(v);
	}
}
