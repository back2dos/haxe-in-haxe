package hxmc;

// What a run of the tool does (Main lists the defines and variables).
class Options {
	public var target = host();
	public var rtObj:Null<String> = null; // the runtime object (default: <tool dir>/rt/<target>/rt.o)
	public var stats = false;
	public var verbose = false;
	public var segAlign = 0; // -D hxmc.seg-align: the alignment of loadable segments (0: the target's)
	public var strip = true; // no symbol table unless -debug, -D hxmc.symbols or HXMC_SYMBOLS=1
	public var pic = false; // -D hxmc.pic: position-independent executable
	public var shared = false; // -D hxmc.shared: a shared library
	public var opt = true; // MIR optimizations (HXMC_OPT=0: off)
	public var jobs = 0; // parallel module compilations (HXMC_JOBS, -D hxmc.jobs; 0: the cores)
	public var dump:Null<String> = null; // function names whose machine code is printed (HXMC_DUMP)
	// -D hxmc.link=<path>[,<path>...]: objects and archives linked with the program (LinkInputs)
	public var links:Array<String> = [];
	// -D hxmc.wasm-eh=legacy: wasm32-wasi with the legacy exception-handling instructions
	// (try/catch_all/rethrow) for engines without exnref (default: exnref)
	public var wasmLegacyEh = false;
	// -D hxmc.libc=glibc: Linux, a dynamically linked executable against the system's glibc (Abi.setLibc; default: musl, static)
	public var libc:Null<String> = null;

	public function new() {}

	// the default target: the one the tool runs on (WebAssembly, Eval: linux-x86_64)
	static function host():String {
		#if eval
		return "linux-x86_64";
		#else
		return switch hxmc.unsafe.Mem.target() {
			case 1 | 8: "linux-arm64";
			case 2: "macos-x86_64";
			case 3: "macos-arm64";
			case 4: "windows-x86_64";
			case 5: "windows-arm64";
			case _: "linux-x86_64";
		}
		#end
	}

	// the directory of the hxmc binary (with a trailing slash)
	public static function toolDir():String {
		var p = Sys.programPath();
		var d = haxe.io.Path.directory(p);
		return d == "" ? "./" : haxe.io.Path.addTrailingSlash(d);
	}

	// the directory of the runtime objects (<dir><target>/rt.o; HXMC_RT_DIR,
	// else <tool dir>rt/)
	public static var rtDirOverride:Null<String> = null;

	public static function rtDir():String {
		if (rtDirOverride != null) return rtDirOverride;
		var env = Sys.getEnv("HXMC_RT_DIR");
		return env != null && env != "" ? haxe.io.Path.addTrailingSlash(env) : toolDir() + "rt/";
	}

	public static function read(com:context.Common.CommonContext):Options {
		var o = new Options();
		inline function def(k:String):Null<String>
			return core.Define.rawDefined(com.defines, k) ? core.Define.rawDefinedValue(com.defines, k) : null;
		var env = Sys.getEnv;
		var t = def("hxmc.target");
		if (t != null && t != "1") o.target = t;
		o.rtObj = env("HXMC_RT_OBJ");
		o.stats = env("HXMC_STATS") == "1";
		o.verbose = def("hxmc.verbose") != null || env("HXMC_VERBOSE") == "1";
		o.dump = env("HXMC_DUMP");
		var sa = def("hxmc.seg-align");
		if (sa != null) o.segAlign = Std.parseInt(sa);
		o.pic = def("hxmc.pic") != null;
		o.strip = !(def("debug") != null || def("hxmc.symbols") != null || env("HXMC_SYMBOLS") == "1");
		o.shared = def("hxmc.shared") != null;
		o.opt = env("HXMC_OPT") != "0";
		var eh = def("hxmc.wasm_eh"); // (-D turns the dash into an underscore)
		if (eh != null) switch eh {
			case "legacy": o.wasmLegacyEh = true;
			case "exnref":
			case _: throw "hxmc: -D hxmc.wasm-eh=" + eh + ": exnref or legacy";
		}
		o.libc = def("hxmc.libc");
		var j = def("hxmc.jobs");
		if (j == null) j = env("HXMC_JOBS");
		if (j != null) o.jobs = Std.parseInt(j);
		var ls = def("hxmc.link");
		if (ls != null)
			for (p in ls.split(","))
				if (StringTools.trim(p) != "") o.links.push(sys.FileSystem.absolutePath(StringTools.trim(p)));
		return o;
	}
}
