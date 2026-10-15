import Harness.*;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

using StringTools;

// Compares two HXB archives member by member (the port's self-compile check):
//   <haxe> -cp haxe/test --run HxbCmp <a.hxb> <b.hxb> [--roots <root a> <root b>]
// Without --roots the uncompressed .hxb payloads must be byte-identical. With
// --roots, archives written in different directories (and on Windows, whose
// absolute paths the port takes from the system: D:\x\src\...) are compared
// with each root replaced by one placeholder, and the separators after it by
// "/", in the strings of each module's string pool (the STR chunk), which is
// where file names are; everything else must be identical.
class HxbCmp {
	static function main() {
		var args = Sys.args();
		var roots = args.indexOf("--roots");
		var ra = null, rb = null;
		if (roots >= 0) {
			ra = args[roots + 1];
			rb = args[roots + 2];
			args.splice(roots, 3);
		}
		var r = compareArchives(args[0], args[1], ra, rb);
		Sys.println(r.line);
		Sys.exit(r.ok ? 0 : 1);
	}

	/** The comparison of two archives (roots null: byte for byte). **/
	public static function compareArchives(pa:String, pb:String, ra:Null<String>, rb:Null<String>):{ok:Bool, line:String} {
		var a = readZip(pa), b = readZip(pb);
		var na = [for (n in a.names) if (n.endsWith(".hxb")) n], nb = [for (n in b.names) if (n.endsWith(".hxb")) n];
		na.sort(compare);
		nb.sort(compare);
		var namesEqual = na.join("\n") == nb.join("\n");
		var diff = [for (n in na) if (b.data.exists(n) && normalize(a.data[n], ra).compare(normalize(b.data[n], rb)) != 0) n];
		var line = '${na.length} modules, ${namesEqual ? "names equal" : "NAMES DIFFER"}, ${diff.length} differ' + (ra != null ? " (roots normalized)" : "");
		for (n in diff.slice(0, 10)) line += "\n  differs: " + n;
		if (diff.length > 0) line += "\n  first: " + explain(normalize(a.data[diff[0]], ra), normalize(b.data[diff[0]], rb));
		var only = [for (n in na) if (!b.data.exists(n)) "a: " + n].concat([for (n in nb) if (!a.data.exists(n)) "b: " + n]);
		for (n in only.slice(0, 10)) line += "\n  only in " + n;
		return {ok: namesEqual && diff.length == 0, line: line};
	}

	static function uleb(b:Bytes, i:Int):{v:Int, i:Int} {
		var v = 0, s = 0;
		while (true) {
			var c = b.get(i++);
			v |= (c & 0x7F) << s;
			s += 7;
			if (c < 0x80) return {v: v, i: i};
		}
	}

	static function wuleb(o:BytesBuffer, v:Int) {
		while (true) {
			var c = v & 0x7F;
			v >>>= 7;
			if (v != 0) o.addByte(c | 0x80) else {
				o.addByte(c);
				return;
			}
		}
	}

	public static function normalize(b:Bytes, root:Null<String>):Bytes {
		if (root == null) return b;
		var r1 = Bytes.ofString(root), r2 = Bytes.ofString(root.replace("\\", "/"));
		var out = new BytesBuffer();
		out.addBytes(b, 0, 4); // "hxb" + version
		var i = 4;
		while (i < b.length) {
			var kind = b.getString(i, 3);
			var n = b.getInt32(i + 3);
			var data = b.sub(i + 7, n);
			i += 7 + n;
			if (kind == "STR") {
				var p = uleb(data, 0);
				var nd = new BytesBuffer();
				wuleb(nd, p.v);
				var j = p.i;
				for (_ in 0...p.v) {
					var l = uleb(data, j);
					var s = data.sub(l.i, l.v);
					j = l.i + l.v;
					for (r in [r1, r2])
						if (s.length >= r.length && s.sub(0, r.length).compare(r) == 0) {
							var rest = s.getString(r.length, s.length - r.length).replace("\\", "/");
							s = Bytes.ofString("<ROOT>" + rest);
							break;
						}
					wuleb(nd, s.length);
					nd.add(s);
				}
				data = nd.getBytes();
			}
			out.addString(kind);
			var len = Bytes.alloc(4);
			len.setInt32(0, data.length);
			out.add(len);
			out.add(data);
		}
		return out.getBytes();
	}

	static function strings(b:Bytes):Array<String> {
		var i = 4;
		while (i < b.length) {
			var kind = b.getString(i, 3);
			var n = b.getInt32(i + 3);
			var data = b.sub(i + 7, n);
			i += 7 + n;
			if (kind == "STR") {
				var p = uleb(data, 0);
				var j = p.i, out = [];
				for (_ in 0...p.v) {
					var l = uleb(data, j);
					out.push(data.getString(l.i, l.v));
					j = l.i + l.v;
				}
				return out;
			}
		}
		return [];
	}

	/** The first strings that differ between two normalized members. **/
	public static function explain(a:Bytes, b:Bytes):String {
		var sa = strings(a), sb = strings(b);
		var s = '${sa.length}/${sb.length} strings';
		var k = 0;
		for (i in 0...(sa.length < sb.length ? sa.length : sb.length))
			if (sa[i] != sb[i] && k++ < 3) s += '\n    ${haxe.Json.stringify(sa[i])} / ${haxe.Json.stringify(sb[i])}';
		return s;
	}
}
