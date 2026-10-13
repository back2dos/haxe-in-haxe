package hxmc;

import backend.Ir;
import hxmc.Mir;
import hxmc.MirBuild.Unsupported;

// One run of the tool: lowers every function to machine code and writes
// the output (development builds: an object, the C of the rest, linked by
// the system's compiler).
class Driver {
	public static function run(prog:Program, out:String, o:Options) {
		var t0 = haxe.Timer.stamp();
		var prep = new Prep(prog);
		var abi = Abi.get(o.target);
		if (abi.name != "linux-x86_64") throw "hxmc: only linux-x86_64 so far";
		var t1 = haxe.Timer.stamp();
		var obj = new Obj();
		var emit = new hxmc.x64.Emit(obj);
		var bss = obj.section(".bss", Bss, 16);
		var native = new Map<FuncInfo, Bool>();
		var reasons = new Map<String, Int>();
		var examples = new Map<String, String>();
		var count = 0;
		var dumpSet = o.dump == null ? null : [for (n in o.dump.split(",")) n => true];
		var tm = [0.0, 0.0, 0.0, 0.0, 0.0];
		var slow:Array<{name:String, t:Float}> = [];
		for (fn in prog.funcs) {
			var name = prep.funcSym(fn);
			if (o.skip.exists(name) || (o.only != null && !o.only.exists(name))) continue;
			count++;
			var mf:MFunc = null;
			try {
				var s0 = haxe.Timer.stamp();
				var mb = new MirBuild(prep, abi, fn);
				mb.icSym = name + "__ic";
				mf = mb.build();
				var layout = Layout.order(mf);
				var s1 = haxe.Timer.stamp();
				var isel = new hxmc.x64.Isel();
				var lf = isel.select(mf, layout);
				var s2 = haxe.Timer.stamp();
				var ra = new Regalloc(lf, isel);
				ra.run();
				var s3 = haxe.Timer.stamp();
				if (dumpSet != null && dumpSet.exists(name)) Sys.println(mf.dump());
				emit.func(lf, ra.usedRegs, true);
				var s4 = haxe.Timer.stamp();
				tm[0] += s1 - s0;
				tm[1] += s2 - s1;
				tm[2] += s3 - s2;
				tm[3] += s4 - s3;
				if (o.stats && s4 - s0 > 0.05) slow.push({name: name + " (" + mf.vals.length + " values, " + mf.blocks.length + " blocks)", t: s4 - s0});
				if (mb.icaches > 0) {
					bss.bssSize = (bss.bssSize + 15) & ~15;
					obj.define(mb.icSym, bss, bss.bssSize, Abi.IC_SIZE * mb.icaches, false);
					bss.bssSize += Abi.IC_SIZE * mb.icaches;
				}
				native.set(fn, true);
			} catch (e:Unsupported) {
				var k = e.msg;
				reasons.set(k, (reasons.exists(k) ? reasons.get(k) : 0) + 1);
				if (!examples.exists(k)) examples.set(k, name);
				if (!o.hybrid) throw 'hxmc: $name: ${e.msg}';
			}
		}
		var t2 = haxe.Timer.stamp();
		var n = Lambda.count(native);
		if (o.stats) {
			Sys.println('hxmc: ${n}/${prog.funcs.length} functions native (${Math.round(1000 * n / prog.funcs.length) / 10}%)');
			var ks = [for (k in reasons.keys()) k];
			ks.sort((a, b) -> reasons.get(b) - reasons.get(a));
			for (k in ks)
				Sys.println('  ${reasons.get(k)}\t$k\t(${examples.get(k)})');
			Sys.println('hxmc: prepare ${ms(t1 - t0)}, codegen ${ms(t2 - t1)} (mir ${ms(tm[0])}, isel ${ms(tm[1])}, regalloc ${ms(tm[2])}, emit ${ms(tm[3])})');
			slow.sort((a, b) -> a.t < b.t ? 1 : -1);
			for (x in slow.slice(0, 10))
				Sys.println('  ${ms(x.t)}\t${x.name}');
		}
		if (!o.hybrid) throw "hxmc: only development (hybrid) builds so far: -D hxmc.hybrid";
		sys.io.File.saveBytes(out + ".o", ElfWriter.write(obj, false));
		sys.io.File.saveContent(out + ".c", CWriter.write(prep, f -> native.exists(f), true));
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
