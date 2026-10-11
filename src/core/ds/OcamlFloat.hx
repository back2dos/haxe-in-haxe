package core.ds;

// port: OCaml Stdlib `float_of_string` (runtime/floats.c caml_float_of_string):
// underscores are skipped, then the whole remaining string must be read by
// strtod (leading whitespace, optional sign, decimal or hexadecimal forms,
// "nan", "inf", "infinity"); anything else fails with Failure "float_of_string".
class OcamlFloat {
	// port: [ws][+-](digits[.digits]|.digits)[(e|E)[+-]digits], the whole string
	static function isDecimal(t:String):Bool {
		var i = 0, n = t.length;
		inline function digits():Int {
			var start = i;
			while (i < n && t.charCodeAt(i) >= "0".code && t.charCodeAt(i) <= "9".code) i++;
			return i - start;
		}
		while (i < n && (t.charCodeAt(i) == " ".code || (t.charCodeAt(i) > 8 && t.charCodeAt(i) < 14))) i++;
		if (i < n && (t.charCodeAt(i) == "+".code || t.charCodeAt(i) == "-".code)) i++;
		var count = digits();
		if (i < n && t.charCodeAt(i) == ".".code) {
			i++;
			count += digits();
		}
		if (count == 0) return false;
		if (i < n && (t.charCodeAt(i) == "e".code || t.charCodeAt(i) == "E".code)) {
			i++;
			if (i < n && (t.charCodeAt(i) == "+".code || t.charCodeAt(i) == "-".code)) i++;
			if (digits() == 0) return false;
		}
		return i == n;
	}

	public static function ofString(s:String):Float {
		var t = s;
		if (s.indexOf("_") >= 0) {
			var buf = new StringBuf();
			for (i in 0...s.length) {
				var c = s.charCodeAt(i);
				if (c != "_".code) buf.addChar(c);
			}
			t = buf.toString();
		}
		if (isDecimal(t)) return Std.parseFloat(StringTools.trim(t));
		// port: rare forms: local EReg instances (an EReg keeps match state)
		var hex = ~/^\s*([+-]?)0[xX]([0-9a-fA-F]*)\.?([0-9a-fA-F]*)([pP]([+-]?[0-9]+))?$/;
		var special = ~/^\s*([+-]?)(nan|inf|infinity)$/i;
		if (special.match(t)) {
			if (special.matched(2).toLowerCase() == "nan") return Math.NaN;
			return special.matched(1) == "-" ? Math.NEGATIVE_INFINITY : Math.POSITIVE_INFINITY;
		}
		if (hex.match(t)) {
			var intPart = hex.matched(2), fracPart = hex.matched(3);
			if (intPart.length + fracPart.length == 0) throw new Failure("float_of_string");
			var m = 0.0;
			for (i in 0...intPart.length) m = m * 16 + Std.parseInt("0x" + intPart.charAt(i));
			var scale = 1.0 / 16;
			for (i in 0...fracPart.length) {
				m += Std.parseInt("0x" + fracPart.charAt(i)) * scale;
				scale /= 16;
			}
			var exp = hex.matched(5) == null ? 0 : Std.parseInt(hex.matched(5));
			var f = m * Math.pow(2, exp);
			return hex.matched(1) == "-" ? -f : f;
		}
		throw new Failure("float_of_string");
	}
}
