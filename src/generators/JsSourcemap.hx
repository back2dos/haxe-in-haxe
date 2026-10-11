package generators;

import core.Globals.Pos;
import core.TType;

@:structInit class Sourcemap {
	public var sources:Array<String>;
	public var sourcesHash:haxe.ds.StringMap<Int>;
	// port: Rbuffer.t
	public var mappings:StringBuf;

	public var sourceLastPos:SourcemapPos;
	public var printComma:Bool;
	public var outputLastCol:Int;
	public var outputCurrentCol:Int;
	public var currentExpr:Null<SourcemapPos>;
}

@:structInit class SourcemapPos {
	public var file:Int;
	public var line:Int;
	public var col:Int;
}

class JsSourcemap {
	static final chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

	public static function encodeMapping(smap:Sourcemap, pos:SourcemapPos):Void {
		if (smap.printComma) smap.mappings.addChar(",".code) else smap.printComma = true;

		function base64Vlq(number:Int):Void {
			function encodeDigit(digit:Int):Int return StringTools.fastCodeAt(chars, digit);
			function toVlq(number:Int):Int return if (number < 0) ((-number) << 1) + 1 else number << 1;
			function loop(vlq:Int):Void {
				var shift = 5;
				var base = 1 << shift;
				var mask = base - 1;
				var continuationBit = base;
				var digit = vlq & mask;
				var next = vlq >> shift;
				smap.mappings.addChar(encodeDigit(if (next > 0) digit | continuationBit else digit));
				if (next > 0) loop(next);
			}
			loop(toVlq(number));
		}

		base64Vlq(smap.outputCurrentCol - smap.outputLastCol);
		base64Vlq(pos.file - smap.sourceLastPos.file);
		base64Vlq(pos.line - smap.sourceLastPos.line);
		base64Vlq(pos.col - smap.sourceLastPos.col);

		smap.sourceLastPos = pos;
		smap.outputLastCol = smap.outputCurrentCol;
	}

	public static function noop():Void {}

	static function addMappingPos(smap:Sourcemap, pos:Pos):Void->Void {
		if (pos.pmin < 0) return noop;

		var file = if (smap.sourcesHash.exists(pos.pfile)) smap.sourcesHash.get(pos.pfile) else {
			var length = smap.sources.length;
			smap.sourcesHash.set(pos.pfile, length);
			smap.sources.push(pos.pfile);
			length;
		}

		var pos:SourcemapPos = {
			var lc = syntax.Lexer.findPos(pos);
			var line = lc.line - 1;
			{file: file, line: line, col: lc.column};
		}

		var last = smap.sourceLastPos;
		if (last.file != pos.file || last.line != pos.line || last.col != pos.col) {
			var oldCurrentExpr = smap.currentExpr;
			smap.currentExpr = pos;
			encodeMapping(smap, pos);
			return function() smap.currentExpr = oldCurrentExpr;
		} else return noop;
	}

	public static function addMapping(smap:Null<Sourcemap>, e:TExpr):Void->Void return smap == null ? noop : addMappingPos(smap, e.epos);

	public static function handleNewlines(smap:Null<Sourcemap>, str:String):Void {
		if (smap == null) return;
		function loop(from:Int):Void {
			var idx = str.indexOf("\n", from);
			if (idx >= 0) {
				var next = idx + 1;
				smap.mappings.addChar(";".code);
				smap.outputLastCol = 0;
				smap.outputCurrentCol = 0;
				smap.printComma = false;
				if (smap.currentExpr != null) encodeMapping(smap, smap.currentExpr);
				loop(next);
			} else smap.outputCurrentCol = smap.outputCurrentCol + utf8Length(str, from);
		}
		loop(0);
	}

	// port: String.length counts the bytes of OCaml's UTF-8 strings: (String.length str - from).
	static function utf8Length(str:String, from:Int):Int {
		var n = 0;
		for (i in from...str.length) {
			var c = StringTools.fastCodeAt(str, i);
			// port: a UTF-16 surrogate half counts 2, so a pair counts the 4 bytes of its code point.
			n += c < 0x80 ? 1 : c < 0x800 ? 2 : (c >= 0xD800 && c < 0xE000) ? 2 : c < 0x10000 ? 3 : 4;
		}
		return n;
	}

	public static function writeMappings(com:Gctx, smap:Sourcemap, sourcePathPrefix:String):Void {
		// port: Filename.basename on Unix (only '/' separates; a file path has no trailing slash).
		var basefile = com.file.substr(com.file.lastIndexOf("/") + 1);
		var channel = new StringBuf();
		var sources = smap.sources;
		function toUrl(file:String):String return core.Path.getFullPath(file).split("\\").join("/");
		channel.add("{\n");
		channel.add("\"version\":3,\n");
		channel.add("\"file\":\"" + basefile.split("\\").join("\\\\") + "\",\n");
		channel.add("\"sourceRoot\":\"\",\n");
		channel.add("\"sources\":[" + sources.map(s -> "\"" + sourcePathPrefix + toUrl(s) + "\"").join(",") + "],\n");
		if (Gctx.defined(com, core.Define.SourceMapContent)) {
			channel.add("\"sourcesContent\":["
				+ sources.map(s -> try "\"" + core.StringHelper.sEscape(sys.io.File.getContent(s)) + "\"" catch (_:Dynamic) "null").join(",")
				+ "],\n");
		}
		channel.add("\"names\":[],\n");
		channel.add("\"mappings\":\"");
		channel.add(smap.mappings.toString());
		channel.add("\"\n");
		channel.add("}");
		sys.io.File.saveContent(com.file + ".map", channel.toString());
	}
}
