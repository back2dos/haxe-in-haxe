package hxmc;

import haxe.io.Bytes;
import hxmc.Obj;
import hxmc.CoffReader;

// `hxmc --mkrt <out> <inputs...> [-u symbol...] [-x symbol...] [-i archive...]
// [-U file]` (-x: defined by the program, not looked for in the archives; -i:
// an archive only the imports of which are taken; -U: the names left
// undefined are written to file): the runtime object of a
// COFF target (Windows), built once on our machine (hxmc/c/mkrt.sh):
// the runtime's objects and the members of the C library's archives they
// need (as a linker would pick them), COMDAT duplicates dropped, weak
// externals resolved, and the symbols import libraries define recorded as
// imports (DLL and name) instead of keeping the import libraries. The result
// is one Obj written in hxmc's ELF container (ElfWriter), with the imports
// in a .hxmc.imports section, which LinkPE reads at every link.
// The objects of sys.ssl and libuv (ssl.o, uv.o; mkrt.sh) are built the same
// way from their own objects and archives, with the C library's archives as
// -i: what they need of the C library besides imports stays undefined (-U)
// and is added to the runtime object's roots, so the two never both hold a
// member of the C library.
class MkRt {
	var included:Array<Obj> = [];
	var defined = new Map<String, Bool>();
	var archives:Array<Archive> = [];
	var loaded = new Map<String, Bool>(); // archive path + member offset
	public var imports = new Map<String, {dll:String, name:String, code:Bool}>();
	var weakDefaults = new Map<Symbol, Symbol>();
	var undefinedQueue:Array<String> = [];
	var importsOnly = new Map<Archive, Bool>();
	var comdatSecs = new Map<Section, Bool>();
	public var arm = false; // the objects are arm64 COFF

	public function new() {}

