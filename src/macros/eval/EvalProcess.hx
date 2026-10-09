package macros.eval;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import core.ds.Failure;

/**
	haxe/libs/extc/process.ml: the subprocesses behind Eval's sys.io.Process,
	over the host's sys.io.Process.

	Upstream spawns with Unix.create_process (posix_spawnp). When that fails
	because the command is not found, `run` returns a process whose stdout is
	at EOF, whose stderr holds the error message and whose exit code is 127.
	Host processes fork first and report a failed exec only through their own
	exit code (1 on HashLink), so the command is looked up in PATH here, as
	posix_spawnp does, before the host process is created.
**/
class EvalProcess {
	final host:Null<sys.io.Process>;
	final failedStderr:Null<BytesInput>;
	var exitCode:Null<Int>;

	function new(host:Null<sys.io.Process>, failedStderr:Null<BytesInput>, exitCode:Null<Int>) {
		this.host = host;
		this.failedStderr = failedStderr;
		this.exitCode = exitCode;
	}

	public static function run(cmd:String, args:Null<Array<String>>):EvalProcess {
		// with args = None upstream runs /bin/sh -c (cmd.exe on Windows), which always exists
		if (args != null && Sys.systemName() != "Windows" && !commandExists(cmd)) {
			var msg = "create_process(" + cmd + "): No such file or directory\n";
			return new EvalProcess(null, new BytesInput(Bytes.ofString(msg)), 127);
		}
		return new EvalProcess(new sys.io.Process(cmd, args), null, null);
	}

	/** The execvp/posix_spawnp lookup: a path with a slash is used as is, otherwise PATH is searched. **/
	static function commandExists(cmd:String):Bool {
		inline function isExecutableFile(path:String):Bool {
			// 73 = 0o111: some execute bit
			return sys.FileSystem.exists(path) && !sys.FileSystem.isDirectory(path) && (sys.FileSystem.stat(path).mode & 73) != 0;
		}
		if (cmd.indexOf("/") >= 0)
			return sys.FileSystem.exists(cmd);
		if (cmd == "")
			return false;
		var path = Sys.getEnv("PATH");
		if (path == null)
			path = "/bin:/usr/bin";
		for (dir in path.split(":"))
			if (isExecutableFile((dir == "" ? "." : dir) + "/" + cmd))
				return true;
		return false;
	}

	public function readStdout(b:Bytes, pos:Int, len:Int):Int {
		if (host == null)
			throw new Failure("process_stdout_read");
		return host.stdout.readBytes(b, pos, len);
	}

	public function readStderr(b:Bytes, pos:Int, len:Int):Int {
		if (host == null)
			return failedStderr.readBytes(b, pos, len);
		return host.stderr.readBytes(b, pos, len);
	}

	public function writeStdin(b:Bytes, pos:Int, len:Int):Int {
		if (host == null)
			throw new Failure("write(): Broken pipe");
		return host.stdin.writeBytes(b, pos, len);
	}

	public function closeStdin():Void {
		if (host != null)
			host.stdin.close();
	}

	public function exit():Int {
		if (exitCode == null)
			exitCode = host.exitCode(true);
		return exitCode;
	}

	public function pid():Int {
		return host == null ? 0 : host.getPid();
	}

	public function close():Void {
		if (host != null)
			host.close();
	}

	public function kill():Void {
		if (host != null && exitCode == null)
			host.kill();
	}
}
