package core;

import core.ds.Failure;
import core.ds.InvalidArgument;

// port: OCaml strings are byte strings. The functions below that work byte by byte on
// identifiers and paths only change ASCII bytes, so they work on characters here.
class StringHelper {
	public static function uppercase(s:String):String {
		var bytes = new StringBuf();
		for (idx in 0...s.length) {
			var code = StringTools.fastCodeAt(s, idx);
			bytes.addChar(97 <= code && code <= 122 ? code - 32 : code);
		}
		return bytes.toString();
	}

	public static function capitalize(s:String):String {
		if (s.length == 0) return "";
		else {
			var code = StringTools.fastCodeAt(s, 0);
			return if (97 <= code && code <= 122) String.fromCharCode(code - 32) + s.substr(1) else s;
		}
	}

	public static function startsUppercaseIdentifier(x:String):Bool {
		if (x.length == 0) throw new InvalidArgument("Identifier name must not be empty");
		else {
			function loop(p:Int):Bool {
				return switch StringTools.fastCodeAt(x, p) {
					case c if (c >= "A".code && c <= "Z".code): true;
					case "_".code: p + 1 < x.length && loop(p + 1);
					case _: false;
				}
			}
			return loop(0);
		}
	}

	public static function checkUppercase(x:String):Void {
		if (x.length == 0) throw new Failure("empty part");
		else if (!startsUppercaseIdentifier(x)) throw new Failure("Class name must start with an uppercase letter");
	}

	public static function sEscape(s:String, hex:Bool = true):String {
		var b = new StringBuf();
		for (i in 0...s.length) {
			switch StringTools.fastCodeAt(s, i) {
				case "\n".code:
					b.add("\\n");
				case "\t".code:
					b.add("\\t");
				case "\r".code:
					b.add("\\r");
				case "\"".code:
					b.add("\\\"");
				case "\\".code:
					b.add("\\\\");
				case c if (c < 32 && hex):
					b.add("\\x" + StringTools.hex(c, 2));
				case c:
					b.addChar(c);
			}
		}
		return b.toString();
	}

	public static function escapeResName(name:String, allowed:Array<String>):String {
		var result = new StringBuf();
		// port: ExtString.String.replace_chars goes through the bytes; a non-ASCII character
		// is escaped as its UTF-8 bytes.
		var bytes = haxe.io.Bytes.ofString(name);
		for (index in 0...bytes.length) {
			var chr = bytes.get(index);
			if ((chr >= "a".code && chr <= "z".code)
				|| (chr >= "A".code && chr <= "Z".code)
				|| (chr >= "0".code && chr <= "9".code)
				|| chr == "_".code
				|| chr == ".".code) result.add(charEscaped(chr));
			else if (allowed.indexOf(String.fromCharCode(chr)) >= 0) result.add(charEscaped(chr));
			else result.add("-x" + chr);
		}
		return result.toString();
	}

	// port: OCaml's Char.escaped
	static function charEscaped(c:Int):String {
		return switch c {
			case "'".code: "\\'";
			case "\\".code: "\\\\";
			case "\n".code: "\\n";
			case "\t".code: "\\t";
			case "\r".code: "\\r";
			case 8: "\\b";
			case c if (c >= 32 && c <= 126): String.fromCharCode(c);
			case c: "\\" + StringTools.lpad(Std.string(c), "0", 3);
		}
	}

	public static function removeExtension(file:String):String {
		var dot = file.lastIndexOf(".");
		return dot < 0 ? file : file.substr(0, dot);
	}

	public static function extension(file:String):String {
		var dotPos = file.lastIndexOf(".");
		return dotPos < 0 ? file : file.substr(dotPos);
	}

	/* UTF8 */

	// port: returns (u8, ccount). Haxe strings are always valid Unicode, so the
	// Malformed_code branch (ISO to utf8) cannot occur.
	public static function toUtf8(str:String, p:core.Globals.Pos):{value:String, utf16Length:Int} {
		var u8 = str;
		var ccount = 0;
		for (c in new haxe.iterators.StringIteratorUnicode(u8)) {
			if ((c >= 0xD800 && c <= 0xDFFF) || c >= 0x110000) throw new Failure("Invalid unicode char");
			ccount++;
			if (c > 0x10000) ccount++;
		}
		return {value: u8, utf16Length: ccount};
	}

	// port: the buffer holds bytes, one character (0-255) each.
	public static function utf16Add(buf:StringBuf, c:Int):Void {
		function add(c:Int) {
			buf.addChar(c & 0xFF);
			buf.addChar(c >>> 8);
		}
		if (c >= 0 && c < 0x10000) {
			if (c >= 0xD800 && c <= 0xDFFF) throw new Failure("Invalid unicode char " + c);
			add(c);
		} else if (c < 0x110000) {
			var c = c - 0x10000;
			add((c >> 10) + 0xD800);
			add((c & 1023) + 0xDC00);
		} else
			throw new Failure("Invalid unicode char " + c);
	}

	// port: the result is a byte string, one character (0-255) per byte.
	public static function utf8ToUtf16(str:String, zt:Bool):String {
		var b = new StringBuf();
		for (c in new haxe.iterators.StringIteratorUnicode(str)) utf16Add(b, c);
		if (zt) utf16Add(b, 0);
		return b.toString();
	}

	// port: `str` is a byte string, one character (0-255) per byte.
	public static function utf16ToUtf8(str:String):String {
		var b = new StringBuf();
		function add(c:Int) b.addChar(c & 0xFF);
		function get(i:Int) return StringTools.fastCodeAt(str, i) & 0xFF;
		function loop(i:Int) {
			while (true) {
				if (i >= str.length) return;
				else {
					var c = get(i);
					if (c < 0x80) {
						add(c);
						i += 2;
					} else if (c < 0x800) {
						var c = c | (get(i + 1) << 8);
						add(c);
						add(c >> 8);
						i += 2;
					} else
						core.Globals.die("", "stringHelper.ml");
				}
			}
		}
		loop(0);
		return b.toString();
	}

	public static function urlEncode(s:String, addChar:String->Void):Void {
		var hex = "0123456789ABCDEF";
		// port: OCaml iterates the bytes
		var bytes = haxe.io.Bytes.ofString(s);
		for (i in 0...bytes.length) {
			var c = bytes.get(i);
			if ((c >= "A".code && c <= "Z".code)
				|| (c >= "a".code && c <= "z".code)
				|| (c >= "0".code && c <= "9".code)
				|| c == "_".code
				|| c == "-".code
				|| c == ".".code) addChar(String.fromCharCode(c));
			else {
				addChar("%");
				addChar(hex.charAt(c >> 4));
				addChar(hex.charAt(c & 0xF));
			}
		}
	}

	public static function urlEncodeString(s:String):String {
		var b = new StringBuf();
		urlEncode(s, b.add);
		return b.toString();
	}
}
