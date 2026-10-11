package libs.swflib;

import haxe.io.Bytes;
import libs.extlib.IO;
import libs.extlib.IO.Output;
import libs.swflib.Swf;

// port: the LENGTH and writing sections of haxe/libs/swflib/swfParser.ml for
// the tags of Swf.hx, and `init`. Parsing and `scan` (used to merge SWF
// libraries) are not ported.
class SwfParser {
	static var swf_version = 0;
	static final tag_end:Tag = {tid: 0, textended: false, tdata: TEnd};

	// port: Swf.__deflate, installed by init.
	static var deflate_fn:Null<Output->Output>;

	static function sum<T>(f:T->Int, l:Array<T>):Int {
		var acc = 0;
		for (x in l) acc += f(x);
		return acc;
	}

	static function bytes_opt_len(x:Null<Bytes>):Int return x == null ? 0 : x.length;

	static function make_flags(l:Array<Bool>):Int {
		var r = 0;
		var i = l.length;
		while (i-- > 0) r = (if (l[i]) 1 else 0) | (r << 1);
		return r;
	}

	/* ************************************************************************ */
	/* LENGTH */
	static function rect_nbits(r:Rect):Int return r.rect_nbits;

	static final rgb_length = 3;

	// port: OCaml strings are bytes: the length of the UTF-8 encoding.
	static function string_length(s:String):Int return Bytes.ofString(s).length + 1;

	static function rect_length(r:Rect):Int {
		var nbits = rect_nbits(r);
		var nbits = nbits * 4 + 5;
		return Std.int((nbits + 7) / 8);
	}

	static function bitmap_lossless_length(b:BitmapLossless):Int return 2 + 1 + 2 + 2 + b.bll_data.length;

	static function sound_length(s:Sound):Int return 2 + 1 + 4 + s.so_data.length;

	static function tag_data_length(t:TagData):Int return switch t {
		case TEnd:
			0;
		case TShowFrame:
			0;
		case TSetBgColor(_):
			rgb_length;
		case TSound(s):
			sound_length(s);
		case TBitsJPEG2(b):
			2 + bytes_opt_len(b.bd_table) + b.bd_data.length;
		case TBitsJPEG3(b):
			2 + 4 + bytes_opt_len(b.bd_table) + b.bd_data.length + bytes_opt_len(b.bd_alpha);
		case TBitsLossless2(b):
			bitmap_lossless_length(b);
		case TEnableDebugger2(_, pass):
			2 + string_length(pass);
		case TScriptLimits(_):
			4;
		case TFilesAttributes(_):
			4;
		case TF9Classes(l):
			2 + sum(c -> string_length(c.f9_classname) + 2, l);
		case TMetaData(meta):
			meta.length + 1;
		case TActionScript3(id, a):
			(switch id {
				case null: 0;
				case {frame: f}: 4 + string_length(f);
			}) + As3parse.as3_length(a);
		case TScenes(sl, fl):
			As3parse.int_length(sl.length) + sum(x -> As3parse.int_length(x.n) + string_length(x.s), sl) + As3parse.int_length(fl.length)
			+ sum(x -> As3parse.int_length(x.n) + string_length(x.s), fl);
		case TBinaryData(_, data):
			2 + 4 + data.length;
		case TUnknown(_, data):
			data.length;
	}

	static function tag_length(t:Tag):Int {
		var dlen = tag_data_length(t.tdata);
		return dlen + 2 + (if (t.textended || dlen >= 63) 4 else 0);
	}

	/* ************************************************************************ */
	/* WRITING */
	static function write_rgb(ch:Output, c:Rgb):Void {
		IO.writeByte(ch, c.cr);
		IO.writeByte(ch, c.cg);
		IO.writeByte(ch, c.cb);
	}

	static function write_rect(ch:Output, r:Rect):Void {
		var b = IO.outputBits(ch);
		var nbits = rect_nbits(r);
		IO.writeBits(b, 5, nbits);
		IO.writeBits(b, nbits, r.left);
		IO.writeBits(b, nbits, r.right);
		IO.writeBits(b, nbits, r.top);
		IO.writeBits(b, nbits, r.bottom);
		IO.flushBits(b);
	}

	static function write_bitmap_lossless(ch:Output, b:BitmapLossless):Void {
		IO.writeUi16(ch, b.bll_id);
		IO.writeByte(ch, b.bll_format);
		IO.writeUi16(ch, b.bll_width);
		IO.writeUi16(ch, b.bll_height);
		IO.nwrite(ch, b.bll_data);
	}

