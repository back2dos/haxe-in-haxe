package libs.swflib;

import haxe.io.Bytes;
import libs.extlib.IO;
import libs.extlib.IO.Input;
import libs.extlib.IO.Output;
import libs.extlib.IO.InBits;
import libs.extlib.IO.OutBits;
import libs.swflib.Swf;
import libs.swflib.ActionScript.actions_length;
import libs.swflib.ActionScript.parse_actions;
import libs.swflib.ActionScript.write_actions;

// port: haxe/libs/swflib/swfParser.ml. `tag_name` (a debug printer) has no
// caller in the compiler and is not translated.
class SwfParser {
	static function assertFalse():Dynamic throw new core.ds.Failure("assert false");

	/* ************************************************************************ */
	/* TOOLS */
	public static var full_parsing = true;
	public static var force_as3_parsing = false;
	static var swf_version = 0;
	static var id_count = 0;
	static final tag_end:Tag = {tid: 0, textended: false, tdata: TEnd};

	static function sum<T>(f:T->Int, l:Array<T>):Int {
		var acc = 0;
		for (x in l) acc += f(x);
		return acc;
	}

	static function gen_id():Int {
		id_count++;
		return id_count;
	}

	static function opt_len<T>(f:T->Int, x:Null<T>):Int return x == null ? 0 : f(x);

	// port: String.length of a binary payload.
	static function blen(b:Bytes):Int return b.length;

	static function opt_flag<T>(flags:Int, fid:Int, f:Input->T, fparam:Input):Null<T> {
		if ((flags & fid) == 0)
			return null
		else
			return f(fparam);
	}

	static function flag(x:Null<Dynamic>):Bool return x != null;

	static function make_flags(l:Array<Bool>):Int {
		var r = 0;
		var i = l.length;
		while (i-- > 0) r = (if (l[i]) 1 else 0) | (r << 1);
		return r;
	}

	static function read_count<T>(n:Int, f:Void->T):Array<T> {
		var l = [];
		for (_ in 0...n) l.push(f());
		return l;
	}

	// port: OCaml strings are bytes: the length of the UTF-8 encoding.
	static inline function slen(s:String):Int return Bytes.ofString(s).length;

	/* ************************************************************************ */
	/* LENGTH */
	static function _nbits(x:Int):Int {
		if (x < 0) Swf.error("Negative nbits");
		if (x == 0)
			return 0
		else {
			var x = x;
			var nbits = 0;
			while (x > 0) {
				x = x >>> 1;
				nbits++;
			}
			return nbits;
		}
	}

	static function rect_nbits(r:Rect):Int return r.rect_nbits;

	static function bigrect_nbits(r:BigRect):Int return r.brect_nbits;

	static function cxa_nbits(c:ColorTransformAlpha):Int return c.cxa_nbits;

	static function matrix_part_nbits(m:MatrixPart):Int return m.m_nbits;

	static final rgb_length = 3;

	static final rgba_length = 4;

	static function string_length(s:String):Int return slen(s) + 1;

	static function color_length(c:Color):Int return switch c {
		case ColorRGB(_): rgb_length;
		case ColorRGBA(_): rgba_length;
	}

	static function rect_length(r:Rect):Int {
		var nbits = rect_nbits(r);
		var nbits = nbits * 4 + 5;
		return Std.int((nbits + 7) / 8);
	}

	static function big_rect_length(r:BigRect):Int {
		var nbits = bigrect_nbits(r);
		var nbits = nbits * 4 + 5;
		return Std.int((nbits + 7) / 8);
	}

	static function gradient_length(g:Gradient):Int return switch g {
		case GradientRGB(l, _): 1 + (1 + rgb_length) * l.length;
		case GradientRGBA(l, _): 1 + (1 + rgba_length) * l.length;
	}

	static function matrix_length(m:Matrix):Int {
		function matrix_part_len(m:MatrixPart) return 5 + matrix_part_nbits(m) * 2;
		var nbits = 2 + opt_len(matrix_part_len, m.scale) + opt_len(matrix_part_len, m.rotate) + matrix_part_len(m.trans);
		return Std.int((nbits + 7) / 8);
	}

	static function cxa_length(c:ColorTransformAlpha):Int {
		var nbits = cxa_nbits(c);
		var nbits = 6 + opt_len(_ -> nbits * 4, c.cxa_add) + opt_len(_ -> nbits * 4, c.cxa_mult);
		return Std.int((nbits + 7) / 8);
	}

	static function clip_event_length(c:ClipEvent):Int {
		return (if (swf_version >= 6) 4 else 2) + 4 + (opt_len(_ -> 1, c.cle_key)) + actions_length(c.cle_actions);
	}

	static function clip_events_length(l:Array<ClipEvent>):Int {
		return (if (swf_version >= 6) 10 else 6) + sum(clip_event_length, l);
	}

	static function export_length(e:Export):Int return 2 + string_length(e.exp_name);

	static function import_length(i:Import):Int return 2 + string_length(i.imp_name);

	static function sound_length(s:Sound):Int return 2 + 1 + 4 + s.so_data.length;

	static function shape_fill_style_length(s:ShapeFillStyle):Int {
		return 1 + switch s {
			case SFSSolid(_): rgb_length;
			case SFSSolid3(_): rgba_length;
			case SFSLinearGradient(m, g) | SFSRadialGradient(m, g, null): matrix_length(m) + gradient_length(g);
			case SFSRadialGradient(m, g, _): matrix_length(m) + gradient_length(g) + 2;
			case SFSBitmap(b): 2 + matrix_length(b.sfb_mpos);
		}
	}

	static function shape_line_style_length(s:ShapeLineStyle):Int {
		return 2 + switch s.sls_flags {
			case null:
				color_length(s.sls_color);
			case _:
				2 + (switch s.sls_fill {
					case null: color_length(s.sls_color);
					case f: shape_fill_style_length(f);
				}) + opt_len(_ -> 2, s.sls_miter);
		}
	}

	static function shape_array_length<T>(f:T->Int, s:Array<T>):Int {
		var n = s.length;
		return (if (n < 0xFF) 1 else 3) + sum(f, s);
	}

	static function shape_new_styles_length(s:ShapeNewStyles):Int {
		return shape_array_length(shape_fill_style_length, s.sns_fill_styles) + shape_array_length(shape_line_style_length, s.sns_line_styles) + 1;
	}

	static function shape_records_length(records:ShapeRecords):Int {
		var nbits = 8;
		var nfbits = records.srs_nfbits;
		var nlbits = records.srs_nlbits;
		for (r in records.srs_records) {
			nbits = nbits + 6;
			switch r {
				case SRStyleChange(s):
					nbits = nbits
						+ opt_len(m -> 5 + m.n * 2, s.scsr_move)
						+ opt_len(_ -> nfbits, s.scsr_fs0)
						+ opt_len(_ -> nfbits, s.scsr_fs1)
						+ opt_len(_ -> nlbits, s.scsr_ls);
					switch s.scsr_new_styles {
						case null:
						case s:
							nbits = ((Std.int((nbits + 7) / 8)) + shape_new_styles_length(s)) * 8;
							nfbits = s.sns_nfbits;
							nlbits = s.sns_nlbits;
					}
				case SRCurvedEdge(s):
					nbits = nbits + s.scer_nbits * 4;
				case SRStraightEdge(s):
					nbits = nbits + 1 + (switch [s.sser_line.dx, s.sser_line.dy] {
						case [null, null]: assertFalse();
						case [_, null] | [null, _]: 1 + s.sser_nbits;
						case [_, _]: 2 * s.sser_nbits;
					});
			}
		}
		nbits = nbits + 6;
		return Std.int((nbits + 7) / 8);
	}

	static function shape_with_style_length(s:ShapeWithStyle):Int {
		return shape_array_length(shape_fill_style_length, s.sws_fill_styles)
			+ shape_array_length(shape_line_style_length, s.sws_line_styles)
			+ shape_records_length(s.sws_records);
	}

	static function shape_length(s:Shape):Int {
		return 2 + rect_length(s.sh_bounds) + opt_len(b -> rect_length(b.r) + 1, s.sh_bounds2) + shape_with_style_length(s.sh_style);
	}

	static function bitmap_lossless_length(b:BitmapLossless):Int return 2 + 1 + 2 + 2 + b.bll_data.length;

	static function morph_shape_length(s:MorphShape):Int {
		return 2 + rect_length(s.msh_start_bounds) + rect_length(s.msh_end_bounds) + s.msh_data.length;
	}

	static function text_record_length(t:Text, r:TextRecord):Int {
		return 1
			+ opt_len(_ -> 4, r.txr_font)
			+ opt_len(color_length, r.txr_color)
			+ opt_len(_ -> 2, r.txr_dx)
			+ opt_len(_ -> 2, r.txr_dy)
			+ 1
			+ (Std.int((((t.txt_ngbits + t.txt_nabits) * r.txr_glyphs.length) + 7) / 8));
	}

	static function text_length(t:Text):Int {
		return 2 + big_rect_length(t.txt_bounds) + matrix_length(t.txt_matrix) + 2 + sum(text_record_length.bind(t), t.txt_records) + 1;
	}

	static function filters_length(l:Array<Filter>):Int {
		return 1 + sum(f -> 1 + switch f {
			case FDropShadow(s) | FBlur(s) | FGlow(s) | FBevel(s) | FAdjustColor(s):
				s.length;
			case FGradientGlow(fg) | FGradientBevel(fg):
				1 + ((rgba_length + 1) * fg.fgr_colors.length) + fg.fgr_data.length;
		}, l);
	}

	static function button_record_length(r:ButtonRecord):Int {
		return 1 + 2 + 2 + matrix_length(r.btr_mpos) + (switch r.btr_color {
			case null: 0;
			case c: cxa_length(c);
		}) + opt_len(filters_length, r.btr_filters) + (switch r.btr_blendmode {
			case null: 0;
			case c: 1;
		});
	}

	static function button_action_length(r:ButtonAction):Int return 2 + 2 + actions_length(r.bta_actions);

	static function button2_length(b:Button2):Int {
		return 2 + 1 + 2 + 1 + sum(button_record_length, b.bt2_records) + sum(button_action_length, b.bt2_actions);
	}

	static function cid_data_length(c:CidData):Int return 2 + c.cd_data.length;

