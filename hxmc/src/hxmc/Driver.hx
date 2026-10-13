package hxmc;

import backend.Ir;
import hxmc.Mir;
import hxmc.Abi;
import hxmc.MirBuild.Unsupported;

// One run of the tool. Functions are compiled per Haxe module (the unit of
// the object cache): each module becomes an object of its own, cached in
// <out>.hxmc/ under a key hashing its Fingerprint (with the tool and the
// target), so a rebuild after an edit compiles only the modules whose code
// can change. The program's data (DataGen) is regenerated every time, and
// everything is linked with the runtime object (Link). Development (hybrid)
// builds instead write the C of what is not compiled natively and link with
// the system's compiler, without the cache.
class Driver {
	var prep:Prep;
	var abi:Abi;
	var o:Options;
	var out:String;
	var native = new Map<FuncInfo, Bool>();
	var reasons = new Map<String, Int>();
	var examples = new Map<String, String>();
	var dumpSet:Null<Map<String, Bool>>;
	var tm = [0.0, 0.0, 0.0, 0.0];
	var slow:Array<{name:String, t:Float}> = [];

	function new(prog:Program, out:String, o:Options) {
		this.o = o;
		this.out = out;
		prep = new Prep(prog);
		abi = Abi.get(o.target);
		if (o.segAlign > 0) abi.segAlign = o.segAlign;
		if (o.pic) abi.reloc = Pic;
		if (o.shared) {
			abi.reloc = Pic;
			abi.output = SharedLibrary;
		}
		if (abi.os == "macos" || abi.os == "windows" && abi.arm) throw "hxmc: target " + abi.name + " is not supported yet";
		dumpSet = o.dump == null ? null : [for (n in o.dump.split(",")) n => true];
	}

	public static function run(prog:Program, out:String, o:Options) {
		var t0 = haxe.Timer.stamp();
		var d = new Driver(prog, out, o);
		var t1 = haxe.Timer.stamp();
		if (o.hybrid) d.hybrid(t0, t1) else d.build(t0, t1);
	}

	// ---- compiling

	// one function into `obj` (with its emitter); false: unsupported (hybrid builds)
	// guards what workers share: the queue and the statistics
	var lock = new sys.thread.Mutex();

	// runs work(0...n) on up to `jobs` threads (the first failure is rethrown)
	function parallel(n:Int, jobs:Int, work:Int->Void) {
		var next = 0;
		var failure:Null<String> = null;
		function run() {
			while (true) {
				lock.acquire();
				var k = next++;
				lock.release();
				if (k >= n || failure != null) return;
				try work(k) catch (e:Dynamic) {
					lock.acquire();
					if (failure == null) failure = Std.string(e);
					lock.release();
					return;
				}
			}
		}
		if (jobs > n) jobs = n;
		if (jobs <= 1) run() else {
			var done = new sys.thread.Lock();
			for (_ in 0...jobs)
				sys.thread.Thread.create(() -> {
					run();
					done.release();
				});
			for (_ in 0...jobs)
				done.wait();
		}
		if (failure != null) throw failure;
	}
	var raRounds = 0;
	var raInsns = 0;
	var raFuncs = 0;

