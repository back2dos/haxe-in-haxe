// the std over the runtime: Array's methods, Bytes, maps, Int64, dates, string switches (GcCheck)
class Library {
	static function main() {
		// Array's methods
		var a = [5, 3, 9, 1, 7];
		a.sort((x, y) -> x - y);
		Sys.println(a.join(",") + " " + a.indexOf(9) + " " + a.contains(4) + " " + a.lastIndexOf(1));
		var b = a.copy();
		b.reverse();
		Sys.println(b.toString() + " " + a.slice(1, 3) + " " + a.concat([10, 11]).length);
		var c = a.splice(1, 2);
		Sys.println(c + " " + a + " " + a.pop() + " " + a.shift() + " " + a);
		a.insert(0, 42);
		a.unshift(-1);
		a.remove(42);
		Sys.println(a + " " + a.map(x -> x * 2) + " " + a.filter(x -> x > 0));
		var words = ["pear", "apple", "fig"];
		words.sort((x, y) -> x < y ? -1 : x > y ? 1 : 0);
		Sys.println(words.join("|") + " " + [1.5, 2.25].toString());
		var total = 0;
		for (w in words.map(w -> w.length))
			total += w;
		Sys.println(total);
		// Bytes
		var bytes = haxe.io.Bytes.alloc(16);
		bytes.setInt32(0, 0x12345678);
		bytes.setDouble(4, 3.25);
		bytes.set(12, 255);
		bytes.setUInt16(13, 0xBEEF);
		Sys.println(bytes.getInt32(0) + " " + bytes.getDouble(4) + " " + bytes.get(12) + " " + bytes.getUInt16(13) + " " + bytes.length);
		var s = haxe.io.Bytes.ofString("héllo €");
		Sys.println(s.length + " " + s.toHex() + " " + s.toString() + " " + s.sub(0, 1).toString());
		var bb = new haxe.io.BytesBuffer();
		for (i in 0...70)
			bb.addByte(i);
		bb.addInt32(-2);
		bb.addDouble(1.5);
		bb.addFloat(0.25);
		bb.addString("é!");
		bb.addBytes(s, 1, 2);
		var all = bb.getBytes();
		Sys.println(bb.length + " " + all.get(69) + " " + all.getInt32(70) + " " + all.getDouble(74) + " " + all.getFloat(82) + " " + all.sub(86, 5).toHex());
		// a string of more than 24 characters (made from a data segment), and one beyond Latin-1
		Sys.println("a literal long enough for a data segment, " + "and one past Latin-1: €€€€€€€€€€€€€€€€€€€€€€€".length);
		// maps
		var m = new Map<String, Int>();
		m.set("one", 1);
		m.set("two", 2);
		m["three"] = 3;
		var keys = [for (k in m.keys()) k];
		keys.sort((x, y) -> x < y ? -1 : 1);
		Sys.println(keys.join(",") + " " + m.get("two") + " " + m.exists("four") + " " + m.remove("one") + " " + m.exists("one"));
		var im = new Map<Int, String>();
		for (i in 0...50)
			im.set(i * 7, "v" + i);
		Sys.println(im.get(49) + " " + im.get(343) + " " + Lambda.count(im));
		// (Vector<T>'s blit, generic, on a Vector<Float>)
		var v = new haxe.ds.Vector<Float>(4, 0.5), w = new haxe.ds.Vector<Float>(6, 0.0);
		v[3] = 2.5;
		haxe.ds.Vector.blit(v, 0, w, 1, 4);
		Sys.println(w.toArray());
		// (Iterator<Int>'s next on a class whose next returns Dynamic)
		var ks = [for (k in im.keys()) k];
		ks.sort((x, y) -> x - y);
		Sys.println(ks.slice(0, 5));
		// Int64
		var big = haxe.Int64.make(1, 0);
		var prod = haxe.Int64.mul(big, haxe.Int64.ofInt(1000));
		Sys.println(Std.string(prod) + " " + haxe.Int64.toStr(haxe.Int64.add(prod, haxe.Int64.ofInt(7))));
		// switch on strings, Std
		for (w in ["fig", "kiwi"])
			Sys.println(switch w {
				case "fig": "small";
				case "melon": "big";
				case _: "?";
			});
		Sys.println(Std.parseInt("0x1F") + " " + Std.parseInt("-12abc") + " " + Std.parseFloat("2.5e3") + " " + Math.max(2, 7) + " " + Math.abs(-3));
		var d = Date.fromString("2024-02-29 13:45:10");
		Sys.println(d.getFullYear() + " " + d.getMonth() + " " + d.getDate() + " " + d.getHours() + " " + d.toString());
		Sys.println(StringTools.trim("  x  ") + "|" + StringTools.lpad("7", "0", 3) + "|" + StringTools.replace("a-b-c", "-", "+") + "|" + StringTools.hex(255));
		Sys.println("done");
	}
}
