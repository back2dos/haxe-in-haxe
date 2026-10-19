package hxmc.interp;

#if hxmc.jit
import hxmc.Obj;
import hxmc.ir.Ir;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// `--interp` and `--run` with -D hxmc.mir-run, in a compiler built with
// -D hxmc.jit: the program typed for hxmc (its std, not Eval's), its
// functions encoded for the Mir interpreter (InterpGen: all but the
// runtime's, which is the compiler's own), linked into the running compiler
// (macro.Loader: the std's types and statics are the compiler's where the
// program has them as the compiler does, the others new) and run here: its
// static initializers, then main, with the program's arguments.
@:access(hxmc.Driver)
@:access(hxmc.DataGen)
@:access(hxmc.ir.Facts)
@:access(hxmc.ir.Lower)
@:access(hxmc.macro.Guest)
@:access(hxmc.macro.Loader)
@:access(hxmc.rt.Start)
@:access(hxmc.rt.Gc)
class MirRun {
	// (-D turns the dash into an underscore)
	public static inline var DEFINE = "hxmc.mir_run";

	// the program's arguments (--run's after its module)
	static var args:Array<String> = [];

	// the command line with -D hxmc.mir-run: --interp and --run as an hxmc
	// compile that ends here (generateHook: run); null without it
	public static function rewrite(argv:Array<String>):Null<Array<String>> {
		var on = false;
		for (i in 0...argv.length - 1)
			if ((argv[i] == "-D" || argv[i] == "--define") && (argv[i + 1] == "hxmc.mir-run" || argv[i + 1] == DEFINE)) on = true;
		if (!on) return null;
		var out = [];
		var i = 0;
		while (i < argv.length) {
			var a = argv[i];
			if (a == "--interp") {
				i++;
				continue;
			}
			if (a == "--run" && i + 1 < argv.length) {
				out.push("-main");
				out.push(argv[i + 1]);
				args = argv.slice(i + 2);
				break;
			}
			out.push(a);
			i++;
		}
		return out.concat(["--custom-target", "hxmc", "-D", "hxmc.interp"]);
	}

	public static function run(com:context.Common.CommonContext) {
		if (com.main.mainPath == null) throw "a program needs an entry point: -main <module>";
		var mainClass = context.Common.getEntryPoint(com).cls;
		var o = Options.read(com);
		var abi = Abi.get(o.target);
		if (abi.name != "linux-x86_64" || o.libc != null) throw "-D hxmc.mir-run: linux-x86_64 (static) only, as the loader";
		abi.framePointers = abi.arm || o.framePointers; // (as Driver)
		hxmc.ir.Lower.targetOs = abi.osCode();
		hxmc.ir.Lower.targetArm = abi.arm ? 1 : 0;
		hxmc.ir.Lower.targetCode = MirBuild.targetCode(abi);
		hxmc.ir.Lower.targetPlatform = abi.platformCode();
		hxmc.ir.Lower.bounds = o.bounds;
		hxmc.ir.Lower.resources = com.resources.fold((name, data, acc:Array<{name:String, data:String}>) -> [{name: name, data: codegen.Codegen.bytesSerialize(data)}].concat(acc), []);
		var t0 = haxe.Timer.stamp();
		var l = new hxmc.ir.Lower();
		var prog = hxmc.ir.Lower.program(mainClass, com.types, com.basic, l);
		// (what a native build keeps: reflection sees the same methods)
		hxmc.ir.Reach.run(prog, o.stats);
		var d = new Driver(prog, "", o);
		d.inlineCandidates();
		var prep = d.prep;
		var e = prep.e;
		// (the runtime's functions are the compiler's, but those it lacks: a
		// runtime function is made when something calls it, @:hxmc.host)
		var host = hxmc.macro.Loader.hostSyms();
		InterpGen.emulatedTls = new Map();
		InterpGen.nativeTls = s -> {
			var h = host.get(s);
			h != null && h.k == "l";
		};
		// (and those whose source the program's defines change: -D hxmc.native-array-outofbounds)
		var ownRuntime = o.bounds != 0 ? ["hxmc.rt.Dyn" => true, "hxmc.rt.NArray" => true] : new Map<String, Bool>();
		var funcs = [for (f in prog.funcs) if (!hxmc.macro.Guest.runtime(f) || !host.exists(e.symbol(f)) || ownRuntime.exists(f.module)) f];
		// the string literals (as Driver registers them)
		for (f in funcs) {
			var fp = new Fingerprint(prep, null);
			fp.func(f);
			var k = 0;
			while (k < fp.newStrings.length) {
				prep.addStr(fp.newStrings[k], fp.newStrings[k + 1]);
				k += 2;
			}
		}
		var obj = new Obj();
		var emit = Target.emitter(abi, obj);
		var ras = new Regalloc.Scratch(Target.selector(abi));
		for (f in funcs)
			d.compileFunc(f, obj, emit, ras);
		var dg = new DataGen(prep, abi, obj, mf -> d.compileMir(mf, emit, obj));
		dg.strings();
		for (s in prog.sigs) {
			d.compileMir(dg.dynTrampoline(s), emit, obj);
			d.compileMir(dg.boundTrampoline(s), emit, obj);
		}
		dg.allocStubs([], emit);
		dg.stubs([], emit);
		dg.cstrLiterals([]);
		dg.emptyArrays([]);
		var facts:Dynamic = hxmc.macro.Guest.facts(com, prog, e, l, mainClass);
		(facts.entries : Array<Dynamic>).push({name: "main", sym: e.symbol(prog.main)});
		unshare(facts, host, l, e, com);
		var t1 = haxe.Timer.stamp();
		setArgs();
		var b = hxmc.macro.Loader.loadObj(obj, facts);
		if (o.stats)
			Sys.println('hxmc mir-run: ${funcs.length} functions, compiled ${Std.int((t1 - t0) * 1000)} ms, loaded ${Std.int((haxe.Timer.stamp() - t1) * 1000)} ms');
		var main = b.entries.get("main");
		try {
			Mem.call0(main);
		} catch (e:Dynamic) {
			// (as the program would: hxmc.rt.Start's rt_throw without a handler)
			hxmc.rt.Gc.uncaught("Uncaught exception: ", e);
			Sys.exit(1);
		}
	}

