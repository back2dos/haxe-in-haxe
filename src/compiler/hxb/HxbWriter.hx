package compiler.hxb;

import core.ds.StringPool;
import core.Globals.GlobalTypePath;
import core.Globals.Pos;
import core.TType;
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
	var classes:Map<String, TClass> = new Map();
	var enums:Map<String, TEnum> = new Map();
	var typedefs:Map<String, TDef> = new Map();
	var abstracts:Map<String, TAbstract> = new Map();
	var ownClasses:Array<TClass> = [];
	var ownEnums:Array<TEnum> = [];
	var ownTypedefs:Array<TDef> = [];
	var ownAbstracts:Array<TAbstract> = [];

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

	/**
		Writes the module-level portion of hxbWriter.ml.  This intentionally only
		covers data the batch typer currently constructs: positions, module types,
		field signatures, and type references.  Field expressions, metadata with
		expressions, type parameters and anonymous types still need their dedicated
		writer passes.
	**/
	public function writeModule(module:ModuleDef):Void {
		if (chunks.length != 0) throw "A typed module writer must start with an empty HxbWriter";
		forwardModuleTypes(module);

		if (ownAbstracts.length > 0) {
			var chunk = startChunk(ABD); chunk.writeList(ownAbstracts, function(value) writeAbstract(chunk, value));
			chunk = startChunk(AFD); chunk.writeList(ownAbstracts, function(value) writeAbstractFields(chunk, value));
		}
		if (ownClasses.length > 0) {
			var chunk = startChunk(CLD); chunk.writeList(ownClasses, function(value) writeClass(chunk, value));
			chunk = startChunk(CFD); chunk.writeList(ownClasses, function(value) writeClassFields(chunk, value));
		}
		if (ownEnums.length > 0) {
			var chunk = startChunk(END); chunk.writeList(ownEnums, function(value) writeEnum(chunk, value));
			chunk = startChunk(EFD); chunk.writeList(ownEnums, function(value) writeEnumFields(chunk, value));
		}
		if (ownTypedefs.length > 0) {
			var chunk = startChunk(TDD); chunk.writeList(ownTypedefs, function(value) writeTypedef(chunk, value));
		}

		writeReferences();
		var mdf = startChunk(MDF);
		writePath(mdf, module.mPath);
		mdf.writeString(Std.string(module.mExtra.mFile));
		mdf.writeUleb128(0); // anonymous-object pool (not ported yet)
		mdf.writeUleb128(0); // monomorph pool (not ported yet)
		startChunk(EOT); startChunk(EOF); startChunk(EOM);
		writeStringPool();
	}

	public function exportModule():Bytes {
		var output = new BytesOutput();
		HxbData.writeHeader(output);
		var sorted = chunks.copy();
		sorted.sort(function(a, b) return chunkOrder(a.kind) - chunkOrder(b.kind));
		for (chunk in sorted) chunk.exportTo(output);
		return output.getBytes();
	}

	function forwardModuleTypes(module:ModuleDef):Void {
		var mtf = startChunk(MTF);
		mtf.writeUleb128(module.mTypes.length);
		for (type in module.mTypes) forwardType(mtf, type);
	}

	function forwardType(chunk:HxbChunk, type:ModuleType):Void {
		switch type {
			case TClassDecl(value):
				addClass(value, true); chunk.writeU8(0); writePath(chunk, value.clPath); writePosPair(chunk, value.clPos, value.clNamePos); writeEmptyTypeParams(chunk);
				chunk.writeUleb128(value.clFlags); chunk.writeOption(value.clConstructor, function(field) writeClassFieldForward(chunk, field)); chunk.writeOption(value.clInit, function(field) writeClassFieldForward(chunk, field));
				chunk.writeUleb128(value.clOrderedFields.length); chunk.writeUleb128(value.clOrderedStatics.length);
				// hxbReader reads these tail-recursively, hence upstream writes reverse order.
				for (i in 0...value.clOrderedFields.length) writeClassFieldForward(chunk, value.clOrderedFields[value.clOrderedFields.length - 1 - i]);
				for (i in 0...value.clOrderedStatics.length) writeClassFieldForward(chunk, value.clOrderedStatics[value.clOrderedStatics.length - 1 - i]);
			case TEnumDecl(value):
				addEnum(value, true); chunk.writeU8(1); writePath(chunk, value.ePath); writePosPair(chunk, value.ePos, value.eNamePos); writeEmptyTypeParams(chunk);
				chunk.writeUleb128(value.eNames.length);
				for (name in value.eNames) { var field = value.eConstrs.get(name); chunk.writeString(name); writePosPair(chunk, field.efPos, field.efNamePos); chunk.writeUleb128(field.efIndex); }
			case TTypeDecl(value): addTypedef(value, true); chunk.writeU8(2); writePath(chunk, value.tPath); writePosPair(chunk, value.tPos, value.tNamePos); writeEmptyTypeParams(chunk);
			case TAbstractDecl(value): addAbstract(value, true); chunk.writeU8(3); writePath(chunk, value.aPath); writePosPair(chunk, value.aPos, value.aNamePos); writeEmptyTypeParams(chunk);
		}
	}

	function writeClass(chunk:HxbChunk, value:TClass):Void {
		writeCommon(chunk, value.clPrivate, value.clDoc, value.clMeta, value.clUsing);
		writeClassKind(chunk, value.clKind);
		chunk.writeOption(value.clSuper, function(parent) { writeClassRef(chunk, parent.cls); writeTypes(chunk, parent.params); });
		chunk.writeList(value.clImplements, function(parent) { writeClassRef(chunk, parent.cls); writeTypes(chunk, parent.params); });
		chunk.writeOption(value.clDynamic, function(type) writeType(chunk, type));
		chunk.writeOption(value.clArrayAccess, function(type) writeType(chunk, type));
	}

	function writeClassFields(chunk:HxbChunk, value:TClass):Void {
		chunk.writeOption(value.clConstructor, function(field) writeClassFieldData(chunk, field));
		chunk.writeOption(value.clInit, function(field) writeClassFieldData(chunk, field));
		chunk.writeList(value.clOrderedFields, function(field) writeClassFieldData(chunk, field));
		chunk.writeList(value.clOrderedStatics, function(field) writeClassFieldData(chunk, field));
	}

	function writeEnum(chunk:HxbChunk, value:TEnum):Void { writeCommon(chunk, value.ePrivate, value.eDoc, value.eMeta, value.eUsing); chunk.writeUleb128(value.eFlags); chunk.writeList(value.eNames, chunk.writeString); }
	function writeEnumFields(chunk:HxbChunk, value:TEnum):Void {
		chunk.writeUleb128(value.eNames.length);
		for (name in value.eNames) { var field = value.eConstrs.get(name); chunk.writeString(name); writeType(chunk, field.efType); writeEmptyTypeParamsData(chunk); writeDocumentation(chunk, field.efDoc); writeMetadata(chunk, field.efMeta); }
	}
	function writeTypedef(chunk:HxbChunk, value:TDef):Void { writeCommon(chunk, value.tPrivate, value.tDoc, value.tMeta, value.tUsing); writeType(chunk, value.tType); }
	function writeAbstract(chunk:HxbChunk, value:TAbstract):Void {
		writeCommon(chunk, value.aPrivate, value.aDoc, value.aMeta, value.aUsing); chunk.writeOption(value.aImpl, function(cls) writeClassRef(chunk, cls));
		chunk.writeU8(1); writeType(chunk, value.aThis); writeTypes(chunk, value.aFrom); writeTypes(chunk, value.aTo); chunk.writeBool(value.aExtern); chunk.writeBool(value.aEnum);
	}
	function writeAbstractFields(chunk:HxbChunk, value:TAbstract):Void {
		// Field references are deliberately deferred until the field-reference pool is ported.
		if (value.aArray.length != 0 || value.aRead != null || value.aWrite != null || value.aCall != null || value.aConstructor != null || value.aOps.length != 0 || value.aUnops.length != 0 || value.aFromField.length != 0 || value.aToField.length != 0) throw "Abstract field serialization is not ported";
		chunk.writeUleb128(0); for (_ in 0...4) chunk.writeU8(0); chunk.writeUleb128(0); chunk.writeUleb128(0); chunk.writeUleb128(0); chunk.writeUleb128(0);
	}

	function writeClassFieldForward(chunk:HxbChunk, field:TClassField):Void { chunk.writeString(field.cfName); writePosPair(chunk, field.cfPos, field.cfNamePos); writeMetadata(chunk, field.cfMeta); chunk.writeUleb128(field.cfOverloads.length); for (other in field.cfOverloads) writeClassFieldForward(chunk, other); }
	function writeClassFieldData(chunk:HxbChunk, field:TClassField):Void {
		var all = [field].concat(field.cfOverloads); chunk.writeUleb128(all.length);
		for (value in all) { writeType(chunk, value.cfType); chunk.writeUleb128(value.cfFlags); writeDocumentation(chunk, value.cfDoc); writeFieldKind(chunk, value.cfKind); chunk.writeU8(0); writeEmptyTypeParamsData(chunk); }
	}

	function writeCommon(chunk:HxbChunk, privateType:Bool, doc:Dynamic, meta:Dynamic, usingTypes:Array<{var cls:TClass; var pos:Pos;}>):Void { chunk.writeBool(privateType); writeDocumentation(chunk, doc); writeMetadata(chunk, meta); writeEmptyTypeParamsData(chunk); chunk.writeList(usingTypes, function(value) { writeClassRef(chunk, value.cls); writePos(chunk, value.pos); }); }
	function writeClassKind(chunk:HxbChunk, kind:TClassKind):Void switch kind { case KNormal: chunk.writeU8(0); case KGeneric: chunk.writeU8(3); case KGenericInstance(cls, params): chunk.writeU8(4); writeClassRef(chunk, cls); writeTypes(chunk, params); case KMacroType: chunk.writeU8(5); case KModuleFields(_): chunk.writeU8(8); case _: throw "Class kind serialization is not ported"; }
	function writeFieldKind(chunk:HxbChunk, kind:FieldKind):Void switch kind { case Method(MethNormal): chunk.writeU8(0); case Method(MethInline): chunk.writeU8(1); case Method(MethDynamic): chunk.writeU8(2); case Method(MethMacro): chunk.writeU8(3); case Var(value): if (value.vRead != AccNormal || value.vWrite != AccNormal) throw "Property access serialization is not ported"; chunk.writeU8(10); }

	function writeType(chunk:HxbChunk, type:T):Void switch type {
		case TAbstract(value, params) if (value.aPath.pack.length == 0 && params.length == 0): switch value.aPath.name { case "Void": chunk.writeU8(100); case "Int": chunk.writeU8(101); case "Float": chunk.writeU8(102); case "Bool": chunk.writeU8(103); case "String": chunk.writeU8(104); case _: writeReferenceType(chunk, 70, function() return addAbstract(value, false), params); }
		case TInst(value, params): writeReferenceType(chunk, 40, function() return addClass(value, false), params);
		case TEnum(value, params): writeReferenceType(chunk, 50, function() return addEnum(value, false), params);
		case TType(value, params): writeReferenceType(chunk, 60, function() return addTypedef(value, false), params);
		case TAbstract(value, params): writeReferenceType(chunk, 70, function() return addAbstract(value, false), params);
		case TDynamic(null): chunk.writeU8(4);
		case TDynamic(value): chunk.writeU8(89); writeType(chunk, value);
		case TFun(signature):
			var args = signature.args;
			var ret = signature.ret;
			if (args.length > 4) { chunk.writeU8((ret == null || isVoid(ret)) ? 29 : 39); chunk.writeUleb128(args.length); } else chunk.writeU8((ret == null || isVoid(ret)) ? 20 + args.length : 30 + args.length);
			for (arg in args) { chunk.writeString(arg.name); chunk.writeBool(arg.optional); writeType(chunk, arg.type); }
			if (!isVoid(ret)) writeType(chunk, ret);
		case TLazy(value): switch value { case LAvailable(inner) | LProcessing(inner): writeType(chunk, inner); case LWait(_): throw "Unevaluated lazy type cannot be serialized"; }
		case TMono(value): if (value.tmType == null) throw "Unbound monomorph cannot be serialized" else writeType(chunk, value.tmType);
		case TAnon(_): throw "Anonymous type serialization is not ported";
	}
	function writeReferenceType(chunk:HxbChunk, base:Int, getIndex:Void->Int, params:TParams):Void { if (params.length > 2) { chunk.writeU8(base + 9); chunk.writeUleb128(getIndex()); writeTypes(chunk, params); } else { chunk.writeU8(base + params.length); chunk.writeUleb128(getIndex()); for (type in params) writeType(chunk, type); } }
	function writeClassRef(chunk:HxbChunk, value:TClass):Void chunk.writeUleb128(addClass(value, false));
	function isVoid(type:T):Bool return switch type { case TAbstract(value, params): value.aPath.pack.length == 0 && value.aPath.name == "Void" && params.length == 0; case _: false; }

	function writeReferences():Void {
		if (classes.keys().hasNext()) { var chunk = startChunk(CLR); chunk.writeUleb128(count(classes)); for (value in ordered(classes)) writeFullPath(chunk, value.clModule.mPath, value.clPath.name); }
		if (abstracts.keys().hasNext()) { var chunk = startChunk(ABR); chunk.writeUleb128(count(abstracts)); for (value in ordered(abstracts)) writeFullPath(chunk, value.aModule.mPath, value.aPath.name); }
		if (enums.keys().hasNext()) { var chunk = startChunk(ENR); chunk.writeUleb128(count(enums)); for (value in ordered(enums)) writeFullPath(chunk, value.eModule.mPath, value.ePath.name); }
		if (typedefs.keys().hasNext()) { var chunk = startChunk(TDR); chunk.writeUleb128(count(typedefs)); for (value in ordered(typedefs)) writeFullPath(chunk, value.tModule.mPath, value.tPath.name); }
	}
	function writeStringPool():Void { var values = strings.finalize(); var chunk = startChunk(STR); chunk.writeUleb128(values.length); values.iter(function(value) chunk.writeLengthPrefixedBytes(Bytes.ofString(value))); }

	function addClass(value:TClass, own:Bool):Int return add(classes, pathKey(value.clPath), value, own ? ownClasses : null);
	function addEnum(value:TEnum, own:Bool):Int return add(enums, pathKey(value.ePath), value, own ? ownEnums : null);
	function addTypedef(value:TDef, own:Bool):Int return add(typedefs, pathKey(value.tPath), value, own ? ownTypedefs : null);
	function addAbstract(value:TAbstract, own:Bool):Int return add(abstracts, pathKey(value.aPath), value, own ? ownAbstracts : null);
	function add<T>(pool:Map<String, T>, key:String, value:T, own:Array<T>):Int { var index = indexOf(pool, key); if (index >= 0) return index; var result = count(pool); pool.set(key, value); if (own != null) own.push(value); return result; }
	function indexOf<T>(pool:Map<String, T>, key:String):Int { var index = 0; for (existing in pool.keys()) { if (existing == key) return index; index++; } return -1; }
	function ordered<T>(pool:Map<String, T>):Array<T> { var result = []; for (key in pool.keys()) result.push(pool.get(key)); return result; }
	function count<T>(pool:Map<String, T>):Int { var result = 0; for (_ in pool.keys()) result++; return result; }
	static function pathKey(path:GlobalTypePath):String return path.pack.join(".") + ":" + path.name;
	static function writePath(chunk:HxbChunk, path:GlobalTypePath):Void { chunk.writeList(path.pack, chunk.writeString); chunk.writeString(path.name); }
	static function writeFullPath(chunk:HxbChunk, modulePath:GlobalTypePath, typeName:String):Void { chunk.writeList(modulePath.pack, chunk.writeString); chunk.writeString(modulePath.name); chunk.writeString(typeName); }
	static function writePos(chunk:HxbChunk, pos:Pos):Void { chunk.writeString(pos.pfile); chunk.writeLeb128(pos.pmin); chunk.writeLeb128(pos.pmax); }
	static function writePosPair(chunk:HxbChunk, first:Pos, second:Pos):Void { writePos(chunk, first); chunk.writeLeb128(second.pmin - first.pmin); chunk.writeLeb128(second.pmax - first.pmin); }
	static function writeDocumentation(chunk:HxbChunk, doc:Dynamic):Void chunk.writeU8(0);
	static function writeMetadata(chunk:HxbChunk, meta:Dynamic):Void { if (meta != null && (cast meta:Array<Dynamic>).length != 0) throw "Metadata serialization is not ported"; chunk.writeUleb128(0); }
	static function writeEmptyTypeParams(chunk:HxbChunk):Void chunk.writeUleb128(0);
	static function writeEmptyTypeParamsData(chunk:HxbChunk):Void {}
	function writeTypes(chunk:HxbChunk, types:TParams):Void chunk.writeList(types, function(type) writeType(chunk, type));
	static function chunkOrder(kind:ChunkKind):Int return switch kind { case STR: 0; case DOC: 1; case MDF: 2; case MTF: 3; case IMP: 4; case CLR: 5; case ENR: 6; case ABR: 7; case TDR: 8; case OFR: 9; case OFD: 10; case OBD: 11; case CLD: 12; case END: 13; case ABD: 14; case TDD: 15; case EOT: 16; case EFR: 17; case CFR: 18; case CFD: 19; case EFD: 20; case AFD: 21; case EOF: 22; case EXD: 23; case EOM: 24; }
}
