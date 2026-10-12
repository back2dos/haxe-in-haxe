/*
 *  This file is part of SwfLib
 *  Copyright (c)2004 Nicolas Cannasse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
 */

package libs.swflib;

import haxe.io.Bytes;
import libs.extlib.IO.Input;
import libs.extlib.IO.Output;

// port: haxe/libs/swflib/swf.ml. Binary payloads (`unknown`/`binary`, OCaml
// strings) are Bytes, text (names, labels, URLs) is String; lists, arrays and
// `DynArray.t` are Arrays; `int32` values are Ints; `char` values are their
// codes; pairs are anonymous structures.
typedef Float16 = Int;
typedef Unknown = Bytes;
typedef Binary = Bytes;
typedef ActionCount = Int;

typedef Rgb = {
	var cr:Int;
	var cg:Int;
	var cb:Int;
}

typedef Rgba = {
	var r:Int;
	var g:Int;
	var b:Int;
	var a:Int;
}

enum Color {
	ColorRGB(c:Rgb);
	ColorRGBA(c:Rgba);
}

enum Gradient {
	GradientRGB(l:Array<{ratio:Int, c:Rgb}>, flags:Int);
	GradientRGBA(l:Array<{ratio:Int, c:Rgba}>, flags:Int);
}

typedef Rect = {
	var rect_nbits:Int;
	var left:Int;
	var right:Int;
	var top:Int;
	var bottom:Int;
}

typedef BigRect = {
	var brect_nbits:Int;
	var bleft:Array<Int>;
	var bright:Array<Int>;
	var btop:Array<Int>;
	var bbottom:Array<Int>;
}

typedef MatrixPart = {
	var m_nbits:Int;
	var mx:Int;
	var my:Int;
}

typedef Matrix = {
	var scale:Null<MatrixPart>;
	var rotate:Null<MatrixPart>;
	var trans:MatrixPart;
}

typedef ColorTransformAlpha = {
	var cxa_nbits:Int;
	var cxa_add:Null<Rgba>;
	var cxa_mult:Null<Rgba>;
}

typedef FunctionDecl = {
	var f_name:String;
	var f_args:Array<String>;
	var f_codelen:ActionCount;
}

enum Func2Flags {
	ThisRegister;
	ThisNoVar;
	ArgumentsRegister;
	ArgumentsNoVar;
	SuperRegister;
	SuperNoVar;
	RootRegister;
	ParentRegister;
	GlobalRegister;
}

typedef FunctionDecl2 = {
	var f2_name:String;
	var f2_flags:Array<Func2Flags>;
	var f2_args:Array<{r:Int, s:String}>;
	var f2_nregs:Int;
	var f2_codelen:ActionCount;
}

enum TryStyle {
	TryRegister(r:Int);
	TryVariable(v:String);
}

typedef TryBlock = {
	var tr_style:TryStyle;
	var tr_trylen:ActionCount;
	var tr_catchlen:Null<ActionCount>;
	var tr_finallylen:Null<ActionCount>;
}

enum PushItem {
	PString(s:String);
	PFloat(f:Int);
	PNull;
	PUndefined;
	PReg(r:Int);
	PBool(b:Bool);
	PDouble(f:Float);
	PInt(i:Int);
	PStack(i:Int);
	PStack2(i:Int);
}

enum Property {
	PX;
	PY;
	PXScale;
	PYScale;
	PCurrentFrame;
	PTotalFrames;
	PAlpha;
	PVisible;
	PWidth;
	PHeight;
	PRotation;
	PTarget;
	PFramesLoaded;
	PName;
	PDropTarget;
	PUrl;
	PHighQuality;
	PFocusRect;
	PSoundBufTime;
	PQuality;
	PXMouse;
	PYMouse;
}