	public static function main(args:Array<String>) {
		var out = args.shift();
		var m = new MkRt();
		var roots = [];
		var undefOut = null;
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			if (a == "-u") roots.push(args[i++]) else if (a == "-x") m.defined.set(args[i++], true) else if (a == "-U") undefOut = args[i++] else if (a == "-i") {
				var p = args[i++];
				var ar = new Archive(sys.io.File.getBytes(p), p);
				m.archives.push(ar);
				m.importsOnly.set(ar, true);
			} else {
				var b = sys.io.File.getBytes(a);
				if (b.getString(0, 8) == "!<arch>\n") m.archives.push(new Archive(b, a)) else m.add(CoffReader.read(b, 0));
			}
		}
		for (r in roots)
			m.undefinedQueue.push(r);
		m.select();
		var weak = [for (w in m.weakDefaults.keys()) w.name => true];
		for (r in roots)
			if (!m.defined.exists(r) && !m.imports.exists(r) && !weak.exists(r)) throw "mkrt: " + r + " is defined nowhere (are the C library's archives among the inputs?)";
		if (undefOut != null) sys.io.File.saveContent(undefOut, m.undefinedNames().join("\n") + "\n");
		var o = m.merge();
		sys.io.File.saveBytes(out, ElfWriter.write(o, m.arm));
		Sys.println('mkrt: ${m.included.length} objects, ${Lambda.count(m.imports)} imports, ${o.sections.length} sections');
	}

	// ---- the program's own COFF objects and archives (LinkInputs)

	public function markDefined(name:String)
		defined.set(name, true);

	public function addArchive(a:Archive)
		archives.push(a);

	public function addCoff(r:{obj:Obj, reader:CoffReader})
		add(r);

	// takes the archive members that define `roots` (or what taken members need)
	public function selectFor(roots:Array<String>) {
		for (r in roots)
			undefinedQueue.push(r);
		select();
	}

	public function mergeObj():Obj
		return merge();

	// the names the included objects refer to that nothing included defines or imports
	function undefinedNames():Array<String> {
		var weak = [for (w in weakDefaults.keys()) w.name => true];
		var seen = new Map<String, Bool>();
		var r = [];
		for (o in included)
			for (sym in o.symbols)
				if (sym.global && sym.section == null && !sym.abs && !defined.exists(sym.name) && !imports.exists(sym.name) && !weak.exists(sym.name)
					&& !seen.exists(sym.name)) {
					seen.set(sym.name, true);
					r.push(sym.name);
				}
		r.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return r;
	}

	// `hxmc --mkrt-macho <out> <objects and archives...>`: the runtime object
	// of a macOS target: the runtime's Mach-O objects merged (MachOReader)
	// into one Obj in hxmc's ELF container, with the members of the archives
	// (GNU format: mbedtls and libuv for ssl.o and uv.o) the objects need, as
	// a linker picks them. Nothing else is linked in: what stays undefined
	// comes from libSystem at load time (LinkMachO binds it).
	public static function macho(args:Array<String>) {
		var out = args.shift();
		var m = new MkRt();
		function addMacho(b:Bytes) {
			var r = MachOReader.read(b);
			if (r.arm) m.arm = true;
			m.included.push(r.obj);
			for (sym in r.obj.symbols)
				if (sym.global && (sym.section != null || sym.abs)) m.defined.set(sym.name, true);
			for (sym in r.obj.symbols)
				if (sym.global && sym.section == null && !sym.abs) m.undefinedQueue.push(sym.name);
		}
		for (a in args) {
			var b = sys.io.File.getBytes(a);
			if (b.getString(0, 8) == "!<arch>\n") m.archives.push(new Archive(b, a)) else addMacho(b);
		}
		while (m.undefinedQueue.length > 0) {
			var name = m.undefinedQueue.pop();
			if (m.defined.exists(name)) continue;
			for (ar in m.archives) {
				// (the index has the Mach-O names, with their leading underscore)
				var at = ar.index.get("_" + name);
				if (at == null) continue;
				var key = ar.path + ":" + at;
				if (m.loaded.exists(key)) continue;
				m.loaded.set(key, true);
				addMacho(ar.member(at));
				break;
			}
		}
		var o = m.merge();
		sys.io.File.saveBytes(out, ElfWriter.write(o, m.arm));
		Sys.println('mkrt: ${m.included.length} objects, ${o.sections.length} sections');
	}

	function add(r:{obj:Obj, reader:CoffReader}) {
		var o = r.obj;
		if (r.reader.isArm) arm = true;
		// COMDAT sections already defined by an included object are dropped
		var drop = new Map<Section, Bool>();
		for (s => c in r.reader.comdat)
			if (c.sym != null && defined.exists(c.sym)) drop.set(s, true);
		for (s => c in r.reader.comdat)
			if (c.assoc != null && drop.exists(c.assoc)) drop.set(s, true);
		if (drop.keys().hasNext()) {
			o.sections = [for (s in o.sections) if (!drop.exists(s)) s];
			for (sym in o.symbols)
				if (sym.section != null && drop.exists(sym.section)) {
					// becomes a reference to the kept definition
					sym.section = null;
					sym.offset = 0;
				}
		}
		for (s => _ in r.reader.comdat)
			comdatSecs.set(s, true);
		for (w => d in r.reader.weakDefaults)
			weakDefaults.set(w, d);
		included.push(o);
		for (sym in o.symbols)
			if (sym.global && (sym.section != null || sym.abs) && !sym.weak) defined.set(sym.name, true);
		for (sym in o.symbols)
			if (sym.global && sym.section == null && !sym.abs) undefinedQueue.push(sym.name);
	}

	function select() {
		while (undefinedQueue.length > 0) {
			var name = undefinedQueue.pop();
			if (defined.exists(name) || imports.exists(name)) continue;
			for (a in archives) {
				var at = a.index.get(name);
				if (at == null) continue;
				if (importsOnly.exists(a) && !CoffReader.isShortImport(a.b, at)) continue;
				var key = a.path + ":" + at;
				if (loaded.exists(key)) continue;
				loaded.set(key, true);
				if (CoffReader.isShortImport(a.b, at)) {
					var imp = CoffReader.shortImport(a.b, at);
					var rec = {dll: imp.dll, name: imp.name, code: imp.code};
					imports.set("__imp_" + imp.sym, rec);
					if (imp.code) imports.set(imp.sym, rec);
				} else add(CoffReader.read(a.b, at));
				break;
			}
		}
	}

	function merge():Obj {
		var o = new Obj();
		var globals = new Map<String, Symbol>();
		for (x in included)
			for (s in x.symbols)
				if (s.global && (s.section != null || s.abs)) {
					var prev = globals.get(s.name);
					if (prev == null || prev.weak && !s.weak) globals.set(s.name, s);
				}
		// weak externals without a definition become their default (by name:
		// the references of other objects are other Symbol objects)
		var alias = new Map<String, Symbol>();
		for (w => d in weakDefaults)
			if (!globals.exists(w.name) && !imports.exists(w.name) && d != null) alias.set(w.name, d);
		// one symbol per global name; locals stay per object
		var names = new Map<String, Symbol>();
		var localMap = new Map<Symbol, Symbol>();
		function local(t:Symbol):Symbol {
			var l = localMap.get(t);
			if (l == null) {
				l = t;
				localMap.set(t, l);
				o.symbols.push(l);
			}
			return l;
		}
		function canon(s:Symbol):Symbol {
			var n = 0;
			while (s.global && alias.exists(s.name) && n++ < 16)
				s = alias.get(s.name);
			if (!s.global) return local(s);
			var c = names.get(s.name);
			if (c != null) return c;
			var g = globals.get(s.name);
			c = new Symbol(s.name);
			if (g != null) {
				c.section = g.section;
				c.offset = g.offset;
				c.abs = g.abs;
				c.size = g.size;
				c.func = g.func;
				// a COMDAT definition (MinGW's .refptr.*) may be in rt.o and
				// in ssl.o or uv.o alike: weak, the linker keeps one
				if (comdatSecs.exists(g.section)) c.weak = true;
			}
			names.set(s.name, c);
			o.symbols.push(c);
			return c;
		}
		for (x in included) {
			for (s in x.sections) {
				o.sections.push(s);
				for (r in s.relocs)
					r.sym = canon(r.sym);
			}
		}
		for (n => _ in globals)
			canon(globals.get(n));
		// aliases stay reachable by their own name (the program may refer to
		// one, e.g. _setjmp): a second name of a definition, or the import
		for (n => _ in alias) {
			if (names.exists(n)) continue;
			var t = alias.get(n);
			var k = 0;
			while (t.global && alias.exists(t.name) && k++ < 16)
				t = alias.get(t.name);
			var g = t.global ? globals.get(t.name) : t;
			if (g != null && (g.section != null || g.abs)) {
				var c = new Symbol(n);
				c.section = g.section;
				c.offset = g.offset;
				c.abs = g.abs;
				c.func = g.func;
				names.set(n, c);
				o.symbols.push(c);
			} else if (imports.exists(t.name)) imports.set(n, imports.get(t.name));
		}
		// the imports, as text: dll, symbol, imported name, code or data
		var info = new Section(".hxmc.imports", RoData, 1);
		var keys = [for (k in imports.keys()) k];
		keys.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		for (k in keys) {
			var i = imports.get(k);
			info.buf.str(i.dll + "\t" + k + "\t" + i.name + "\t" + (k.indexOf("__imp_") == 0 ? "data" : "code") + "\n");
		}
		o.sections.push(info);
		return o;
	}
}
