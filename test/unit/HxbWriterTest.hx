package unit;

import compiler.hxb.HxbData.ChunkKind;
import compiler.hxb.HxbWriter;

class HxbWriterTest {
	public static function main():Void {
		var strings = new core.ds.StringPool();
		var chunk = new Chunk(MDF, strings, 16);
		chunk.writeUleb128(624485);
		chunk.writeLeb128(-123456);
		chunk.writeI32(0x12345678);
		chunk.writeBool(true);
		chunk.writeString("same");
		chunk.writeString("same");
		var out = new haxe.io.BytesOutput();
		compiler.hxb.HxbData.writeHeader(out);
		chunk.export(out);
		var bytes = out.getBytes();
		var expected = ["h".code, "x".code, "b".code, 1, "M".code, "D".code, "F".code, 13, 0, 0, 0, 0xE5, 0x8E, 0x26, 0xC0, 0xBB, 0x78, 0x78, 0x56, 0x34, 0x12, 1, 0, 0];
		if (bytes.length != expected.length) throw 'Unexpected HXB chunk length: ${bytes.length}';
		for (i in 0...expected.length) if (bytes.get(i) != expected[i]) throw 'Unexpected byte at $i: ${bytes.get(i)}';

		var result = TypeloadModuleTest.compile(["-cp", "test", "unit.moduleload.Inheritance", "unit.moduleload.Documentation", "--hxb", "test/generated/unit-hxbwriter.hxb"]);
		if (result.code != 0 || result.com == null) throw 'Typing the HXB writer fixtures failed with exit code ${result.code}';
		function find(name:String):core.TType.ModuleDef {
			for (m in result.com.modules) if (m.mPath.pack.join(".") == "unit.moduleload" && m.mPath.name == name) return m;
			throw 'Module $name was not typed';
		}
		var module = find("Inheritance");
		var typedWriter = new HxbWriter();
		typedWriter.writeModule(module);
		var typedBytes = typedWriter.exportModule();
		var kinds = chunkKinds(typedBytes);
		var expectedKinds = "STR,MDF,MTF,CLR,CLD,EOT,CFR,CFD,EOF,EXD,EOM";
		if (kinds.join(",") != expectedKinds) throw 'Unexpected typed HXB chunk layout: ${kinds.join(",")}';
		if (typedBytes.get(0) != "h".code || typedBytes.get(1) != "x".code || typedBytes.get(2) != "b".code || typedBytes.get(3) != 1) throw "Typed HXB header was not written";
		var moduleFile = module.mExtra.mFile;
		var lazyFile = core.Path.UniqueKey.createLazy(core.Path.UniqueKey.lazyPath(moduleFile));
		module.mExtra.mFile = lazyFile;
		var lazyFileWriter = new HxbWriter();
		lazyFileWriter.writeModule(module);
		module.mExtra.mFile = moduleFile;
		if (typedBytes.compare(lazyFileWriter.exportModule()) != 0) throw "Module filename representation changed the HXB payload";
		if (lazyFile.key != null) throw "Writing the module filename should not force its unique key";
		var documentationWriter = new HxbWriter();
		documentationWriter.writeModule(find("Documentation"));
		var documentationKinds = chunkKinds(documentationWriter.exportModule());
		if (documentationKinds.indexOf("DOC") < 0) throw "Documentation pool was not serialized";
	}

	static function chunkKinds(bytes:haxe.io.Bytes):Array<String> {
		var result = [];
		var offset = 4;
		while (offset < bytes.length) {
			var kind = String.fromCharCode(bytes.get(offset)) + String.fromCharCode(bytes.get(offset + 1)) + String.fromCharCode(bytes.get(offset + 2));
			var length = bytes.get(offset + 3) | (bytes.get(offset + 4) << 8) | (bytes.get(offset + 5) << 16) | (bytes.get(offset + 6) << 24);
			result.push(kind);
			offset += 7 + length;
		}
		if (offset != bytes.length) throw "Malformed HXB chunk boundaries";
		return result;
	}
}
