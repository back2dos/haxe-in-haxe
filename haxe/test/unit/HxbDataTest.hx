package unit;

import compiler.hxb.HxbData;
import compiler.hxb.HxbData.ChunkKind;
import haxe.io.BytesOutput;

class HxbDataTest {
	public static function main():Void {
		for (kind in [STR, DOC, MDF, MTF, IMP, CLR, ENR, ABR, TDR, OFR, OFD, OBD, CLD, END, ABD, TDD, EOT, EFR, CFR, CFD, EFD, AFD, EOF, EXD, EOM]) {
			if (HxbData.chunkKindOfString(HxbData.stringOfChunkKind(kind)) != kind) throw 'Chunk round-trip failed for $kind';
		}

		var output = new BytesOutput();
		HxbData.writeHeader(output);
		HxbData.writeChunkPrefix(STR, 42, output);
		var bytes = output.getBytes();
		if (bytes.get(0) != "h".code || bytes.get(1) != "x".code || bytes.get(2) != "b".code || bytes.get(3) != 1) throw "Invalid HXB header";
		if (bytes.sub(4, 3).toString() != "STR" || bytes.getInt32(7) != 42) throw "Invalid chunk prefix";

		try {
			HxbData.chunkKindOfString("BAD");
			throw "Invalid chunk kind must fail";
		} catch (error:Dynamic) {
			if (Std.string(error).indexOf("Invalid chunk name: BAD") < 0) throw error;
		}
	}
}
