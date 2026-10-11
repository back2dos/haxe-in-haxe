package libs.ziplib;

import haxe.io.Bytes;
import libs.extc.Extc;
import libs.extc.Zlib as Z;

// port: the writer side of haxe/libs/ziplib/zip.ml (open_out, add_entry,
// close_out) and zlib.ml (compress, update_crc), as used for SWC output.
private enum CompressionMethod {
	Stored;
	Deflated;
}

private typedef Entry = {
	var filename:String;
	var extra:String;
	var comment:String;
	var methd:CompressionMethod;
	var mtime:Float;
	var crc:Int;
	var uncompressed_size:Int;
	var compressed_size:Int;
	var is_directory:Bool;
	var file_offset:Int;
}

class ZipError extends haxe.Exception {
	public function new(file:String, entry:String, msg:String) super(file + ": " + entry + ": " + msg);
}

class OutFile {
	public final of_filename:String;
	public final of_channel:sys.io.FileOutput;
	public var of_entries:Array<Entry>; // port: most recent first, as the OCaml list
	public final of_comment:String;
	public var pos:Int; // port: pos_out

	public function new(filename, channel, comment) {
		of_filename = filename;
		of_channel = channel;
		of_entries = [];
		of_comment = comment;
		pos = 0;
	}
}

class Zip {
	static function write1(oc:OutFile, n:Int):Void {
		oc.of_channel.writeByte(n & 0xFF);
		oc.pos++;
	}

	static function write2(oc:OutFile, n:Int):Void {
		write1(oc, n);
		write1(oc, n >>> 8);
	}

	static function write4(oc:OutFile, n:Int):Void {
		write2(oc, n);
		write2(oc, n >>> 16);
	}

	static function write4_int(oc:OutFile, n:Int):Void {
		write2(oc, n);
		write2(oc, n >>> 16);
	}

	static function writestring(oc:OutFile, s:String):Void writebytes(oc, Bytes.ofString(s));

	static function writebytes(oc:OutFile, b:Bytes):Void {
		oc.of_channel.writeBytes(b, 0, b.length);
		oc.pos += b.length;
	}

	static function output(oc:OutFile, b:Bytes, p:Int, l:Int):Void {
		oc.of_channel.writeFullBytes(b, p, l);
		oc.pos += l;
	}

	static function filename_is_directory(name:String):Bool return name.length > 0 && name.charAt(name.length - 1) == "/";

	/* Convert between Unix dates and DOS dates */
	// port: Unix.localtime through Date (local time).
	static function dostime_of_unixtime(t:Float):{time:Int, date:Int} {
		var tm = Date.fromTime(t * 1000.);
		return {
			time: (tm.getSeconds() >>> 1) + (tm.getMinutes() << 5) + (tm.getHours() << 11),
			date: tm.getDate() + ((tm.getMonth() + 1) << 5) + ((tm.getFullYear() - 1900 - 80) << 9)
		};
	}

	/* Open a ZIP file for writing */
	// port: the optional arguments come after the required ones.
	public static function open_out(filename:String, ?comment:String = ""):OutFile {
		if (Bytes.ofString(comment).length >= 0x10000) throw new ZipError(filename, "", "comment too long");
		return new OutFile(filename, sys.io.File.write(filename, true), comment);
	}

	/* Close a ZIP file for writing.  Add central directory. */
	static function write_directory_entry(oc:OutFile, e:Entry):Void {
		write4(oc, 0x02014b50); /* signature */
		var version = switch e.methd {
			case Stored: 10;
			case Deflated: 20;
		};
		write2(oc, version); /* version made by */
		write2(oc, version); /* version needed to extract */
		write2(oc, 8); /* flags */
		write2(oc, switch e.methd {
			case Stored: 0;
			case Deflated: 8;
		}); /* method */
		var td = dostime_of_unixtime(e.mtime);
		write2(oc, td.time); /* last mod time */
		write2(oc, td.date); /* last mod date */
		write4(oc, e.crc); /* CRC32 */
		write4_int(oc, e.compressed_size); /* compressed size */
		write4_int(oc, e.uncompressed_size); /* uncompressed size */
		write2(oc, Bytes.ofString(e.filename).length); /* filename length */
		write2(oc, Bytes.ofString(e.extra).length); /* extra length */
		write2(oc, Bytes.ofString(e.comment).length); /* comment length */
		write2(oc, 0); /* disk number start */
		write2(oc, 0); /* internal attributes */
		write4_int(oc, 0); /* external attributes */
		write4(oc, e.file_offset); /* offset of local header */
		writestring(oc, e.filename); /* filename */
		writestring(oc, e.extra); /* extra info */
		writestring(oc, e.comment); /* file comment */
	}

	public static function close_out(ofile:OutFile):Void {
		var oc = ofile;
		var start_cd = oc.pos;
		var entries = ofile.of_entries.copy();
		entries.reverse();
		for (e in entries) write_directory_entry(oc, e);
		var cd_size = oc.pos - start_cd;
		var num_entries = ofile.of_entries.length;
		if (num_entries >= 0x10000) throw new ZipError(ofile.of_filename, "", "too many entries");
		write4(oc, 0x06054b50); /* signature */
		write2(oc, 0); /* disk number */
		write2(oc, 0); /* number of disk with central dir */
		write2(oc, num_entries); /* # entries in this disk */
		write2(oc, num_entries); /* # entries in central dir */
		write4_int(oc, cd_size); /* size of central dir */
		write4_int(oc, start_cd); /* offset of central dir */
		write2(oc, Bytes.ofString(ofile.of_comment).length); /* length of comment */
		writestring(oc, ofile.of_comment); /* comment */
		oc.of_channel.close();
	}

