package unit;

import haxe.Main;
import haxe.io.Bytes;
import sys.io.File;

/** Uses the `haxe` executable on PATH as the immediate byte-comparison oracle. */
class HostConformanceTest {
	static function main():Void {
		var reference = "/private/tmp/haxe-in-haxe-reference-basic.hxb";
		var port = "/private/tmp/haxe-in-haxe-port-basic.hxb";
		var code = Sys.command("haxe", ["-cp", "test/conformance", "--main", "unit.moduleload.Basic", "--hxb", reference]);
		if (code != 0) throw 'Host Haxe reference compilation failed with exit code $code';
		Main.run(["-cp", "test/conformance", "--main", "unit.moduleload.Basic", "--hxb", port]);
		assertEqual(File.getBytes(reference), File.getBytes(port));
	}

	static function assertEqual(reference:Bytes, port:Bytes):Void {
		if (reference.length != port.length) throw 'HXB mismatch: reference has ${reference.length} bytes; port has ${port.length} bytes';
		for (index in 0...reference.length) {
			if (reference.get(index) != port.get(index)) throw 'HXB mismatch at byte $index: reference=${reference.get(index)}, port=${port.get(index)}';
		}
	}
}
