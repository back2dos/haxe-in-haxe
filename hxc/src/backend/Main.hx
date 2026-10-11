package backend;

// The backend tool (docs/WASM-BACKEND.md). Runs the port's compiler
// pipeline, then lowers the filtered program (the data an HXB archive holds)
// to the IR and writes C: the files of <out>_hxc/ (files.txt lists the .c
// files to compile; HXC_CHUNK_KB sets the chunk size, default 192) or, with
// HXC_SINGLE=1, one file <out>.c:
//   node bin/hxc/wbk.js <out> <haxe arguments...> --custom-target hxc
class Main {
	static function chunkKb():Int {
		var v = Sys.getEnv("HXC_CHUNK_KB");
		var n = v == null ? null : Std.parseInt(v);
		return n == null || n <= 0 ? 192 : n;
	}

	// writes only the files whose content changed (their mtimes say what to
	// recompile) and removes the generated files of an earlier run that are gone
	static function writeChunks(dir:String, files:Array<{name:String, content:String}>) {
		if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
		var keep = new Map<String, Bool>();
		var cs = [];
		function write(name:String, content:String) {
			keep.set(name, true);
			var path = dir + "/" + name;
			if (sys.FileSystem.exists(path) && sys.io.File.getContent(path) == content) return;
			sys.io.File.saveContent(path, content);
		}
		for (f in files) {
			if (StringTools.endsWith(f.name, ".c")) cs.push(f.name);
			write(f.name, f.content);
		}
		write("files.txt", cs.join("\n") + "\n");
		for (n in sys.FileSystem.readDirectory(dir))
			if (!keep.exists(n) && (StringTools.endsWith(n, ".c") || StringTools.endsWith(n, ".h"))) sys.FileSystem.deleteFile(dir + "/" + n);
	}

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
				var prog = Lower.program(mainClass, com.types);
				if (Lower.survey) return;
				var single = Sys.getEnv("HXC_SINGLE");
				if (single != null && single != "" && single != "0") sys.io.File.saveContent(out + ".c", EmitC.emit(prog));
				else writeChunks(out + "_hxc", EmitC.emitChunks(prog, chunkKb() * 1024));
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
