package core;

import haxe.ds.List;
import haxe.io.Bytes;
import haxe.zip.Entry;
import haxe.zip.Writer;
import sys.io.File;

// Port of haxe/src/core/zip_output.ml.
class AnyOutput {
	public function new() {}

	public function addEntry(content:String, name:String):Void {
		throw "Not implemented";
	}

	public function close():Void {
		throw "Not implemented";
	}
}

class ZipOutput extends AnyOutput {
	final output:sys.io.FileOutput;
	final writer:Writer;
	final compressionLevel:Int;
	final entries:List<Entry> = new List();
	var closed = false;

	public function new(zipPath:String, compressionLevel:Int) {
		super();
		this.output = File.write(zipPath, true);
		this.writer = new Writer(output);
		this.compressionLevel = compressionLevel;
	}

	override public function addEntry(content:String, name:String):Void {
		addBytesEntry(Bytes.ofString(content), name);
	}

	/**
		Adds binary data without round-tripping it through a Haxe String. HXB
		modules are byte streams, so archive generation must retain every byte.
	**/
	public function addBytesEntry(content:Bytes, name:String):Void {
		if (closed) throw "Output is closed";
		var data = content;
		var fileSize = data.length;
		var compressed = compressionLevel != 0;
		var crc32 = haxe.crypto.Crc32.make(data);
		if (compressed) {
			// haxe.zip.Compress emits a zlib stream, while ZIP stores raw DEFLATE.
			var zlibData = haxe.zip.Compress.run(data, compressionLevel);
			data = zlibData.sub(2, zlibData.length - 6);
		}
		entries.add({
			fileName: name,
			fileSize: fileSize,
			fileTime: Date.now(),
			compressed: compressed,
			dataSize: data.length,
			data: data,
			crc32: crc32
		});
	}

	override public function close():Void {
		if (closed) return;
		writer.write(entries);
		output.close();
		closed = true;
	}
}