	/* Write a local file header and return the corresponding entry */
	static function add_entry_header(ofile:OutFile, extra:String, comment:String, level:Int, mtime:Float, filename:String):Entry {
		if (level < 0 || level > 9) throw new ZipError(ofile.of_filename, filename, "wrong compression level");
		if (Bytes.ofString(filename).length >= 0x10000) throw new ZipError(ofile.of_filename, filename, "filename too long");
		if (Bytes.ofString(extra).length >= 0x10000) throw new ZipError(ofile.of_filename, filename, "extra data too long");
		if (Bytes.ofString(comment).length >= 0x10000) throw new ZipError(ofile.of_filename, filename, "comment too long");
		var oc = ofile;
		var pos = oc.pos;
		write4(oc, 0x04034b50); /* signature */
		var version = if (level == 0) 10 else 20;
		write2(oc, version); /* version needed to extract */
		write2(oc, 8); /* flags */
		write2(oc, if (level == 0) 0 else 8); /* method */
		var td = dostime_of_unixtime(mtime);
		write2(oc, td.time); /* last mod time */
		write2(oc, td.date); /* last mod date */
		write4(oc, 0); /* CRC32 - to be filled later */
		write4_int(oc, 0); /* compressed size - later */
		write4_int(oc, 0); /* uncompressed size - later */
		write2(oc, Bytes.ofString(filename).length); /* filename length */
		write2(oc, Bytes.ofString(extra).length); /* extra length */
		writestring(oc, filename); /* filename */
		writestring(oc, extra); /* extra info */
		return {
			filename: filename,
			extra: extra,
			comment: comment,
			methd: (if (level == 0) Stored else Deflated),
			mtime: mtime,
			crc: 0,
			uncompressed_size: 0,
			compressed_size: 0,
			is_directory: filename_is_directory(filename),
			file_offset: pos
		};
	}

	/* Write a data descriptor and update the entry */
	static function add_data_descriptor(ofile:OutFile, crc:Int, compr_size:Int, uncompr_size:Int, entry:Entry):Entry {
		var oc = ofile;
		write4(oc, 0x08074b50); /* signature */
		write4(oc, crc); /* CRC */
		write4_int(oc, compr_size); /* compressed size */
		write4_int(oc, uncompr_size); /* uncompressed size */
		return {
			filename: entry.filename,
			extra: entry.extra,
			comment: entry.comment,
			methd: entry.methd,
			mtime: entry.mtime,
			crc: crc,
			uncompressed_size: uncompr_size,
			compressed_size: compr_size,
			is_directory: entry.is_directory,
			file_offset: entry.file_offset
		};
	}

	/* Add an entry with the contents of a string */
	public static function add_entry(data:Bytes, ofile:OutFile, name:String, ?extra:String = "", ?comment:String = "", ?level:Int = 6, ?mtime:Null<Float>):Void {
		if (mtime == null) mtime = Date.now().getTime() / 1000.;
		var e = add_entry_header(ofile, extra, comment, level, mtime, name);
		var crc = update_crc(0, data, 0, data.length);
		var compr_size = switch level {
			case 0:
				output(ofile, data, 0, data.length);
				data.length;
			case _:
				var in_pos = 0;
				var out_pos = 0;
				try {
					compress(level, false, buf -> {
						var n = Std.int(Math.min(data.length - in_pos, buf.length));
						buf.blit(0, data, in_pos, n);
						in_pos = in_pos + n;
						n;
					}, (buf, n) -> {
						output(ofile, buf, 0, n);
						out_pos = out_pos + n;
					});
					out_pos;
				} catch (_:core.ds.Failure) {
					throw new ZipError(ofile.of_filename, name, "compression error");
				}
		}
		var e2 = add_data_descriptor(ofile, crc, compr_size, data.length, e);
		ofile.of_entries.unshift(e2);
	}

	/* zlib.ml */
	static final buffer_size = 1024;

	static final crc_table = [
		for (n in 0...256) {
			var crc = n;
			for (j in 0...8) {
				crc = if (crc & 1 != 0) (crc >>> 1) ^ 0xedb88320 else crc >>> 1;
			}
			crc;
		}
	];

	static final max_wbits = 15;

	static function compress(level:Int, header:Bool, refill:Bytes->Int, flush:Bytes->Int->Void):Void {
		var inbuf = Bytes.alloc(buffer_size);
		var outbuf = Bytes.alloc(buffer_size);
		var zs = Extc.zlibDeflateInit2(level, if (header) max_wbits else -max_wbits);
		// port: the tail-recursive compr/compr_finish as loops.
		var inpos = 0, inavail = 0;
		while (true) {
			if (inavail == 0) {
				var incount = refill(inbuf);
				if (incount == 0) break;
				inpos = 0;
				inavail = incount;
			} else {
				var res = Extc.zlibDeflate(zs, inbuf, inpos, inavail, outbuf, 0, buffer_size, Z.Z_NO_FLUSH);
				flush(outbuf, res.z_wrote);
				inpos += res.z_read;
				inavail -= res.z_read;
			}
		}
		while (true) {
			var ret = Extc.zlibDeflate(zs, inbuf, 0, 0, outbuf, 0, buffer_size, Z.Z_FINISH);
			flush(outbuf, ret.z_wrote);
			if (ret.z_finish) break;
		}
		Extc.zlibDeflateEnd(zs);
	}

	static function update_crc(crc:Int, buf:Bytes, pos:Int, len:Int):Int {
		var c = ~crc;
		for (i in pos...len + pos) {
			var b = buf.get(i);
			c = crc_table[(c ^ b) & 0xFF] ^ (c >>> 8);
		}
		return ~c;
	}
}
