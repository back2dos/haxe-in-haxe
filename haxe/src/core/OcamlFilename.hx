package core;

// port: OCaml's Filename module (stdlib/filename.ml), with its Unix and Win32
// ... variants chosen by the host system as `Sys.os_type` chooses them upstream.
class OcamlFilename {
	static final win32 = Sys.systemName() == "Windows";

	public static inline final currentDirName = ".";

	// port: Sys.getcwd, which has no trailing separator but at a root (Sys.getCwd appends "/")
	public static function sysGetcwd():String {
		var cwd = Sys.getCwd();
		if (cwd.length > 1 && cwd.charAt(cwd.length - 1) == "/") cwd = cwd.substr(0, cwd.length - 1);
		return cwd;
	}

	public static var dirSep(get, never):String;

	static function get_dirSep():String return win32 ? "\\" : "/";

	public static function isDirSep(s:String, i:Int):Bool {
		var c = StringTools.fastCodeAt(s, i);
		return c == "/".code || (win32 && (c == "\\".code || c == ":".code));
	}

	public static function isRelative(n:String):Bool {
		if (!win32) return n.length < 1 || n.charAt(0) != "/";
		return (n.length < 1 || n.charAt(0) != "/") && (n.length < 1 || n.charAt(0) != "\\") && (n.length < 2 || n.charAt(1) != ":");
	}

	public static function concat(dirname:String, filename:String):String {
		var l = dirname.length;
		return if (l == 0 || isDirSep(dirname, l - 1)) dirname + filename else dirname + dirSep + filename;
	}

	public static function checkSuffix(name:String, suff:String):Bool {
		if (!win32) return StringTools.endsWith(name, suff);
		return name.length >= suff.length && asciiLower(name.substr(name.length - suff.length)) == asciiLower(suff);
	}

	static function asciiLower(s:String):String {
		var b = new StringBuf();
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			b.addChar(c >= "A".code && c <= "Z".code ? c + 32 : c);
		}
		return b.toString();
	}

	public static function quote(s:String):String {
		if (!win32) return "'" + s.split("'").join("'\\''") + "'";
		// port: Win32.quote: the C runtime's argument rules (backslashes before a quote doubled)
		var b = new StringBuf();
		b.add("\"");
		var bs = 0;
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (c == "\\".code) {
				bs++;
				continue;
			}
			for (_ in 0...(c == "\"".code ? 2 * bs + 1 : bs))
				b.add("\\");
			bs = 0;
			b.addChar(c);
		}
		for (_ in 0...2 * bs)
			b.add("\\");
		b.add("\"");
		return b.toString();
	}

	// port: generic_basename / generic_dirname, after the drive on Win32
	static function driveLength(s:String):Int {
		if (!win32 || s.length < 2 || s.charAt(1) != ":") return 0;
		var c = StringTools.fastCodeAt(s, 0);
		return (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code) ? 2 : 0;
	}

	public static function basename(s:String):String {
		var name = s.substr(driveLength(s));
		if (name == "") return currentDirName;
		var n = name.length - 1;
		while (n >= 0 && isDirSep(name, n)) n--;
		if (n < 0) return name.substr(0, 1);
		var p = n + 1;
		while (n >= 0 && !isDirSep(name, n)) n--;
		return name.substring(n + 1, p);
	}

	public static function dirname(s:String):String {
		var d = driveLength(s);
		var drive = s.substr(0, d), name = s.substr(d);
		return drive + genericDirname(name);
	}

	static function genericDirname(name:String):String {
		if (name == "") return currentDirName;
		var n = name.length - 1;
		while (n >= 0 && isDirSep(name, n)) n--;
		if (n < 0) return name.substr(0, 1);
		while (n >= 0 && !isDirSep(name, n)) n--;
		if (n < 0) return currentDirName;
		while (n >= 0 && isDirSep(name, n)) n--;
		if (n < 0) return name.substr(0, 1);
		return name.substr(0, n + 1);
	}

	static function extensionLen(name:String):Int {
		var i = name.length - 1;
		while (true) {
			if (i < 0 || isDirSep(name, i)) return 0;
			if (name.charAt(i) == ".") break;
			i--;
		}
		var i0 = i;
		i--;
		while (true) {
			if (i < 0 || isDirSep(name, i)) return 0;
			if (name.charAt(i) == ".") i-- else return name.length - i0;
		}
	}

	public static function chopExtension(name:String):String {
		var l = extensionLen(name);
		if (l == 0) throw new core.ds.InvalidArgument("Filename.chop_extension");
		return name.substr(0, name.length - l);
	}
}
