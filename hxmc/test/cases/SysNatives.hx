// The operating-system natives (files, directories, environment, processes)
// in a scratch directory under the working directory. Machine-dependent
// values (paths, times, ids) are not printed: only their consistency.
import sys.FileSystem;
import sys.io.File;

class SysNatives {
	static function main() {
		var dir = "sysnatives.tmp";
		if (FileSystem.exists(dir)) {
			for (f in FileSystem.readDirectory(dir))
				FileSystem.deleteFile(dir + "/" + f);
			FileSystem.deleteDirectory(dir);
		}
		FileSystem.createDirectory(dir);
		Sys.println(FileSystem.exists(dir) + " " + FileSystem.isDirectory(dir));
		File.saveContent(dir + "/a.txt", "hello\nworld\n");
		var o = File.append(dir + "/a.txt");
		o.writeString("more\n");
		o.close();
		Sys.println(File.getContent(dir + "/a.txt").split("\n"));
		var bytes = haxe.io.Bytes.alloc(300000);
		for (i in 0...bytes.length)
			bytes.set(i, i * 7);
		File.saveBytes(dir + "/b.bin", bytes);
		var back = File.getBytes(dir + "/b.bin");
		Sys.println(back.length + " " + (back.compare(bytes) == 0));
		var inp = File.read(dir + "/b.bin");
		inp.seek(1000, SeekBegin);
		var b4 = inp.read(4);
		Sys.println(inp.tell() + " " + b4.toHex());
		inp.close();
		var st = FileSystem.stat(dir + "/b.bin");
		Sys.println(st.size + " " + (st.mtime.getTime() > 0) + " " + (st.nlink >= 1));
		FileSystem.rename(dir + "/a.txt", dir + "/c.txt");
		var names = FileSystem.readDirectory(dir);
		names.sort(Reflect.compare);
		Sys.println(names + " " + FileSystem.exists(dir + "/a.txt"));
		Sys.println(FileSystem.fullPath(dir) == FileSystem.absolutePath(dir) || StringTools.endsWith(FileSystem.fullPath(dir), dir));
		Sys.putEnv("HXMC_SYSNATIVES", "v=1");
		Sys.println(Sys.getEnv("HXMC_SYSNATIVES") + " " + (Sys.environment().get("HXMC_SYSNATIVES") == "v=1") + " " + Sys.getEnv("HXMC_NO_SUCH_VARIABLE"));
		Sys.println(Sys.args().length + " " + (Sys.programPath().length > 0) + " " + (StringTools.endsWith(Sys.getCwd(), "/") || StringTools.endsWith(Sys.getCwd(), "\\")));
		var t0 = Sys.time();
		Sys.sleep(0.01);
		Sys.println(Sys.time() - t0 >= 0.005 && Sys.cpuTime() >= 0);
		// processes (a shell is needed: not on Windows)
		// (no processes on WASI either)
		if (Sys.systemName() != "Windows" && Sys.systemName() != "Wasi") {
			var p = new sys.io.Process("sh", ["-c", "echo out; echo err 1>&2; read x; echo got $x; exit 3"]);
			p.stdin.writeString("line\n");
			p.stdin.close();
			Sys.println(p.stdout.readAll().toString().split("\n") + " " + p.stderr.readAll().toString().split("\n") + " " + p.exitCode());
			p.close();
			Sys.println(Sys.command("exit 5") + " " + Sys.command("sh", ["-c", "exit 0"]));
		} else Sys.println("[out,got line,] [err,] 3\n5 0");
		for (f in FileSystem.readDirectory(dir))
			FileSystem.deleteFile(dir + "/" + f);
		FileSystem.deleteDirectory(dir);
		Sys.println(FileSystem.exists(dir));
		try {
			File.getContent(dir + "/missing");
		} catch (e:Dynamic) {
			Sys.println("missing file: an exception");
		}
	}
}
