package unit;

import compiler.hxb.HxbData.ChunkKind;
import compiler.hxb.HxbWriter;

class HxbWriterTest {
	public static function main():Void {
		var writer = new HxbWriter();
		var chunk = writer.startChunk(MDF);
		chunk.writeUleb128(624485);
		chunk.writeLeb128(-123456);
		chunk.writeI32(0x12345678);
		chunk.writeBool(true);
		chunk.writeString("same");
		chunk.writeString("same");
		var bytes = writer.exportRaw();
		var expected = ["h".code, "x".code, "b".code, 1, "M".code, "D".code, "F".code, 13, 0, 0, 0, 0xE5, 0x8E, 0x26, 0xC0, 0xBB, 0x78, 0x78, 0x56, 0x34, 0x12, 1, 0, 0];
		if (bytes.length != expected.length) throw 'Unexpected HXB chunk length: ${bytes.length}';
		for (i in 0...expected.length) if (bytes.get(i) != expected[i]) throw 'Unexpected byte at $i: ${bytes.get(i)}';

		var negative = writer.startChunk(EOM);
		try {
			negative.writeUleb128(-1);
			throw "Negative ULEB128 must fail";
		} catch (error:Dynamic) {
			if (Std.string(error).indexOf("negative ULEB128") < 0) throw error;
		}
	}
}