enum Action {
	AEnd;
	ANextFrame;
	APrevFrame;
	APlay;
	AStop;
	AToggleHighQuality;
	AStopSounds;
	AAddNum;
	ASubtract;
	AMultiply;
	ADivide;
	ACompareNum;
	AEqualNum;
	ALogicalAnd;
	ALogicalOr;
	ANot;
	AStringEqual;
	AStringLength;
	ASubString;
	APop;
	AToInt;
	AEval;
	ASet;
	ATellTarget;
	AStringAdd;
	AGetProperty;
	ASetProperty;
	ADuplicateMC;
	ARemoveMC;
	ATrace;
	AStartDrag;
	AStopDrag;
	AThrow;
	ACast;
	AImplements;
	AFSCommand2;
	ARandom;
	AMBStringLength;
	AOrd;
	AChr;
	AGetTimer;
	AMBStringSub;
	AMBOrd;
	AMBChr;
	ADeleteObj;
	ADelete;
	ALocalAssign;
	ACall;
	AReturn;
	AMod;
	ANew;
	ALocalVar;
	AInitArray;
	AObject;
	ATypeOf;
	ATargetPath;
	AEnum;
	AAdd;
	ACompare;
	AEqual;
	AToNumber;
	AToString;
	ADup;
	ASwap;
	AObjGet;
	AObjSet;
	AIncrement;
	ADecrement;
	AObjCall;
	ANewMethod;
	AInstanceOf;
	AEnum2;
	AAnd;
	AOr;
	AXor;
	AShl;
	AShr;
	AAsr;
	APhysEqual;
	AGreater;
	AStringGreater;
	AExtends;
	AGotoFrame(n:Int);
	AGetURL(url:String, target:String);
	ASetReg(r:Int);
	AStringPool(l:Array<String>);
	AWaitForFrame(frame:Int, skip:Int);
	ASetTarget(s:String);
	AGotoLabel(s:String);
	AWaitForFrame2(n:Int);
	AFunction2(f:FunctionDecl2);
	ATry(t:TryBlock);
	AWith(n:Int);
	APush(l:Array<PushItem>);
	AJump(n:ActionCount);
	AGetURL2(n:Int);
	AFunction(f:FunctionDecl);
	ACondJump(n:ActionCount);
	ACallFrame; /* no data */
	AGotoFrame2(play:Bool, delta:Null<Int>);
	AUnknown(id:Int, data:Unknown);
}

typedef Actions = Array<Action>;

typedef Header = {
	var h_version:Int;
	var h_size:Rect;
	var h_fps:Float16;
	var h_frame_count:Int;
	var h_compressed:Bool;
}

typedef Export = {
	var exp_id:Int;
	var exp_name:String;
}

typedef Import = {
	var imp_id:Int;
	var imp_name:String;
}

typedef DoInitAction = {
	var dia_id:Int;
	var dia_actions:Actions;
}

typedef Sound = {
	var so_id:Int;
	var so_flags:Int;
	var so_samples:Int;
	var so_data:Unknown;
}

typedef StartSound = {
	var sts_id:Int;
	var sts_data:Unknown;
}

typedef SfsBitmap = {
	var sfb_repeat:Bool;
	var sfb_smooth:Bool;
	var sfb_cid:Int;
	var sfb_mpos:Matrix;
}

enum ShapeFillStyle {
	SFSSolid(c:Rgb);
	SFSSolid3(c:Rgba);
	SFSLinearGradient(m:Matrix, g:Gradient);
	SFSRadialGradient(m:Matrix, g:Gradient, i:Null<Int>);
	SFSBitmap(b:SfsBitmap);
}

typedef ShapeLineStyle = {
	var sls_width:Int;
	var sls_color:Color;
	var sls_flags:Null<Int>;
	var sls_fill:Null<ShapeFillStyle>;
	var sls_miter:Null<Int>;
}

typedef ShapeNewStyles = {
	var sns_fill_styles:Array<ShapeFillStyle>;
	var sns_line_styles:Array<ShapeLineStyle>;
	var sns_nlbits:Int;
	var sns_nfbits:Int;
}

typedef ShapeChangeStyleRecord = {
	var scsr_move:Null<{n:Int, dx:Int, dy:Int}>;
	var scsr_fs0:Null<Int>;
	var scsr_fs1:Null<Int>;
	var scsr_ls:Null<Int>;
	var scsr_new_styles:Null<ShapeNewStyles>;
}

typedef ShapeCurvedEdgeRecord = {
	var scer_nbits:Int;
	var scer_cx:Int;
	var scer_cy:Int;
	var scer_ax:Int;
	var scer_ay:Int;
}

typedef ShapeStraightEdgeRecord = {
	var sser_nbits:Int;
	var sser_line:{dx:Null<Int>, dy:Null<Int>};
}

enum ShapeRecord {
	SRStyleChange(s:ShapeChangeStyleRecord);
	SRCurvedEdge(s:ShapeCurvedEdgeRecord);
	SRStraightEdge(s:ShapeStraightEdgeRecord);
}