	function compileFunc(fn:FuncInfo, obj:Obj, emit:Target.Emitter, ras:Regalloc.Scratch):Bool {
		var name = prep.funcSym(fn);
		try {
			var s0 = haxe.Timer.stamp();
			var mb = new MirBuild(prep, abi, fn);
			mb.icSym = name + "__ic";
			var mf = mb.build();
			if (o.opt) {
				// to a depth (Fingerprint keys callers with their callees' callees)
				var todo = mb.inlineSites;
				for (_ in 0...Inline.DEPTH) {
					if (todo.length == 0) break;
					var sites = [];
					for (s in todo) {
						var t = ras.templates.get(s.fn);
						if (!ras.templates.exists(s.fn)) {
							var cb = new MirBuild(prep, abi, s.fn);
							cb.icSym = prep.funcSym(s.fn) + "__ic";
							t = try Inline.template(cb, cb.build()) catch (_:Unsupported) null;
							ras.templates.set(s.fn, t);
						}
						if (t != null && s.fn != fn) sites.push({call: s.call, callee: t});
					}
					todo = Inline.run(mf, sites);
				}
			}
			if (o.opt) new Opt(mf).run();
			if (dumpSet != null && dumpSet.exists(name)) Sys.println(mf.dump());
			var layout = Layout.order(mf);
			var s1 = haxe.Timer.stamp();
			var isel = Target.selector(abi);
			var lf = isel.select(mf, layout);
			var s2 = haxe.Timer.stamp();
			var ra = new Regalloc(lf, isel, ras);
			ra.run();
			var s3 = haxe.Timer.stamp();
			emit.func(lf, ra.usedRegs, true);
			var s4 = haxe.Timer.stamp();
			lock.acquire();
			tm[0] += s1 - s0;
			tm[1] += s2 - s1;
			tm[2] += s3 - s2;
			tm[3] += s4 - s3;
			raRounds += ra.rounds;
			raInsns += ra.insns;
			raFuncs++;
			if (o.stats && s4 - s0 > 0.05) slow.push({name: name + " (" + mf.vals.length + " values, " + mf.blocks.length + " blocks)", t: s4 - s0});
			native.set(fn, true);
			lock.release();
			if (mb.icaches > 0) {
				var bss = obj.section(".bss", Bss, 16);
				bss.bssSize = (bss.bssSize + 15) & ~15;
				obj.define(mb.icSym, bss, bss.bssSize, Abi.IC_SIZE * mb.icaches, false);
				bss.bssSize += Abi.IC_SIZE * mb.icaches;
			}
			return true;
		} catch (e:Unsupported) {
			var k = e.msg;
			lock.acquire();
			reasons.set(k, (reasons.exists(k) ? reasons.get(k) : 0) + 1);
			if (!examples.exists(k)) examples.set(k, name);
			lock.release();
			if (!o.hybrid) throw 'hxmc: $name: ${e.msg}';
			return false;
		}
	}

	// a synthetic function (DataGen) into obj
	function compileMir(mf:MFunc, emit:Target.Emitter) {
		var isel = Target.selector(abi);
		var lf = isel.select(mf, Layout.order(mf));
		var ra = new Regalloc(lf, isel);
		ra.run();
		emit.func(lf, ra.usedRegs, true);
	}

	function stats(t0:Float, t1:Float, t2:Float) {
		if (!o.stats) return;
		var n = Lambda.count(native);
		var total = prep.p.funcs.length;
		Sys.println('hxmc: ${n}/${total} functions native (${Math.round(1000 * n / total) / 10}%)');
		var ks = [for (k in reasons.keys()) k];
		ks.sort((a, b) -> reasons.get(b) - reasons.get(a));
		for (k in ks)
			Sys.println('  ${reasons.get(k)}\t$k\t(${examples.get(k)})');
		Sys.println('hxmc: prepare ${ms(t1 - t0)}, codegen ${ms(t2 - t1)} (cpu: mir ${ms(tm[0])}, isel ${ms(tm[1])}, regalloc ${ms(tm[2])}, emit ${ms(tm[3])})');
		Sys.println('hxmc: regalloc: $raFuncs functions, $raRounds rounds, $raInsns instructions');
		slow.sort((a, b) -> a.t < b.t ? 1 : -1);
		for (x in slow.slice(0, 5))
			Sys.println('  ${ms(x.t)}\t${x.name}');
	}

	// ---- the shipped path: per-module objects, cache, own linker

	static function moduleFile(m:String):String {
		var r = new StringBuf();
		for (i in 0...m.length) {
			var c = m.charCodeAt(i);
			r.addChar((c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code) || c == ".".code || c == "_".code ? c : "_".code);
		}
		return r.toString() + ".o";
	}

	// what every key includes: the tool binary (its size and date) and the target
	function toolKey():String {
		var p = Sys.programPath();
		var st = try sys.FileSystem.stat(p) catch (_:Dynamic) null;
		return "hxmc|" + abi.name + "|" + (st == null ? "?" : st.size + "@" + st.mtime.getTime()) + "|";
	}

	// the functions that may be inlined (before the keys: they are part of them)
	function inlineCandidates() {
		if (!o.opt) return;
		var m = new Map<FuncInfo, Bool>();
		for (f in prep.p.funcs)
			if (Inline.candidate(f)) m.set(f, true);
		MirBuild.inlineCands = m;
	}

