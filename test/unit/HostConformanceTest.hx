package unit;

import haxe.Main;
import haxe.ds.StringMap;
import haxe.io.Bytes;
import haxe.zip.Reader;
import sys.io.File;

/** Uses the `haxe` executable on PATH as the immediate HXB-member oracle. */
class HostConformanceTest {
	static function main():Void {
		var reference = "/private/tmp/haxe-in-haxe-reference-basic.hxb";
		var port = "/private/tmp/haxe-in-haxe-port-basic.hxb";
		var code = Sys.command("haxe", ["-cp", "test/conformance", "--main", "unit.moduleload.Basic", "--hxb", reference]);
		if (code != 0) throw 'Host Haxe reference compilation failed with exit code $code';
		Main.run(["-cp", "test/conformance", "--main", "unit.moduleload.Basic", "--hxb", port]);
		assertArchivesEqual(reference, port);
	}

	static function assertArchivesEqual(referenceFile:String, portFile:String):Void {
		var reference = readArchive(referenceFile);
		var port = readArchive(portFile);
		var referenceNames = [for (name in reference.keys()) name];
		var portNames = [for (name in port.keys()) name];
		referenceNames.sort(Reflect.compare);
		portNames.sort(Reflect.compare);
		if (referenceNames.join("\n") != portNames.join("\n")) throw 'HXB archive members differ:\nreference=${referenceNames.join(",")}\nport=${portNames.join(",")}';
		for (name in referenceNames) assertEqual(name, reference.get(name), port.get(name));
	}

	static function readArchive(file:String):StringMap<Bytes> {
		var input = File.read(file, true);
		var entries = Reader.readZip(input);
		input.close();
		var result = new StringMap<Bytes>();
		for (entry in entries) result.set(entry.fileName, entry.data);
		return result;
	}

	static function assertEqual(name:String, reference:Bytes, port:Bytes):Void {
		if (reference.length != port.length) throw '$name: reference has ${reference.length} bytes; port has ${port.length} bytes';
		for (index in 0...reference.length) {
			if (reference.get(index) != port.get(index)) throw '$name differs at byte $index: reference=${reference.get(index)}, port=${port.get(index)}';
		}
	}
}
