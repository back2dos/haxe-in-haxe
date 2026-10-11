package unit;

import core.Numeric;

class NumericTest {
	public static function main():Void {
		if (Numeric.validFloatLexeme("12") != "12." || Numeric.validFloatLexeme("-12") != "-12." || Numeric.validFloatLexeme("1e2") != "1e2") throw "Float lexeme normalization failed";
		if (Numeric.floatRepres(12.0) != "12." || Numeric.floatRepres(Math.POSITIVE_INFINITY) != "infinity" || Numeric.floatRepres(Math.NEGATIVE_INFINITY) != "neg_infinity" || Numeric.floatRepres(Math.NaN) != "nan") throw "Float representation failed";
		if (!Numeric.isWhitespace(9) || !Numeric.isWhitespace(13) || Numeric.isWhitespace(8) || Numeric.isWhitespace(14)) throw "Whitespace detection failed";
		if (Numeric.parseFloat(" \t-12.5e1suffix") != -125.0 || Numeric.parseFloat("+.5") != .5) throw "Float parsing failed";
		if (Numeric.parseInt(" \n+123suffix") != 123 || Numeric.parseInt("-0xFFsuffix") != -255 || Numeric.parseInt("0X10x") != 16) throw "Integer parsing failed";
		if (Numeric.parseInt("+0xFFsuffix") != 255) throw "Positive hexadecimal parsing failed";
		assertThrows(function() Numeric.parseFloat("invalid"));
		assertThrows(function() Numeric.parseInt("invalid"));
	}

	static function assertThrows(callback:Void->Void):Void {
		try {
			callback();
		} catch (_:Dynamic) {
			return;
		}
		throw "Expected parse failure";
	}
}
