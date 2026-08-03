package unit;

import core.ds.StringDynArray;
import core.ds.StringPool;

class StringPoolTest {
	public static function main():Void {
		var values = new StringDynArray(1);
		values.add("first");
		values.add("second");
		var iterated:Array<String> = [];
		values.iter(iterated.push);
		if (values.length != 2 || iterated.join(",") != "first,second") throw "Dynamic string array failed";

		var pool = new StringPool();
		if (pool.getOrAdd("one") != 0 || pool.getOrAdd("two") != 1 || pool.getOrAdd("one") != 0) throw "String pool indexing failed";
		var finalized = pool.finalize();
		if (finalized.length != 2 || finalized.get(1) != "two") throw "String pool finalization failed";
		try {
			pool.add("three");
			throw "Finalized pool must reject additions";
		} catch (error:Dynamic) {
			if (Std.string(error).indexOf("finalized") < 0) throw error;
		}
	}
}
