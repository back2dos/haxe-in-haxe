class Json {
	static function main() {
		var n = 0;
		for (i in 0...300) {
			var data = {name: "item" + i, values: [for (j in 0...50) j * i], nested: {flag: i % 2 == 0, text: "hello world"}};
			var s = haxe.Json.stringify(data);
			var back:Dynamic = haxe.Json.parse(s);
			n += back.values.length + s.length;
		}
		Sys.println(n);
	}
}
