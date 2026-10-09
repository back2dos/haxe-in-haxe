import hxc.NativeSys;

// hxc target (backend/): Sys over hxc.NativeSys.
class Sys {
	public static function print(v:Dynamic):Void
		NativeSys.print(Std.string(v));

	public static function println(v:Dynamic):Void
		NativeSys.print(Std.string(v) + "\n");

	public static function args():Array<String>
		return NativeSys.args();

	public static function getEnv(s:String):Null<String>
		return NativeSys.getEnv(s);

	public static function putEnv(s:String, v:Null<String>):Void
		NativeSys.putEnv(s, v);

	public static function environment():Map<String, String> {
		var m = new Map<String, String>();
		for (kv in NativeSys.environ()) {
			var i = kv.indexOf("=");
			if (i > 0) m.set(kv.substr(0, i), kv.substr(i + 1));
		}
		return m;
	}

	public static function sleep(seconds:Float):Void
		NativeSys.sleep(seconds);

	public static function setTimeLocale(loc:String):Bool
		return false;

	public static function getCwd():String
		return NativeSys.getCwd();

	public static function setCwd(s:String):Void
		if (!NativeSys.setCwd(s)) throw "Could not change directory to " + s;

	public static function systemName():String
		return NativeSys.systemName();

	static function quote(a:String):String {
		var b = new StringBuf();
		b.add("'");
		for (i in 0...a.length) {
			var c = a.charAt(i);
			b.add(c == "'" ? "'\\''" : c);
		}
		b.add("'");
		return b.toString();
	}

	public static function command(cmd:String, ?args:Array<String>):Int {
		if (args != null) {
			cmd = quote(cmd);
			for (a in args)
				cmd += " " + quote(a);
		}
		return NativeSys.command(cmd);
	}

	public static function exit(code:Int):Void
		NativeSys.exit(code);

	public static function time():Float
		return NativeSys.time();

	public static function cpuTime():Float
		return NativeSys.cpuTime();

	@:deprecated("Use programPath instead") public static function executablePath():String
		return NativeSys.programPath();

	public static function programPath():String
		return NativeSys.programPath();

	public static function getChar(echo:Bool):Int
		return NativeSys.getChar(echo);

	static var _stdin:haxe.io.Input;
	static var _stdout:haxe.io.Output;
	static var _stderr:haxe.io.Output;

	public static function stdin():haxe.io.Input {
		if (_stdin == null) _stdin = @:privateAccess new sys.io.FileInput(0);
		return _stdin;
	}

	public static function stdout():haxe.io.Output {
		if (_stdout == null) _stdout = @:privateAccess new sys.io.FileOutput(1);
		return _stdout;
	}

	public static function stderr():haxe.io.Output {
		if (_stderr == null) _stderr = @:privateAccess new sys.io.FileOutput(2);
		return _stderr;
	}
}
