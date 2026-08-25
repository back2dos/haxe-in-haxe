package unit;

import compiler.hxb.HxbData.ChunkKind;
import compiler.hxb.HxbWriter;
import core.ClassPath.DirectoryClassPath;
import core.ClassPaths;
import core.Define;
import typing.TypeloadModule;

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

		var paths = new ClassPaths();
		paths.push(new DirectoryClassPath("test/", core.ClassPath.ClassPathScope.User));
		var module = new TypeloadModule(paths, Define.emptyDefines()).loadModule({pack:["unit", "moduleload"], name:"Example"});
		var typedWriter = new HxbWriter();
		typedWriter.writeModule(module);
		var typedBytes = typedWriter.exportModule();
		var kinds = chunkKinds(typedBytes);
		var expectedKinds = "STR,MDF,MTF,CLR,ENR,ABR,TDR,CLD,END,ABD,TDD,EOT,CFR,CFD,EFD,AFD,EOF,EXD,EOM";
		if (kinds.join(",") != expectedKinds) throw 'Unexpected typed HXB chunk layout: ${kinds.join(",")}';
		if (typedBytes.get(0) != "h".code || typedBytes.get(1) != "x".code || typedBytes.get(2) != "b".code || typedBytes.get(3) != 1) throw "Typed HXB header was not written";
		var metadataModule = new TypeloadModule(paths, Define.emptyDefines()).loadModule({pack:["unit", "moduleload"], name:"Metadata"});
		var metadataWriter = new HxbWriter();
		metadataWriter.writeModule(metadataModule);
		if (metadataWriter.exportModule().length <= 4) throw "Metadata-bearing module was not serialized";
		var propertyModule = new TypeloadModule(paths, Define.emptyDefines()).loadModule({pack:["unit", "moduleload"], name:"Property"});
		var propertyWriter = new HxbWriter();
		propertyWriter.writeModule(propertyModule);
		if (propertyWriter.exportModule().length <= 4) throw "Property module was not serialized";
		var metadataFunctionModule = new TypeloadModule(paths, Define.emptyDefines()).loadModule({pack:["unit", "moduleload"], name:"MetadataFunction"});
		var metadataFunctionWriter = new HxbWriter();
		metadataFunctionWriter.writeModule(metadataFunctionModule);
		if (metadataFunctionWriter.exportModule().length <= 4) throw "Function-valued metadata was not serialized";
		var documentationModule = new TypeloadModule(paths, Define.emptyDefines()).loadModule({pack:["unit", "moduleload"], name:"Documentation"});
		var documentationClass = switch documentationModule.mTypes[0] { case TClassDecl(value): value; case _: throw "Expected documented class"; };
		if (documentationClass.clDoc == null || documentationClass.clDoc.docOwn != " Module type documentation. ") throw "Module documentation was not parsed";
		var documentationWriter = new HxbWriter();
		documentationWriter.writeModule(documentationModule);
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
