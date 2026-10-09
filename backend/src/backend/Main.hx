package backend;

// EXPERIMENTAL code generator (bench/WASM-BACKEND.md). Runs the port's
// compiler pipeline, then lowers the filtered program (the data an HXB
// archive holds) to the shared IR and writes <out>.wat and <out>.c:
//   node wbk.js <out> <haxe arguments...>
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
				var prog = Lower.program(mainClass);
				sys.io.File.saveContent(out + ".wat", EmitWat.emit(prog));
				sys.io.File.saveContent(out + ".c", EmitC.emit(prog));
			} catch (e:Dynamic) {
				failed = Std.string(e);
			}
		}
		var code = haxe.Main.run(args.concat(["--no-output"]));
		if (failed != null) {
			Sys.stderr().writeString(failed + "\n");
			Sys.exit(1);
		}
		Sys.exit(code);
	}
}
