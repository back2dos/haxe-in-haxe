package unit;

import core.Define;

class DefineTest {
	public static function main():Void {
		var defines = Define.emptyDefines();
		if (Define.rawDefined(defines, "debug")) throw "empty define context";
		if (Define.rawDefinedValueSafe(defines, "missing") != "") throw "safe default";
		if (Define.rawDefinedValueSafe(defines, "missing", "fallback") != "fallback") throw "explicit safe default";

		var missing = false;
		try Define.rawDefinedValue(defines, "missing") catch (_:Dynamic) missing = true;
		if (!missing) throw "missing raw value must throw";

		Define.rawDefine(defines, "debug");
		if (!Define.rawDefined(defines, "debug") || Define.rawDefinedValue(defines, "debug") != "1") throw "raw define";
		Define.rawDefineValue(defines, "target-threaded", "true");
		var signature = Define.getSignature(defines);
		if (signature != Define.getSignature(defines)) throw "signature cache";
		if (signature != "dac5da3dc6977f321325445652e0ea28") throw "signature content";

		Define.rawDefineValue(defines, "debug", "0");
		if (signature == Define.getSignature(defines)) throw "signature invalidation";
		Define.rawUndefine(defines, "debug");
		if (Define.rawDefined(defines, "debug")) throw "raw undefine";
	}
}
