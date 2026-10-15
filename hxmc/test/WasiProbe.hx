// What a WebAssembly program sees of the file system through node's WASI
// (CI's npm job on Windows): for each argument, whether it exists, is a
// directory, and its first entries; then Sys.getCwd().
class WasiProbe {
	static function main() {
		Sys.println("cwd " + (try Sys.getCwd() catch (e:Dynamic) "error " + e));
		for (a in Sys.args()) {
			var line = a + ": exists " + (try Std.string(sys.FileSystem.exists(a)) catch (e:Dynamic) "error " + e);
			line += ", dir " + (try Std.string(sys.FileSystem.isDirectory(a)) catch (e:Dynamic) "error " + e);
			line += ", entries " + (try sys.FileSystem.readDirectory(a).slice(0, 5).join(" ") catch (e:Dynamic) "error " + e);
			Sys.println(line);
		}
	}
}
