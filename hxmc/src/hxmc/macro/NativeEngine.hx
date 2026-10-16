package hxmc.macro;

#if hxmc.jit
import core.TType;
import core.TFunctions;
import macros.MacroApi.CompilerApi;
import macros.eval.EvalContext;
import macros.eval.EvalValue.Value;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;
import hxmc.macro.Loader.Bundle;

// The macro engine of `-D hxmc.macros=native|verify` (HaxeMain installs it
// in a compiler built with -D hxmc.jit): Eval for everything, except macro
// calls that run natively. A macro function is compiled on its first call
// (Guest, in a child process; then Loader) and called with its arguments
// converted (Bridge); what cannot be compiled, loaded or converted runs on
// Eval. verify runs both engines for each call, Eval's result being the one
// used, compares the results (the values, positions included) and errors,
// and reports mismatches and fallbacks.
@:access(hxmc.macro.Bridge)
class NativeEngine extends macros.MacroEngine.EvalEngine {
	public var verify = false;
	var types:Array<ModuleType> = [];
	var com:Null<context.Common.CommonContext> = null;
	var compiled = new Map<String, Null<{bundle:Bundle, entry:Ptr}>>();
	var dir:String;
	var ncompiled = 0;
	// -D hxmc.macros=native or verify (else this is Eval: set when the macro context is created)
	public var enabled = false;
	// statistics (printed at exit with HXMC_MACRO_STATS=1 or in verify mode)
	public var calls = 0;
	public var native = 0;
	public var matched = 0;
	public var mismatched = 0;
	public var fallbacks = 0;
	public var tNative = 0.0;
	public var tEval = 0.0;
	public var tCompile = 0.0;

	public function new() {
		super();
		dir = haxe.io.Path.join([Sys.getEnv("TMPDIR") != null ? Sys.getEnv("TMPDIR") : "/tmp", "hxmc-macros-" + Std.string(Std.int(Sys.time() * 1000) % 1000000000) + "-" + Std.string(Std.random(1 << 30))]);
	}

	function note(s:String)
		if (verify || Sys.getEnv("HXMC_MACRO_STATS") == "1") Sys.stderr().writeString("hxmc.macros: " + s + "\n");

	override public function create(com:context.Common.CommonContext, api:CompilerApi, isMacro:Bool, args:Array<String>):Context {
		this.com = com;
		var m = core.Define.rawDefined(com.defines, "hxmc.macros") ? core.Define.rawDefinedValue(com.defines, "hxmc.macros") : "eval";
		enabled = m == "native" || m == "verify";
		verify = m == "verify";
		return super.create(com, api, isMacro, args);
	}

	override public function addTypes(ctx:Context, types:Array<ModuleType>, ready:ModuleType->Void):Void {
		super.addTypes(ctx, types, ready);
		this.types = types;
	}

	function findClass(path:Array<String>):Null<TClass> {
		var name = path.join(".");
		for (t in types)
			switch t {
				case TClassDecl(c) if (core.Globals.sTypePath(c.clPath) == name): return c;
				case _:
			}
		return null;
	}

	function findEnum(name:String):Null<TEnum> {
		for (t in types)
			switch t {
				case TEnumDecl(e) if (core.Globals.sTypePath(e.ePath) == name): return e;
				case _:
			}
		return null;
	}