	// which of the std's types stay the compiler's own (Guest.facts: those the
	// compiler has): only those with the compiler's layout, that no new class
	// extends, whose supertypes are shared (an instance test is a type index
	// in a class's span: a new class has no place in the compiler's); a type
	// not shared has its statics and initializer of its own
	static function unshare(facts:Dynamic, host:Map<String, {k:String, v:Int}>, l:hxmc.ir.Lower, e:hxmc.ir.Facts, com:context.Common.CommonContext) {
		var types:Array<Dynamic> = facts.types;
		var fids = new Map<String, Int>();
		for (f in (facts.fields : Array<Dynamic>)) {
			var h = host.get(f.sym);
			if (h != null && h.k == "a") fids.set(f.name, h.v);
		}
		var bySym = new Map<String, Dynamic>();
		for (t in types)
			bySym.set(t.sym, t);
		inline function shared(sym:Dynamic):Bool {
			var t = bySym.get(sym);
			return t != null && t.share == true;
		}
		for (t in types) {
			if (t.share != true) continue;
			var h = host.get(t.sym);
			if (h == null || h.k != "a") continue; // (new anyway)
			var ok = true;
			for (f in (t.fields : Array<Dynamic>))
				if (!fids.exists(f.name)) ok = false;
			if (ok && hxmc.macro.Loader.sameLayout(h.v, t, fids) != null) ok = false;
			if (!ok) t.share = false;
		}
		var changed = true;
		while (changed) {
			changed = false;
			for (t in types) {
				if (t.tk != "TK_CLASS" && t.tk != "TK_INTERFACE" && t.tk != "TK_CTOR") continue;
				var sup:Null<String> = t.sup;
				if (sup == null || sup == "TY_Object" || !bySym.exists(sup)) continue;
				// a new class over a shared one: that one is new too; a shared one over a new one: new
				if (t.share != true && shared(sup)) {
					bySym.get(sup).share = false;
					changed = true;
				} else if (t.share == true && !shared(sup)) {
					t.share = false;
					changed = true;
				}
			}
		}
		// the statics of the types no longer shared
		var own = new Map<String, Bool>();
		for (t in com.types)
			switch t {
				case TClassDecl(c):
					var ci = l.classes.get(c);
					if (ci == null || ci.tindex < 0 || hxmc.macro.Guest.runtimeClass(c)) continue;
					var sym = e.typeNames[ci.tindex];
					if (!bySym.exists(sym) || shared(sym)) continue;
					for (cf in c.clOrderedStatics) {
						var g = l.staticVars.get(cf);
						if (g != null) own.set(e.globalNames[g], true);
					}
				case _:
			}
		for (g in (facts.globals : Array<Dynamic>))
			if (own.exists(g.name)) g.share = false;
	}

	// the runtime's argc and argv the program reads (Sys.args): the compiler's
	// path, then the program's arguments
	static function setArgs() {
		var all = [Sys.programPath()].concat(args);
		var a = LibC.malloc(((all.length + 1) * 8 : I64));
		for (i in 0...all.length) {
			var bs = haxe.io.Bytes.ofString(all[i]);
			var s = LibC.malloc(((bs.length + 1) : I64));
			for (k in 0...bs.length)
				Mem.setI8(s, k, bs.get(k));
			Mem.setI8(s, bs.length, 0);
			Mem.setPtr(a, 8 * i, s);
		}
		Mem.setPtr(a, 8 * all.length, Ptr.nil());
		hxmc.rt.Start.argc = all.length;
		hxmc.rt.Start.argv = a;
	}
}
#end
