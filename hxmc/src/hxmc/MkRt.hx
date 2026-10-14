package hxmc;

import haxe.io.Bytes;
import hxmc.Obj;
import hxmc.CoffReader;

// `hxmc --mkrt <out> <inputs...> [-u symbol...] [-x symbol...]` (-x: defined
// by the program, not looked for in the archives): the runtime object of a
// COFF target (Windows), built once on our machine (hxmc/tools/mkrt.sh):
// the runtime's objects and the members of the C library's archives they
// need (as a linker would pick them), COMDAT duplicates dropped, weak
// externals resolved, and the symbols import libraries define recorded as
// imports (DLL and name) instead of keeping the import libraries. The result
// is one Obj written in hxmc's ELF container (ElfWriter), with the imports
// in a .hxmc.imports section, which LinkPE reads at every link.
class MkRt {
	var included:Array<Obj> = [];
	var defined = new Map<String, Bool>();
	var archives:Array<Archive> = [];
	var loaded = new Map<String, Bool>(); // archive path + member offset
	public var imports = new Map<String, {dll:String, name:String, code:Bool}>();
	var weakDefaults = new Map<Symbol, Symbol>();
	var undefinedQueue:Array<String> = [];
	public var arm = false; // the objects are arm64 COFF

	public function new() {}

	public static function main(args:Array<String>) {
		var out = args.shift();
		var m = new MkRt();
		var roots = [];
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			if (a == "-u") roots.push(args[i++]) else if (a == "-x") m.defined.set(args[i++], true) else {
				var b = sys.io.File.getBytes(a);
				if (b.getString(0, 8) == "!<arch>\n") m.archives.push(new Archive(b, a)) else m.add(CoffReader.read(b, 0));
			}
		}
		for (r in roots)
			m.undefinedQueue.push(r);
		m.select();
		var o = m.merge();
		sys.io.File.saveBytes(out, ElfWriter.write(o, m.arm));
		Sys.println('mkrt: ${m.included.length} objects, ${Lambda.count(m.imports)} imports, ${o.sections.length} sections');
	}

	// `hxmc --mkrt-macho <out> <objects...>`: the runtime object of a macOS
	// target: the runtime's Mach-O objects merged (MachOReader) into one Obj
	// in hxmc's ELF container. Nothing else is linked in: what stays
	// undefined comes from libSystem at load time (LinkMachO binds it).
	public static function macho(args:Array<String>) {
		var out = args.shift();
		var m = new MkRt();
		for (a in args) {
			var r = MachOReader.read(sys.io.File.getBytes(a));
			if (r.arm) m.arm = true;
			m.included.push(r.obj);
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
