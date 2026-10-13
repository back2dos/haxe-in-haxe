package hxmc;

import haxe.io.Bytes;
import hxmc.Obj;

// COFF input for the Windows runtime (MkRt): object files as Obj, archives
// (their symbol index and members), and the short import members of import
// libraries (which DLL exports a symbol). Relocations get explicit addends
// (COFF keeps them in the relocated field).
class CoffReader {
	var b:Bytes;
	var base:Int;
	var arm:Bool;

	// COMDAT sections (by section): the name of their COMDAT symbol, the
	// selection, the associated section for selection 5
	public var comdat = new Map<Section, {sym:String, selection:Int, assoc:Null<Section>}>();
	// weak externals: symbol -> its default symbol
	public var weakDefaults = new Map<Symbol, Symbol>();

	function new(b:Bytes, base:Int) {
		this.b = b;
		this.base = base;
	}

	inline function u8(at:Int):Int
		return b.get(base + at);

	inline function u16(at:Int):Int
		return b.getUInt16(base + at);

	inline function i16(at:Int):Int {
		var v = b.getUInt16(base + at);
		return v >= 0x8000 ? v - 0x10000 : v;
	}

	inline function u32(at:Int):Int
		return b.getInt32(base + at);

	function cstr(at:Int):String {
		var e = at;
		while (b.get(base + e) != 0)
			e++;
		return b.getString(base + at, e - at);
	}

	public static function isShortImport(b:Bytes, at:Int):Bool
		return b.getUInt16(at) == 0 && b.getUInt16(at + 2) == 0xffff;

	// a short import member: {symbol, dll, import name, code}
	public static function shortImport(b:Bytes, at:Int):{sym:String, dll:String, name:String, code:Bool, ordinal:Int, byOrdinal:Bool} {
		var r = new CoffReader(b, at);
		var hint = r.u16(16);
		var info = r.u16(18);
		var type = info & 3, nameType = (info >> 2) & 7;
		var sym = r.cstr(20);
		var dll = r.cstr(20 + Bytes.ofString(sym).length + 1);
		var name = sym;
		switch nameType {
			case 2:
				while (name.length > 0 && (name.charAt(0) == "?" || name.charAt(0) == "@" || name.charAt(0) == "_"))
					name = name.substr(1);
			case 3:
				while (name.length > 0 && (name.charAt(0) == "?" || name.charAt(0) == "@" || name.charAt(0) == "_"))
					name = name.substr(1);
				var k = name.indexOf("@");
				if (k >= 0) name = name.substr(0, k);
			case _:
		}
		return {sym: sym, dll: dll, name: name, code: type == 0, ordinal: hint, byOrdinal: nameType == 0};
	}

	public static function read(b:Bytes, at = 0):{obj:Obj, reader:CoffReader} {
		var r = new CoffReader(b, at);
		return {obj: r.run(), reader: r};
	}

	function relocKind(t:Int):{kind:RelKind, extra:Int} {
		if (!arm) return switch t {
			case 1: {kind: RAbs64, extra: 0};
			case 2: {kind: RAbs32, extra: 0};
			case 3: {kind: RImgRel32, extra: 0};
			case 4: {kind: RPc32, extra: -4};
			case 5 | 6 | 7 | 8 | 9: {kind: RPc32, extra: -4 - (t - 4)};
			case 0xb: {kind: RSecRel32, extra: 0};
			case _: throw "hxmc: COFF relocation type " + t;
		}
		throw "hxmc: COFF on arm64 is not supported yet";
	}

