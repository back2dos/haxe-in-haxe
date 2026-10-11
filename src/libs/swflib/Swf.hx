package libs.swflib;

import libs.extlib.IO.Output;

// port: haxe/libs/swflib/swf.ml, restricted to the tags genswf creates itself.
// The shape, text, button, morph, font, action and placement tags only come
// from SWF libraries (--swf-lib), which the port does not load.
typedef Float16 = Int;
typedef Unknown = String;
typedef Binary = String;

typedef Rgb = {
	var cr:Int;
	var cg:Int;
	var cb:Int;
}

typedef Rect = {
	var rect_nbits:Int;
	var left:Int;
	var right:Int;
	var top:Int;
	var bottom:Int;
}

typedef Header = {
	var h_version:Int;
	var h_size:Rect;
	var h_fps:Float16;
	var h_frame_count:Int;
	var h_compressed:Bool;
}

typedef Sound = {
	var so_id:Int;
	var so_flags:Int;
	var so_samples:Int;
	var so_data:haxe.io.Bytes;
}

typedef BitmapData = {
	var bd_id:Int;
	var bd_table:Null<haxe.io.Bytes>;
	var bd_data:haxe.io.Bytes;
	var bd_alpha:Null<haxe.io.Bytes>;
	var bd_deblock:Null<Int>;
}

typedef BitmapLossless = {
	var bll_id:Int;
	var bll_format:Int;
	var bll_width:Int;
	var bll_height:Int;
	var bll_data:haxe.io.Bytes;
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

// port: binary payloads (`string` upstream) are Bytes.
enum TagData {
	TEnd;
	TShowFrame;
	TSetBgColor(c:Rgb);
	TSound(s:Sound);
	TBitsJPEG2(b:BitmapData);
	TBitsJPEG3(b:BitmapData);
	TBitsLossless2(b:BitmapLossless);
	TEnableDebugger2(tag:Int, pass:String);
	TScriptLimits(recursionDepth:Int, scriptTimeout:Int);
	TFilesAttributes(f:FilesAttrib);
	TF9Classes(l:Array<F9Class>);
	TMetaData(meta:haxe.io.Bytes);
	TActionScript3(id:Null<{id:Int, frame:String}>, a:As3.As3Tag);
	TScenes(sl:Array<{n:Int, s:String}>, fl:Array<{n:Int, s:String}>);
	TBinaryData(id:Int, data:haxe.io.Bytes);
	TUnknown(id:Int, data:haxe.io.Bytes);
}

typedef Tag = {
	var tid:Int;
	var textended:Bool;
	var tdata:TagData;
}

typedef SwfData = {
	var header:Header;
	var tags:Array<Tag>;
}

class Swf {
	public static var warnings = true;

	public static function to_float16(f:Float):Float16 {
		var sign = f < 0.;
		var f = sign ? 0. - f : f;
		var high = Std.int(f);
		var low = Std.int((f - high) * 256.);
		if (high > 127) throw new core.ds.Failure("to_float16");
		return (high << 8) | (if (sign) low | (1 << 15) else low);
	}

	public static function write(ch:Output, data:SwfData):Void SwfParser.write(ch, data);
}
