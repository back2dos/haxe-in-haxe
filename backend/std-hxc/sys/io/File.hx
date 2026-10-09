package sys.io;

import hxc.NativeSys;

// hxc target (backend/): files through hxc.NativeSys.
class File {
	public static function getContent(path:String):String
		return getBytes(path).toString();

	public static function saveContent(path:String, content:String):Void
		saveBytes(path, haxe.io.Bytes.ofString(content));

	public static function getBytes(path:String):haxe.io.Bytes {
		var b = NativeSys.fileContent(path);
		if (b == null) throw "Could not read file " + path;
		return b;
	}

	public static function saveBytes(path:String, bytes:haxe.io.Bytes):Void
		if (!NativeSys.fileSave(path, bytes, false)) throw "Could not write file " + path;

	static function open(path:String, mode:Int):Int {
		var fd = NativeSys.fileOpen(path, mode);
		if (fd < 0) throw "Could not open file " + path;
		return fd;
	}

	public static function read(path:String, binary:Bool = true):FileInput
		return @:privateAccess new FileInput(open(path, 0));

	public static function write(path:String, binary:Bool = true):FileOutput
		return @:privateAccess new FileOutput(open(path, 1));

	public static function append(path:String, binary:Bool = true):FileOutput
		return @:privateAccess new FileOutput(open(path, 2));

	public static function update(path:String, binary:Bool = true):FileOutput
		return @:privateAccess new FileOutput(open(path, 3));

	public static function copy(srcPath:String, dstPath:String):Void
		saveBytes(dstPath, getBytes(srcPath));
}
