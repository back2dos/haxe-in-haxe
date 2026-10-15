// Pulls a broad part of the standard library into the archive.
import haxe.ds.BalancedTree;
import haxe.ds.GenericStack;
import haxe.ds.IntMap;
import haxe.ds.List;
import haxe.ds.ObjectMap;
import haxe.ds.StringMap;
import haxe.ds.Vector;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

using Lambda;
using StringTools;

class StdMain {
	static function main() {
		var m = new StringMap<Int>();
		m.set("a", 1);
		var im = new IntMap<String>();
		im.set(1, "one");
		var om = new ObjectMap<{}, Int>();
		var l = new List<Int>();
		l.add(1);
		var gs = new GenericStack<Int>();
		gs.add(1);
		var bt = new BalancedTree<String, Int>();
		bt.set("k", 1);
		var v = new Vector<Int>(3);
		var b = Bytes.ofString("hello");
		var bb = new BytesBuffer();
		bb.addByte(1);
		trace(haxe.Json.stringify({a: [1, 2], b: "x"}));
		trace(haxe.Json.parse('{"x":1}').x);
		var s = new haxe.Serializer();
		s.serialize(([1, "a", {b: true}] : Array<Dynamic>));
		trace(haxe.Unserializer.run(s.toString()));
		trace(~/a(b+)c/.match("xabbbc"));
		trace([1, 2, 3].map(x -> x * 2).filter(x -> x > 2).fold((a, b) -> a + b, 0));
		trace(" pad ".trim().lpad("-", 6));
		trace(haxe.crypto.Md5.encode("x"));
		trace(haxe.crypto.Base64.encode(b));
		trace(Std.parseInt("42") + Math.floor(2.5));
		trace(Type.getClassName(StringMap));
		trace(Reflect.fields({p: 1, q: 2}).length);
		trace(Date.fromTime(0).getTime());
		trace(haxe.EnumTools.getConstructors(haxe.ds.Option));
		var buf = new StringBuf();
		buf.add("x");
		trace(buf.toString());
		trace(haxe.Int64.toStr(haxe.Int64.make(1, 0)));
		trace(sys.FileSystem.exists("."));
		trace(haxe.io.Path.join(["a", "b"]));
		trace(haxe.Template != null);
	}
}
