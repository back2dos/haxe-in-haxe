package core;

import haxe.ds.List;
import haxe.io.Bytes;
import haxe.zip.Entry;
import haxe.zip.Writer;
import sys.io.File;

// port: from haxe/src/core/zip_output.ml.
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

	// port: adds binary data without round-tripping it through a Haxe String. HXB
	// modules are byte streams, so archive generation must retain every byte.
	public function addBytesEntry(content:Bytes, name:String):Void {
		if (closed) throw "Output is closed";
		var data = content;
		var fileSize = data.length;
		var compressed = compressionLevel != 0;
		var crc32 = crc32Of(data);
		if (compressed) {
			// port: haxe.zip.Compress emits a zlib stream, while ZIP stores raw DEFLATE.
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

	// port: table-driven CRC-32, as in zlib (upstream's Zip uses zlib's crc32);
	// haxe.crypto.Crc32 computes it bit by bit.
	static final crcTable:haxe.ds.Vector<Int> = {
		var t = new haxe.ds.Vector<Int>(256);
		for (n in 0...256) {
			var c = n;
			for (_ in 0...8) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
			t[n] = c;
		}
		t;
	};

	static function crc32Of(b:Bytes):Int {
		var crc = 0xFFFFFFFF, table = crcTable;
		for (i in 0...b.length) crc = table[(crc ^ b.get(i)) & 0xFF] ^ (crc >>> 8);
		return crc ^ 0xFFFFFFFF;
	}

	override public function close():Void {
		if (closed) return;
		writer.write(entries);
		output.close();
		closed = true;
	}
}
