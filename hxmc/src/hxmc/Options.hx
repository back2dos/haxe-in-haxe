package hxmc;

// What a run of the tool does (Main lists the defines and variables).
class Options {
	public var target = "linux-x86_64";
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

	public function new() {}

	// the directory of the hxmc binary (with a trailing slash)
	public static function toolDir():String {
		var p = Sys.programPath();
		var d = haxe.io.Path.directory(p);
		return d == "" ? "./" : haxe.io.Path.addTrailingSlash(d);
	}

	// the directory of the runtime objects (<dir><target>/rt.o; default: <tool dir>rt/)
	public static var rtDirOverride:Null<String> = null;

	public static function rtDir():String
		return rtDirOverride != null ? rtDirOverride : toolDir() + "rt/";

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
		var j = def("hxmc.jobs");
		if (j == null) j = env("HXMC_JOBS");
		if (j != null) o.jobs = Std.parseInt(j);
		return o;
	}
}
