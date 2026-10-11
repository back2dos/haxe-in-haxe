package sys.io;

import hxc.NativeSys;

// hxc target (hxc/): a file descriptor written through hxc.NativeSys.
class FileOutput extends haxe.io.Output {
	var fd:Int;
	var one:haxe.io.Bytes;

	function new(fd:Int) {
		this.fd = fd;
	}

	override public function writeByte(c:Int):Void {
		if (one == null) one = haxe.io.Bytes.alloc(1);
		one.set(0, c);
		writeBytes(one, 0, 1);
	}

	override public function writeBytes(b:haxe.io.Bytes, pos:Int, len:Int):Int {
		var n = NativeSys.fileWrite(fd, b, pos, len);
		if (n < 0) throw haxe.io.Error.Custom("write error");
		return n;
	}

	override public function close():Void
		NativeSys.fileClose(fd);

	public function seek(p:Int, pos:FileSeek):Void
		NativeSys.fileSeek(fd, p, switch pos {
			case SeekBegin: 0;
			case SeekCur: 1;
			case SeekEnd: 2;
		});

	public function tell():Int
		return NativeSys.fileTell(fd);
}
