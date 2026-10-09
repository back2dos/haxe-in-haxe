package sys.io;

import hxc.NativeSys;

// hxc target (backend/): child processes through hxc.NativeSys.
class Process {
	public var stdout(default, null):haxe.io.Input;
	public var stderr(default, null):haxe.io.Input;
	public var stdin(default, null):haxe.io.Output;

	var pid:Int;
	var code:Null<Int>;

	public function new(cmd:String, ?args:Array<String>, ?detached:Bool):Void {
		var fds = [0, 0, 0];
		pid = NativeSys.processRun(cmd, args, fds);
		if (pid < 0) throw "Process creation failure : " + cmd;
		stdin = @:privateAccess new FileOutput(fds[0]);
		stdout = @:privateAccess new FileInput(fds[1]);
		stderr = @:privateAccess new FileInput(fds[2]);
	}

	public function getPid():Int
		return pid;

	public function exitCode(block:Bool = true):Null<Int> {
		if (code == null) {
			var c = NativeSys.processWait(pid, block);
			if (c >= 0) code = c;
		}
		return code;
	}

	public function close():Void {
		stdin.close();
		stdout.close();
		stderr.close();
	}

	public function kill():Void
		NativeSys.processKill(pid);
}