	function build(t0:Float, t1:Float) {
		inlineCandidates();
		var p = prep.p;
		// modules in the order of their first function
		var order:Array<String> = [];
		var byModule = new Map<String, Array<FuncInfo>>();
		for (f in p.funcs) {
			var m = f.module == null ? "_" : f.module;
			var fs = byModule.get(m);
			if (fs == null) {
				byModule.set(m, fs = []);
				order.push(m);
			}
			fs.push(f);
		}
		var dir = out + ".hxmc";
		if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
		var index = new Map<String, String>();
		var indexPath = dir + "/index";
		if (sys.FileSystem.exists(indexPath))
			for (l in sys.io.File.getContent(indexPath).split("\n")) {
				var sp = l.indexOf(" ");
				if (sp > 0) index.set(l.substr(0, sp), l.substr(sp + 1));
			}
		var tk = toolKey();
		var hits = 0, misses = 0;
		var tWrite = 0.0;
		var keep = new Map<String, Bool>();
		var jobs = o.jobs > 0 ? o.jobs : core.ds.TaskPool.recommendedDomainCount();
		// the modules' keys, and the cached objects that match, in parallel
		// (the threads only read the program); then, in module order, the
		// string literals they found are registered and the index written
		var nm = order.length;
		var paths = [for (m in order) dir + "/" + moduleFile(m)];
		var keys = [for (_ in 0...nm) ""];
		var lits:Array<Array<String>> = [for (_ in 0...nm) null];
		var objs:Array<Obj> = [for (_ in 0...nm) null];
		var s0 = haxe.Timer.stamp();
		parallel(nm, jobs, mi -> {
			var fp = new Fingerprint(prep);
			var text = new StringBuf();
			text.add(tk);
			for (f in byModule.get(order[mi]))
				fp.func(f, text);
			var key = Fingerprint.hash(text.toString());
			keys[mi] = key;
			lits[mi] = fp.newStrings;
			if (index.get(moduleFile(order[mi])) == key && sys.FileSystem.exists(paths[mi])) objs[mi] = ElfReader.read(sys.io.File.getBytes(paths[mi]));
		});
		var tKey = haxe.Timer.stamp() - s0;
		var newIndex = new StringBuf();
		var todo:Array<Int> = [];
		for (mi in 0...nm) {
			var l = lits[mi];
			var k = 0;
			while (k < l.length) {
				prep.addStr(l[k], l[k + 1]);
				k += 2;
			}
			var file = moduleFile(order[mi]);
			keep.set(file, true);
			newIndex.add(file + " " + keys[mi] + "\n");
			if (objs[mi] != null) {
				for (f in byModule.get(order[mi]))
					native.set(f, true);
				hits++;
			} else {
				todo.push(mi);
				misses++;
			}
		}
		// largest modules first, so the last ones to finish are small
		var weight = [for (m in order) 0];
		for (mi in todo)
			for (f in byModule.get(order[mi]))
				weight[mi] += f.body.length + f.locals.length;
		todo.sort((a, b) -> weight[b] - weight[a]);
		parallel(todo.length, jobs, k -> {
			var mi = todo[k];
			var obj = new Obj();
			var emit = Target.emitter(abi, obj);
			var ras = new Regalloc.Scratch(Target.selector(abi));
			for (f in byModule.get(order[mi]))
				compileFunc(f, obj, emit, ras);
			sys.io.File.saveBytes(paths[mi], ElfWriter.write(obj, abi.arm));
			objs[mi] = obj;
		});
		sys.io.File.saveContent(indexPath, newIndex.toString());
		for (f in sys.FileSystem.readDirectory(dir))
			if (StringTools.endsWith(f, ".o") && !keep.exists(f)) sys.FileSystem.deleteFile(dir + "/" + f);
		var t2 = haxe.Timer.stamp();
		stats(t0, t1, t2);
		var data = new Obj();
		var demit = Target.emitter(abi, data);
		new DataGen(prep, abi, data, mf -> compileMir(mf, demit)).run();
		var t3 = haxe.Timer.stamp();
		var rtPath = o.rtObj != null ? o.rtObj : Options.toolDir() + "rt/" + abi.name + "/rt.o";
		if (!sys.FileSystem.exists(rtPath)) throw "hxmc: the runtime object " + rtPath + " is missing (hxmc/tools/mkrt.sh)";
		var rt = ElfReader.read(sys.io.File.getBytes(rtPath));
		var t4 = haxe.Timer.stamp();
		var all = [data].concat(objs).concat([rt]);
		var exe = abi.os == "windows" ? new LinkPE(all, abi.arm).link("mainCRTStartup") : {
			var l = new Link(all, abi);
			l.symbols = !o.strip;
			l.link("_start");
		};
		if (abi.os == "windows" && !StringTools.endsWith(out, ".exe")) out += ".exe";
		sys.io.File.saveBytes(out, exe);
		Sys.command("chmod", ["755", out]);
		if (o.stats) {
			Sys.println('hxmc: modules ${order.length}: ${hits} cached, ${misses} compiled (keys and reading ${ms(tKey)})');
			Sys.println('hxmc: data ${ms(t3 - t2)}, runtime read ${ms(t4 - t3)}, link ${ms(haxe.Timer.stamp() - t4)}');
		}
	}

