package hxmc.wasmgc;

import hxmc.ir.Ir;

// -D hxmc.wasm-gc: the program's IR (after Lower) as a WasmGC module, an
// experiment to compare with the linear-memory target (docs/plans/targets.md,
// "WasmGC"). What is emitted is what the program-wide reachability keeps
// (hxmc.ir.Reach, as for linear memory: method-level, by name), the runtime's
// exports where this target's code calls them (runtimeCalls).
class GcGen {
	// HXMC_GC_SURVEY=1: what is emitted, then what the module would lack (each
	// unsupported construct, the functions with it); =2: also the module
	// written, those functions trapping (to measure the rest)
	public static function run(prog:Program, out:String, o:Options) {
		// (twice: then over the bodies as emitted, without what IrOpt inlined everywhere)
		var calls:hxmc.ir.Reach.RuntimeCalls = {ex: runtimeCalls, stmt: s -> s.match(SAnonSet(_)) ? "gc_anon_set" : null};
		hxmc.ir.Reach.run(prog, o.stats, calls);
		var u = new Uses(prog, o.opt);
		hxmc.ir.Reach.run(prog, o.stats, calls, f -> u.bodies.get(f).body);
		u.scan();
		var survey = Sys.getEnv("HXMC_GC_SURVEY");
		if (survey != "1" && survey != "2") {
			sys.io.File.saveBytes(out, new GcModule(prog, u).build());
			return;
		}
		u.report();
		GcModule.survey = new Map();
		var bytes = try new GcModule(prog, u).build() catch (e:Dynamic) {
			GcModule.note(Std.string(e), "(the module)");
			null;
		}
		var ks = [for (k in GcModule.survey.keys()) k];
		ks.sort(Reflect.compare);
		Sys.println('unsupported (${ks.length}):');
		for (k in ks) {
			var fs = GcModule.survey.get(k);
			Sys.println('  $k: ${fs.length} (${fs.slice(0, 4).join(", ")}${fs.length > 4 ? ", ..." : ""})');
		}
		if (survey == "2" && bytes != null) sys.io.File.saveBytes(out, bytes);
	}

	// the runtime's exports this target's code calls for an expression
	// (FuncGen: structural access it does not know the layout of, enum comparisons)
	static function runtimeCalls(e:Ex):Null<String>
		return switch e {
			case EAnonGet(_) | ECallAnon(_): "gc_anon_get";
			case ECallHost("hxmc_rt_gc_W_enumEq", _, _): "gc_dyn_eq";
			case _: null;
		}
}

// What the emitted functions use: each one's body as emitted (IrOpt: inlined,
// objects scalar-replaced), the host functions it calls, the classes it
// makes (or has the class value of), the selectors it dispatches on, the
// closures and anonymous structures it makes
class Uses {
	public final prog:Program;
	public final funcs:Array<FuncInfo> = [];
	public final hosts = new Map<String, Int>();
	public final sels = new Map<Int, Bool>();
	public final classes = new Map<ClassInfo, Bool>();
	public final lambdas = new Map<LambdaInfo, Bool>();
	public final shapes = new Map<ShapeInfo, Bool>();
	public final bodies = new Map<FuncInfo, {body:Array<Stmt>, locals:Array<Local>}>();

	public function new(prog:Program, optimize:Bool) {
		this.prog = prog;
		var opt = new IrOpt();
		for (f in prog.funcs)
			bodies.set(f, opt.run(f, optimize));
	}

	// (the functions the program keeps: what they use)
	public function scan() {
		for (f in prog.funcs) {
			funcs.push(f);
			for (s in bodies.get(f).body)
				stmt(s);
		}
	}

	function cls(c:ClassInfo) {
		var k = c;
		while (k != null && !classes.exists(k)) {
			classes.set(k, true);
			k = k.sup;
		}
	}

	function stmt(s:Stmt)
		hxmc.ir.Facts.iterStmt(stmt, ex, s);

	function ex(e:Ex) {
		switch e {
			case ECallDispatch(sel, _, _): sels.set(sel, true);
			case ECallHost(n, args, _):
				hosts.set(n, (hosts.exists(n) ? hosts.get(n) : 0) + 1);
				if (n == "Type_createEmptyInstance") switch args[0] {
					case EType(TRClass(c)): cls(c);
					case _:
				}
			case ENewObj(c): cls(c);
			case ENewAnon(s, _): shapes.set(s, true);
			case EType(TRClass(c)) if (!c.isInterface): cls(c);
			case ENewClos(l, _): lambdas.set(l, true);
			case _:
		}
		hxmc.ir.Facts.iterEx(ex, e);
	}

	public function report() {
		Sys.println('wasm-gc survey: ${funcs.length} functions, ${Lambda.count(classes)} classes, ${Lambda.count(sels)} selectors, ${Lambda.count(lambdas)} closures');
		var mods = new Map<String, Int>();
		for (f in funcs)
			mods.set(f.module, (mods.exists(f.module) ? mods.get(f.module) : 0) + 1);
		var ms = [for (k in mods.keys()) k];
		ms.sort(Reflect.compare);
		for (m in ms)
			Sys.println('  module $m: ${mods.get(m)}');
		var hs = [for (k in hosts.keys()) k];
		hs.sort(Reflect.compare);
		Sys.println('host calls (${hs.length}):');
		for (h in hs)
			Sys.println('  $h ${hosts.get(h)}');
	}
}
