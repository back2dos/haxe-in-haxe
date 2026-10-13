package hxmc;

// A relocatable object in memory, independent of the file format: sections
// of bytes, symbols and relocations. The code generators fill one; the
// writers (ElfWriter, ...) serialize it, the linker (Link) consumes it.
enum abstract SecKind(Int) {
	var Text;
	var Data;
	var RoData;
	var Bss;
	var Tdata;
	var Tbss;
	var InitArray;
	var FiniArray;
}

// relocation kinds (each writer maps them to its format's types)
enum abstract RelKind(Int) to Int {
	var RAbs64; // S + A, 64 bits
	var RAbs32; // S + A, 32 bits (zero-extended)
	var RAbs32S; // S + A, 32 bits (sign-extended)
	var RPc32; // S + A - P, 32 bits
	var RCall32; // a call or jump: S + A - P (ELF PLT32)
	var RTpOff32; // x86-64 local-exec TLS: S - TP + A, signed 32 bits (fs:disp32)
	var RGotPcRel32; // x86-64: G + GOT + A - P (mov reg, [rip + sym@GOTPCREL])
	// arm64
	var RA64Call26; // bl
	var RA64Jump26; // b
	var RA64AdrPage21; // adrp: Page(S + A) - Page(P)
	var RA64AddLo12; // add: (S + A) & 0xfff
	var RA64Ldst8Lo12;
	var RA64Ldst16Lo12;
	var RA64Ldst32Lo12;
	var RA64Ldst64Lo12;
	var RA64Ldst128Lo12;
	var RA64TlsLeHi12; // add xd, xn, #:tprel_hi12:S
	var RA64TlsLeLo12Nc; // add xd, xd, #:tprel_lo12_nc:S
	var RA64GotPage21;
	var RA64GotLo12;
}

class Section {
	public var name:String;
	public var kind:SecKind;
	public var align:Int;
	public var buf = new Buf(1024);
	public var bssSize = 0; // Bss/Tbss: the size (no bytes)
	public var relocs:Array<Reloc> = [];
	public var index = -1; // writers

	public function new(name, kind, align) {
		this.name = name;
		this.kind = kind;
		this.align = align;
	}

	public inline function size():Int
		return kind == Bss || kind == Tbss ? bssSize : buf.len;
}

class Symbol {
	public var name:String;
	public var section:Null<Section>; // null: undefined (defined elsewhere)
	public var offset = 0;
	public var size = 0;
	public var global = true;
	public var func = false;
	public var tls = false;
	public var weak = false;
	public var abs = false; // an absolute value (offset), no section
	public var index = -1; // writers

	public function new(name) {
		this.name = name;
	}
}

class Reloc {
	public var offset:Int;
	public var kind:RelKind;
	public var sym:Symbol;
	public var addend:Int;

	public function new(offset, kind, sym, addend) {
		this.offset = offset;
		this.kind = kind;
		this.sym = sym;
		this.addend = addend;
	}
}

class Obj {
	public var sections:Array<Section> = [];
	public var symbols:Array<Symbol> = [];
	var byName = new Map<String, Symbol>();

	public function new() {}

	public function section(name:String, kind:SecKind, align:Int):Section {
		for (s in sections)
			if (s.name == name) return s;
		var s = new Section(name, kind, align);
		sections.push(s);
		return s;
	}

	// the symbol of that name (undefined until defined)
	public function sym(name:String):Symbol {
		var s = byName.get(name);
		if (s == null) {
			s = new Symbol(name);
			byName.set(name, s);
			symbols.push(s);
		}
		return s;
	}

	public function define(name:String, sec:Section, offset:Int, size = 0, global = true):Symbol {
		var s = sym(name);
		if (s.section != null) throw 'hxmc: symbol $name defined twice';
		s.section = sec;
		s.offset = offset;
		s.size = size;
		s.global = global;
		s.func = sec.kind == Text;
		s.tls = sec.kind == Tdata || sec.kind == Tbss;
		return s;
	}

	public inline function exists(name:String):Bool
		return byName.exists(name);
}
