package compiler.hxb;

import core.ds.StringPool;
import core.Ast.Constant;
import core.Ast.Binop;
import core.Ast.Unop;
import core.Ast.UnopFlag;
import core.Ast.EFieldKind;
import core.Ast.ExprDef;
import core.Ast.StringLiteralKind;
import core.Globals.GlobalTypePath;
import core.Globals.Pos;
import core.TType;
import compiler.hxb.HxbData.ChunkKind;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.ds.ObjectMap;

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
	final documentation:StringPool;
	var hasDocumentation = false;
	final chunks:Array<HxbChunk>;
	var classIndices:Map<String, Int> = new Map();
	var enumIndices:Map<String, Int> = new Map();
	var typedefIndices:Map<String, Int> = new Map();
	var abstractIndices:Map<String, Int> = new Map();
	var classOrder:Array<TClass> = [];
	var enumOrder:Array<TEnum> = [];
	var typedefOrder:Array<TDef> = [];
	var abstractOrder:Array<TAbstract> = [];
	var ownClasses:Array<TClass> = [];
	var ownEnums:Array<TEnum> = [];
	var ownTypedefs:Array<TDef> = [];
	var ownAbstracts:Array<TAbstract> = [];
	var fieldReferences:Array<{var cls:TClass; var field:TClassField; var kind:Int; var depth:Int;}> = [];
	var fieldReferenceIndices:Map<String, Int> = new Map();
	var anonymousTypes:Array<TAnon> = [];
	var anonymousTypeIndices:Map<TAnon, Int> = new Map();
	var inlineAnonymousTypes:ObjectMap<TAnon, Bool> = new ObjectMap();
	var anonymousFields:Array<TClassField> = [];
	var anonymousFieldData:Array<Bytes> = [];
	var anonymousFieldIndices:Map<TClassField, Int> = new Map();
	var inlineAnonymousFields:ObjectMap<TClassField, Bool> = new ObjectMap();
	var expressionVars:Array<TVar> = [];
	var expressionVarIndices:ObjectMap<TVar, Int> = new ObjectMap();
	var expressionThisType:Null<T> = null;
	var optimizedExpressionPositions = false;
	var skipOptimizedSingleBlocks = false;
	var writingUnoptimizedExpression = false;
	var skipUnoptimizedParentheses = false;
	var fieldTypeParamIndices:ObjectMap<TypedTypeParam, Int> = new ObjectMap();
	var typeTypeParamIndices:Map<String, Int> = new Map();

	public function new() {
		strings = new StringPool();
		documentation = new StringPool();
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
		Writes the module-level portion of hxbWriter.ml for the typed data currently
		constructed by the batch typer, including field expressions and anonymous
		object pools. Advanced generic-context and local-variable cases remain
		outside this batch slice.
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
			var expressions:Array<{var cls:TClass; var field:TClassField; var bytes:Bytes;}> = [];
			chunk = startChunk(CFD); chunk.writeList(ownClasses, function(value) writeClassFields(chunk, value, expressions));
			if (expressions.length > 0) {
				chunk = startChunk(EXD);
				var owners:Array<TClass> = [];
				for (expression in expressions) if (owners.indexOf(expression.cls) == -1) owners.push(expression.cls);
				chunk.writeUleb128(owners.length);
				for (owner in owners) {
					writeClassRef(chunk, owner);
					var fields = [for (expression in expressions) if (expression.cls == owner) expression];
					chunk.writeUleb128(fields.length);
					for (expression in fields) {
						var kind = expression.cls.clConstructor == expression.field ? 2 : expression.cls.clInit == expression.field ? 3 : expression.cls.clStatics.get(expression.field.cfName) == expression.field ? 0 : 1;
						chunk.writeUleb128(writeFieldRef(expression.cls, expression.field, kind));
						chunk.writeUleb128(expression.bytes.length);
						chunk.writeBytes(expression.bytes);
					}
				}
			}
		}
		if (ownEnums.length > 0) {
			var chunk = startChunk(END); chunk.writeList(ownEnums, function(value) writeEnum(chunk, value));
			chunk = startChunk(EFD); chunk.writeList(ownEnums, function(value) writeEnumFields(chunk, value));
		}
		if (ownTypedefs.length > 0) {
			var chunk = startChunk(TDD); chunk.writeList(ownTypedefs, function(value) writeTypedef(chunk, value));
		}
		// References and anonymous fields are finalized only after every owned
		// declaration has been serialized because typedef bodies can discover both.
		writeFieldReferences();
		writeAnonymousPools();

		writeReferences();
		var mdf = startChunk(MDF);
		writePath(mdf, module.mPath);
		mdf.writeString(Std.string(module.mExtra.mFile));
		mdf.writeUleb128(anonymousTypes.length);
		mdf.writeUleb128(0); // monomorph pool (not ported yet)
		startChunk(EOT); startChunk(EOF); startChunk(EOM);
		writeStringPool();
		writeDocumentationPool();
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
				addClass(value, true); chunk.writeU8(0); writePath(chunk, value.clPath); writePosPair(chunk, value.clPos, value.clNamePos); writeTypeParamsForward(chunk, value.clParams);
				chunk.writeUleb128(value.clFlags); chunk.writeOption(value.clConstructor, function(field) writeClassFieldForward(chunk, field)); chunk.writeOption(value.clInit, function(field) writeClassFieldForward(chunk, field));
				chunk.writeUleb128(value.clOrderedFields.length); chunk.writeUleb128(value.clOrderedStatics.length);
				// hxbReader reads these tail-recursively, hence upstream writes reverse order.
				for (i in 0...value.clOrderedFields.length) writeClassFieldForward(chunk, value.clOrderedFields[value.clOrderedFields.length - 1 - i]);
				for (i in 0...value.clOrderedStatics.length) writeClassFieldForward(chunk, value.clOrderedStatics[value.clOrderedStatics.length - 1 - i]);
			case TEnumDecl(value):
				addEnum(value, true); chunk.writeU8(1); writePath(chunk, value.ePath); writePosPair(chunk, value.ePos, value.eNamePos); writeTypeParamsForward(chunk, value.eParams);
				var names = enumMapNames(value); chunk.writeUleb128(names.length);
				for (name in names) { var field = value.eConstrs.get(name); chunk.writeString(name); writePosPair(chunk, field.efPos, field.efNamePos); chunk.writeUleb128(field.efIndex); }
			case TTypeDecl(value): addTypedef(value, true); chunk.writeU8(2); writePath(chunk, value.tPath); writePosPair(chunk, value.tPos, value.tNamePos); writeTypeParamsForward(chunk, value.tParams);
			case TAbstractDecl(value): addAbstract(value, true); chunk.writeU8(3); writePath(chunk, value.aPath); writePosPair(chunk, value.aPos, value.aNamePos); writeTypeParamsForward(chunk, value.aParams);
		}
	}

	function writeClass(chunk:HxbChunk, value:TClass):Void {
		selectTypeParams(value.clParams);
		writeCommon(chunk, value.clPrivate, value.clDoc, value.clMeta, value.clParams, value.clUsing);
		writeClassKind(chunk, value.clKind);
		chunk.writeOption(value.clSuper, function(parent) { writeClassRef(chunk, parent.cls); writeTypes(chunk, parent.params); });
		chunk.writeList(value.clImplements, function(parent) { writeClassRef(chunk, parent.cls); writeTypes(chunk, parent.params); });
		chunk.writeOption(value.clDynamic, function(type) writeType(chunk, type));
		chunk.writeOption(value.clArrayAccess, function(type) writeType(chunk, type));
	}

	function writeClassFields(chunk:HxbChunk, value:TClass, expressions:Array<{var cls:TClass; var field:TClassField; var bytes:Bytes;}>):Void {
		selectTypeParams(value.clParams);
		chunk.writeOption(value.clConstructor, function(field) writeClassFieldData(chunk, value, field, expressions));
		chunk.writeOption(value.clInit, function(field) writeClassFieldData(chunk, value, field, expressions));
		chunk.writeList(value.clOrderedFields, function(field) writeClassFieldData(chunk, value, field, expressions));
		chunk.writeList(value.clOrderedStatics, function(field) writeClassFieldData(chunk, value, field, expressions));
	}

	function writeEnum(chunk:HxbChunk, value:TEnum):Void { selectTypeParams(value.eParams); writeCommon(chunk, value.ePrivate, value.eDoc, value.eMeta, value.eParams, value.eUsing); chunk.writeUleb128(value.eFlags); chunk.writeList(value.eNames, chunk.writeString); }
	function writeEnumFields(chunk:HxbChunk, value:TEnum):Void {
		var names = enumMapNames(value); chunk.writeUleb128(names.length);
		for (name in names) { var field = value.eConstrs.get(name); chunk.writeString(name); writeEmptyTypeParamsData(chunk); writeType(chunk, field.efType); writeDocumentation(chunk, field.efDoc); writeMetadata(chunk, field.efMeta); }
	}
	function enumMapNames(value:TEnum):Array<String> { var names = value.eNames.copy(); names.sort(function(a, b) return a < b ? 1 : a > b ? -1 : 0); return names; }
	function writeTypedef(chunk:HxbChunk, value:TDef):Void { selectTypeParams(value.tParams); writeCommon(chunk, value.tPrivate, value.tDoc, value.tMeta, value.tParams, value.tUsing); writeType(chunk, value.tType); }
	function writeAbstract(chunk:HxbChunk, value:TAbstract):Void {
		selectTypeParams(value.aParams); writeCommon(chunk, value.aPrivate, value.aDoc, value.aMeta, value.aParams, value.aUsing); chunk.writeOption(value.aImpl, function(cls) writeClassRef(chunk, cls));
		if (hasMetadataName(value.aMeta, "coreType")) chunk.writeU8(0) else { chunk.writeU8(1); writeType(chunk, value.aThis); }
		writeTypes(chunk, value.aFrom); writeTypes(chunk, value.aTo); chunk.writeBool(value.aExtern); chunk.writeBool(value.aEnum);
	}
	function writeAbstractFields(chunk:HxbChunk, value:TAbstract):Void {
		var impl = value.aImpl;
		if (impl == null) {
			if (value.aArray.length != 0 || value.aRead != null || value.aWrite != null || value.aCall != null || value.aConstructor != null || value.aOps.length != 0 || value.aUnops.length != 0 || value.aFromField.length != 0 || value.aToField.length != 0) throw "Abstract fields require an implementation class";
			chunk.writeUleb128(0); for (_ in 0...4) chunk.writeU8(0); chunk.writeUleb128(0); chunk.writeUleb128(0); chunk.writeUleb128(0); chunk.writeUleb128(0);
			return;
		}
		chunk.writeList(value.aArray, function(field) chunk.writeUleb128(writeFieldRef(impl, field, 0)));
		chunk.writeOption(value.aRead, function(field) chunk.writeUleb128(writeFieldRef(impl, field, 0)));
		chunk.writeOption(value.aWrite, function(field) chunk.writeUleb128(writeFieldRef(impl, field, 0)));
		chunk.writeOption(value.aCall, function(field) chunk.writeUleb128(writeFieldRef(impl, field, 0)));
		chunk.writeOption(value.aConstructor, function(field) chunk.writeUleb128(writeFieldRef(impl, field, 0)));
		chunk.writeList(value.aOps, function(item) { chunk.writeU8(binopIndex(item.op)); chunk.writeUleb128(writeFieldRef(impl, item.field, 0)); });
		chunk.writeList(value.aUnops, function(item) { chunk.writeU8(unopIndex(item.op, item.flag)); chunk.writeUleb128(writeFieldRef(impl, item.field, 0)); });
		chunk.writeList(value.aFromField, function(item) chunk.writeUleb128(writeFieldRef(impl, item.field, 0)));
		chunk.writeList(value.aToField, function(item) chunk.writeUleb128(writeFieldRef(impl, item.field, 0)));
	}

	function writeClassFieldForward(chunk:HxbChunk, field:TClassField):Void { chunk.writeString(field.cfName); writePosPair(chunk, field.cfPos, field.cfNamePos); writeMetadata(chunk, field.cfMeta); chunk.writeUleb128(field.cfOverloads.length); for (other in field.cfOverloads) writeClassFieldForward(chunk, other); }
	function writeClassFieldData(chunk:HxbChunk, owner:TClass, field:TClassField, expressions:Array<{var cls:TClass; var field:TClassField; var bytes:Bytes;}>):Void {
		var all = [field].concat(field.cfOverloads); chunk.writeUleb128(all.length);
		for (value in all) {
			fieldTypeParamIndices = new ObjectMap();
			for (index in 0...value.cfParams.length) fieldTypeParamIndices.set(value.cfParams[index], index);
			// Upstream stages field data before committing its type-parameter prefix.
			// Besides framing nested scopes, this fixes reference-pool insertion order.
			var data = new HxbChunk(EOM, strings);
			writeType(data, value.cfType); data.writeUleb128(value.cfFlags); writeDocumentation(data, value.cfDoc); writeFieldKind(data, value.cfKind);
			if (value.cfExpr == null || !canWriteExpression(value.cfExpr)) data.writeU8(0) else {
				data.writeU8(2);
				var coreAbstractImpl = switch owner.clKind { case KAbstractImpl(abs): hasMetadataName(abs.aMeta, "coreType"); case _: false; };
				var optimizePositions = switch owner.clKind { case KAbstractImpl(_): coreAbstractImpl; case _: true; };
				// Cross filtering keeps StringBuf's native-runtime inline bodies in their
				// original block form. Preserve that distinction until filters.ml is ported.
				var skipSingleBlocks = switch owner.clKind {
					case KAbstractImpl(_): coreAbstractImpl;
					case _: owner.clPath.pack.length == 0 && owner.clPath.name != "StringBuf";
				};
				var skipUnoptimizedParens = owner.clPath.name != "StringBuf";
				expressions.push({cls:owner, field:value, bytes:writeExpression(value.cfExpr, coreAbstractImpl ? null : value.cfExprUnoptimized, optimizePositions, skipSingleBlocks, skipUnoptimizedParens)});
			}
			writeFieldTypeParamsData(chunk, value.cfParams);
			chunk.writeBytes(data.getBytes());
		}
	}

	function writeCommon(chunk:HxbChunk, privateType:Bool, doc:Dynamic, meta:Dynamic, params:TypeParams, usingTypes:Array<{var cls:TClass; var pos:Pos;}>):Void { chunk.writeBool(privateType); writeDocumentation(chunk, doc); writeMetadata(chunk, meta); writeTypeParamsData(chunk, params); chunk.writeList(usingTypes, function(value) { writeClassRef(chunk, value.cls); writePos(chunk, value.pos); }); }
	function writeClassKind(chunk:HxbChunk, kind:TClassKind):Void switch kind { case KNormal: chunk.writeU8(0); case KGeneric: chunk.writeU8(3); case KGenericInstance(cls, params): chunk.writeU8(4); writeClassRef(chunk, cls); writeTypes(chunk, params); case KMacroType: chunk.writeU8(5); case KAbstractImpl(abs): chunk.writeU8(7); chunk.writeUleb128(addAbstract(abs, false)); case KModuleFields(_): chunk.writeU8(8); case _: throw "Class kind serialization is not ported"; }
	function writeFieldKind(chunk:HxbChunk, kind:FieldKind):Void switch kind {
		case Method(MethNormal): chunk.writeU8(0);
		case Method(MethInline): chunk.writeU8(1);
		case Method(MethDynamic): chunk.writeU8(2);
		case Method(MethMacro): chunk.writeU8(3);
		case Var(value):
			var kind = switch [value.vRead, value.vWrite] {
				case [AccNormal, AccNormal]: 10; case [AccNormal, AccNo]: 11; case [AccNormal, AccNever]: 12; case [AccNormal, AccCtor]: 13; case [AccNormal, AccCall]: 14;
				case [AccInline, AccNever]: 20;
				case [AccCall, AccNormal]: 30; case [AccCall, AccNo]: 31; case [AccCall, AccNever]: 32; case [AccCall, AccCtor]: 33; case [AccCall, AccCall]: 34;
				case _: throw "Unsupported property access serialization";
			};
			chunk.writeU8(kind);
	}

	function writeType(chunk:HxbChunk, type:T):Void switch type {
		case TInst(value, []) if (value.clPath.pack.length == 0 && value.clPath.name == "String"): chunk.writeU8(104);
		case TInst(value, []) if (switch value.clKind { case KTypeParameter(_): true; case _: false; }): switch value.clKind { case KTypeParameter(param): writeTypeParameterRef(chunk, param); case _: };
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
		case TAnon(anon):
			if (!anon.aFields.keys().hasNext()) chunk.writeU8(80) else {
				chunk.writeU8(81);
				var known = anonymousTypeIndices.exists(anon);
				var index = addAnonymousType(anon);
				var inlineMode = !known && anonymousNeedsLocalContext(anon);
				if (inlineMode) inlineAnonymousTypes.set(anon, true);
				chunk.writeU8(inlineMode ? 1 : 0);
				chunk.writeUleb128(index);
				if (inlineMode) writeAnonymousType(chunk, anon);
			}
	}
	function writeReferenceType(chunk:HxbChunk, base:Int, getIndex:Void->Int, params:TParams):Void { if (params.length > 2) { chunk.writeU8(base + 9); chunk.writeUleb128(getIndex()); writeTypes(chunk, params); } else { chunk.writeU8(base + params.length); chunk.writeUleb128(getIndex()); for (type in params) writeType(chunk, type); } }
	function writeTypeParameterRef(chunk:HxbChunk, param:TypedTypeParam):Void switch param.ttpHost {
		case TPHType: chunk.writeU8(1); chunk.writeUleb128(typeTypeParamIndices.get(param.ttpName));
		case TPHConstructor | TPHMethod | TPHEnumConstructor | TPHAnonField: chunk.writeU8(2); chunk.writeUleb128(fieldTypeParamIndices.get(param));
		case TPHLocal: throw "Local type parameter serialization is not ported";
		case TPHUnbound: throw "Unbound type parameter cannot be serialized";
	}
	function selectTypeParams(params:TypeParams):Void { typeTypeParamIndices = new Map(); for (index in 0...params.length) typeTypeParamIndices.set(params[index].ttpName, index); }
	function writeClassRef(chunk:HxbChunk, value:TClass):Void chunk.writeUleb128(addClass(value, false));
	function isVoid(type:T):Bool return switch type { case TAbstract(value, params): value.aPath.pack.length == 0 && value.aPath.name == "Void" && params.length == 0; case _: false; }

	function writeFieldRef(cls:TClass, field:TClassField, kind:Int):Int {
		var key = pathKey(cls.clPath) + ":" + kind + ":" + field.cfName;
		if (fieldReferenceIndices.exists(key)) return fieldReferenceIndices.get(key);
		var index = fieldReferences.length;
		fieldReferenceIndices.set(key, index);
		fieldReferences.push({cls:cls, field:field, kind:kind, depth:0});
		return index;
	}

	function writeExpression(root:TExpr, unoptimized:Null<TExpr>, optimizePositions:Bool, skipSingleBlocks:Bool, skipUnoptimizedParens:Bool):Bytes {
		var expression = new HxbChunk(EOM, strings);
		var typePool:Array<Bytes> = [];
		expressionVars = [];
		expressionVarIndices = new ObjectMap();
		expressionThisType = null;
		var pos = {file:root.epos.pfile, min:root.epos.pmin, max:root.epos.pmax};
		writePos(expression, root.epos);
		optimizedExpressionPositions = optimizePositions;
		skipOptimizedSingleBlocks = skipSingleBlocks;
		writingUnoptimizedExpression = false;
		skipUnoptimizedParentheses = skipUnoptimizedParens;
		writeTExpr(expression, root, root, typePool, pos);
		if (unoptimized == null || !canWriteExpression(unoptimized)) expression.writeU8(0) else { expression.writeU8(1); optimizedExpressionPositions = false; skipOptimizedSingleBlocks = false; writingUnoptimizedExpression = true; writeTExpr(expression, unoptimized, root, typePool, pos); }
		var context = new HxbChunk(EOM, strings);
		context.writeU8(1); // top-level expression scope
		context.writeUleb128(0); // local type parameters
		context.writeOption(expressionThisType, function(type) writeType(context, type));
		context.writeUleb128(typePool.length);
		for (index in 0...typePool.length) {
			context.writeBytes(typePool[index]);
		}
		context.writeUleb128(expressionVars.length);
		for (variable in expressionVars) writeVar(context, variable);
		context.writeBytes(expression.getBytes());
		return context.getBytes();
	}

	function declareVar(chunk:HxbChunk, variable:TVar):Void {
		var index = expressionVarIndices.get(variable);
		if (index == null) {
			index = expressionVars.length;
			expressionVars.push(variable);
			expressionVarIndices.set(variable, index);
		}
		chunk.writeUleb128(index);
		chunk.writeU8(0); // v_extra
		writeType(chunk, variable.vType);
	}

	function writeVar(chunk:HxbChunk, variable:TVar):Void {
		chunk.writeUleb128(variable.vId);
		chunk.writeString(variable.vName);
		writeVarKind(chunk, variable.vKind);
		chunk.writeUleb128(variable.vFlags);
		writeMetadata(chunk, variable.vMeta);
		writePos(chunk, variable.vPos);
	}

	function writeVarKind(chunk:HxbChunk, kind:TVarKind):Void switch kind {
		case VUser(TVOLocalVariable): chunk.writeU8(0);
		case VUser(TVOArgument): chunk.writeU8(1);
		case VUser(TVOForVariable): chunk.writeU8(2);
		case VUser(TVOPatternVariable): chunk.writeU8(3);
		case VUser(TVOCatchVariable): chunk.writeU8(4);
		case VUser(TVOLocalFunction): chunk.writeU8(5);
		case VGenerated: chunk.writeU8(6);
		case VInlined: chunk.writeU8(7);
		case VInlinedConstructorVariable(fields): chunk.writeU8(8); chunk.writeList(fields, chunk.writeString);
		case VExtractorVariable: chunk.writeU8(9);
		case VAbstractThis: chunk.writeU8(10);
	}

	function canWriteExpression(expr:TExpr):Bool return switch expr.eexpr {
		case TConst(_): true;
		case TLocal(_): true;
		case TArray(array, index): canWriteExpression(array) && canWriteExpression(index);
		case TVar(_, value): value == null || canWriteExpression(value);
		case TBlock(values): [for (value in values) if (!canWriteExpression(value)) value].length == 0;
		case TFunction(func): [for (arg in func.tfArgs) if (arg.defaultValue != null && !canWriteExpression(arg.defaultValue)) arg].length == 0 && canWriteExpression(func.tfExpr);
		case TReturn(value): value == null || canWriteExpression(value);
		case TIf(condition, thenExpr, elseExpr): canWriteExpression(condition) && canWriteExpression(thenExpr) && (elseExpr == null || canWriteExpression(elseExpr));
		case TWhile(condition, body, _): canWriteExpression(condition) && canWriteExpression(body);
		case TCall(callee, args): canWriteExpression(callee) && [for (value in args) if (!canWriteExpression(value)) value].length == 0;
		case TNew(_, _, args): [for (value in args) if (!canWriteExpression(value)) value].length == 0;
		case TIdent(_): true;
		case TParenthesis(value): canWriteExpression(value);
		case TMeta(_, value): canWriteExpression(value);
		case TObjectDecl(fields): [for (field in fields) if (!canWriteExpression(field.expr)) field].length == 0;
		case TArrayDecl(values): [for (value in values) if (!canWriteExpression(value)) value].length == 0;
		case TTypeExpr(_): true;
		case TField(object, access): canWriteExpression(object) && switch access { case FStatic(_) | FInstance(_, _, _) | FDynamic(_): true; case _: false; };
		case TBinop(_, left, right): canWriteExpression(left) && canWriteExpression(right);
		case TUnop(_, _, value): canWriteExpression(value);
		case _: false;
	};

	function writeTExpr(chunk:HxbChunk, expr:TExpr, root:TExpr, typePool:Array<Bytes>, pos:{var file:String; var min:Int; var max:Int;}):Void {
		if (writingUnoptimizedExpression && skipUnoptimizedParentheses) switch expr.eexpr { case TParenthesis(value): writeTExpr(chunk, value, root, typePool, pos); return; case _: }
		if (skipOptimizedSingleBlocks) switch expr.eexpr {
			case TBlock([value]) if (switch expr.etype { case TDynamic(_): false; case _: true; }): writeTExpr(chunk, value, root, typePool, pos); return;
			case _:
		}
		var writesType = switch expr.eexpr {
			case TConst(value):
				var writesConstantType = false;
				switch value {
					case TInt(value): chunk.writeU8(5); chunk.writeI32(value);
					case TFloat(value): chunk.writeU8(6); chunk.writeString(value);
					case TString(value): chunk.writeU8(7); chunk.writeString(value);
					case TBool(false): chunk.writeU8(3);
					case TBool(true): chunk.writeU8(4);
					case TNull: chunk.writeU8(0); writesConstantType = true;
					case TThis: expressionThisType = expr.etype; chunk.writeU8(1);
					case TSuper: chunk.writeU8(2); writesConstantType = true;
				};
				writesConstantType;
			case TLocal(variable): chunk.writeU8(20); chunk.writeUleb128(expressionVarIndices.get(variable)); true;
			case TVar(variable, value): if (value == null) { chunk.writeU8(21); declareVar(chunk, variable); } else { chunk.writeU8(22); declareVar(chunk, variable); writeTExpr(chunk, value, root, typePool, pos); } false;
			case TBlock(values):
				switch values.length {
					case 0: chunk.writeU8(30);
					case 1: chunk.writeU8(31); writeTExpr(chunk, values[0], root, typePool, pos);
					case 2 | 3 | 4 | 5: chunk.writeU8(30 + values.length); for (value in values) writeTExpr(chunk, value, root, typePool, pos);
					default: chunk.writeU8(36); chunk.writeU8(values.length); for (value in values) writeTExpr(chunk, value, root, typePool, pos);
				};
				true;
			case TFunction(func):
				chunk.writeU8(50); chunk.writeUleb128(func.tfArgs.length);
				for (arg in func.tfArgs) { declareVar(chunk, arg.variable); if (arg.defaultValue != null) { chunk.writeU8(1); writeTExpr(chunk, arg.defaultValue, root, typePool, pos); } else chunk.writeU8(0); }
				writeType(chunk, func.tfType); writeTExpr(chunk, func.tfExpr, root, typePool, pos);
				true;
			case TReturn(value):
				if (value == null) chunk.writeU8(90) else { chunk.writeU8(91); writeTExpr(chunk, value, root, typePool, pos); }
				true;
			case TIf(condition, thenExpr, elseExpr):
				if (elseExpr == null) { chunk.writeU8(80); writeTExpr(chunk, condition, root, typePool, pos); writeTExpr(chunk, thenExpr, root, typePool, pos); false; }
				else { chunk.writeU8(81); writeTExpr(chunk, condition, root, typePool, pos); writeTExpr(chunk, thenExpr, root, typePool, pos); writeTExpr(chunk, elseExpr, root, typePool, pos); true; }
			case TWhile(condition, body, flag): chunk.writeU8(flag == NormalWhile ? 84 : 85); writeTExpr(chunk, condition, root, typePool, pos); writeTExpr(chunk, body, root, typePool, pos); false;
			case TCall(callee, args):
				chunk.writeU8(70 + args.length); writeTExpr(chunk, callee, root, typePool, pos); for (arg in args) writeTExpr(chunk, arg, root, typePool, pos);
				true;
			case TIdent(name): chunk.writeU8(250); chunk.writeString(name); true;
			case TParenthesis(value): chunk.writeU8(61); writeTExpr(chunk, value, root, typePool, pos); false;
			case TArray(array, index): chunk.writeU8(60); writeTExpr(chunk, array, root, typePool, pos); writeTExpr(chunk, index, root, typePool, pos); true;
			case TArrayDecl(values): chunk.writeU8(62); chunk.writeList(values, function(value) writeTExpr(chunk, value, root, typePool, pos)); true;
			case TObjectDecl(fields):
				chunk.writeU8(63); chunk.writeList(fields, function(field) {
					chunk.writeString(field.key.name); writePos(chunk, field.key.pos);
					chunk.writeU8(switch field.key.quote { case NoQuotes: 0; case DoubleQuotes: 1; });
					writeTExpr(chunk, field.expr, root, typePool, pos);
				});
				true;
			case TMeta(meta, value): chunk.writeU8(65); writeMetadataEntry(chunk, meta); writeTExpr(chunk, value, root, typePool, pos); true;
			case TField(object, access):
				switch access {
					case FStatic(cls, field):
						switch object.eexpr {
							case TTypeExpr(TClassDecl(objectClass)) if (objectClass == cls):
								chunk.writeU8(110); writeRelativePos(chunk, object.epos, pos); writeClassRef(chunk, cls); chunk.writeUleb128(writeFieldRef(cls, field, 0));
							case _:
								chunk.writeU8(103); writeTExpr(chunk, object, root, typePool, pos); writeClassRef(chunk, cls); chunk.writeUleb128(writeFieldRef(cls, field, 0));
						}
					case FInstance(cls, params, field):
						if (expressionThisType != null && switch object.eexpr { case TConst(TThis): true; case _: false; }) {
							chunk.writeU8(111); writeRelativePos(chunk, object.epos, pos); writeClassRef(chunk, cls); writeTypes(chunk, params); chunk.writeUleb128(writeFieldRef(cls, field, 1));
						} else { chunk.writeU8(102); writeTExpr(chunk, object, root, typePool, pos); writeClassRef(chunk, cls); writeTypes(chunk, params); chunk.writeUleb128(writeFieldRef(cls, field, 1)); }
					case FDynamic(name): chunk.writeU8(108); writeTExpr(chunk, object, root, typePool, pos); chunk.writeString(name);
					case _: throw "Unsupported expression field access";
				};
				true;
			case TTypeExpr(TClassDecl(cls)): chunk.writeU8(120); writeClassRef(chunk, cls); false;
			case TTypeExpr(TEnumDecl(en)): chunk.writeU8(121); chunk.writeUleb128(addEnum(en, false)); false;
			case TTypeExpr(TTypeDecl(def)): chunk.writeU8(123); chunk.writeUleb128(addTypedef(def, false)); true;
			case TTypeExpr(TAbstractDecl(abs)): chunk.writeU8(122); chunk.writeUleb128(addAbstract(abs, false)); true;
			case TNew(cls, params, args): chunk.writeU8(126); writeClassRef(chunk, cls); writeTypes(chunk, params); chunk.writeList(args, function(arg) writeTExpr(chunk, arg, root, typePool, pos)); true;
			case TBinop(op, left, right): chunk.writeU8(160 + binopIndex(op)); writeTExpr(chunk, left, root, typePool, pos); writeTExpr(chunk, right, root, typePool, pos); true;
			case TUnop(op, flag, value): chunk.writeU8(140 + unopIndex(op, flag)); writeTExpr(chunk, value, root, typePool, pos); true;
			case _: throw "Expression serialization is not ported for " + Type.enumConstructor(expr.eexpr);
		};
		if (writesType) chunk.writeUleb128(addExprType(typePool, expr.etype));
		var outputPos = optimizedExpressionPositions ? switch expr.eexpr { case TBlock([value]): value.epos; case _: expr.epos; } : expr.epos;
		writeRelativePos(chunk, outputPos, pos);
	}

	function addExprType(pool:Array<Bytes>, type:T):Int {
		var chunk = new HxbChunk(EOM, strings); writeType(chunk, type); var bytes = chunk.getBytes();
		for (index in 0...pool.length) if (pool[index].length == bytes.length && pool[index].compare(bytes) == 0) return index;
		pool.push(bytes); return pool.length - 1;
	}

	function writeRelativePos(chunk:HxbChunk, value:Pos, current:{var file:String; var min:Int; var max:Int;}):Void {
		if (value.pfile != current.file) { chunk.writeU8(4); writePos(chunk, value); current.file = value.pfile; current.min = value.pmin; current.max = value.pmax; }
		else if (value.pmin != current.min && value.pmax != current.max) { chunk.writeU8(3); chunk.writeLeb128(value.pmin); chunk.writeLeb128(value.pmax); current.min = value.pmin; current.max = value.pmax; }
		else if (value.pmin != current.min) { chunk.writeU8(1); chunk.writeLeb128(value.pmin); current.min = value.pmin; }
		else if (value.pmax != current.max) { chunk.writeU8(2); chunk.writeLeb128(value.pmax); current.max = value.pmax; }
		else chunk.writeU8(0);
	}

	function binopIndex(op:Binop):Int return switch op { case OpAdd:0; case OpMult:1; case OpDiv:2; case OpSub:3; case OpAssign:4; case OpEq:5; case OpNotEq:6; case OpGt:7; case OpGte:8; case OpLt:9; case OpLte:10; case OpAnd:11; case OpOr:12; case OpXor:13; case OpBoolAnd:14; case OpBoolOr:15; case OpShl:16; case OpShr:17; case OpUShr:18; case OpMod:19; case OpInterval:20; case OpArrow:21; case OpIn:22; case OpNullCoal:23; case OpAssignOp(inner):30 + binopIndex(inner); };
	function unopIndex(op:Unop, flag:UnopFlag):Int return switch [op, flag] { case [Increment, Prefix]:0; case [Decrement, Prefix]:1; case [Not, Prefix]:2; case [Neg, Prefix]:3; case [NegBits, Prefix]:4; case [Spread, Prefix]:5; case [Increment, Postfix]:6; case [Decrement, Postfix]:7; case [Not, Postfix]:8; case [Neg, Postfix]:9; case [NegBits, Postfix]:10; case [Spread, Postfix]:11; };

	function addAnonymousType(value:TAnon):Int {
		if (anonymousTypeIndices.exists(value)) return anonymousTypeIndices.get(value);
		var index = anonymousTypes.length;
		anonymousTypeIndices.set(value, index);
		anonymousTypes.push(value);
		return index;
	}

	function addAnonymousField(value:TClassField):Int {
		if (anonymousFieldIndices.exists(value)) return anonymousFieldIndices.get(value);
		var index = anonymousFields.length;
		anonymousFieldIndices.set(value, index);
		anonymousFields.push(value);
		return index;
	}

	function writeAnonymousFieldRef(chunk:HxbChunk, value:TClassField):Void {
		var known = anonymousFieldIndices.exists(value);
		var index = addAnonymousField(value);
		// Upstream serializes a newly discovered field into a temporary chunk
		// immediately, even when its bytes are emitted later through OFD. Besides
		// handling nested references, this fixes string/document pool order.
		if (!known) anonymousFieldData[index] = writeAnonymousFieldData(value);
		var inlineMode = !known && typeNeedsLocalContext(value.cfType);
		if (inlineMode) inlineAnonymousFields.set(value, true);
		chunk.writeU8(inlineMode ? 1 : 0);
		chunk.writeUleb128(index);
		if (inlineMode) chunk.writeBytes(anonymousFieldData[index]);
	}

	function anonymousNeedsLocalContext(value:TAnon):Bool {
		for (field in value.aFields) if (typeNeedsLocalContext(field.cfType)) return true;
		return false;
	}

	function typeNeedsLocalContext(type:T):Bool return switch type {
		case TInst(cls, _) if (switch cls.clKind { case KTypeParameter(param): param.ttpHost == TPHType; case _: false; }): true;
		case TInst(_, params) | TEnum(_, params) | TType(_, params) | TAbstract(_, params): Lambda.exists(params, typeNeedsLocalContext);
		case TFun(signature): Lambda.exists(signature.args, function(arg) return typeNeedsLocalContext(arg.type)) || typeNeedsLocalContext(signature.ret);
		case TDynamic(inner): inner != null && typeNeedsLocalContext(inner);
		case TAnon(anon): anonymousNeedsLocalContext(anon);
		case TLazy(value): switch value { case LAvailable(inner) | LProcessing(inner): typeNeedsLocalContext(inner); case LWait(_): false; };
		case TMono(value): value.tmType != null && typeNeedsLocalContext(value.tmType);
	};

	function writeAnonymousType(chunk:HxbChunk, value:TAnon):Void {
		switch value.aStatus {
			case Closed: chunk.writeU8(0);
			case Const: chunk.writeU8(1);
			case Extend(types): chunk.writeU8(2); writeTypes(chunk, types);
			case _: throw "Unsupported anonymous type status";
		}
		var fields = [];
		for (name in value.aFields.keys()) fields.push(value.aFields.get(name));
		fields.sort(function(a, b) return a.cfName < b.cfName ? -1 : a.cfName > b.cfName ? 1 : 0);
		chunk.writeUleb128(fields.length);
		for (field in fields) writeAnonymousFieldRef(chunk, field);
	}

	function writeAnonymousFieldData(value:TClassField):Bytes {
		var chunk = new HxbChunk(EOM, strings);
		chunk.writeUleb128(1);
		writeEmptyTypeParamsData(chunk);
		writeType(chunk, value.cfType);
		chunk.writeUleb128(value.cfFlags);
		writeDocumentation(chunk, value.cfDoc);
		writeFieldKind(chunk, value.cfKind);
		chunk.writeU8(0);
		return chunk.getBytes();
	}

	function writeAnonymousPools():Void {
		// Materialize anonymous definitions first; this also discovers the field
		// reference pool in the same order as hxbWriter.ml.
		var definitions:Array<{var index:Int; var bytes:Bytes;}> = [];
		for (index in 0...anonymousTypes.length) {
			var anon = anonymousTypes[index];
			if (inlineAnonymousTypes.exists(anon)) continue;
			var chunk = new HxbChunk(EOM, strings);
			writeAnonymousType(chunk, anon);
			definitions.push({index:index, bytes:chunk.getBytes()});
		}
		if (anonymousFields.length > 0) {
			var chunk = startChunk(OFR);
			chunk.writeUleb128(anonymousFields.length);
			for (field in anonymousFields) writeClassFieldForward(chunk, field);
			var definitions = [for (index in 0...anonymousFields.length) if (!inlineAnonymousFields.exists(anonymousFields[index])) index];
			chunk = startChunk(OFD);
			chunk.writeUleb128(definitions.length);
			for (index in definitions) {
				chunk.writeUleb128(index);
				chunk.writeBytes(anonymousFieldData[index]);
			}
		}
		if (definitions.length > 0) {
			var chunk = startChunk(OBD);
			chunk.writeUleb128(definitions.length);
			for (definition in definitions) { chunk.writeUleb128(definition.index); chunk.writeBytes(definition.bytes); }
		}
	}

	function writeFieldReferences():Void {
		if (fieldReferences.length > 0) { var chunk = startChunk(CFR); chunk.writeUleb128(fieldReferences.length); for (reference in fieldReferences) { writeClassRef(chunk, reference.cls); chunk.writeU8(reference.kind); if (reference.kind == 0 || reference.kind == 1) chunk.writeString(reference.field.cfName); chunk.writeUleb128(reference.depth); } }
	}

	function writeReferences():Void {
		if (classOrder.length > 0) { var chunk = startChunk(CLR); chunk.writeUleb128(classOrder.length); for (value in classOrder) writeFullPath(chunk, value.clModule.mPath, value.clPath.name); }
		if (abstractOrder.length > 0) { var chunk = startChunk(ABR); chunk.writeUleb128(abstractOrder.length); for (value in abstractOrder) writeFullPath(chunk, value.aModule.mPath, value.aPath.name); }
		if (enumOrder.length > 0) { var chunk = startChunk(ENR); chunk.writeUleb128(enumOrder.length); for (value in enumOrder) writeFullPath(chunk, value.eModule.mPath, value.ePath.name); }
		if (typedefOrder.length > 0) { var chunk = startChunk(TDR); chunk.writeUleb128(typedefOrder.length); for (value in typedefOrder) writeFullPath(chunk, value.tModule.mPath, value.tPath.name); }
	}
	function writeStringPool():Void writePool(STR, strings);
	function writeDocumentationPool():Void {
		if (hasDocumentation) writePool(DOC, documentation);
	}
	function writePool(kind:ChunkKind, pool:StringPool):Void {
		var values = pool.finalize();
		var chunk = startChunk(kind);
		chunk.writeUleb128(values.length);
		values.iter(function(value) chunk.writeLengthPrefixedBytes(Bytes.ofString(value)));
	}

	function addClass(value:TClass, own:Bool):Int return addOrdered(classIndices, classOrder, pathKey(value.clPath), value, own ? ownClasses : null);
	function addEnum(value:TEnum, own:Bool):Int return addOrdered(enumIndices, enumOrder, pathKey(value.ePath), value, own ? ownEnums : null);
	function addTypedef(value:TDef, own:Bool):Int return addOrdered(typedefIndices, typedefOrder, pathKey(value.tPath), value, own ? ownTypedefs : null);
	function addAbstract(value:TAbstract, own:Bool):Int return addOrdered(abstractIndices, abstractOrder, pathKey(value.aPath), value, own ? ownAbstracts : null);
	function addOrdered<T>(indices:Map<String, Int>, order:Array<T>, key:String, value:T, own:Array<T>):Int {
		if (indices.exists(key)) return indices.get(key);
		var index = order.length;
		indices.set(key, index);
		order.push(value);
		if (own != null) own.push(value);
		return index;
	}
	static function pathKey(path:GlobalTypePath):String return path.pack.join(".") + ":" + path.name;
	static function writePath(chunk:HxbChunk, path:GlobalTypePath):Void { chunk.writeList(path.pack, chunk.writeString); chunk.writeString(path.name); }
	static function writeFullPath(chunk:HxbChunk, modulePath:GlobalTypePath, typeName:String):Void { chunk.writeList(modulePath.pack, chunk.writeString); chunk.writeString(modulePath.name); chunk.writeString(typeName); }
	static function writePos(chunk:HxbChunk, pos:Pos):Void { chunk.writeString(pos.pfile); chunk.writeLeb128(pos.pmin); chunk.writeLeb128(pos.pmax); }
	static function writePosPair(chunk:HxbChunk, first:Pos, second:Pos):Void { writePos(chunk, first); chunk.writeLeb128(second.pmin - first.pmin); chunk.writeLeb128(second.pmax - first.pmin); }
	function writeDocumentation(chunk:HxbChunk, doc:core.Ast.Documentation):Void {
		if (doc == null) {
			chunk.writeU8(0);
			return;
		}
		hasDocumentation = true;
		chunk.writeU8(1);
		chunk.writeOption(doc.docOwn, function(value) chunk.writeUleb128(documentation.getOrAdd(value)));
		chunk.writeList(doc.docInherited, function(value) chunk.writeUleb128(documentation.getOrAdd(value)));
	}
	static function writeMetadata(chunk:HxbChunk, meta:Dynamic):Void {
		var entries:Array<Dynamic> = meta == null ? [] : cast meta;
		chunk.writeUleb128(entries.length);
		for (entry in entries) {
			// write_metadata in hxbWriter.ml stores the original AST metadata,
			// including its source position.
			var exprs:Array<core.Ast.Expr> = cast entry.exprs;
			chunk.writeString(metadataName(entry.meta));
			writePos(chunk, entry.pos);
			chunk.writeList(exprs, function(expr) writeMetadataExpr(chunk, expr));
		}
	}
	static function writeMetadataExpr(chunk:HxbChunk, expr:core.Ast.Expr):Void {
		writePos(chunk, expr.pos);
		switch expr.expr {
			case EConst(Int(value, suffix)):
				chunk.writeU8(0); chunk.writeString(value); chunk.writeOption(suffix, chunk.writeString);
			case EConst(Float(value, suffix)):
				chunk.writeU8(1); chunk.writeString(value); chunk.writeOption(suffix, chunk.writeString);
			case EConst(String(value, kind)):
				chunk.writeU8(2); chunk.writeString(value); chunk.writeU8(switch kind { case SDoubleQuotes: 0; case SSingleQuotes: 1; });
			case EConst(Ident(value)):
				chunk.writeU8(3); chunk.writeString(value);
			case EField(object, field, kind):
				chunk.writeU8(7); writeMetadataExpr(chunk, object); chunk.writeString(field);
				chunk.writeU8(switch kind { case EFNormal: 0; case EFSafe: 1; });
			case EObjectDecl(fields):
				chunk.writeU8(9); chunk.writeList(fields, function(field) {
					chunk.writeString(field.key.name); writePos(chunk, field.key.pos);
					chunk.writeU8(switch field.key.quote { case NoQuotes: 0; case DoubleQuotes: 1; });
					writeMetadataExpr(chunk, field.expr);
				});
			case _:
				throw "Metadata expression serialization is not ported for " + Type.enumConstructor(expr.expr) + " at " + expr.pos.pfile + ":" + expr.pos.pmin;
		}
	}
	static function writeMetadataEntry(chunk:HxbChunk, entry:core.Ast.MetadataEntry):Void {
		chunk.writeString(metadataName(entry.meta)); writePos(chunk, entry.pos); chunk.writeList(entry.exprs, function(expr) writeMetadataExpr(chunk, expr));
	}
	static function metadataName(value:Dynamic):String { var name = Std.string(value); return StringTools.startsWith(name, ":") ? name : ":" + name; }
	static function hasMetadataName(metadata:Dynamic, name:String):Bool { var entries:Array<Dynamic> = metadata == null ? [] : cast metadata; for (entry in entries) if (metadataName(entry.meta) == ":" + name) return true; return false; }
	static function writeEmptyTypeParamsData(chunk:HxbChunk):Void { chunk.writeUleb128(0); chunk.writeU8(1); chunk.writeUleb128(0); }
	function writeFieldTypeParamsData(chunk:HxbChunk, params:TypeParams):Void {
		chunk.writeUleb128(params.length);
		chunk.writeU8(1); // top-level field scope
		writeTypeParamsForward(chunk, params);
		for (param in params) {
			writeMetadata(chunk, param.ttpClass.clMeta);
			writeTypes(chunk, param.ttpConstraints == null ? [] : param.ttpConstraints.force());
			chunk.writeOption(param.ttpDefault, function(type) writeType(chunk, type));
		}
	}
	function writeTypeParamsForward(chunk:HxbChunk, params:TypeParams):Void chunk.writeList(params, function(param) {
		writePath(chunk, param.ttpClass.clPath);
		writePos(chunk, param.ttpClass.clNamePos);
		chunk.writeU8(switch param.ttpHost { case TPHType:0; case TPHConstructor:1; case TPHMethod:2; case TPHEnumConstructor:3; case TPHAnonField:4; case TPHLocal:5; case TPHUnbound:6; });
	});
	function writeTypeParamsData(chunk:HxbChunk, params:TypeParams):Void for (param in params) {
		writeMetadata(chunk, param.ttpClass.clMeta);
		writeTypes(chunk, param.ttpConstraints == null ? [] : param.ttpConstraints.force());
		chunk.writeOption(param.ttpDefault, function(type) writeType(chunk, type));
	}
	function writeTypes(chunk:HxbChunk, types:TParams):Void chunk.writeList(types, function(type) writeType(chunk, type));
	static function chunkOrder(kind:ChunkKind):Int return switch kind { case STR: 0; case DOC: 1; case MDF: 2; case MTF: 3; case IMP: 4; case CLR: 5; case ENR: 6; case ABR: 7; case TDR: 8; case OFR: 9; case OFD: 10; case OBD: 11; case CLD: 12; case END: 13; case ABD: 14; case TDD: 15; case EOT: 16; case EFR: 17; case CFR: 18; case CFD: 19; case EFD: 20; case AFD: 21; case EOF: 22; case EXD: 23; case EOM: 24; }
}
