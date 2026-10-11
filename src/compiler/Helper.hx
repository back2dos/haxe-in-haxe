package compiler;

import core.ds.InvalidArgument;
import core.ds.NotFound;

// port: OCaml exception HelpMessage of string.
class HelpMessage {
	public final message:String;

	public function new(message:String) {
		this.message = message;
	}
}

class Helper {
	public static final isDebugRun:Bool = Sys.getEnv("HAXEDEBUG") == "1";
	public static var prompt:Bool = false;

	// port: the optional Hashtbl h, as a Map.
	public static function expandEnv(path:String, ?h:Map<String, String>):String {
		var r = ~/%([A-Za-z0-9_]+)%/g;
		return r.map(path, function(s) {
			var key = s.matched(1);
			var value = Sys.getEnv(key);
			if (value != null) return value;
			if (h != null && h.exists(key)) return h.get(key);
			return "%" + key + "%";
		});
	}

	public static function unquote(v:String):String {
		var len = v.length;
		if (len > 0) {
			return switch [v.charAt(0), v.charAt(len - 1)] {
				case ['"', '"'] | ["'", "'"]:
					// port: String.sub v 1 (len - 2) raises for a lone quote character.
					if (len < 2) throw new InvalidArgument("String.sub / Bytes.sub");
					v.substr(1, len - 2);
				case _: v;
			}
		} else return v;
	}

	// port: ExtString.String.strip with its default characters " \t\r\n".
	static function strip(s:String):String {
		inline function isStrip(c:Int) return c == " ".code || c == "\t".code || c == "\r".code || c == "\n".code;
		var p = 0, l = s.length;
		while (p < l && isStrip(StringTools.fastCodeAt(s, p))) p++;
		while (l > p && isStrip(StringTools.fastCodeAt(s, l - 1))) l--;
		return s.substring(p, l);
	}

	public static function parseHxmlData(data:String):Array<String> {
		// port: Str.split drops empty leading/trailing fields; empty lines are skipped below anyway.
		var lines = ~/[\r\n]+/g.split(data);
		var result:Array<String> = [];
		for (l in lines) {
			var l = unquote(strip(l));
			if (l == "" || l.charAt(0) == "#") {} else if (l.charAt(0) == "-") {
				// port: ExtString.String.split raises Invalid_string when " " is absent;
				// `with _` also catches an Invalid_argument from unquote.
				try {
					var i = l.indexOf(" ");
					if (i < 0) throw new InvalidArgument("Invalid_string");
					var a = l.substr(0, i), b = l.substr(i + 1);
					var parts = [unquote(a), unquote(strip(b))];
					for (p in parts) result.push(p);
				} catch (_:Dynamic) {
					result.push(l);
				}
			} else result.push(l);
		}
		return result;
	}

	public static function parseHxml(file:String):Array<String> {
		var data = try sys.io.File.getContent(file) catch (_:Dynamic) throw NotFound.raise();
		return parseHxmlData(data);
	}
}