	function run():Obj {
		var machine = u16(0);
		arm = machine == 0xaa64;
		if (machine != 0x8664 && !arm) throw "hxmc: COFF machine " + StringTools.hex(machine);
		var nsec = u16(2);
		var symOff = u32(8);
		var nsym = u32(12);
		var optSize = u16(16);
		var strOff = symOff + 18 * nsym;
		function name8(at:Int):String {
			if (u32(at) == 0 && u8(at) == 0) return cstr(strOff + u32(at + 4));
			var e = 0;
			while (e < 8 && u8(at + e) != 0)
				e++;
			var s = b.getString(base + at, e);
			if (s.charAt(0) == "/") return cstr(strOff + Std.parseInt(s.substr(1)));
			return s;
		}
		var o = new Obj();
		var secs:Array<Null<Section>> = [null];
		var secChars:Array<Int> = [0];
		for (i in 0...nsec) {
			var h = 20 + optSize + 40 * i;
			var name = name8(h);
			var size = u32(h + 16);
			var raw = u32(h + 20);
			var chars = u32(h + 36);
			secChars.push(chars);
			// not loaded: debug information, linker directives, removed sections
			if ((chars & 0x800) != 0 || (chars & 0x200) != 0 || StringTools.startsWith(name, ".debug") || name == ".llvm_addrsig") {
				secs.push(null);
				continue;
			}
			var alignBits = (chars >> 20) & 0xf;
			var align = alignBits == 0 ? 16 : 1 << (alignBits - 1);
			var kind:SecKind = if (StringTools.startsWith(name, ".tls")) Tdata else if ((chars & 0x20000020) != 0) Text else if ((chars & 0x80) != 0) Bss
				else if ((chars & 0x80000000) != 0) Data else RoData;
			var s = new Section(name, kind, align);
			if (kind == Bss) s.bssSize = size else if (raw != 0) s.buf.bytes(b, base + raw, size) else s.buf.zeros(size);
			o.sections.push(s);
			secs.push(s);
		}
		// symbols
		var syms:Array<Null<Symbol>> = [];
		var k = 0;
		var pendingComdat = new Map<Int, Int>(); // section number -> selection, until its COMDAT symbol
		var assocOf = new Map<Int, Int>();
		while (k < nsym) {
			var at = symOff + 18 * k;
			var name = name8(at);
			var value = u32(at + 8);
			var secNum = i16(at + 12);
			var cls = u8(at + 16);
			var naux = u8(at + 17);
			var s:Null<Symbol> = null;
			if (cls == 104 /* section */ || cls == 3 && naux > 0 && secNum > 0 && value == 0 && secs[secNum] != null && name == secs[secNum].name) {
				// a section symbol; its aux record holds the COMDAT selection
				if (secNum > 0 && secs[secNum] != null) {
					s = new Symbol(".Lsec" + secNum + name);
					s.global = false;
					s.section = secs[secNum];
					o.symbols.push(s);
					if (naux > 0 && (secChars[secNum] & 0x1000) != 0) {
						var aux = at + 18;
						var sel = u8(aux + 14);
						var number = u16(aux + 12);
						if (sel == 5) assocOf.set(secNum, number);
						pendingComdat.set(secNum, sel);
					}
				}
			} else if (cls == 2 || cls == 105 || cls == 3 || cls == 6) {
				var external = cls == 2 || cls == 105;
				if (secNum == -2) {
					// debug
				} else if (external) {
					s = o.sym(name);
					if (secNum > 0) {
						if (secs[secNum] != null) {
							if (s.section != null) throw "hxmc: COFF: " + name + " defined twice in one object";
							s.section = secs[secNum];
							s.offset = value;
						}
					} else if (secNum == -1) {
						s.abs = true;
						s.offset = value;
					} else if (value > 0 && cls == 2) {
						// a common symbol: its own zeroed section
						var c = new Section(".bss$common", Bss, value >= 16 ? 16 : 8);
						c.bssSize = value;
						o.sections.push(c);
						s.section = c;
						s.offset = 0;
					}
					if (cls == 105) {
						s.weak = true;
						var tag = u32(at + 18);
						weakDefaults.set(s, null);
						weakTags.push({sym: s, tag: tag});
					}
				} else if (secNum > 0 && secs[secNum] != null) {
					s = new Symbol(name);
					s.global = false;
					s.section = secs[secNum];
					s.offset = value;
					o.symbols.push(s);
				}
				// the first symbol of a COMDAT section names it
				if (secNum > 0 && pendingComdat.exists(secNum)) {
					comdat.set(secs[secNum], {sym: name, selection: pendingComdat.get(secNum), assoc: null});
					pendingComdat.remove(secNum);
				}
			}
			syms.push(s);
			for (_ in 0...naux)
				syms.push(null);
			k += 1 + naux;
		}
		for (w in weakTags)
			weakDefaults.set(w.sym, syms[w.tag]);
		for (secNum => target in assocOf) {
			var s = secs[secNum];
			if (s == null) continue;
			var c = comdat.get(s);
			if (c == null) comdat.set(s, {sym: null, selection: 5, assoc: secs[target]}) else c.assoc = secs[target];
		}
		for (secNum => sel in pendingComdat)
			if (secs[secNum] != null && !comdat.exists(secs[secNum])) comdat.set(secs[secNum], {sym: null, selection: sel, assoc: null});
		// relocations, with their addends taken out of the fields
		for (i in 0...nsec) {
			var s = secs[i + 1];
			if (s == null) continue;
			var h = 20 + optSize + 40 * i;
			var off = u32(h + 24);
			var n = u16(h + 32);
			if ((secChars[i + 1] & 0x01000000) != 0 && n == 0xffff) {
				n = u32(off);
				off += 10;
			}
			for (j in 0...n) {
				var at = off + 10 * j;
				var va = u32(at);
				var sym = syms[u32(at + 4)];
				var t = u16(at + 8);
				var rk = relocKind(t);
				if (sym == null) throw "hxmc: COFF relocation against a dropped symbol in " + s.name;
				var field = rk.kind == RAbs64 ? s.buf.get32(va) : s.buf.get32(va);
				if (rk.kind == RAbs64) s.buf.set64(va, 0, 0) else s.buf.set32(va, 0);
				s.relocs.push(new Reloc(va, rk.kind, sym, field + rk.extra));
			}
		}
		return o;
	}

	var weakTags:Array<{sym:Symbol, tag:Int}> = [];
}

// a Unix/COFF archive (.a, .lib): members by offset, symbol index
class Archive {
	public var b:Bytes;
	public var index = new Map<String, Int>(); // symbol -> member offset (of the member's data)
	public var path:String;

	public function new(b:Bytes, path:String) {
		this.b = b;
		this.path = path;
		if (b.getString(0, 8) != "!<arch>\n") throw "hxmc: not an archive: " + path;
		var at = 8;
		var first = true;
		while (at + 60 <= b.length) {
			var name = StringTools.trim(b.getString(at, 16));
			var size = Std.parseInt(StringTools.trim(b.getString(at + 48, 10)));
			var data = at + 60;
			if (name == "/" && first) {
				// the first linker member: big-endian count, offsets, names
				var n = be32(data);
				var p = data + 4 + 4 * n;
				for (k in 0...n) {
					var e = p;
					while (b.get(e) != 0)
						e++;
					var sym = b.getString(p, e - p);
					var memberHeader = be32(data + 4 + 4 * k);
					if (!index.exists(sym)) index.set(sym, memberHeader + 60);
					p = e + 1;
				}
				first = false;
			}
			at = data + size;
			if (at & 1 != 0) at++;
		}
	}

	function be32(at:Int):Int
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);
}
