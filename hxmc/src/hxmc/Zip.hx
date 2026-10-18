package hxmc;

import haxe.io.Bytes;

// Zip archives (an APK: hxmc.android.Apk; an .ipa: hxmc.ios.Bundle)
class Zip {
	// stored entries, each one's data at a multiple of its alignment (over
	// 1: the local header's extra field padded, Android's alignment field
	// 0xd935, as zipalign and apksigner write it), with a Unix mode when it
	// has one (an .ipa's executable: 0755); a fixed date (1981-01-01): the
	// same input gives the same bytes
	public static function stored(entries:Array<ZipEntry>):Bytes {
		var out = new Buf(1 << 20), cd = new Buf(4096);
		inline function dosTime(b:Buf) {
			b.u16(0); // 00:00:00
			b.u16((1 << 9) | (1 << 5) | 1); // 1981-01-01 (1980 + 1)
		}
		for (e in entries) {
			var at = out.len, name = Bytes.ofString(e.name);
			var crc = haxe.crypto.Crc32.make(e.data);
			// the data's offset: header (30) + name + extra (4 + 2 + padding)
			var aligned = e.align > 1;
			var extra = aligned ? 6 : 0, dataAt = at + 30 + name.length + extra;
			var pad = aligned ? (e.align - (dataAt % e.align)) % e.align : 0;
			extra += pad;
			out.u32(0x04034b50);
			out.u16(10); // version needed
			out.u16(0x0800); // flags: UTF-8 names
			out.u16(0); // stored
			dosTime(out);
			out.u32(crc);
			out.u32(e.data.length);
			out.u32(e.data.length);
			out.u16(name.length);
			out.u16(extra);
			out.bytes(name);
			if (aligned) {
				out.u16(0xd935);
				out.u16(extra - 4);
				out.u16(e.align);
				out.zeros(pad);
			}
			out.bytes(e.data);
			cd.u32(0x02014b50);
			cd.u16(e.mode != null ? 0x30a : 10); // version made by (3: Unix, with a mode)
			cd.u16(10);
			cd.u16(0x0800);
			cd.u16(0);
			dosTime(cd);
			cd.u32(crc);
			cd.u32(e.data.length);
			cd.u32(e.data.length);
			cd.u16(name.length);
			cd.u16(0); // extra
			cd.u16(0); // comment
			cd.u16(0); // disk
			cd.u16(0); // internal attributes
			cd.u32(e.mode != null ? (0x8000 | e.mode) << 16 : 0); // external attributes (S_IFREG | mode)
			cd.u32(at);
			cd.bytes(name);
		}
		var cdAt = out.len;
		out.buf(cd);
		out.u32(0x06054b50);
		out.u16(0);
		out.u16(0);
		out.u16(entries.length);
		out.u16(entries.length);
		out.u32(cd.len);
		out.u32(cdAt);
		out.u16(0);
		return out.toBytes();
	}
}

typedef ZipEntry = {name:String, data:Bytes, align:Int, ?mode:Int};