	override public function callPath(ctx:Context, path:Array<String>, f:String, vl:Array<Value>, api:CompilerApi):Null<Value> {
		if (!enabled) return super.callPath(ctx, path, f, vl, api);
		if (ctx.hadError) return null;
		calls++;
		var key = path.join(".") + "." + f;
		var c = compiled.exists(key) ? compiled.get(key) : compile(key, path, f);
		if (c == null) {
			fallbacks++;
			return super.callPath(ctx, path, f, vl, api);
		}
		if (!verify) {
			var t0 = haxe.Timer.stamp();
			var r = runNative(ctx, c, vl, api);
			tNative += haxe.Timer.stamp() - t0;
			switch r {
				case Ok(v):
					native++;
					return v;
				case Failed(msg, e) if (e == null):
					// (unsupported at the boundary: Eval runs it instead)
					fallbacks++;
					note(key + ": " + msg + ": on Eval");
					return super.callPath(ctx, path, f, vl, api);
				case Failed(_, e):
					native++;
					throw e;
			}
		}
		// verify: Eval's result is the one used
		var t0 = haxe.Timer.stamp();
		var ev:Null<Value> = null, eerr:Null<Dynamic> = null;
		try ev = super.callPath(ctx, path, f, vl, api) catch (e:Dynamic) eerr = e;
		tEval += haxe.Timer.stamp() - t0;
		var t1 = haxe.Timer.stamp();
		var r = runNative(ctx, c, vl, api);
		tNative += haxe.Timer.stamp() - t1;
		switch r {
			case Failed(msg, e) if (e == null):
				fallbacks++;
				note(key + ": " + msg + ": on Eval");
			case Failed(msg, e):
				native++;
				if (eerr != null) matched++ else {
					mismatched++;
					note(key + ": MISMATCH: native failed (" + msg + "), Eval did not");
				}
			case Ok(nv):
				native++;
				if (eerr != null) {
					mismatched++;
					note(key + ": MISMATCH: Eval failed (" + Std.string(eerr) + "), native did not");
				} else {
					var d = diff(ev, nv, "");
					if (d == null) matched++ else {
						mismatched++;
						note(key + ": MISMATCH at " + d);
					}
				}
		}
		if (eerr != null) throw eerr;
		return ev;
	}

	public function report() {
		if (calls == 0) return;
		note('$calls macro calls: $native native (${matched} matched, ${mismatched} mismatched), $fallbacks on Eval; compile ${ms(tCompile)}, native ${ms(tNative)}' + (verify ? ', eval ${ms(tEval)}' : '') + ', ${Bridge.apiCalls} API calls');
	}

	static function ms(s:Float):String
		return Std.int(s * 1000) + " ms";

	function runNative(ctx:Context, c:{bundle:Bundle, entry:Ptr}, vl:Array<Value>, api:CompilerApi):NativeResult {
		var old = ctx.curapi;
		ctx.curapi = api;
		EvalContext.select(ctx);
		Bridge.bundle = c.bundle;
		Bridge.enumLookup = findEnum;
		Bridge.reset();
		try {
			var args:Array<Dynamic> = [for (v in vl) Bridge.ofValue(v)];
			var r:Dynamic = Mem.callRef1(c.entry, args);
			var v = Bridge.toValue(r);
			ctx.curapi = old;
			return Ok(v);
		} catch (e:Bridge.Unsupported) {
			ctx.curapi = old;
			return Failed(e.message, null);
		} catch (e:Dynamic) {
			ctx.curapi = old;
			return Failed(Std.string(e), e);
		}
	}

	// ---- compiling a macro function

	function compile(key:String, path:Array<String>, f:String):Null<{bundle:Bundle, entry:Ptr}> {
		var t0 = haxe.Timer.stamp();
		var r = try compileImpl(key, path, f) catch (e:Dynamic) {
			note(key + ": not compiled: " + Std.string(e).split("\n")[0]);
			null;
		}
		tCompile += haxe.Timer.stamp() - t0;
		compiled.set(key, r);
		return r;
	}

