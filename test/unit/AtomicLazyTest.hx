package unit;

import core.ds.AtomicLazy;

class AtomicLazyTest {
	public static function main():Void {
		var calls = 0;
		var value = AtomicLazy.fromFun(function() return ++calls);
		if (value.isVal()) throw "Fresh lazy value must not be forced";
		if (value.force() != 1 || value.force() != 1 || calls != 1 || !value.isVal()) throw "Lazy value must be evaluated once";
		if (!AtomicLazy.fromVal("ready").isVal()) throw "Precomputed lazy value must be forced";
	}
}
