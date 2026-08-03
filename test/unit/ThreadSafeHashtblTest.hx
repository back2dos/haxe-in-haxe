package unit;

import core.ds.ThreadSafeHashtbl;

class ThreadSafeHashtblTest {
	public static function main():Void {
		var table = new ThreadSafeHashtbl<String, Int>(16);
		table.add("one", 1);
		table.replace("one", 2);
		if (table.find("one") != 2) throw "Hash table lookup failed";
		var invoked = 0;
		if (table.findOrAdd("one", function() return ++invoked) != 2 || invoked != 0) throw "Existing key must not be recreated";
		if (table.findOrAdd("two", function() return ++invoked) != 1 || invoked != 1) throw "Missing key must be created once";
		if (table.fold(function(_, value, total) return total + value, 0) != 3) throw "Hash table fold failed";
		table.remove("one");
		if (table.exists("one")) throw "Hash table removal failed";
	}
}
