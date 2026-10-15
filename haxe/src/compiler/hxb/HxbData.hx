package compiler.hxb;

import haxe.io.BytesOutput;

/*
	MD = module
	MT = module type
	CL = class
	EN = enum
	AB = abstract
	TD = typedef
	OB = anonymous object
	CF = class field
	EF = enum field
	OF = object field
	EX = expression
	EO = end of (Types | Fields | Module)
	..F = forward definition
	..R = reference
	..D = definition
*/
enum ChunkKind {
	STR; /* string pool */
	DOC; /* doc pool */
	MDF; /* module forward */
	MTF; /* module types forward */
	/* Module type references */
	IMP; /* imports */
	CLR; /* class references */
	ENR; /* enum references */
	ABR; /* abstract references */
	TDR; /* typedef references */
	/* Anonymous objects */
	OFR; /* object field references */
	OFD; /* object field definitions */
	OBD; /* object definitions */
	/* Own module type definitions */
	CLD; /* class definition */
	END; /* enum definition */
	ABD; /* abstract definition */
	TDD; /* typedef definition */
	EOT; /* end of module types */
	/* Field references */
	EFR; /* enum field references */
	CFR; /* class field references */
	/* Own field definitions */
	CFD; /* class fields */
	EFD; /* enum fields */
	AFD; /* abstract fields */
	EOF; /* end of fields */
	EXD; /* class field expressions */
	EOM; /* end of module */
}

typedef CachedChunk = {kind:ChunkKind, data:haxe.io.Bytes};
typedef CachedChunks = Array<CachedChunk>;

@:structInit class ModuleCache {
	public var mcPath:core.Globals.GlobalTypePath;
	public var mcId:Int;
	public var mcChunks:CachedChunks;
	public var mcExtra:core.TType.ModuleDefExtra;

	public inline function new(mcPath:core.Globals.GlobalTypePath, mcId:Int, mcChunks:CachedChunks, mcExtra:core.TType.ModuleDefExtra) {
		this.mcPath = mcPath;
		this.mcId = mcId;
		this.mcChunks = mcChunks;
		this.mcExtra = mcExtra;
	}
}

enum TypingMode {
	FullTyping;
	AllowPartialTyping;
}

class HxbFailure {
	public final message:String;

	public function new(message:String) {
		this.message = message;
	}

	public function toString():String {
		return message;
	}
}

class HxbData {
	public static inline var VERSION = 1;

	public static function stringOfChunkKind(kind:ChunkKind):String {
		return switch (kind) {
			case STR: "STR";
			case DOC: "DOC";
			case MDF: "MDF";
			case MTF: "MTF";
			case IMP: "IMP";
			case CLR: "CLR";
			case ENR: "ENR";
			case ABR: "ABR";
			case TDR: "TDR";
			case OFR: "OFR";
			case OFD: "OFD";
			case OBD: "OBD";
			case EFR: "EFR";
			case CFR: "CFR";
			case CLD: "CLD";
			case END: "END";
			case ABD: "ABD";
			case TDD: "TDD";
			case EOT: "EOT";
			case CFD: "CFD";
			case EFD: "EFD";
			case AFD: "AFD";
			case EOF: "EOF";
			case EXD: "EXD";
			case EOM: "EOM";
		};
	}

	public static function chunkKindOfString(name:String):ChunkKind {
		return switch (name) {
			case "STR": STR;
			case "DOC": DOC;
			case "MDF": MDF;
			case "MTF": MTF;
			case "IMP": IMP;
			case "CLR": CLR;
			case "ENR": ENR;
			case "ABR": ABR;
			case "TDR": TDR;
			case "OFR": OFR;
			case "OFD": OFD;
			case "OBD": OBD;
			case "EFR": EFR;
			case "CFR": CFR;
			case "CLD": CLD;
			case "END": END;
			case "ABD": ABD;
			case "TDD": TDD;
			case "EOT": EOT;
			case "CFD": CFD;
			case "EFD": EFD;
			case "AFD": AFD;
			case "EOF": EOF;
			case "EXD": EXD;
			case "EOM": EOM;
			case _: throw new HxbFailure('Invalid chunk name: $name');
		};
	}

	public static function error(message:String):Dynamic {
		Sys.stderr().writeString('[error] $message\n');
		throw new HxbFailure(message);
	}

	public static function writeHeader(output:BytesOutput):Void {
		output.writeString("hxb");
		output.writeByte(VERSION);
	}

	public static function writeChunkPrefix(kind:ChunkKind, length:Int, output:BytesOutput):Void {
		output.writeString(stringOfChunkKind(kind));
		output.writeInt32(length);
	}
}