	// ---- development builds

	function hybrid(t0:Float, t1:Float) {
		var p = prep.p;
		var obj = new Obj();
		var emit = Target.emitter(abi, obj);
		var ras = new Regalloc.Scratch(Target.selector(abi));
		for (fn in p.funcs) {
			var name = prep.funcSym(fn);
			if (o.skip.exists(name) || (o.only != null && !o.only.exists(name))) continue;
			compileFunc(fn, obj, emit, ras);
		}
		var t2 = haxe.Timer.stamp();
		stats(t0, t1, t2);
		// the C of the other functions (it may add string literals), then the data
		for (f in p.funcs)
			if (!native.exists(f)) prep.cBody(f);
		new DataGen(prep, abi, obj, mf -> compileMir(mf, emit)).run();
		sys.io.File.saveBytes(out + ".o", ElfWriter.write(obj, abi.arm));
		sys.io.File.saveContent(out + ".c", CWriter.write(prep, f -> native.exists(f), false));
		var rt = o.rtDir;
		if (rt == null) throw "hxmc: HXMC_RT (the runtime objects) is not set";
		var objs = [for (f in sys.FileSystem.readDirectory(rt)) if (StringTools.endsWith(f, ".o")) rt + "/" + f];
		objs.sort((a, b) -> a < b ? -1 : 1);
		var cc = o.cc.split(" ");
		var hxrt = Sys.getEnv("HXMC_RT_INCLUDE");
		var args = cc.slice(1).concat(["-w", "-fno-strict-aliasing", "-DHXC_NO_SSL", "-DHXC_NO_UV", "-I", hxrt == null ? "hxc/rt" : hxrt, "-no-pie", out + ".c", out + ".o"])
			.concat(objs)
			.concat(["-lm", "-lpthread", "-o", out]);
		if (o.verbose) Sys.println(cc[0] + " " + args.join(" "));
		var code = Sys.command(cc[0], args);
		if (code != 0) throw "hxmc: the C compiler failed";
		if (o.stats) Sys.println('hxmc: link ${ms(haxe.Timer.stamp() - t2)}');
	}

	static function ms(s:Float):String
		return Std.int(s * 1000) + " ms";
}

// The order blocks are laid out in: reverse postorder, the cold blocks (slow
// paths) at the end.
class Layout {
	public static function order(f:MFunc):Array<MBlock> {
		var seen = new Map<Int, Bool>();
		var post = [];
		// iterative DFS: successors pushed in reverse so the first is visited first
		var stack:Array<{b:MBlock, k:Int}> = [{b: f.entry, k: 0}];
		seen.set(f.entry.id, true);
		while (stack.length > 0) {
			var top = stack[stack.length - 1];
			if (top.k < top.b.succs.length) {
				var s = top.b.succs[top.k++];
				if (!seen.exists(s.id)) {
					seen.set(s.id, true);
					stack.push({b: s, k: 0});
				}
			} else {
				post.push(top.b);
				stack.pop();
			}
		}
		post.reverse();
		var hot = [for (b in post) if (!b.cold) b];
		var cold = [for (b in post) if (b.cold) b];
		return hot.concat(cold);
	}
}
