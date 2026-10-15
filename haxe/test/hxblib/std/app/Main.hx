import haxe.ds.BalancedTree;
import haxe.ds.IntMap;
import haxe.ds.Option;
import haxe.ds.StringMap;

using Lambda;
using StringTools;

class Main {
	static function main() {
		var m = new StringMap<Array<Int>>();
		m.set("x", [3, 1, 2]);
		var a = m.get("x");
		a.sort(Reflect.compare);
		trace(a);
		var im = new IntMap<String>();
		for (i in 0...5)
			im.set(i, "v" + i);
		trace([for (k in im.keys()) k].length);
		var bt = new BalancedTree<String, Int>();
		bt.set("b", 2);
		bt.set("a", 1);
		trace([for (k in bt.keys()) k]);
		trace(haxe.Json.stringify({list: [for (i in 0...3) i * i]}));
		var o:Option<String> = Some("s");
		trace(switch o {
			case Some(v): v.toUpperCase();
			case None: "none";
		});
		trace("a,b,,c".split(",").filter(s -> s.length > 0).join("|"));
		trace("hello world".replace("o", "0").startsWith("hell"));
		trace([1, 2, 3, 4].exists(x -> x > 3) && [1, 2].has(2));
		var re = ~/(\d+)-(\d+)/;
		if (re.match("10-20"))
			trace(Std.parseInt(re.matched(1)) + Std.parseInt(re.matched(2)));
		var b = haxe.io.Bytes.alloc(4);
		b.setInt32(0, 0x01020304);
		trace(b.toHex());
		trace(haxe.crypto.Sha1.encode("abc"));
		trace(haxe.Unserializer.run(haxe.Serializer.run({k: ([1.5, "s"] : Array<Dynamic>)})).k);
		var l = new haxe.ds.List<Int>();
		l.push(1);
		l.add(2);
		trace(l.length);
		trace(Math.max(1, 2) + Math.abs(-3));
		trace(Type.enumConstructor(o));
		trace(StringTools.hex(255, 4));
		trace(Date.fromString("2020-01-02").getFullYear());
	}
}