	static function tag_id(t:TagData):Int return switch t {
		case TEnd: 0x00;
		case TShowFrame: 0x01;
		case TSetBgColor(_): 0x09;
		case TSound(_): 0x0E;
		case TBitsJPEG2(_): 0x15;
		case TBitsJPEG3(_): 0x23;
		case TBitsLossless2(_): 0x24;
		case TEnableDebugger2(_): 0x40;
		case TScriptLimits(_): 0x41;
		case TFilesAttributes(_): 0x45;
		case TF9Classes(_): 0x4C;
		case TMetaData(_): 0x4D;
		case TActionScript3(null, _): 0x48;
		case TActionScript3(_): 0x52;
		case TScenes(_): 0x56;
		case TBinaryData(_): 0x57;
		case TUnknown(id, _): id;
	}

	static function write_tag_data(ch:Output, t:TagData):Void {
		switch t {
			case TEnd:
			case TShowFrame:
			case TSetBgColor(c):
				write_rgb(ch, c);
			case TSound(s):
				IO.writeUi16(ch, s.so_id);
				IO.writeByte(ch, s.so_flags);
				IO.writeI32(ch, s.so_samples);
				IO.nwrite(ch, s.so_data);
			case TBitsJPEG2(b):
				IO.writeUi16(ch, b.bd_id);
				if (b.bd_table != null) IO.nwrite(ch, b.bd_table);
				IO.nwrite(ch, b.bd_data);
			case TBitsJPEG3(b):
				IO.writeUi16(ch, b.bd_id);
				IO.writeI32(ch, b.bd_data.length + bytes_opt_len(b.bd_table));
				if (b.bd_table != null) IO.nwrite(ch, b.bd_table);
				IO.nwrite(ch, b.bd_data);
				if (b.bd_alpha != null) IO.nwrite(ch, b.bd_alpha);
			case TBitsLossless2(b):
				write_bitmap_lossless(ch, b);
			case TEnableDebugger2(tag, pass):
				IO.writeUi16(ch, tag);
				IO.writeString(ch, pass);
			case TScriptLimits(recursion_depth, script_timeout):
				IO.writeUi16(ch, recursion_depth);
				IO.writeUi16(ch, script_timeout);
			case TFilesAttributes(f):
				var flags = make_flags([f.fa_network, false, false, f.fa_as3, f.fa_metadata, f.fa_gpu, f.fa_direct_blt]);
				IO.writeI32(ch, flags);
			case TF9Classes(l):
				IO.writeUi16(ch, l.length);
				for (c in l) {
					IO.writeUi16(ch, (switch c.f9_cid {
						case null: 0;
						case id: id;
					}));
					IO.writeString(ch, c.f9_classname);
				}
			case TMetaData(meta):
				IO.nwrite(ch, meta);
				IO.write(ch, 0);
			case TActionScript3(id, a):
				switch id {
					case null:
					case {id: id, frame: frame}:
						IO.writeI32(ch, id);
						IO.writeString(ch, frame);
				}
				As3parse.write(ch, a);
			case TScenes(sl, fl):
				As3parse.write_int(ch, sl.length);
				for (x in sl) {
					As3parse.write_int(ch, x.n);
					IO.writeString(ch, x.s);
				}
				As3parse.write_int(ch, fl.length);
				for (x in fl) {
					As3parse.write_int(ch, x.n);
					IO.writeString(ch, x.s);
				}
			case TBinaryData(id, data):
				IO.writeUi16(ch, id);
				IO.writeI32(ch, 0);
				IO.nwrite(ch, data);
			case TUnknown(_, data):
				IO.nwrite(ch, data);
		}
	}

	static function write_tag(ch:Output, t:Tag):Void {
		var id = tag_id(t.tdata);
		var dlen = tag_data_length(t.tdata);
		if (t.textended || dlen >= 63) {
			IO.writeUi16(ch, (id << 6) | 63);
			IO.writeI32(ch, dlen);
		} else {
			IO.writeUi16(ch, (id << 6) | dlen);
		}
		write_tag_data(ch, t.tdata);
	}

	public static function write(ch:Output, swf:SwfData):Void {
		var h = swf.header, tags = swf.tags;
		swf_version = h.h_version;
		IO.nwriteString(ch, if (h.h_compressed) "CWS" else "FWS");
		// port: char_of_int raises Invalid_argument outside 0..255.
		if (h.h_version < 0 || h.h_version > 255) throw new core.ds.InvalidArgument("char_of_int");
		IO.write(ch, h.h_version);
		var len = tag_length(tag_end);
		for (t in tags) len += tag_length(t);
		var len = len + 4 + 4 + rect_length(h.h_size) + 2 + 2;
		IO.writeI32(ch, len);
		var ch = (if (h.h_compressed) deflate_fn(ch) else ch);
		write_rect(ch, h.h_size);
		IO.writeUi16(ch, h.h_fps);
		IO.writeUi16(ch, h.h_frame_count);
		for (t in tags) write_tag(ch, t);
		write_tag(ch, tag_end);
		if (h.h_compressed) IO.closeOut(ch);
	}

	// port: init installs the deflater only (no SWF is parsed).
	public static function init(deflate:Output->Output):Void {
		deflate_fn = deflate;
	}
}