	static final edit_text_layout_length = 9;

	static function edit_text_length(t:EditText):Int {
		return 2
			+ rect_length(t.edt_bounds)
			+ 2
			+ opt_len(_ -> 4, t.edt_font)
			+ opt_len(_ -> rgba_length, t.edt_color)
			+ opt_len(_ -> 2, t.edt_maxlen)
			+ opt_len(_ -> edit_text_layout_length, t.edt_layout)
			+ string_length(t.edt_variable)
			+ opt_len(string_length, t.edt_text);
	}

	static function place_object_length(p:PlaceObject, v3:Bool):Int {
		return 3
			+ (if (v3) 1 else 0)
			+ 0 /* po_move */
			+ opt_len(_ -> 2, p.po_cid)
			+ opt_len(matrix_length, p.po_matrix)
			+ opt_len(cxa_length, p.po_color)
			+ opt_len(_ -> 2, p.po_ratio)
			+ opt_len(string_length, p.po_inst_name)
			+ opt_len(_ -> 2, p.po_clip_depth)
			+ opt_len(clip_events_length, p.po_events)
			+ (if (v3) opt_len(filters_length, p.po_filters) + opt_len(_ -> 1, p.po_blend) + opt_len(_ -> 1, p.po_bcache) else 0);
	}

	static function tag_data_length(t:TagData):Int return switch t {
		case TEnd:
			0;
		case TShowFrame:
			0;
		case TShape(s):
			shape_length(s);
		case TRemoveObject(_):
			4;
		case TBitsJPEG(b):
			2 + b.jpg_data.length;
		case TJPEGTables(tab):
			tab.length;
		case TSetBgColor(_):
			rgb_length;
		case TFont(c):
			cid_data_length(c);
		case TText(t):
			text_length(t);
		case TDoAction(acts):
			actions_length(acts);
		case TFontInfo(c):
			cid_data_length(c);
		case TSound(s):
			sound_length(s);
		case TStartSound(s):
			2 + s.sts_data.length;
		case TBitsLossless(b):
			bitmap_lossless_length(b);
		case TBitsJPEG2(b):
			2 + opt_len(blen, b.bd_table) + b.bd_data.length;
		case TShape2(s):
			shape_length(s);
		case TProtect:
			0;
		case TPlaceObject2(p):
			place_object_length(p, false);
		case TRemoveObject2(_):
			2;
		case TShape3(s):
			shape_length(s);
		case TText2(t):
			text_length(t);
		case TButton2(b):
			button2_length(b);
		case TBitsJPEG3(b):
			2 + 4 + opt_len(blen, b.bd_table) + b.bd_data.length + opt_len(blen, b.bd_alpha);
		case TBitsLossless2(b):
			bitmap_lossless_length(b);
		case TEditText(t):
			edit_text_length(t);
		case TClip(c):
			4 + sum(tag_length, [tag_end].concat(c.c_tags));
		case TProductInfo(s):
			s.length;
		case TFrameLabel(label, id):
			string_length(label) + (switch id {
				case null: 0;
				case _: 1;
			});
		case TSoundStreamHead2(data):
			data.length;
		case TMorphShape(s) | TMorphShape2(s):
			morph_shape_length(s);
		case TFont2(c) | TFont3(c) | TFontAlignZones(c):
			cid_data_length(c);
		case TExport(el):
			2 + sum(export_length, el);
		case TImport(url, il):
			string_length(url) + 2 + sum(import_length, il);
		case TDoInitAction(i):
			2 + actions_length(i.dia_actions);
		case TVideoStream(c):
			cid_data_length(c);
		case TVideoFrame(c):
			cid_data_length(c);
		case TFontInfo2(c):
			cid_data_length(c);
		case TDebugID(s):
			s.length;
		case TEnableDebugger2(_, pass):
			2 + string_length(pass);
		case TScriptLimits(_):
			4;
		case TFilesAttributes(_):
			4;
		case TPlaceObject3(p):
			place_object_length(p, true);
		case TImport2(url, il):
			string_length(url) + 1 + 1 + 2 + sum(import_length, il);
		case TCSMSettings(c):
			cid_data_length(c);
		case TF9Classes(l):
			2 + sum(c -> string_length(c.f9_classname) + 2, l);
		case TMetaData(meta):
			meta.length + 1;
		case TScale9(_, r):
			2 + rect_length(r);
		case TActionScript3(id, a):
			(switch id {
				case null: 0;
				case {frame: f}: 4 + string_length(f);
			}) + As3parse.as3_length(a);
		case TShape4(s):
			shape_length(s);
		case TScenes(sl, fl):
			As3parse.int_length(sl.length) + sum(x -> As3parse.int_length(x.n) + string_length(x.s), sl) + As3parse.int_length(fl.length)
			+ sum(x -> As3parse.int_length(x.n) + string_length(x.s), fl);
		case TBinaryData(_, data):
			2 + 4 + data.length;
		case TBigBinaryData(_, data):
			var acc = 0;
			for (s in data) acc = acc + s.length;
			2 + 4 + acc;
		case TFontName(c):
			cid_data_length(c);
		case TBitsJPEG4(b):
			2 + 2 + 4 + opt_len(blen, b.bd_table) + b.bd_data.length + opt_len(blen, b.bd_alpha);
		case TFont4(c):
			cid_data_length(c);
		case TUnknown(_, data):
			data.length;
	}

	static function tag_length(t:Tag):Int {
		var dlen = tag_data_length(t.tdata);
		return dlen + 2 + (if (t.textended || dlen >= 63) 4 else 0);
	}

	/* ************************************************************************ */
	/* READ PRIMS */
	static function read_rgba(ch:Input):Rgba {
		var r = IO.readByte(ch);
		var g = IO.readByte(ch);
		var b = IO.readByte(ch);
		var a = IO.readByte(ch);
		return {
			r: r,
			g: g,
			b: b,
			a: a,
		};
	}

	static function read_rgb(ch:Input):Rgb {
		var r = IO.readByte(ch);
		var g = IO.readByte(ch);
		var b = IO.readByte(ch);
		return {
			cr: r,
			cg: g,
			cb: b,
		};
	}

	static function read_gradient(ch:Input, is_rgba:Bool):Gradient {
		function grad_rgb() {
			var r = IO.readByte(ch);
			var c = read_rgb(ch);
			return {ratio: r, c: c};
		}
		function grad_rgba() {
			var r = IO.readByte(ch);
			var c = read_rgba(ch);
			return {ratio: r, c: c};
		}
		var n = IO.readByte(ch);
		var flags = n >>> 4;
		var n = n & 0xF;
		if (is_rgba)
			return GradientRGBA(read_count(n, grad_rgba), flags)
		else
			return GradientRGB(read_count(n, grad_rgb), flags);
	}

	static function read_rect(ch:Input):Rect {
		var b = IO.inputBits(ch);
		var nbits = IO.readBits(b, 5);
		var left = IO.readBits(b, nbits);
		var right = IO.readBits(b, nbits);
		var top = IO.readBits(b, nbits);
		var bottom = IO.readBits(b, nbits);
		return {
			rect_nbits: nbits,
			left: left,
			right: right,
			top: top,
			bottom: bottom,
		};
	}

	static function read_multi_bits(b:InBits, n:Int):Array<Int> {
		if (n <= 30)
			return [IO.readBits(b, n)]
		else {
			var d = IO.readBits(b, 30);
			return [d].concat(read_multi_bits(b, n - 30));
		}
	}

	static function read_big_rect(ch:Input):BigRect {
		var b = IO.inputBits(ch);
		var nbits = IO.readBits(b, 5);
		var left = read_multi_bits(b, nbits);
		var right = read_multi_bits(b, nbits);
		var top = read_multi_bits(b, nbits);
		var bottom = read_multi_bits(b, nbits);
		return {
			brect_nbits: nbits,
			bleft: left,
			bright: right,
			btop: top,
			bbottom: bottom,
		};
	}

	static function read_matrix(ch:Input):Matrix {
		var b = IO.inputBits(ch);
		function read_matrix_part():MatrixPart {
			var nbits = IO.readBits(b, 5);
			var x = IO.readBits(b, nbits);
			var y = IO.readBits(b, nbits);
			return {
				m_nbits: nbits,
				mx: x,
				my: y,
			};
		}
		var has_scale = (IO.readBits(b, 1) == 1);
		var scale = (if (has_scale) read_matrix_part() else null);
		var has_rotate = (IO.readBits(b, 1) == 1);
		var rotate = (if (has_rotate) read_matrix_part() else null);
		var trans = read_matrix_part();
		return {
			scale: scale,
			rotate: rotate,
			trans: trans,
		};
	}

	static function read_cxa(ch:Input):ColorTransformAlpha {
		var b = IO.inputBits(ch);
		var has_add = (IO.readBits(b, 1) == 1);
		var has_mult = (IO.readBits(b, 1) == 1);
		var nbits = IO.readBits(b, 4);
		function read_cxa_color():Rgba {
			var r = IO.readBits(b, nbits);
			var g = IO.readBits(b, nbits);
			var bl = IO.readBits(b, nbits);
			var a = IO.readBits(b, nbits);
			return {
				r: r,
				g: g,
				b: bl,
				a: a,
			};
		}
		var mult = (if (has_mult) read_cxa_color() else null);
		var add = (if (has_add) read_cxa_color() else null);
		return {
			cxa_nbits: nbits,
			cxa_add: add,
			cxa_mult: mult,
		};
	}

	static function read_event(ch:Input):Int {
		return if (swf_version >= 6) IO.readI32(ch) else IO.readUi16(ch);
	}

	/* ************************************************************************ */
	/* WRITE PRIMS */
	static function write_rgb(ch:Output, c:Rgb):Void {
		IO.writeByte(ch, c.cr);
		IO.writeByte(ch, c.cg);
		IO.writeByte(ch, c.cb);
	}

	static function write_rgba(ch:Output, c:Rgba):Void {
		IO.writeByte(ch, c.r);
		IO.writeByte(ch, c.g);
		IO.writeByte(ch, c.b);
		IO.writeByte(ch, c.a);
	}

	static function write_color(ch:Output, c:Color):Void {
		switch c {
			case ColorRGB(c):
				write_rgb(ch, c);
			case ColorRGBA(c):
				write_rgba(ch, c);
		}
	}

