package compiler.hxb;

import core.ds.StringPool;
import compiler.hxb.HxbData.ChunkKind;
import haxe.io.Bytes;
import haxe.io.BytesOutput;

// Low-level portion of haxe/src/compiler/hxb/hxbWriter.ml.  Module/type
// serialization intentionally remains separate until the typed writer is ported.
class HxbChunk {
	public final kind:ChunkKind;
	final strings:StringPool;
	var output:BytesOutput;

	public function new(kind:ChunkKind, strings:StringPool) {
		this.kind = kind;
		this.strings = strings;
		output = new BytesOutput();
	}

	public function reset():Void output = new BytesOutput();
	public function writeU8(value:Int):Void output.writeByte(value & 0xFF);

	public function writeI32(value:Int):Void {
		writeU8(value);
		writeU8(value >>> 8);
		writeU8(value >>> 16);
		writeU8(value >>> 24);
	}

	public function writeI64(value:haxe.Int64):Void {
		writeI32(value.low);
		writeI32(value.high);
	}

	public function writeF64(value:Float):Void writeI64(haxe.io.FPHelper.doubleToI64(value));
	public function writeBytes(value:Bytes):Void output.writeBytes(value, 0, value.length);
	public inline function writeUi16(value:Int):Void { writeU8(value); writeU8(value >>> 8); }

	public function writeUleb128(value:Int):Void {
		if (value < 0) throw "Cannot encode a negative ULEB128 value";
		do {
			var byte = value & 0x7F;
			value = value >>> 7;
			if (value != 0) byte |= 0x80;
			writeU8(byte);
		} while (value != 0);
	}

	public function writeLeb128(value:Int):Void {
		var more = true;
		while (more) {
			var byte = value & 0x7F;
			value >>= 7;
			more = !((value == 0 && (byte & 0x40) == 0) || (value == -1 && (byte & 0x40) != 0));
			if (more) byte |= 0x80;
			writeU8(byte);
		}
	}

	public function writeLengthPrefixedBytes(value:Bytes):Void {
		writeUleb128(value.length);
		writeBytes(value);
	}

	public inline function writeBool(value:Bool):Void writeU8(value ? 1 : 0);
	public function writeString(value:String):Void writeUleb128(strings.getOrAdd(value));

	public function writeList<T>(values:Array<T>, write:T->Void):Void {
		writeUleb128(values.length);
		for (value in values) write(value);
	}

	public function writeOption<T>(value:Null<T>, write:T->Void):Void {
		if (value == null) writeU8(0) else { writeU8(1); write(value); }
	}

	public function getBytes():Bytes return output.getBytes();
	public function exportTo(output:BytesOutput):Void {
		var bytes = getBytes();
		HxbData.writeChunkPrefix(kind, bytes.length, output);
		output.writeBytes(bytes, 0, bytes.length);
	}
}

class HxbWriter {
	public final strings:StringPool;
	final chunks:Array<HxbChunk>;

	public function new() {
		strings = new StringPool();
		chunks = [];
	}

	public function startChunk(kind:ChunkKind):HxbChunk {
		var chunk = new HxbChunk(kind, strings);
		chunks.push(chunk);
		return chunk;
	}

	// This is useful for diagnostics and unit tests. It does not serialize typed
	// modules yet, and therefore must not be presented as a compiler HXB output.
	public function exportRaw():Bytes {
		var output = new BytesOutput();
		HxbData.writeHeader(output);
		for (chunk in chunks) chunk.exportTo(output);
		return output.getBytes();
	}
}
