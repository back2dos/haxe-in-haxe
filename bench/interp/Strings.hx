class Strings {
	static function main() {
		var counts = new Map<String, Int>();
		var buf = new StringBuf();
		for (i in 0...200000) {
			var key = "k" + (i % 1000);
			counts[key] = (counts.exists(key) ? counts[key] : 0) + 1;
			if (i % 100 == 0) buf.add(key.toUpperCase());
		}
		var s = buf.toString();
		var parts = s.split("K");
		Sys.println(counts["k7"] + " " + parts.length + " " + StringTools.replace(s.substr(0, 50), "K", "-").length);
	}
}