	function compileImpl(key:String, path:Array<String>, f:String):{bundle:Bundle, entry:Ptr} {
		var c = findClass(path);
		if (c == null) throw "class not in the macro context";
		var cf = c.clStatics.get(f);
		if (cf == null) throw "no static " + f;
		var args, ret;
		switch TFunctions.follow(cf.cfType) {
			case TFun(s):
				args = s.args;
				ret = s.ret;
			case _:
				throw "not a function";
		}
		for (a in args)
			switch TFunctions.follow(a.type) {
				case TAbstract({aPath: {pack: ["haxe"], name: "Rest"}}, _): throw "rest arguments";
				case _:
			}
		var n = ncompiled++;
		var d = dir + "/" + n;
		if (sys.FileSystem.exists(d)) removeDir(d);
		sys.FileSystem.createDirectory(d + "/hxmc/macro");
		sys.FileSystem.createDirectory(d + "/haxe/macro");
		// (the module, the class: a class may be a module's secondary type)
		var mp = core.Globals.sTypePath(c.clModule.mPath);
		var ref = c.clModule.mPath.name == c.clPath.name ? mp : mp + "." + c.clPath.name;
		sys.io.File.saveContent(d + "/" + Guest.ENTRY + ".hx", 'class ${Guest.ENTRY} {\n'
			+ '\tstatic function main() {\n\t\te(null);\n\t\thxmc.macro.GuestHost.mkPos("", 0, 0);\n\t\thxmc.macro.GuestHost.enumPos(null, "", 0, 0);\n\t\thxmc.macro.GuestHost.api("", []);\n\t}\n\n'
			+ '\t@:hxmc.macroCall("' + key + '")\n\tpublic static function e(a:Array<Dynamic>):Dynamic\n\t\treturn ' + ref + ';\n}\n');
		sys.io.File.saveContent(d + "/hxmc/macro/GuestHost.hx", GUEST_HOST);
		sys.io.File.saveContent(d + "/haxe/macro/Context.hx", contextSource());
		// the child: this compiler, typing the entry in macro mode for hxmc (Guest)
		var cargs = [];
		var cps = com.classPaths.asList();
		cps.reverse();
		for (cp in cps)
			switch cp.scope {
				case Std | StdTarget:
				case _: if (cp.path != "") cargs = cargs.concat(["-cp", cp.path]);
			}
		cargs = cargs.concat(["-cp", hxmcStd(), "-cp", d]);
		var raw = compiler.Args.toRawArgs(com.parsedArgs);
		for (i in 0...raw.length - 1)
			if (raw[i] == "-D" || raw[i] == "--define") {
				var k = raw[i + 1].split("=")[0];
				if (!StringTools.startsWith(k, "hxmc.") && k != "dump" && k != "dump-dependencies") cargs = cargs.concat(["-D", raw[i + 1]]);
			}
		var out = d + "/bundle";
		cargs = cargs.concat(["-D", "hxmc.target=linux-x86_64", "-D", "disable-parallelism", "-dce", "no", "-main", Guest.ENTRY, "--custom-target", "hxmc=" + out]);
		var exe = try sys.FileSystem.fullPath(Sys.programPath()) catch (_:Dynamic) Sys.programPath();
		Sys.putEnv("HXMC_MACRO_GUEST", out);
		var p = new sys.io.Process(exe, cargs);
		var stderr = p.stderr.readAll().toString();
		var stdout = p.stdout.readAll().toString();
		var code = p.exitCode();
		p.close();
		Sys.putEnv("HXMC_MACRO_GUEST", "");
		if (sys.FileSystem.exists(out + ".error")) throw sys.io.File.getContent(out + ".error");
		if (code != 0 || !sys.FileSystem.exists(out + ".o")) throw "the child compile failed: " + StringTools.trim(stderr + stdout);
		var b = Loader.load(out);
		var e = b.entries.get("e");
		if (e == null) throw "no entry";
		if (Sys.getEnv("HXMC_MACRO_KEEP") != "1") removeDir(d);
		note(key + ": compiled (" + b.codeBytes + " bytes of code)");
		return {bundle: b, entry: e};
	}

	static function removeDir(d:String) {
		for (n in sys.FileSystem.readDirectory(d)) {
			var p = d + "/" + n;
			if (sys.FileSystem.isDirectory(p)) removeDir(p) else sys.FileSystem.deleteFile(p);
		}
		sys.FileSystem.deleteDirectory(d);
	}

	function hxmcStd():String {
		var e = Sys.getEnv("HXMC_STD");
		if (e != null && e != "") return e;
		for (cp in com.classPaths.asStringList())
			if (cp != "" && sys.FileSystem.exists(haxe.io.Path.addTrailingSlash(cp) + "hxmc/rt/Runtime.hx")) return cp;
		var exe = try sys.FileSystem.fullPath(Sys.programPath()) catch (_:Dynamic) Sys.programPath();
		return haxe.io.Path.directory(haxe.io.Path.directory(exe)) + "/hxmc/std";
	}

	// the std's haxe.macro.Context with its API bound to this compiler (GuestHost.load)
	function contextSource():String {
		for (cp in com.classPaths.asList())
			if (cp.scope == Std) {
				var p = haxe.io.Path.addTrailingSlash(cp.path) + "haxe/macro/Context.hx";
				if (sys.FileSystem.exists(p)) {
					var s = sys.io.File.getContent(p);
					s = StringTools.replace(s, "#if eval", "#if true");
					s = StringTools.replace(s, "return eval.vm.Context.callMacroApi(f);", "return hxmc.macro.GuestHost.load(f);");
					return s;
				}
			}
		throw "no haxe/macro/Context.hx in the std";
	}