typedef ShapeRecords = {
	var srs_nlbits:Int;
	var srs_nfbits:Int;
	var srs_records:Array<ShapeRecord>;
}

typedef ShapeWithStyle = {
	var sws_fill_styles:Array<ShapeFillStyle>;
	var sws_line_styles:Array<ShapeLineStyle>;
	var sws_records:ShapeRecords;
}

typedef Shape = {
	var sh_id:Int;
	var sh_bounds:Rect;
	var sh_bounds2:Null<{r:Rect, b:Int}>;
	var sh_style:ShapeWithStyle;
}

typedef FilterGradient = {
	var fgr_colors:Array<{c:Rgba, n:Int}>;
	var fgr_data:Unknown;
}

enum Filter {
	FDropShadow(s:Unknown);
	FBlur(s:Unknown);
	FGlow(s:Unknown);
	FBevel(s:Unknown);
	FGradientGlow(fg:FilterGradient);
	FAdjustColor(s:Unknown);
	FGradientBevel(fg:FilterGradient);
}

typedef BitmapJpg = {
	var jpg_id:Int;
	var jpg_data:Binary;
}

typedef BitmapData = {
	var bd_id:Int;
	var bd_table:Null<Binary>;
	var bd_data:Binary;
	var bd_alpha:Null<Binary>;
	var bd_deblock:Null<Int>;
}

typedef BitmapLossless = {
	var bll_id:Int;
	var bll_format:Int;
	var bll_width:Int;
	var bll_height:Int;
	var bll_data:Unknown;
}

typedef MorphShape = {
	var msh_id:Int;
	var msh_start_bounds:Rect;
	var msh_end_bounds:Rect;
	var msh_data:Unknown;
}

typedef CidData = {
	var cd_id:Int;
	var cd_data:Binary;
}

typedef TextGlyph = {
	var txg_index:Int;
	var txg_advanced:Int;
}

typedef TextRecord = {
	var txr_font:Null<{id:Int, id2:Int}>;
	var txr_color:Null<Color>;
	var txr_dx:Null<Int>;
	var txr_dy:Null<Int>;
	var txr_glyphs:Array<TextGlyph>;
}

typedef Text = {
	var txt_id:Int;
	var txt_bounds:BigRect;
	var txt_matrix:Matrix;
	var txt_ngbits:Int;
	var txt_nabits:Int;
	var txt_records:Array<TextRecord>;
}

typedef ButtonRecord = {
	var btr_flags:Int;
	var btr_cid:Int;
	var btr_depth:Int;
	var btr_mpos:Matrix;
	var btr_color:Null<ColorTransformAlpha>;
	var btr_filters:Null<Array<Filter>>;
	var btr_blendmode:Null<Int>;
}

typedef ButtonAction = {
	var bta_flags:Int;
	var bta_actions:Actions;
}

typedef Button2 = {
	var bt2_id:Int;
	var bt2_track_as_menu:Bool;
	var bt2_records:Array<ButtonRecord>;
	var bt2_actions:Array<ButtonAction>;
}

typedef RemoveObject = {
	var rmo_id:Int;
	var rmo_depth:Int;
}

typedef EditTextLayout = {
	var edtl_align:Int;
	var edtl_left_margin:Int;
	var edtl_right_margin:Int;
	var edtl_indent:Int;
	var edtl_leading:Int;
}

typedef EditText = {
	var edt_id:Int;
	var edt_bounds:Rect;
	var edt_font:Null<{id:Int, h:Int}>;
	var edt_color:Null<Rgba>;
	var edt_maxlen:Null<Int>;
	var edt_layout:Null<EditTextLayout>;
	var edt_variable:String;
	var edt_text:Null<String>;
	var edt_wordwrap:Bool;
	var edt_multiline:Bool;
	var edt_password:Bool;
	var edt_readonly:Bool;
	var edt_autosize:Bool;
	var edt_noselect:Bool;
	var edt_border:Bool;
	var edt_html:Bool;
	var edt_outlines:Bool;
}

typedef F9Class = {
	var f9_cid:Null<Int>;
	var f9_classname:String;
}

typedef FilesAttrib = {
	var fa_network:Bool;
	var fa_as3:Bool;
	var fa_metadata:Bool;
	var fa_gpu:Bool;
	var fa_direct_blt:Bool;
}

