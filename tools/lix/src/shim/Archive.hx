package shim;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.zip.InflateImpl;

using StringTools;

enum EntryKind {
	File(data:Bytes);
	Directory;
	Symlink(target:String);
	HardLink(target:String);
}

typedef ArchiveEntry = {
	final path:String;
	final mode:Int;
	final kind:EntryKind;
}

// port: what the tar and yauzl npm packages do for lix.client.Download:
// reading .tar.gz and .zip archives (in memory), with std's pure Haxe inflate
// (haxe.zip.InflateImpl; haxe.zip.Uncompress, which std's zip Reader.unzip
// uses, is not implemented on hxmc)
class Archive {
	static function inflateRaw(data:Bytes, pos:Int, len:Int):Bytes {
		var input = new BytesInput(data, pos, len);
		var inflate = new InflateImpl(input, false, false);
		var buf = Bytes.alloc(65536);
		var out = new haxe.io.BytesBuffer();
		while (true) {
			var n = inflate.readBytes(buf, 0, buf.length);
			out.addBytes(buf, 0, n);
			if (n < buf.length)
				break;
		}
		return out.getBytes();
	}

	static public function isGzip(b:Bytes)
		return b.length > 2 && b.get(0) == 0x1f && b.get(1) == 0x8b;

	static public function isZip(b:Bytes)
		return b.length > 4 && b.get(0) == 'P'.code && b.get(1) == 'K'.code && b.get(2) == 3 && b.get(3) == 4;

	/** Decompresses a gzip stream (RFC 1952). **/
	static public function gunzip(b:Bytes):Bytes {
		if (!isGzip(b) || b.get(2) != 8)
			throw new Error(UnprocessableEntity, 'Invalid gzip data');
		var flags = b.get(3);
		var pos = 10;
		if (flags & 4 != 0)
			pos += 2 + (b.get(pos) | (b.get(pos + 1) << 8));
		if (flags & 8 != 0) {
			while (b.get(pos) != 0) pos++;
			pos++;
		}
		if (flags & 16 != 0) {
			while (b.get(pos) != 0) pos++;
			pos++;
		}
		if (flags & 2 != 0)
			pos += 2;
		return inflateRaw(b, pos, b.length - pos - 8);
	}

	static function octal(b:Bytes, pos:Int, len:Int):Int {
		var ret = 0;
		for (i in pos...pos + len) {
			var c = b.get(i);
			if (c >= '0'.code && c <= '7'.code)
				ret = ret * 8 + (c - '0'.code);
			else if (c != ' '.code && ret != 0)
				break;
		}
		return ret;
	}

	static function cstring(b:Bytes, pos:Int, len:Int):String {
		var end = pos;
		while (end < pos + len && b.get(end) != 0)
			end++;
		return b.getString(pos, end - pos);
	}

	/** The entries of a tar archive (ustar, GNU long names, pax paths). **/
	static public function untar(b:Bytes):Array<ArchiveEntry> {
		var ret = [];
		var pos = 0;
		var longName:Null<String> = null,
			longLink:Null<String> = null;
		while (pos + 512 <= b.length) {
			if (b.get(pos) == 0)
				break; // end of archive
			var name = cstring(b, pos, 100);
			var mode = octal(b, pos + 100, 8);
			var size = octal(b, pos + 124, 12);
			var type = b.get(pos + 156);
			var link = cstring(b, pos + 157, 100);
			if (b.getString(pos + 257, 5) == 'ustar') {
				var prefix = cstring(b, pos + 345, 155);
				if (prefix != '')
					name = '$prefix/$name';
			}
			var data = pos + 512;
			pos = data + Std.int((size + 511) / 512) * 512;
			switch type {
				case 'L'.code:
					longName = cstring(b, data, size);
					continue;
				case 'K'.code:
					longLink = cstring(b, data, size);
					continue;
				case 'x'.code:
					for (record in b.getString(data, size).split('\n')) {
						var space = record.indexOf(' ');
						var eq = record.indexOf('=');
						if (space == -1 || eq == -1)
							continue;
						switch record.substring(space + 1, eq) {
							case 'path': longName = record.substr(eq + 1);
							case 'linkpath': longLink = record.substr(eq + 1);
							case _:
						}
					}
					continue;
				case 'g'.code:
					continue;
				case _:
			}
			if (longName != null)
				name = longName;
			if (longLink != null)
				link = longLink;
			longName = longLink = null;
			ret.push({
				path: name,
				mode: mode,
				kind: switch type {
					case '5'.code: Directory;
					case '2'.code: Symlink(link);
					case '1'.code: HardLink(link);
					case '0'.code | 0 | '7'.code: File(b.sub(data, size));
					case _: continue; // devices, fifos
				}
			});
		}
		return ret;
	}

	/** The entries of a zip archive, read from its central directory. **/
	static public function unzip(b:Bytes):Array<ArchiveEntry> {
		var end = b.length - 22;
		while (end >= 0 && b.getInt32(end) != 0x06054b50)
			end--;
		if (end < 0)
			throw new Error(UnprocessableEntity, 'Unzip failed to find central directory');
		var count = b.getUInt16(end + 10);
		var pos = b.getInt32(end + 16);
		var ret = [];
		for (_ in 0...count) {
			if (b.getInt32(pos) != 0x02014b50)
				throw new Error(UnprocessableEntity, 'Invalid zip central directory');
			var madeBy = b.getUInt16(pos + 4) >> 8;
			var method = b.getUInt16(pos + 10);
			var compressed = b.getInt32(pos + 20);
			var nameLen = b.getUInt16(pos + 28);
			var extraLen = b.getUInt16(pos + 30);
			var commentLen = b.getUInt16(pos + 32);
			var attrs = b.getInt32(pos + 38);
			var local = b.getInt32(pos + 42);
			var name = b.getString(pos + 46, nameLen);
			pos += 46 + nameLen + extraLen + commentLen;

			var mode = madeBy == 3 ? (attrs >>> 16) & 0xFFFF : 0;
			var data = local + 30 + b.getUInt16(local + 26) + b.getUInt16(local + 28);
			function content()
				return switch method {
					case 0: b.sub(data, compressed);
					case 8: inflateRaw(b, data, compressed);
					case v: throw new Error(UnprocessableEntity, 'Unsupported zip compression method $v for $name');
				}
			ret.push({
				path: name,
				mode: mode & 0xFFF,
				kind:
					if (name.endsWith('/')) Directory;
					else if (mode & 0xF000 == 0xA000) Symlink(content().toString());
					else File(content())
			});
		}
		return ret;
	}
}
