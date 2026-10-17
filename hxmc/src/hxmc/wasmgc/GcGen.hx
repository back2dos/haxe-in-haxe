package hxmc.wasmgc;

import hxmc.ir.Ir;

// -D hxmc.wasm-gc: the program's IR (after Lower) as a WasmGC module, an
// experiment to compare with the linear-memory target (docs/plans/targets.md,
// "WasmGC"). Only what main and the static initializers reach is emitted.
class GcGen {
	public static function run(prog:Program, out:String, o:Options) {
		var r = new Reach(prog);
		if (Sys.getEnv("HXMC_GC_SURVEY") == "1") {
			r.report();
			return;
		}
		var m = new GcModule(prog, r);
		sys.io.File.saveBytes(out, m.build());
	}
}

// what main and the initializers reach: functions, classes, selectors, host calls
class Reach {
	public final prog:Program;
	public final funcs:Array<FuncInfo> = [];
	public final seen = new Map<FuncInfo, Bool>();
	public final hosts = new Map<String, Int>();
	public final sels = new Map<Int, Bool>();
	public final classes = new Map<ClassInfo, Bool>();
	public final lambdas = new Map<LambdaInfo, Bool>();
	var queue:Array<FuncInfo> = [];

	public function new(prog:Program) {
		this.prog = prog;
		for (f in prog.inits)
			add(f);
		add(prog.main);
		while (queue.length > 0 || pendingDispatch()) {
			while (queue.length > 0)
				scan(queue.pop());
		}
	}

	function add(f:FuncInfo) {
		if (f == null || seen.exists(f)) return;
		seen.set(f, true);
		funcs.push(f);
		queue.push(f);
	}

	function cls(c:ClassInfo) {
		var k = c;
		while (k != null && !classes.exists(k)) {
			classes.set(k, true);
			if (k.ctor != null) add(k.ctor);
			k = k.sup;
		}
	}

	// a selector's implementations in the classes made so far
	var done = new Map<String, Bool>();

	function pendingDispatch():Bool {
		var more = false;
		for (s in sels.keys())
			for (c in classes.keys()) {
				var key = s + ":" + c.id;
				if (done.exists(key)) continue;
				done.set(key, true);
				var m = c.findMethod(prog.selectors[s].name);
				if (m != null && !seen.exists(m)) {
					add(m);
					more = true;
				}
			}
		return more;
	}

	function scan(f:FuncInfo) {
		for (s in f.body)
			stmt(s);
	}

	function stmt(s:Stmt) {
		hxmc.ir.Facts.iterStmt(stmt, ex, s);
	}

	function ex(e:Ex) {
		switch e {
			case ECall(f, _): add(f);
			case ECallDispatch(sel, _, _): sels.set(sel, true);
			case ECallHost(n, _, _): hosts.set(n, (hosts.exists(n) ? hosts.get(n) : 0) + 1);
			case ENewObj(c): cls(c);
			case ENewClos(l, _):
				lambdas.set(l, true);
				add(l.fn);
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