enum TagData {
	TEnd;
	TShowFrame;
	TShape(s:Shape);
	TRemoveObject(r:RemoveObject);
	TBitsJPEG(b:BitmapJpg);
	TJPEGTables(tab:Binary);
	TSetBgColor(c:Rgb);
	TFont(c:CidData);
	TText(t:Text);
	TDoAction(acts:Actions);
	TFontInfo(c:CidData);
	TSound(s:Sound);
	TStartSound(s:StartSound);
	TBitsLossless(b:BitmapLossless);
	TBitsJPEG2(b:BitmapData);
	TShape2(s:Shape);
	TProtect;
	TPlaceObject2(p:PlaceObject);
	TRemoveObject2(depth:Int);
	TShape3(s:Shape);
	TText2(t:Text);
	TButton2(b:Button2);
	TBitsJPEG3(b:BitmapData);
	TBitsLossless2(b:BitmapLossless);
	TEditText(t:EditText);
	TClip(c:Clip);
	TProductInfo(s:Unknown);
	TFrameLabel(label:String, id:Null<Int>);
	TSoundStreamHead2(data:Unknown);
	TMorphShape(s:MorphShape);
	TFont2(c:CidData);
	TExport(el:Array<Export>);
	TImport(url:String, il:Array<Import>);
	TDoInitAction(i:DoInitAction);
	TVideoStream(c:CidData);
	TVideoFrame(c:CidData);
	TFontInfo2(c:CidData);
	TDebugID(s:Unknown);
	TEnableDebugger2(tag:Int, pass:String);
	TScriptLimits(recursionDepth:Int, scriptTimeout:Int);
	TFilesAttributes(f:FilesAttrib);
	TPlaceObject3(p:PlaceObject);
	TImport2(url:String, il:Array<Import>);
	TFontAlignZones(c:CidData);
	TCSMSettings(c:CidData);
	TFont3(c:CidData);
	TF9Classes(l:Array<F9Class>);
	TMetaData(meta:Bytes);
	TScale9(id:Int, r:Rect);
	TActionScript3(id:Null<{id:Int, frame:String}>, a:As3.As3Tag);
	TShape4(s:Shape);
	TMorphShape2(s:MorphShape);
	TScenes(sl:Array<{n:Int, s:String}>, fl:Array<{n:Int, s:String}>);
	TBinaryData(id:Int, data:Binary);
	TBigBinaryData(id:Int, data:Array<Binary>);
	TFontName(c:CidData);
	TBitsJPEG4(b:BitmapData);
	TFont4(c:CidData);
	TUnknown(id:Int, data:Unknown);
}

typedef Tag = {
	var tid:Int;
	var textended:Bool;
	var tdata:TagData;
}

typedef ClipEvent = {
	var cle_events:Int;
	var cle_key:Null<Int>;
	var cle_actions:Actions;
}

typedef PlaceObject = {
	var po_depth:Int;
	var po_move:Bool;
	var po_cid:Null<Int>;
	var po_matrix:Null<Matrix>;
	var po_color:Null<ColorTransformAlpha>;
	var po_ratio:Null<Float16>;
	var po_inst_name:Null<String>;
	var po_clip_depth:Null<Int>;
	var po_events:Null<Array<ClipEvent>>;
	var po_filters:Null<Array<Filter>>;
	var po_blend:Null<Int>;
	var po_bcache:Null<Int>;
}

typedef Clip = {
	var c_id:Int;
	var c_frame_count:Int;
	var c_tags:Array<Tag>;
}

// port: font_language_code, font_glyph_data, font_layout_glyph_data,
// font_kerning_data, font_layout_data and font2_data are only used by
// swfPic/the font tools, which no compiler path reaches; they are not declared.

typedef SwfData = {
	var header:Header;
	var tags:Array<Tag>;
}

class SwfError extends haxe.Exception {}

class Swf {
	// port: __deflate, __inflate, __parser and __printer are SwfParser's (set by
	// SwfParser.init); parse and write call SwfParser directly.
	public static function error(msg:String):Dynamic throw new SwfError(msg);

	public static var warnings = true;

	public static function to_float16(f:Float):Float16 {
		var sign = f < 0.;
		var f = sign ? 0. - f : f;
		var high = Std.int(f);
		var low = Std.int((f - high) * 256.);
		if (high > 127) throw new core.ds.Failure("to_float16");
		return (high << 8) | (if (sign) low | (1 << 15) else low);
	}

	public static function parse(ch:Input):SwfData return SwfParser.parse(ch);

	public static function write(ch:Output, data:SwfData):Void SwfParser.write(ch, data);
}
