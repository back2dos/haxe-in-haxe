package hxmc;

// The hxmc tool (hxmc/README.md): runs the port's compiler pipeline on the
// program (from an HXB archive with --hxb-lib, or from source), lowers the
// filtered program to hxc's IR (backend.Lower) and compiles it to machine
// code:
//   hxmc <out> <haxe arguments...> --custom-target hxc
// Options (defines, or the environment for development):
//   -D hxmc.target=linux-x86_64     the target (only this one so far)
//   -D hxmc.hybrid / HXMC_HYBRID=1  development mode: the functions hxmc cannot
//                                   compile yet are written as C (<out>.c) and
//                                   everything is linked by the system's cc
//   HXMC_CC                         that C compiler (default clang -O0)
//   HXMC_RT                         the runtime objects for hybrid builds (a directory)
//   HXMC_STATS=1                    print the share of natively compiled functions
//   HXMC_ONLY=<name,...>            compile only these functions natively (bisecting)
//   HXMC_SKIP=<name,...>            never compile these natively
class Main {
	static function main() {
		var args = Sys.args();
		var out = args.shift();
		var failed = null;
		compiler.Compiler.generateHook = function(com) {
			try {
				var path = com.main.mainPath;
				var mainClass = null;
				for (t in com.types)
					switch t {
						case TClassDecl(c) if (c.clPath.name == path.name && c.clPath.pack.join(".") == path.pack.join(".")):
							mainClass = c;
						case _:
					}
				var opts = Options.read(com);
				Driver.run(backend.Lower.program(mainClass, com.types, com.basic), out, opts);
			} catch (e:Dynamic) {
				failed = Std.string(e) + "\n" + haxe.CallStack.toString(haxe.CallStack.exceptionStack());
			}
		}
		var code = haxe.Main.run(args.concat(["--no-output"]));
		if (failed != null) {
			Sys.stderr().writeString("hxmc: " + failed + "\n");
			Sys.exit(1);
		}
		Sys.exit(code);
	}
}