	static var GUEST_HOST = "package hxmc.macro;\n\n"
		+ "// native macros: the compiler running this code (hxmc/src/hxmc/macro/Bridge.hx)\n"
		+ "@:keep @:hxmc.rt extern class GuestHost {\n"
		+ "\t@:native(\"hxmc_macro_api\") static function api(name:String, args:Array<Dynamic>):Dynamic;\n"
		+ "\t@:native(\"hxmc_macro_pos\") static function mkPos(file:String, min:Int, max:Int):Dynamic;\n"
		+ "\t@:native(\"hxmc_macro_enum_pos\") static function enumPos(v:Dynamic, file:String, min:Int, max:Int):Dynamic;\n\n"
		+ "\tstatic inline function load(f:String):Dynamic\n"
		+ "\t\treturn Reflect.makeVarArgs(args -> api(f, args));\n"
		+ "}\n";

	// ---- comparing results: null when equal, else where they differ

	public static function diff(a:Null<Value>, b:Null<Value>, at:String):Null<String> {
		if (a == null) a = VNull;
		if (b == null) b = VNull;
		switch a {
			case VLazy(l): a = l.force();
			case _:
		}
		switch b {
			case VLazy(l): b = l.force();
			case _:
		}
		inline function no(what:String):String
			return (at == "" ? "the result" : at) + ": " + what;
		return switch [a, b] {
			case [VNull, VNull] | [VTrue, VTrue] | [VFalse, VFalse]: null;
			case [VInt32(x), VInt32(y)]: x == y ? null : no(x + " vs " + y);
			case [VFloat(x), VFloat(y)]: x == y || (Math.isNaN(x) && Math.isNaN(y)) ? null : no(x + " vs " + y);
			case [VString(x), VString(y)]: x.sstring == y.sstring ? null : no('"${x.sstring}" vs "${y.sstring}"');
			case [VArray(x), VArray(y)]:
				if (x.alength != y.alength) return no("length " + x.alength + " vs " + y.alength);
				for (i in 0...x.alength) {
					var d = diff(x.avalues[i], y.avalues[i], at + "[" + i + "]");
					if (d != null) return d;
				}
				null;
			case [VEnumValue(x), VEnumValue(y)]:
				var name = macros.eval.EvalHash.revHash(x.epath);
				if (x.epath != y.epath || x.eindex != y.eindex) return no(name + "#" + x.eindex + " vs " + macros.eval.EvalHash.revHash(y.epath) + "#" + y.eindex);
				if (!samePos(x.enpos, y.enpos)) return no(name + "#" + x.eindex + " position " + sPos(x.enpos) + " vs " + sPos(y.enpos));
				for (i in 0...x.eargs.length) {
					var d = diff(x.eargs[i], y.eargs[i], at + "(" + i + ")");
					if (d != null) return d;
				}
				null;
			case [VObject(x), VObject(y)]:
				var fx = EvalContext.objectFields(x), fy = EvalContext.objectFields(y);
				var mx = new Map<Int, Value>(), my = new Map<Int, Value>();
				for (f in fx) mx.set(f.name, f.value);
				for (f in fy) my.set(f.name, f.value);
				for (f in fx) {
					var n = macros.eval.EvalHash.revHash(f.name);
					var yv = my.get(f.name);
					var d = diff(f.value, yv == null ? VNull : yv, at + "." + n);
					if (d != null) return d;
				}
				for (f in fy)
					if (!mx.exists(f.name)) {
						var d = diff(VNull, f.value, at + "." + macros.eval.EvalHash.revHash(f.name));
						if (d != null) return d;
					}
				null;
			case [VInstance({ikind: IPos(p)}), VInstance({ikind: IPos(q)})]:
				samePos(p, q) ? null : no("position " + sPos(p) + " vs " + sPos(q));
			case _:
				a == b ? null : no(macros.eval.EvalPrinting.valueString(a) + " vs " + macros.eval.EvalPrinting.valueString(b));
		}
	}

	static function samePos(p:Null<core.Globals.Pos>, q:Null<core.Globals.Pos>):Bool
		return p == null ? q == null : q != null && p.pfile == q.pfile && p.pmin == q.pmin && p.pmax == q.pmax;

	static function sPos(p:Null<core.Globals.Pos>):String
		return p == null ? "none" : p.pfile + ":" + p.pmin + "-" + p.pmax;
}

enum NativeResult {
	Ok(v:Value);
	// e: the exception the native call raised (null: unsupported, Eval runs the call)
	Failed(msg:String, e:Null<Dynamic>);
}
#end
