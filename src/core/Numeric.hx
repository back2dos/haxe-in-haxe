package core;

// Port of haxe/src/core/numeric.ml.
class Numeric {
	public static function validFloatLexeme(value:String):String {
		var index = 0;
		while (index < value.length) {
			var code = value.charCodeAt(index);
			if (!((code >= "0".code && code <= "9".code) || code == "-".code)) return value;
			index++;
		}
		return value + ".";
	}

	public static function floatRepr(value:Float):String {
		if (Math.isNaN(value)) return "nan";
		if (!Math.isFinite(value)) return value < 0.0 ? "neg_infinity" : "infinity";
		return validFloatLexeme(Std.string(value));
	}

	public static function isWhitespace(code:Int):Bool {
		return code > 8 && code < 14;
	}

	public static function parseFloat(value:String):Float {
		var start = 0;
		var index = 0;
		while (index < value.length) {
			var code = value.charCodeAt(index);
			if (start == index && (code == " ".code || isWhitespace(code))) {
				start++;
				index++;
			} else if ((code >= "0".code && code <= "9".code) || code == "-".code || code == "+".code || code == "e".code || code == "E".code || code == ".".code) {
				index++;
			} else {
				break;
			}
		}
		return parseFloatToken(value.substr(start, index - start));
	}

	public static function parseInt(value:String):Int {
		var start = 0;
		while (start < value.length) {
			var code = value.charCodeAt(start);
			if (code == " ".code || isWhitespace(code)) start++;
			else break;
		}
		if (start == value.length) return parseIntToken("");
		if (value.charCodeAt(start) == "+".code) start++;
		var tokenStart = start;
		var digits = start;
		if (digits < value.length && value.charCodeAt(digits) == "-".code) digits++;
		if (digits + 1 < value.length && value.charCodeAt(digits) == "0".code && (value.charCodeAt(digits + 1) == "x".code || value.charCodeAt(digits + 1) == "X".code)) {
			digits += 2;
			while (digits < value.length) {
				var code = value.charCodeAt(digits);
				if (!((code >= "0".code && code <= "9".code) || (code >= "a".code && code <= "f".code) || (code >= "A".code && code <= "F".code))) break;
				digits++;
			}
		} else {
			while (digits < value.length && value.charCodeAt(digits) >= "0".code && value.charCodeAt(digits) <= "9".code) digits++;
		}
		return parseIntToken(value.substr(tokenStart, digits - tokenStart));
	}

	static function parseFloatToken(value:String):Float {
		var result = Std.parseFloat(value);
		if (Math.isNaN(result)) throw 'Invalid float $value';
		return result;
	}

	static function parseIntToken(value:String):Int {
		var index = 0;
		var negative = false;
		if (value.charCodeAt(index) == "-".code) {
			negative = true;
			index++;
		}
		if (index + 1 < value.length && value.charCodeAt(index) == "0".code && (value.charCodeAt(index + 1) == "x".code || value.charCodeAt(index + 1) == "X".code)) {
			index += 2;
			if (index == value.length) throw 'Invalid integer $value';
			var result = 0;
			while (index < value.length) {
				var code = value.charCodeAt(index++);
				var digit = code >= "0".code && code <= "9".code ? code - "0".code : code >= "a".code && code <= "f".code ? code - "a".code + 10 : code - "A".code + 10;
				result = (result << 4) | digit;
			}
			return negative ? -result : result;
		}
		var result = Std.parseInt(value);
		if (result == null) throw 'Invalid integer $value';
		return result;
	}
}