	static function write_gradient(ch:Output, g:Gradient):Void {
		switch g {
			case GradientRGB(l, flags):
				var n = l.length;
				IO.writeByte(ch, n | (flags << 4));
				for (x in l) {
					IO.writeByte(ch, x.ratio);
					write_rgb(ch, x.c);
				}
			case GradientRGBA(l, flags):
				var n = l.length;
				IO.writeByte(ch, n | (flags << 4));
				for (x in l) {
					IO.writeByte(ch, x.ratio);
					write_rgba(ch, x.c);
				}
		}
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

	static function write_multi_bits(b:OutBits, n:Int, l:Array<Int>):Void {
		if (n <= 30) {
			switch l {
				case []:
					IO.writeBits(b, n, 0);
				case [x]:
					IO.writeBits(b, n, x);
				case _:
					assertFalse();
			}
		} else {
			switch l {
				case []:
					IO.writeBits(b, 30, 0);
					write_multi_bits(b, n - 30, []);
				case _:
					IO.writeBits(b, 30, l[0]);
					write_multi_bits(b, n - 30, l.slice(1));
			}
		}
	}

	static function write_big_rect(ch:Output, r:BigRect):Void {
		var b = IO.outputBits(ch);
		var nbits = bigrect_nbits(r);
		IO.writeBits(b, 5, nbits);
		write_multi_bits(b, nbits, r.bleft);
		write_multi_bits(b, nbits, r.bright);
		write_multi_bits(b, nbits, r.btop);
		write_multi_bits(b, nbits, r.bbottom);
		IO.flushBits(b);
	}

	static function write_matrix(ch:Output, m:Matrix):Void {
		var b = IO.outputBits(ch);
		function write_matrix_part(m:MatrixPart) {
			var nbits = matrix_part_nbits(m);
			IO.writeBits(b, 5, nbits);
			IO.writeBits(b, nbits, m.mx);
			IO.writeBits(b, nbits, m.my);
		}
		switch m.scale {
			case null:
				IO.writeBits(b, 1, 0);
			case s:
				IO.writeBits(b, 1, 1);
				write_matrix_part(s);
		}
		switch m.rotate {
			case null:
				IO.writeBits(b, 1, 0);
			case r:
				IO.writeBits(b, 1, 1);
				write_matrix_part(r);
		}
		write_matrix_part(m.trans);
		IO.flushBits(b);
	}

	static function write_cxa(ch:Output, c:ColorTransformAlpha):Void {
		var b = IO.outputBits(ch);
		var nbits = cxa_nbits(c);
		switch [c.cxa_add, c.cxa_mult] {
			case [null, null]:
				IO.writeBits(b, 2, 0);
				IO.writeBits(b, 4, 1); /* some strange MM thing... */
			case [c, null]:
				IO.writeBits(b, 2, 2);
				IO.writeBits(b, 4, nbits);
				for (x in [c.r, c.g, c.b, c.a]) IO.writeBits(b, nbits, x);
			case [null, c]:
				IO.writeBits(b, 2, 1);
				IO.writeBits(b, 4, nbits);
				for (x in [c.r, c.g, c.b, c.a]) IO.writeBits(b, nbits, x);
			case [c1, c2]:
				IO.writeBits(b, 2, 3);
				IO.writeBits(b, 4, nbits);
				for (x in [c2.r, c2.g, c2.b, c2.a, c1.r, c1.g, c1.b, c1.a]) IO.writeBits(b, nbits, x);
		}
		IO.flushBits(b);
	}

	static function write_event(ch:Output, evt:Int):Void {
		if (swf_version >= 6) IO.writeI32(ch, evt) else IO.writeUi16(ch, evt);
	}

	/* ************************************************************************ */
	/* PARSING */
	static function parse_clip_events(ch:Input):Array<ClipEvent> {
		IO.readUi16(ch); /* reserved */
		read_event(ch); /* all_events */
		var l = [];
		while (true) {
			var events = read_event(ch);
			if (events == 0)
				break
			else {
				IO.readI32(ch); /* len */
				var key = (if (events & (1 << 17) != 0) IO.read(ch) else null);
				var e = {
					cle_events: events,
					cle_key: key,
					cle_actions: parse_actions(ch)
				};
				l.push(e);
			}
		}
		return l;
	}

	static function parse_shape_fill_style(ch:Input, vshape:Int):ShapeFillStyle {
		var t = IO.readByte(ch);
		return switch t {
			case 0x00 if (vshape >= 3):
				SFSSolid3(read_rgba(ch));
			case 0x00:
				SFSSolid(read_rgb(ch));
			case 0x10:
				var m = read_matrix(ch);
				var g = read_gradient(ch, (vshape >= 3));
				SFSLinearGradient(m, g);
			case 0x12:
				var m = read_matrix(ch);
				var g = read_gradient(ch, (vshape >= 3));
				SFSRadialGradient(m, g, null);
			case 0x13:
				var m = read_matrix(ch);
				var g = read_gradient(ch, (vshape >= 3));
				var i = IO.readI16(ch);
				SFSRadialGradient(m, g, i);
			case 0x40 | 0x41 | 0x42 | 0x43:
				var id = IO.readUi16(ch);
				var m = read_matrix(ch);
				SFSBitmap({
					sfb_repeat: (t == 0x40 || t == 0x42),
					sfb_smooth: (t == 0x42 || t == 0x43),
					sfb_cid: id,
					sfb_mpos: m,
				});
			case _:
				assertFalse();
		}
	}

	static function parse_shape_line_style(ch:Input, vshape:Int):ShapeLineStyle {
		var width = IO.readUi16(ch);
		if (vshape >= 4) {
			var flags = IO.readUi16(ch);
			var fill = (flags & 8 != 0);
			var miterjoin = (flags & 0x20 != 0);
			var miter = (if (miterjoin) IO.readUi16(ch) else null);
			var color = (if (fill) ({r: 0, g: 0, b: 0, a: 0} : Rgba) else read_rgba(ch));
			/*
				let noVscale = (flags land 0x02 <> 0) in
				let noHscale = (flags land 0x04 <> 0) in
				let beveljoin = (flags land 0x10 <> 0) in
				let nocap = (flags land 0x40 <> 0) in
				let squarecap = (flags land 0x80 <> 0) in
			 */
			return {
				sls_width: width,
				sls_color: ColorRGBA(color),
				sls_fill: if (fill) parse_shape_fill_style(ch, vshape) else null,
				sls_flags: flags,
				sls_miter: miter,
			};
		} else
			return {
				sls_width: width,
				sls_color: if (vshape == 3) ColorRGBA(read_rgba(ch)) else ColorRGB(read_rgb(ch)),
				sls_fill: null,
				sls_flags: null,
				sls_miter: null,
			};
	}

	static function parse_shape_array<T>(f:Input->Int->T, ch:Input, vshape:Int):Array<T> {
		var n = (switch IO.readByte(ch) {
			case 0xFF: IO.readUi16(ch);
			case n: n;
		});
		return read_count(n, () -> f(ch, vshape));
	}

	static function parse_shape_style_change_record(ch:Input, b:InBits, flags:Int, nbits:{nl:Int, nf:Int}, vshape:Int):ShapeChangeStyleRecord {
		var move = (if (flags & 1 != 0) {
			var mbits = IO.readBits(b, 5);
			var dx = IO.readBits(b, mbits);
			var dy = IO.readBits(b, mbits);
			{n: mbits, dx: dx, dy: dy};
		} else null);
		var fs0 = (if (flags & 2 != 0) IO.readBits(b, nbits.nf) else null);
		var fs1 = (if (flags & 4 != 0) IO.readBits(b, nbits.nf) else null);
		var ls = (if (flags & 8 != 0) IO.readBits(b, nbits.nl) else null);
		var styles = (if (flags & 16 != 0) {
			IO.dropBits(b);
			var fstyles = parse_shape_array(parse_shape_fill_style, ch, vshape);
			var lstyles = parse_shape_array(parse_shape_line_style, ch, vshape);
			var bits = IO.readByte(ch);
			nbits.nl = bits & 15;
			nbits.nf = bits >>> 4;
			({
				sns_fill_styles: fstyles,
				sns_line_styles: lstyles,
				sns_nlbits: nbits.nl,
				sns_nfbits: nbits.nf,
			} : ShapeNewStyles);
		} else null);
		return {
			scsr_move: move,
			scsr_fs0: fs0,
			scsr_fs1: fs1,
			scsr_ls: ls,
			scsr_new_styles: styles,
		};
	}

	static function parse_shape_curved_edge_record(b:InBits, flags:Int):ShapeCurvedEdgeRecord {
		var nbits = (flags & 15) + 2;
		var cx = IO.readBits(b, nbits);
		var cy = IO.readBits(b, nbits);
		var ax = IO.readBits(b, nbits);
		var ay = IO.readBits(b, nbits);
		return {
			scer_nbits: nbits,
			scer_cx: cx,
			scer_cy: cy,
			scer_ax: ax,
			scer_ay: ay,
		};
	}

	static function parse_shape_straight_edge_record(b:InBits, flags:Int):ShapeStraightEdgeRecord {
		var nbits = (flags & 15) + 2;
		var is_general = (IO.readBits(b, 1) == 1);
		var l = (if (is_general) {
			var dx = IO.readBits(b, nbits);
			var dy = IO.readBits(b, nbits);
			{dx: (dx : Null<Int>), dy: (dy : Null<Int>)};
		} else {
			var is_vertical = (IO.readBits(b, 1) == 1);
			var p = IO.readBits(b, nbits);
			if (is_vertical) {dx: null, dy: (p : Null<Int>)} else {dx: (p : Null<Int>), dy: null};
		});
		return {
			sser_nbits: nbits,
			sser_line: l,
		};
	}

	static function parse_shape_records(ch:Input, nlbits:Int, nfbits:Int, vshape:Int):Array<ShapeRecord> {
		var b = IO.inputBits(ch);
		var nbits = {nl: nlbits, nf: nfbits};
		var l = [];
		while (true) {
			var flags = IO.readBits(b, 6);
			if (flags == 0)
				break
			else {
				var r = (if ((flags & 32) == 0) SRStyleChange(parse_shape_style_change_record(ch, b, flags, nbits,
					vshape)) else if ((flags & 48) == 32) SRCurvedEdge(parse_shape_curved_edge_record(b,
						flags)) else SRStraightEdge(parse_shape_straight_edge_record(b, flags)));
				l.push(r);
			}
		}
		return l;
	}

	static function parse_shape_with_style(ch:Input, vshape:Int):ShapeWithStyle {
		var fstyles = parse_shape_array(parse_shape_fill_style, ch, vshape);
		var lstyles = parse_shape_array(parse_shape_line_style, ch, vshape);
		var bits = IO.readByte(ch);
		var nlbits = bits & 15;
		var nfbits = bits >>> 4;
		var records = parse_shape_records(ch, nlbits, nfbits, vshape);
		return {
			sws_fill_styles: fstyles,
			sws_line_styles: lstyles,
			sws_records: {
				srs_nlbits: nlbits,
				srs_nfbits: nfbits,
				srs_records: records,
			}
		};
	}

	static function parse_shape(ch:Input, len:Int, vshape:Int):Shape {
		var id = IO.readUi16(ch);
		var bounds = read_rect(ch);
		var bounds2 = (if (vshape == 4) {
			var r = read_rect(ch);
			var b = IO.readByte(ch);
			{r: r, b: b};
		} else null);
		var style = parse_shape_with_style(ch, vshape);
		return {
			sh_id: id,
			sh_bounds: bounds,
			sh_bounds2: bounds2,
			sh_style: style,
		};
	}

	static function extract_jpg_table(data:Bytes):{data:Bytes, table:Null<Bytes>} {
		// port: `data.[0]` raises Invalid_argument on an empty string.
		if (data.length < 2) throw new core.ds.InvalidArgument("index out of bounds");
		return switch [data.get(0), data.get(1)] {
			case [0xFF, 0xD8]:
				var ch = IO.inputString(data);
				var b = new haxe.io.BytesBuffer();
				var flag = false;
				while (true) {
					var c = IO.read(ch);
					b.addByte(c);
					switch c {
						case 0xFF:
							flag = true;
						case 0xD9 if (flag):
							break;
						case _:
							flag = false;
					}
				}
				var t = b.getBytes();
				var l = t.length;
				{data: data.sub(l, data.length - l), table: t};
			case _:
				{data: data, table: null};
		}
	}

	static function parse_bitmap_lossless(ch:Input, len:Int):BitmapLossless {
		var id = IO.readUi16(ch);
		var format = IO.readByte(ch);
		var width = IO.readUi16(ch);
		var height = IO.readUi16(ch);
		var data = IO.nread(ch, len - 7);
		return {
			bll_id: id,
			bll_format: format,
			bll_width: width,
			bll_height: height,
			bll_data: data,
		};
	}

	static function parse_text(ch:Input, is_txt2:Bool):Text {
		var id = IO.readUi16(ch);
		var bounds = read_big_rect(ch);
		var matrix = read_matrix(ch);
		var ngbits = IO.readByte(ch);
		var nabits = IO.readByte(ch);
		function read_glyph(bits:InBits):TextGlyph {
			var indx = IO.readBits(bits, ngbits);
			var adv = IO.readBits(bits, nabits);
			return {
				txg_index: indx,
				txg_advanced: adv,
			};
		}
		var records = [];
		while (true) {
			var flags = IO.readByte(ch);
			if (flags == 0)
				break
			else {
				var font_id = (if (flags & 8 != 0) IO.readUi16(ch) else 0);
				var color = (if (flags & 4 != 0) (if (is_txt2) ColorRGBA(read_rgba(ch)) else ColorRGB(read_rgb(ch))) else null);
				var dx = (if (flags & 1 != 0) IO.readI16(ch) else null);
				var dy = (if (flags & 2 != 0) IO.readI16(ch) else null);
				var font = (if (flags & 8 != 0) {id: font_id, id2: IO.readUi16(ch)} else null);
				var nglyphs = IO.readByte(ch);
				var bits = IO.inputBits(ch);
				var r:TextRecord = {
					txr_font: font,
					txr_color: color,
					txr_dx: dx,
					txr_dy: dy,
					txr_glyphs: read_count(nglyphs, () -> read_glyph(bits)),
				};
				records.push(r);
			}
		}
		return {
			txt_id: id,
			txt_bounds: bounds,
			txt_matrix: matrix,
			txt_ngbits: ngbits,
			txt_nabits: nabits,
			txt_records: records,
		};
	}

	static function parse_edit_text_layout(ch:Input):EditTextLayout {
		var align = IO.readByte(ch);
		var ml = IO.readUi16(ch);
		var rl = IO.readUi16(ch);
		var ident = IO.readUi16(ch);
		var lead = IO.readUi16(ch);
		return {
			edtl_align: align,
			edtl_left_margin: ml,
			edtl_right_margin: rl,
			edtl_indent: ident,
			edtl_leading: lead,
		};
	}

	static function parse_edit_text(ch:Input):EditText {
		var id = IO.readUi16(ch);
		var bounds = read_rect(ch);
		var flags = IO.readUi16(ch);
		var font = (if (flags & 1 != 0) {
			var fid = IO.readUi16(ch);
			var height = IO.readUi16(ch);
			{id: fid, h: height};
		} else null);
		var color = (if (flags & 4 != 0) read_rgba(ch) else null);
		var maxlen = (if (flags & 2 != 0) IO.readUi16(ch) else null);
		var layout = (if (flags & (1 << 13) != 0) parse_edit_text_layout(ch) else null);
		var variable = IO.readString(ch);
		var text = (if (flags & 128 != 0) IO.readString(ch) else null);
		return {
			edt_id: id,
			edt_bounds: bounds,
			edt_font: font,
			edt_color: color,
			edt_maxlen: maxlen,
			edt_layout: layout,
			edt_variable: variable,
			edt_text: text,
			edt_wordwrap: (flags & 64) != 0,
			edt_multiline: (flags & 32) != 0,
			edt_password: (flags & 16) != 0,
			edt_readonly: (flags & 8) != 0,
			edt_autosize: (flags & (1 << 14)) != 0,
			edt_noselect: (flags & 4096) != 0,
			edt_border: (flags & 2048) != 0,
			edt_html: (flags & 512) != 0,
			edt_outlines: (flags & 256) != 0,
		};
	}

	static function parse_cid_data(ch:Input, len:Int):CidData {
		var id = IO.readUi16(ch);
		var data = IO.nread(ch, len - 2);
		return {
			cd_id: id,
			cd_data: data,
		};
	}

	static function parse_morph_shape(ch:Input, len:Int):MorphShape {
		var id = IO.readUi16(ch);
		var sbounds = read_rect(ch);
		var ebounds = read_rect(ch);
		var data = IO.nread(ch, len - 2 - rect_length(sbounds) - rect_length(ebounds));
		return {
			msh_id: id,
			msh_start_bounds: sbounds,
			msh_end_bounds: ebounds,
			msh_data: data,
		};
	}

	static function parse_filter_gradient(ch:Input):FilterGradient {
		var ncolors = IO.readByte(ch);
		var colors = read_count(ncolors, () -> read_rgba(ch));
		var cvals = read_count(ncolors, () -> IO.readByte(ch));
		var data = IO.nread(ch, 19);
		return {
			fgr_colors: [for (i in 0...colors.length) {c: colors[i], n: cvals[i]}],
			fgr_data: data,
		};
	}

	static function parse_filter(ch:Input):Filter {
		return switch IO.readByte(ch) {
			case 0: FDropShadow(IO.nread(ch, 23));
			case 1: FBlur(IO.nread(ch, 9));
			case 2: FGlow(IO.nread(ch, 15));
			case 3: FBevel(IO.nread(ch, 27));
			case 4: FGradientGlow(parse_filter_gradient(ch));
			case 6: FAdjustColor(IO.nread(ch, 80));
			case 7: FGradientBevel(parse_filter_gradient(ch));
			case _: assertFalse();
		}
	}

	static function parse_filters(ch:Input):Array<Filter> {
		var nf = IO.readByte(ch);
		return read_count(nf, () -> parse_filter(ch));
	}

	static function parse_button_records(ch:Input, color:Bool):Array<ButtonRecord> {
		var l = [];
		while (true) {
			var flags = IO.readByte(ch);
			if (flags == 0) break;
			var cid = IO.readUi16(ch);
			var depth = IO.readUi16(ch);
			var mpos = read_matrix(ch);
			var cxa = (if (color) read_cxa(ch) else null);
			var filters = (if (flags & 16 == 0) null else parse_filters(ch));
			var blendmode = (if (flags & 32 == 0) null else IO.readByte(ch));
			var r = {
				btr_flags: flags,
				btr_cid: cid,
				btr_depth: depth,
				btr_mpos: mpos,
				btr_color: cxa,
				btr_filters: filters,
				btr_blendmode: blendmode,
			};
			l.push(r);
		}
		return l;
	}

	static function parse_button_actions(ch:Input):Array<ButtonAction> {
		var l = [];
		while (true) {
			var size = IO.readUi16(ch);
			var flags = IO.readUi16(ch);
			var actions = parse_actions(ch);
			var bta = {
				bta_flags: flags,
				bta_actions: actions,
			};
			l.push(bta);
			if (size == 0) break;
		}
		return l;
	}

	static function parse_button2(ch:Input, len:Int):Button2 {
		var id = IO.readUi16(ch);
		var flags = IO.readByte(ch);
		var track = (switch flags {
			case 0: false;
			case 1: true;
			case _: assertFalse();
		});
		var offset = IO.readUi16(ch);
		var records = parse_button_records(ch, true);
		var actions = (if (offset == 0) [] else parse_button_actions(ch));
		return {
			bt2_id: id,
			bt2_track_as_menu: track,
			bt2_records: records,
			bt2_actions: actions,
		};
	}

	static function parse_place_object(ch:Input, v3:Bool):PlaceObject {
		var f = IO.readByte(ch);
		var fext = (if (v3) IO.readByte(ch) else 0);
		var depth = IO.readUi16(ch);
		var move = (f & 1) != 0;
		var cid = opt_flag(f, 2, IO.readUi16, ch);
		var matrix = opt_flag(f, 4, read_matrix, ch);
		var color = opt_flag(f, 8, read_cxa, ch);
		var ratio = opt_flag(f, 16, IO.readUi16, ch);
		var name = opt_flag(f, 32, IO.readString, ch);
		var clip_depth = opt_flag(f, 64, IO.readUi16, ch);
		var clip_events = opt_flag(f, 128, parse_clip_events, ch);
		var filters = opt_flag(fext, 1, parse_filters, ch);
		var blend = opt_flag(fext, 2, IO.readByte, ch);
		var bcache = opt_flag(fext, 4, IO.readByte, ch);
		return {
			po_depth: depth,
			po_move: move,
			po_cid: cid,
			po_matrix: matrix,
			po_color: color,
			po_ratio: ratio,
			po_inst_name: name,
			po_clip_depth: clip_depth,
			po_events: clip_events,
			po_filters: filters,
			po_blend: blend,
			po_bcache: bcache,
		};
	}

	static function parse_import(ch:Input):Import {
		var cid = IO.readUi16(ch);
		var name = IO.readString(ch);
		return {
			imp_id: cid,
			imp_name: name
		};
	}

	// port: Sys.max_string_length of 64-bit OCaml.
	static final max_string_length = 0x7FFFFFFF;

	static function parse_tag(ch:Input, h:Int):Tag {
		var id = h >>> 6;
		var len = h & 63;
		var extended = false;
		if (len == 63) {
			len = IO.readI32(ch);
			extended = len < 63;
		}
		var t = (switch id {
			case 0x00:
				TEnd;
			case 0x01:
				TShowFrame;
			case 0x02 if (full_parsing):
				TShape(parse_shape(ch, len, 1));
			/* 0x03 invalid */
			/*//0x04 TPlaceObject */
			case 0x05:
				var cid = IO.readUi16(ch);
				var depth = IO.readUi16(ch);
				TRemoveObject({
					rmo_id: cid,
					rmo_depth: depth,
				});
			case 0x06:
				var id = IO.readUi16(ch);
				var data = IO.nread(ch, len - 2);
				TBitsJPEG({
					jpg_id: id,
					jpg_data: data,
				});
			/*//0x07 TButton */
			case 0x08:
				TJPEGTables(IO.nread(ch, len));
			case 0x09:
				TSetBgColor(read_rgb(ch));
			case 0x0A:
				TFont(parse_cid_data(ch, len));
			case 0x0B if (full_parsing):
				TText(parse_text(ch, false));
			case 0x0C:
				TDoAction(parse_actions(ch));
			case 0x0D:
				TFontInfo(parse_cid_data(ch, len));
			case 0x0E:
				var sid = IO.readUi16(ch);
				var flags = IO.readByte(ch);
				var samples = IO.readI32(ch);
				var data = IO.nread(ch, len - 7);
				TSound({
					so_id: sid,
					so_flags: flags,
					so_samples: samples,
					so_data: data,
				});
			case 0x0F:
				var sid = IO.readUi16(ch);
				var data = IO.nread(ch, len - 2);
				TStartSound({
					sts_id: sid,
					sts_data: data,
				});
			/* 0x10 invalid */
			/*//0x11 TButtonSound */
			/*//0x12 TSoundStreamHead */
			/*//0x13 TSoundStreamBlock */
			case 0x14:
				TBitsLossless(parse_bitmap_lossless(ch, len));
			case 0x15:
				var id = IO.readUi16(ch);
				var data = IO.nread(ch, len - 2);
				var dt = extract_jpg_table(data);
				TBitsJPEG2({
					bd_id: id,
					bd_table: dt.table,
					bd_data: dt.data,
					bd_alpha: null,
					bd_deblock: null,
				});
			case 0x16 if (full_parsing):
				TShape2(parse_shape(ch, len, 2));
			/*//0x17 TButtonCXForm */
			case 0x18:
				TProtect;
			/* 0x19 invalid */
			case 0x1A if (full_parsing):
				TPlaceObject2(parse_place_object(ch, false));
			/* 0x1B invalid */
			case 0x1C:
				var depth = IO.readUi16(ch);
				TRemoveObject2(depth);
			/* 0x1D-1F invalid */
			case 0x20 if (full_parsing):
				TShape3(parse_shape(ch, len, 3));
			case 0x21 if (full_parsing):
				TText2(parse_text(ch, true));
			case 0x22 if (full_parsing):
				TButton2(parse_button2(ch, len));
			case 0x23:
				var id = IO.readUi16(ch);
				var size = IO.readI32(ch);
				var data = IO.nread(ch, size);
				var dt = extract_jpg_table(data);
				var alpha = IO.nread(ch, len - 6 - size);
				TBitsJPEG3({
					bd_id: id,
					bd_table: dt.table,
					bd_data: dt.data,
					bd_alpha: alpha,
					bd_deblock: null,
				});
			case 0x24:
				TBitsLossless2(parse_bitmap_lossless(ch, len));
			case 0x25 if (full_parsing):
				TEditText(parse_edit_text(ch));
			/* 0x26 invalid */
			case 0x27:
				var cid = IO.readUi16(ch);
				var fcount = IO.readUi16(ch);
				var tags = parse_tag_list(ch);
				TClip({
					c_id: cid,
					c_frame_count: fcount,
					c_tags: tags,
				});
			/* 0x28 invalid */
			case 0x29:
				/* undocumented ? */
				TProductInfo(IO.nread(ch, len));
			/* 0x2A invalid */
			case 0x2B:
				var label = IO.readBytesNul(ch);
				var id = (if (len == label.length + 2) IO.read(ch) else null);
				TFrameLabel(label.toString(), id);
			/* 0x2C invalid */
			case 0x2D:
				TSoundStreamHead2(IO.nread(ch, len));
			case 0x2E if (full_parsing):
				TMorphShape(parse_morph_shape(ch, len));
			/* 0x2F invalid */
			case 0x30 if (full_parsing):
				TFont2(parse_cid_data(ch, len));
			/* 0x31-37 invalid */
			case 0x38:
				function read_export():Export {
					var cid = IO.readUi16(ch);
					var name = IO.readString(ch);
					return {
						exp_id: cid,
						exp_name: name
					};
				}
				TExport(read_count(IO.readUi16(ch), read_export));
			case 0x39:
				var url = IO.readString(ch);
				TImport(url, read_count(IO.readUi16(ch), () -> parse_import(ch)));
			/*// 0x3A TEnableDebugger */
			case 0x3B:
				var cid = IO.readUi16(ch);
				var actions = parse_actions(ch);
				TDoInitAction({
					dia_id: cid,
					dia_actions: actions,
				});
			case 0x3C:
				TVideoStream(parse_cid_data(ch, len));
			case 0x3D:
				TVideoFrame(parse_cid_data(ch, len));
			case 0x3E:
				TFontInfo2(parse_cid_data(ch, len));
			case 0x3F:
				/* undocumented ? */
				TDebugID(IO.nread(ch, len));
			case 0x40:
				var tag = IO.readUi16(ch);
				/* 0 in general, 6517 for some swfs */
				var pass_md5 = IO.readString(ch);
				TEnableDebugger2(tag, pass_md5);
			case 0x41:
				var recursion_depth = IO.readUi16(ch);
				var script_timeout = IO.readUi16(ch);
				TScriptLimits(recursion_depth, script_timeout);
			/*// 0x42 TSetTabIndex */
			/* 0x43-0x44 invalid */
			case 0x45:
				var flags = IO.readI32(ch);
				var mask = 1 | 8 | 16 | 32 | 64;
				if ((flags | mask) != mask) throw new core.ds.Failure("Invalid file attributes " + flags);
				TFilesAttributes({
					fa_network: (flags & 1) != 0,
					/* flags 2,4 : reserved */
					fa_as3: (flags & 8) != 0,
					fa_metadata: (flags & 16) != 0,
					fa_gpu: (flags & 32) != 0,
					fa_direct_blt: (flags & 64) != 0,
				});
			case 0x46 if (full_parsing):
				TPlaceObject3(parse_place_object(ch, true));
			case 0x47:
				var url = IO.readString(ch);
				if (IO.readByte(ch) != 1) assertFalse();
				if (IO.readByte(ch) != 0) assertFalse();
				TImport2(url, read_count(IO.readUi16(ch), () -> parse_import(ch)));
			case 0x48 if (full_parsing || force_as3_parsing):
				TActionScript3(null, As3parse.parse(ch, len));
			case 0x49 if (full_parsing):
				TFontAlignZones(parse_cid_data(ch, len));
			case 0x4A:
				TCSMSettings(parse_cid_data(ch, len));
			case 0x4B if (full_parsing):
				TFont3(parse_cid_data(ch, len));
			case 0x4C:
				var i = IO.readUi16(ch);
				var l = [];
				for (_ in 0...i) {
					var a = IO.readUi16(ch);
					var s = IO.readString(ch);
					l.push(({
						f9_cid: if (a == 0) null else a,
						f9_classname: s,
					} : F9Class));
				}
				TF9Classes(l);
			case 0x4D:
				TMetaData(IO.readBytesNul(ch));
			case 0x4E:
				var cid = IO.readUi16(ch);
				var rect = read_rect(ch);
				TScale9(cid, rect);
			/* 0x4F-0x51 invalid */
			case 0x52 if (full_parsing || force_as3_parsing):
				var id = IO.readI32(ch);
				var frame = IO.readBytesNul(ch);
				var len = len - (4 + frame.length + 1);
				TActionScript3({id: id, frame: frame.toString()}, As3parse.parse(ch, len));
			case 0x53 if (full_parsing):
				TShape4(parse_shape(ch, len, 4));
			case 0x54 if (full_parsing):
				TMorphShape2(parse_morph_shape(ch, len));
			/* 0x55 invalid */
			case 0x56:
				var scenes = read_count(As3parse.read_int(ch), () -> {
					var offset = As3parse.read_int(ch);
					var name = IO.readString(ch);
					{n: offset, s: name};
				});
				var frames = read_count(As3parse.read_int(ch), () -> {
					var f = As3parse.read_int(ch);
					var name = IO.readString(ch);
					{n: f, s: name};
				});
				TScenes(scenes, frames);
			case 0x57:
				var cid = IO.readUi16(ch);
				if (IO.readI32(ch) != 0) assertFalse();
				function loop(len:Int):Array<Bytes> {
					if (len > max_string_length) {
						var s = IO.nread(ch, max_string_length);
						return [s].concat(loop(len - max_string_length));
					} else
						return [IO.nread(ch, len)];
				}
				switch loop(len - 6) {
					case [data]: TBinaryData(cid, data);
					case data: TBigBinaryData(cid, data);
				}
			case 0x58:
				TFontName(parse_cid_data(ch, len));
			/* // 0x59 TStartSound2 */
			case 0x5A:
				var id = IO.readUi16(ch);
				var size = IO.readI32(ch);
				var deblock = IO.readUi16(ch);
				var data = IO.nread(ch, size);
				var dt = extract_jpg_table(data);
				var alpha = IO.nread(ch, len - 6 - size);
				TBitsJPEG4({
					bd_id: id,
					bd_table: dt.table,
					bd_data: dt.data,
					bd_alpha: alpha,
					bd_deblock: deblock,
				});
			case 0x5B:
				TFont4(parse_cid_data(ch, len));
			case _:
				/*if !Swf.warnings then Printf.printf "Unknown tag 0x%.2X\n" id;*/
				TUnknown(id, IO.nread(ch, len));
		});
		/*	let len2 = tag_data_length t in
			if len <> len2 then error (Printf.sprintf "Datalen mismatch for tag 0x%.2X (%d != %d)" id len len2);
		 */
		return {
			tid: gen_id(),
			tdata: t,
			textended: extended,
		};
	}

	static function parse_tag_list(ch:Input):Array<Tag> {
		var acc = [];
		while (true) {
			var h = (try IO.readUi16(ch) catch (_:libs.extlib.IO.NoMoreInput) 0);
			var t = parse_tag(ch, h);
			switch t.tdata {
				case TEnd:
					return acc;
				case _:
					acc.push(t);
			}
		}
	}

	// port: Swf.__inflate and Swf.__deflate, installed by init; genswf's module
	// initialization (`SwfParser.init Extc.input_zip Extc.output_zip`) runs at
	// startup upstream, so they start as the Extc functions.
	static var inflate_fn:Input->Input = ch -> libs.extc.Extc.inputZip(ch);

	static var deflate_fn:Output->Output = ch -> libs.extc.Extc.outputZip(ch);

	public static function parse(ch:Input):SwfData {
		var sign = IO.nread(ch, 3).toString();
		if (sign != "FWS" && sign != "CWS") Swf.error("Invalid SWF signature");
		var ver = IO.readByte(ch);
		swf_version = ver;
		IO.readI32(ch); /* file length */
		var compressed = sign == "CWS";
		var ch = (if (compressed) inflate_fn(ch) else ch);
		var size = read_rect(ch);
		var fps = IO.readUi16(ch);
		var frame_count = IO.readUi16(ch);
		var h:Header = {
			h_version: ver,
			h_size: size,
			h_fps: fps,
			h_frame_count: frame_count,
			h_compressed: compressed,
		};
		var data:SwfData = {header: h, tags: parse_tag_list(ch)};
		if (compressed) IO.closeIn(ch);
		return data;
	}

	/* ************************************************************************ */
	/* WRITING */
	static function tag_id(t:TagData):Int return switch t {
		case TEnd: 0x00;
		case TShowFrame: 0x01;
		case TShape(_): 0x02;
		case TRemoveObject(_): 0x05;
		case TBitsJPEG(_): 0x06;
		case TJPEGTables(_): 0x08;
		case TSetBgColor(_): 0x09;
		case TFont(_): 0x0A;
		case TText(_): 0x0B;
		case TDoAction(_): 0x0C;
		case TFontInfo(_): 0x0D;
		case TSound(_): 0x0E;
		case TStartSound(_): 0x0F;
		case TBitsLossless(_): 0x14;
		case TBitsJPEG2(_): 0x15;
		case TShape2(_): 0x16;
		case TProtect: 0x18;
		case TPlaceObject2(_): 0x1A;
		case TRemoveObject2(_): 0x1C;
		case TShape3(_): 0x20;
		case TText2(_): 0x21;
		case TButton2(_): 0x22;
		case TBitsJPEG3(_): 0x23;
		case TBitsLossless2(_): 0x24;
		case TEditText(_): 0x25;
		case TClip(_): 0x27;
		case TProductInfo(_): 0x29;
		case TFrameLabel(_): 0x2B;
		case TSoundStreamHead2(_): 0x2D;
		case TMorphShape(_): 0x2E;
		case TFont2(_): 0x30;
		case TExport(_): 0x38;
		case TImport(_): 0x39;
		case TDoInitAction(_): 0x3B;
		case TVideoStream(_): 0x3C;
		case TVideoFrame(_): 0x3D;
		case TFontInfo2(_): 0x3E;
		case TDebugID(_): 0x3F;
		case TEnableDebugger2(_): 0x40;
		case TScriptLimits(_): 0x41;
		case TFilesAttributes(_): 0x45;
		case TPlaceObject3(_): 0x46;
		case TImport2(_): 0x47;
		case TFontAlignZones(_): 0x49;
		case TCSMSettings(_): 0x4A;
		case TFont3(_): 0x4B;
		case TF9Classes(_): 0x4C;
		case TMetaData(_): 0x4D;
		case TScale9(_): 0x4E;
		case TActionScript3(null, _): 0x48;
		case TActionScript3(_): 0x52;
		case TShape4(_): 0x53;
		case TMorphShape2(_): 0x54;
		case TScenes(_): 0x56;
		case TBinaryData(_) | TBigBinaryData(_): 0x57;
		case TFontName(_): 0x58;
		case TBitsJPEG4(_): 0x5A;
		case TFont4(_): 0x5B;
		case TUnknown(id, _): id;
	}

	static function write_clip_event(ch:Output, c:ClipEvent):Void {
		write_event(ch, c.cle_events);
		IO.writeI32(ch, actions_length(c.cle_actions) + opt_len(_ -> 1, c.cle_key));
		if (c.cle_key != null) IO.write(ch, c.cle_key);
		write_actions(ch, c.cle_actions);
	}

	static function write_clip_events(ch:Output, event_list:Array<ClipEvent>):Void {
		IO.writeUi16(ch, 0);
		var all_events = 0;
		for (c in event_list) all_events = all_events | c.cle_events;
		write_event(ch, all_events);
		for (c in event_list) write_clip_event(ch, c);
		write_event(ch, 0);
	}

	static function write_shape_fill_style(ch:Output, s:ShapeFillStyle):Void {
		switch s {
			case SFSSolid(c):
				IO.writeByte(ch, 0x00);
				write_rgb(ch, c);
			case SFSSolid3(c):
				IO.writeByte(ch, 0x00);
				write_rgba(ch, c);
			case SFSLinearGradient(m, g):
				IO.writeByte(ch, 0x10);
				write_matrix(ch, m);
				write_gradient(ch, g);
			case SFSRadialGradient(m, g, null):
				IO.writeByte(ch, 0x12);
				write_matrix(ch, m);
				write_gradient(ch, g);
			case SFSRadialGradient(m, g, i):
				IO.writeByte(ch, 0x13);
				write_matrix(ch, m);
				write_gradient(ch, g);
				IO.writeI16(ch, i);
			case SFSBitmap(b):
				IO.writeByte(ch, (switch [b.sfb_repeat, b.sfb_smooth] {
					case [true, false]: 0x40;
					case [false, false]: 0x41;
					case [true, true]: 0x42;
					case [false, true]: 0x43;
				}));
				IO.writeUi16(ch, b.sfb_cid);
				write_matrix(ch, b.sfb_mpos);
		}
	}

	static function write_shape_line_style(ch:Output, l:ShapeLineStyle):Void {
		IO.writeUi16(ch, l.sls_width);
		if (l.sls_flags != null) IO.writeUi16(ch, l.sls_flags);
		if (l.sls_miter != null) IO.writeUi16(ch, l.sls_miter);
		switch l.sls_fill {
			case null:
				write_color(ch, l.sls_color);
			case fill:
				write_shape_fill_style(ch, fill);
		}
	}

	static function write_shape_array<T>(ch:Output, f:Output->T->Void, sl:Array<T>):Void {
		var n = sl.length;
		if (n >= 0xFF) {
			IO.writeByte(ch, 0xFF);
			IO.writeUi16(ch, n);
		} else
			IO.writeByte(ch, n);
		for (s in sl) f(ch, s);
	}

	static function write_shape_style_change_record(ch:Output, b:OutBits, nbits:{nl:Int, nf:Int}, s:ShapeChangeStyleRecord):Void {
		var flags = make_flags([flag(s.scsr_move), flag(s.scsr_fs0), flag(s.scsr_fs1), flag(s.scsr_ls), flag(s.scsr_new_styles)]);
		IO.writeBits(b, 6, flags);
		switch s.scsr_move {
			case null:
			case m:
				IO.writeBits(b, 5, m.n);
				IO.writeBits(b, m.n, m.dx);
				IO.writeBits(b, m.n, m.dy);
		}
		if (s.scsr_fs0 != null) IO.writeBits(b, nbits.nf, s.scsr_fs0);
		if (s.scsr_fs1 != null) IO.writeBits(b, nbits.nf, s.scsr_fs1);
		if (s.scsr_ls != null) IO.writeBits(b, nbits.nl, s.scsr_ls);
		switch s.scsr_new_styles {
			case null:
			case s:
				IO.flushBits(b);
				write_shape_array(ch, write_shape_fill_style, s.sns_fill_styles);
				write_shape_array(ch, write_shape_line_style, s.sns_line_styles);
				nbits.nf = s.sns_nfbits;
				nbits.nl = s.sns_nlbits;
				IO.writeBits(b, 4, nbits.nf);
				IO.writeBits(b, 4, nbits.nl);
		}
	}

	static function write_shape_record(ch:Output, b:OutBits, nbits:{nl:Int, nf:Int}, r:ShapeRecord):Void {
		switch r {
			case SRStyleChange(s):
				write_shape_style_change_record(ch, b, nbits, s);
			case SRCurvedEdge(s):
				IO.writeBits(b, 2, 2);
				IO.writeBits(b, 4, (s.scer_nbits - 2));
				IO.writeBits(b, s.scer_nbits, s.scer_cx);
				IO.writeBits(b, s.scer_nbits, s.scer_cy);
				IO.writeBits(b, s.scer_nbits, s.scer_ax);
				IO.writeBits(b, s.scer_nbits, s.scer_ay);
			case SRStraightEdge(s):
				IO.writeBits(b, 2, 3);
				IO.writeBits(b, 4, (s.sser_nbits - 2));
				switch [s.sser_line.dx, s.sser_line.dy] {
					case [null, null]:
						assertFalse();
					case [null, p] | [p, null]:
						IO.writeBits(b, 1, 0);
						IO.writeBits(b, 1, (if (s.sser_line.dx == null) 1 else 0));
						IO.writeBits(b, s.sser_nbits, p);
					case [dx, dy]:
						IO.writeBits(b, 1, 1);
						IO.writeBits(b, s.sser_nbits, dx);
						IO.writeBits(b, s.sser_nbits, dy);
				}
		}
	}

	static function write_shape_with_style(ch:Output, s:ShapeWithStyle):Void {
		write_shape_array(ch, write_shape_fill_style, s.sws_fill_styles);
		write_shape_array(ch, write_shape_line_style, s.sws_line_styles);
		var r = s.sws_records;
		var b = IO.outputBits(ch);
		IO.writeBits(b, 4, r.srs_nfbits);
		IO.writeBits(b, 4, r.srs_nlbits);
		var nbits = {nl: r.srs_nlbits, nf: r.srs_nfbits};
		for (x in r.srs_records) write_shape_record(ch, b, nbits, x);
		IO.writeBits(b, 6, 0);
		IO.flushBits(b);
	}

	static function write_shape(ch:Output, s:Shape):Void {
		IO.writeUi16(ch, s.sh_id);
		write_rect(ch, s.sh_bounds);
		switch s.sh_bounds2 {
			case null:
			case rb:
				write_rect(ch, rb.r);
				IO.writeByte(ch, rb.b);
		}
		write_shape_with_style(ch, s.sh_style);
	}

	static function write_bitmap_lossless(ch:Output, b:BitmapLossless):Void {
		IO.writeUi16(ch, b.bll_id);
		IO.writeByte(ch, b.bll_format);
		IO.writeUi16(ch, b.bll_width);
		IO.writeUi16(ch, b.bll_height);
		IO.nwrite(ch, b.bll_data);
	}

	static function write_morph_shape(ch:Output, s:MorphShape):Void {
		IO.writeUi16(ch, s.msh_id);
		write_rect(ch, s.msh_start_bounds);
		write_rect(ch, s.msh_end_bounds);
		IO.nwrite(ch, s.msh_data);
	}

	static function write_text_record(ch:Output, t:Text, r:TextRecord):Void {
		IO.writeByte(ch, make_flags([flag(r.txr_dx), flag(r.txr_dy), flag(r.txr_color), flag(r.txr_font), false, false, false, true]));
		if (r.txr_font != null) IO.writeUi16(ch, r.txr_font.id);
		if (r.txr_color != null) write_color(ch, r.txr_color);
		if (r.txr_dx != null) IO.writeI16(ch, r.txr_dx);
		if (r.txr_dy != null) IO.writeI16(ch, r.txr_dy);
		if (r.txr_font != null) IO.writeUi16(ch, r.txr_font.id2);
		IO.writeByte(ch, r.txr_glyphs.length);
		var bits = IO.outputBits(ch);
		for (g in r.txr_glyphs) {
			IO.writeBits(bits, t.txt_ngbits, g.txg_index);
			IO.writeBits(bits, t.txt_nabits, g.txg_advanced);
		}
		IO.flushBits(bits);
	}

	static function write_text(ch:Output, t:Text):Void {
		IO.writeUi16(ch, t.txt_id);
		write_big_rect(ch, t.txt_bounds);
		write_matrix(ch, t.txt_matrix);
		IO.writeByte(ch, t.txt_ngbits);
		IO.writeByte(ch, t.txt_nabits);
		for (r in t.txt_records) write_text_record(ch, t, r);
		IO.writeByte(ch, 0);
	}

	static function write_edit_text_layout(ch:Output, l:EditTextLayout):Void {
		IO.writeByte(ch, l.edtl_align);
		IO.writeUi16(ch, l.edtl_left_margin);
		IO.writeUi16(ch, l.edtl_right_margin);
		IO.writeUi16(ch, l.edtl_indent);
		IO.writeUi16(ch, l.edtl_leading);
	}

	static function write_edit_text(ch:Output, t:EditText):Void {
		IO.writeUi16(ch, t.edt_id);
		write_rect(ch, t.edt_bounds);
		IO.writeUi16(ch, make_flags([
			flag(t.edt_font), flag(t.edt_maxlen), flag(t.edt_color), t.edt_readonly,
			t.edt_password, t.edt_multiline, t.edt_wordwrap, flag(t.edt_text),
			t.edt_outlines, t.edt_html, false, t.edt_border,
			t.edt_noselect, flag(t.edt_layout), t.edt_autosize, false
		]));
		switch t.edt_font {
			case null:
			case f:
				IO.writeUi16(ch, f.id);
				IO.writeUi16(ch, f.h);
		}
		if (t.edt_color != null) write_rgba(ch, t.edt_color);
		if (t.edt_maxlen != null) IO.writeUi16(ch, t.edt_maxlen);
		if (t.edt_layout != null) write_edit_text_layout(ch, t.edt_layout);
		IO.writeString(ch, t.edt_variable);
		if (t.edt_text != null) IO.writeString(ch, t.edt_text);
	}

	static function write_cid_data(ch:Output, c:CidData):Void {
		IO.writeUi16(ch, c.cd_id);
		IO.nwrite(ch, c.cd_data);
	}

	static function write_filter_gradient(ch:Output, fg:FilterGradient):Void {
		IO.writeByte(ch, fg.fgr_colors.length);
		for (x in fg.fgr_colors) write_rgba(ch, x.c);
		for (x in fg.fgr_colors) IO.writeByte(ch, x.n);
		IO.nwrite(ch, fg.fgr_data);
	}

	static function write_filter(ch:Output, f:Filter):Void {
		switch f {
			case FDropShadow(s):
				IO.writeByte(ch, 0);
				IO.nwrite(ch, s);
			case FBlur(s):
				IO.writeByte(ch, 1);
				IO.nwrite(ch, s);
			case FGlow(s):
				IO.writeByte(ch, 2);
				IO.nwrite(ch, s);
			case FBevel(s):
				IO.writeByte(ch, 3);
				IO.nwrite(ch, s);
			case FGradientGlow(fg):
				IO.writeByte(ch, 4);
				write_filter_gradient(ch, fg);
			case FAdjustColor(s):
				IO.writeByte(ch, 6);
				IO.nwrite(ch, s);
			case FGradientBevel(fg):
				IO.writeByte(ch, 7);
				write_filter_gradient(ch, fg);
		}
	}

	static function write_button_record(ch:Output, r:ButtonRecord):Void {
		IO.writeByte(ch, r.btr_flags);
		IO.writeUi16(ch, r.btr_cid);
		IO.writeUi16(ch, r.btr_depth);
		write_matrix(ch, r.btr_mpos);
		switch r.btr_color {
			case null:
			case c:
				write_cxa(ch, c);
		}
		switch r.btr_filters {
			case null:
			case l:
				IO.writeByte(ch, l.length);
				for (f in l) write_filter(ch, f);
		}
		switch r.btr_blendmode {
			case null:
			case c:
				IO.writeByte(ch, c);
		}
	}

	static function write_button_actions(ch:Output, l:Array<ButtonAction>):Void {
		switch l.length {
			case 0:
				assertFalse();
			case 1:
				var a = l[0];
				IO.writeUi16(ch, 0);
				IO.writeUi16(ch, a.bta_flags);
				write_actions(ch, a.bta_actions);
			case _:
				var a = l[0];
				var size = button_action_length(a);
				IO.writeUi16(ch, size);
				IO.writeUi16(ch, a.bta_flags);
				write_actions(ch, a.bta_actions);
				write_button_actions(ch, l.slice(1));
		}
	}

	static function write_button2(ch:Output, b:Button2):Void {
		IO.writeUi16(ch, b.bt2_id);
		IO.writeByte(ch, if (b.bt2_track_as_menu) 1 else 0);
		if (b.bt2_actions.length != 0) IO.writeUi16(ch, 3 + sum(button_record_length, b.bt2_records)) else IO.writeUi16(ch, 0);
		for (r in b.bt2_records) write_button_record(ch, r);
		IO.writeByte(ch, 0);
		if (b.bt2_actions.length != 0) write_button_actions(ch, b.bt2_actions);
	}

	static function write_place_object(ch:Output, p:PlaceObject, v3:Bool):Void {
		IO.writeByte(ch, make_flags([
			p.po_move,
			flag(p.po_cid),
			flag(p.po_matrix),
			flag(p.po_color),
			flag(p.po_ratio),
			flag(p.po_inst_name),
			flag(p.po_clip_depth),
			flag(p.po_events)
		]));
		if (v3) IO.writeByte(ch, make_flags([flag(p.po_filters), flag(p.po_blend), flag(p.po_bcache)]));
		IO.writeUi16(ch, p.po_depth);
		if (p.po_cid != null) IO.writeUi16(ch, p.po_cid);
		if (p.po_matrix != null) write_matrix(ch, p.po_matrix);
		if (p.po_color != null) write_cxa(ch, p.po_color);
		if (p.po_ratio != null) IO.writeUi16(ch, p.po_ratio);
		if (p.po_inst_name != null) IO.writeString(ch, p.po_inst_name);
		if (p.po_clip_depth != null) IO.writeUi16(ch, p.po_clip_depth);
		if (p.po_events != null) write_clip_events(ch, p.po_events);
		if (v3) {
			switch p.po_filters {
				case null:
				case l:
					IO.writeByte(ch, l.length);
					for (f in l) write_filter(ch, f);
			}
			if (p.po_blend != null) IO.writeByte(ch, p.po_blend);
			if (p.po_bcache != null) IO.writeByte(ch, p.po_bcache);
		}
	}

	static function write_tag_data(ch:Output, t:TagData):Void {
		switch t {
			case TEnd:
			case TShowFrame:
			case TShape(s):
				write_shape(ch, s);
			case TRemoveObject(r):
				IO.writeUi16(ch, r.rmo_id);
				IO.writeUi16(ch, r.rmo_depth);
			case TBitsJPEG(b):
				IO.writeUi16(ch, b.jpg_id);
				IO.nwrite(ch, b.jpg_data);
			case TJPEGTables(tab):
				IO.nwrite(ch, tab);
			case TSetBgColor(c):
				write_rgb(ch, c);
			case TFont(c):
				write_cid_data(ch, c);
			case TText(t):
				write_text(ch, t);
			case TDoAction(acts):
				write_actions(ch, acts);
			case TFontInfo(c):
				write_cid_data(ch, c);
			case TSound(s):
				IO.writeUi16(ch, s.so_id);
				IO.writeByte(ch, s.so_flags);
				IO.writeI32(ch, s.so_samples);
				IO.nwrite(ch, s.so_data);
			case TStartSound(s):
				IO.writeUi16(ch, s.sts_id);
				IO.nwrite(ch, s.sts_data);
			case TBitsLossless(b):
				write_bitmap_lossless(ch, b);
			case TBitsJPEG2(b):
				IO.writeUi16(ch, b.bd_id);
				if (b.bd_table != null) IO.nwrite(ch, b.bd_table);
				IO.nwrite(ch, b.bd_data);
			case TShape2(s):
				write_shape(ch, s);
			case TProtect:
			case TPlaceObject2(p):
				write_place_object(ch, p, false);
			case TRemoveObject2(depth):
				IO.writeUi16(ch, depth);
			case TShape3(s):
				write_shape(ch, s);
			case TText2(t):
				write_text(ch, t);
			case TButton2(b):
				write_button2(ch, b);
			case TBitsJPEG3(b):
				IO.writeUi16(ch, b.bd_id);
				IO.writeI32(ch, b.bd_data.length + opt_len(blen, b.bd_table));
				if (b.bd_table != null) IO.nwrite(ch, b.bd_table);
				IO.nwrite(ch, b.bd_data);
				if (b.bd_alpha != null) IO.nwrite(ch, b.bd_alpha);
			case TBitsLossless2(b):
				write_bitmap_lossless(ch, b);
			case TEditText(t):
				write_edit_text(ch, t);
			case TClip(c):
				IO.writeUi16(ch, c.c_id);
				IO.writeUi16(ch, c.c_frame_count);
				for (t in c.c_tags) write_tag(ch, t);
				write_tag(ch, tag_end);
			case TProductInfo(s):
				IO.nwrite(ch, s);
			case TFrameLabel(label, id):
				IO.writeString(ch, label);
				if (id != null) IO.write(ch, id);
			case TSoundStreamHead2(data):
				IO.nwrite(ch, data);
			case TMorphShape(s):
				write_morph_shape(ch, s);
			case TFont2(c):
				write_cid_data(ch, c);
			case TExport(el):
				IO.writeUi16(ch, el.length);
				for (e in el) {
					IO.writeUi16(ch, e.exp_id);
					IO.writeString(ch, e.exp_name);
				}
			case TImport(url, il):
				IO.writeString(ch, url);
				IO.writeUi16(ch, il.length);
				for (i in il) {
					IO.writeUi16(ch, i.imp_id);
					IO.writeString(ch, i.imp_name);
				}
			case TDoInitAction(i):
				IO.writeUi16(ch, i.dia_id);
				write_actions(ch, i.dia_actions);
			case TVideoStream(c):
				write_cid_data(ch, c);
			case TVideoFrame(c):
				write_cid_data(ch, c);
			case TFontInfo2(c):
				write_cid_data(ch, c);
			case TDebugID(s):
				IO.nwrite(ch, s);
			case TEnableDebugger2(tag, pass):
				IO.writeUi16(ch, tag);
				IO.writeString(ch, pass);
			case TScriptLimits(recursion_depth, script_timeout):
				IO.writeUi16(ch, recursion_depth);
				IO.writeUi16(ch, script_timeout);
			case TFilesAttributes(f):
				var flags = make_flags([f.fa_network, false, false, f.fa_as3, f.fa_metadata, f.fa_gpu, f.fa_direct_blt]);
				IO.writeI32(ch, flags);
			case TPlaceObject3(p):
				write_place_object(ch, p, true);
			case TImport2(url, il):
				IO.writeString(ch, url);
				IO.writeByte(ch, 1);
				IO.writeByte(ch, 0);
				IO.writeUi16(ch, il.length);
				for (i in il) {
					IO.writeUi16(ch, i.imp_id);
					IO.writeString(ch, i.imp_name);
				}
			case TFontAlignZones(c):
				write_cid_data(ch, c);
			case TCSMSettings(c):
				write_cid_data(ch, c);
			case TFont3(c):
				write_cid_data(ch, c);
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
			case TScale9(cid, r):
				IO.writeUi16(ch, cid);
				write_rect(ch, r);
			case TActionScript3(id, a):
				switch id {
					case null:
					case {id: id, frame: frame}:
						IO.writeI32(ch, id);
						IO.writeString(ch, frame);
				}
				As3parse.write(ch, a);
			case TShape4(s):
				write_shape(ch, s);
			case TMorphShape2(m):
				write_morph_shape(ch, m);
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
			case TBigBinaryData(id, data):
				IO.writeUi16(ch, id);
				IO.writeI32(ch, 0);
				for (s in data) IO.nwrite(ch, s);
			case TFontName(c):
				write_cid_data(ch, c);
			case TBitsJPEG4(b):
				IO.writeUi16(ch, b.bd_id);
				IO.writeI32(ch, b.bd_data.length + opt_len(blen, b.bd_table));
				if (b.bd_deblock != null) IO.writeUi16(ch, b.bd_deblock);
				if (b.bd_table != null) IO.nwrite(ch, b.bd_table);
				IO.nwrite(ch, b.bd_data);
				if (b.bd_alpha != null) IO.nwrite(ch, b.bd_alpha);
			case TFont4(c):
				write_cid_data(ch, c);
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

	/* ************************************************************************ */
	/* EXTRA */
	public static function scan(fid:Int->Int, f:Int->Int, t:Tag):Void {
		switch t.tdata {
			case TEnd | TShowFrame | TJPEGTables(_) | TSetBgColor(_) | TDoAction(_) | TActionScript3(_) | TProtect | TRemoveObject2(_) | TFrameLabel(_) |
				TSoundStreamHead2(_) | TScenes(_) | TEnableDebugger2(_) | TMetaData(_) | TScriptLimits(_) | TDebugID(_) | TFilesAttributes(_) | TProductInfo(_):
			case TF9Classes(l):
				for (c in l) {
					switch c.f9_cid {
						case null:
						case id:
							c.f9_cid = f(id);
					}
				}
			case TShape(s) | TShape2(s) | TShape3(s) | TShape4(s):
				s.sh_id = fid(s.sh_id);
				function loop(fs:Array<ShapeFillStyle>) {
					for (s in fs) switch s {
						case SFSBitmap(b):
							if (b.sfb_cid != 0xFFFF) b.sfb_cid = f(b.sfb_cid);
						case _:
					}
				}
				loop(s.sh_style.sws_fill_styles);
				for (s in s.sh_style.sws_records.srs_records) switch s {
					case SRStyleChange({scsr_new_styles: s}) if (s != null):
						loop(s.sns_fill_styles);
					case _:
				}
			case TRemoveObject(r):
				r.rmo_id = f(r.rmo_id);
			case TBitsJPEG(b):
				b.jpg_id = fid(b.jpg_id);
			case TBitsJPEG2(b):
				b.bd_id = fid(b.bd_id);
			case TText(t) | TText2(t):
				t.txt_id = fid(t.txt_id);
				for (r in t.txt_records) switch r.txr_font {
					case null:
					case font:
						r.txr_font = {id: f(font.id), id2: font.id2};
				}
			case TEditText(t):
				t.edt_id = fid(t.edt_id);
				switch t.edt_font {
					case null:
					case font:
						t.edt_font = {id: f(font.id), h: font.h};
				}
			case TSound(s):
				s.so_id = fid(s.so_id);
			case TStartSound(s):
				s.sts_id = f(s.sts_id);
			case TBitsLossless(b) | TBitsLossless2(b):
				b.bll_id = fid(b.bll_id);
			case TPlaceObject2(p):
				p.po_cid = (switch p.po_cid {
					case null: null;
					case id: f(id);
				});
			case TButton2(b):
				b.bt2_id = fid(b.bt2_id);
				for (r in b.bt2_records) r.btr_cid = f(r.btr_cid);
			case TBitsJPEG3(j):
				j.bd_id = fid(j.bd_id);
			case TClip(c):
				c.c_id = fid(c.c_id);
			case TMorphShape(s) | TMorphShape2(s):
				s.msh_id = fid(s.msh_id);
			case TFont(c) | TFont2(c) | TFont3(c) | TFont4(c):
				c.cd_id = fid(c.cd_id);
			case TExport(el):
				for (e in el) e.exp_id = f(e.exp_id);
			case TImport(_, il) | TImport2(_, il):
				for (i in il) i.imp_id = fid(i.imp_id);
			case TDoInitAction(a):
				a.dia_id = f(a.dia_id);
			case TVideoStream(c):
				c.cd_id = fid(c.cd_id);
			case TVideoFrame(c):
				c.cd_id = f(c.cd_id);
			case TPlaceObject3(p):
				p.po_cid = (switch p.po_cid {
					case null: null;
					case id: f(id);
				});
			case TCSMSettings(c):
				c.cd_id = f(c.cd_id);
			case TBinaryData(id, data):
				t.tdata = TBinaryData(fid(id), data);
			case TBigBinaryData(id, data):
				t.tdata = TBigBinaryData(fid(id), data);
			case TFontAlignZones(c) | TFontInfo(c) | TFontInfo2(c) | TFontName(c):
				c.cd_id = f(c.cd_id);
			case TScale9(id, r):
				t.tdata = TScale9(f(id), r);
			case TBitsJPEG4(j):
				j.bd_id = fid(j.bd_id);
			case TUnknown(_):
		}
	}

	public static function init(inflate:Input->Input, deflate:Output->Output):Void {
		inflate_fn = inflate;
		deflate_fn = deflate;
	}
}
