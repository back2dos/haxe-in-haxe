package unit;

import haxe.Main;
import sys.FileSystem;
import sys.io.File;

class BatchDriverTest {
	public static function main():Void {
		var output = "test/generated/batch-driver.hxb";
		Main.run(["-cp", "test", "-D", "batch_driver", "--main", "unit.moduleload.Example", "--hxb", output]);
		if (!FileSystem.exists(output)) throw "Batch driver did not create HXB output";
		var bytes = File.getBytes(output);
		if (bytes.length < 4 || bytes.get(0) != "h".code || bytes.get(1) != "x".code || bytes.get(2) != "b".code || bytes.get(3) != 1) throw "Batch driver HXB header is invalid";
		var kinds = chunkKinds(bytes);
		if (kinds.indexOf("MTF") < 0 || kinds.indexOf("MDF") < 0 || kinds.indexOf("EOM") < 0) throw 'Batch driver HXB chunks are incomplete: ${kinds.join(",")}';
		try {
			Main.run(["--interp"]);
			throw "Unsupported option must fail";
		} catch (error:Dynamic) {
			if (Std.string(error).indexOf("Unsupported batch HXB compiler option") < 0) throw error;
		}
	}

	static function chunkKinds(bytes:haxe.io.Bytes):Array<String> {
		var result = [];
		var offset = 4;
		while (offset < bytes.length) {
			if (offset + 7 > bytes.length) throw "Malformed batch-driver HXB chunk prefix";
			var kind = String.fromCharCode(bytes.get(offset)) + String.fromCharCode(bytes.get(offset + 1)) + String.fromCharCode(bytes.get(offset + 2));
			var length = bytes.get(offset + 3) | (bytes.get(offset + 4) << 8) | (bytes.get(offset + 5) << 16) | (bytes.get(offset + 6) << 24);
			result.push(kind);
			offset += 7 + length;
		}
		if (offset != bytes.length) throw "Malformed batch-driver HXB chunk boundaries";
		return result;
	}
}
