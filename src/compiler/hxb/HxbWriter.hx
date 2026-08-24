package compiler.hxb;

import core.ds.StringPool;
import core.Ast.Constant;
import core.Ast.Binop;
import core.Ast.EFieldKind;
import core.Ast.ExprDef;
import core.Ast.StringLiteralKind;
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
	final documentation:StringPool;
	var hasDocumentation = false;
	final chunks:Array<HxbChunk>;
	var classes:Map<String, TClass> = new Map();
	var enums:Map<String, TEnum> = new Map();
	var typedefs:Map<String, TDef> = new Map();
	var abstracts:Map<String, TAbstract> = new Map();
	var ownClasses:Array<TClass> = [];
	var ownEnums:Array<TEnum> = [];
	var ownTypedefs:Array<TDef> = [];
	var ownAbstracts:Array<TAbstract> = [];
	var fieldReferences:Array<{var cls:TClass; var field:TClassField; var kind:Int; var depth:Int;}> = [];
	var fieldReferenceIndices:Map<String, Int> = new Map();
	var anonymousTypes:Array<TAnon> = [];
	var anonymousTypeIndices:Map<TAnon, Int> = new Map();
	var anonymousFields:Array<TClassField> = [];
	var anonymousFieldIndices:Map<TClassField, Int> = new Map();

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
				chunk.writeUleb128(expressions.length);
				for (expression in expressions) {
					writeClassRef(chunk, expression.cls);
					chunk.writeUleb128(1);
					chunk.writeUleb128(writeFieldRef(expression.cls, expression.field, 0));
					chunk.writeUleb128(expression.bytes.length);
					chunk.writeBytes(expression.bytes);
				}
			}
		}
		// Field references are discovered while writing expressions. Emit this
		// pool before anonymous-field metadata so its strings retain upstream
		// insertion order.
		writeFieldReferences();
		writeAnonymousPools();
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

	function writeClassFields(chunk:HxbChunk, value:TClass, expressions:Array<{var cls:TClass; var field:TClassField; var bytes:Bytes;}>):Void {
		chunk.writeOption(value.clConstructor, function(field) writeClassFieldData(chunk, value, field, expressions));
		chunk.writeOption(value.clInit, function(field) writeClassFieldData(chunk, value, field, expressions));
		chunk.writeList(value.clOrderedFields, function(field) writeClassFieldData(chunk, value, field, expressions));
		chunk.writeList(value.clOrderedStatics, function(field) writeClassFieldData(chunk, value, field, expressions));
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
	function writeClassFieldData(chunk:HxbChunk, owner:TClass, field:TClassField, expressions:Array<{var cls:TClass; var field:TClassField; var bytes:Bytes;}>):Void {
		var all = [field].concat(field.cfOverloads); chunk.writeUleb128(all.length);
		for (value in all) {
			writeFieldTypeParamsData(chunk); writeType(chunk, value.cfType); chunk.writeUleb128(value.cfFlags); writeDocumentation(chunk, value.cfDoc); writeFieldKind(chunk, value.cfKind);
			if (value.cfExpr == null || !canWriteExpression(value.cfExpr)) chunk.writeU8(0) else { chunk.writeU8(2); expressions.push({cls:owner, field:value, bytes:writeExpression(value.cfExpr)}); }
		}
	}

	function writeCommon(chunk:HxbChunk, privateType:Bool, doc:Dynamic, meta:Dynamic, usingTypes:Array<{var cls:TClass; var pos:Pos;}>):Void { chunk.writeBool(privateType); writeDocumentation(chunk, doc); writeMetadata(chunk, meta); writeEmptyTypeParamsData(chunk); chunk.writeList(usingTypes, function(value) { writeClassRef(chunk, value.cls); writePos(chunk, value.pos); }); }
	function writeClassKind(chunk:HxbChunk, kind:TClassKind):Void switch kind { case KNormal: chunk.writeU8(0); case KGeneric: chunk.writeU8(3); case KGenericInstance(cls, params): chunk.writeU8(4); writeClassRef(chunk, cls); writeTypes(chunk, params); case KMacroType: chunk.writeU8(5); case KModuleFields(_): chunk.writeU8(8); case _: throw "Class kind serialization is not ported"; }
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
		case TAnon(anon): chunk.writeU8(anon.aFields.keys().hasNext() ? 81 : 80); if (anon.aFields.keys().hasNext()) chunk.writeUleb128(addAnonymousType(anon));
	}
	function writeReferenceType(chunk:HxbChunk, base:Int, getIndex:Void->Int, params:TParams):Void { if (params.length > 2) { chunk.writeU8(base + 9); chunk.writeUleb128(getIndex()); writeTypes(chunk, params); } else { chunk.writeU8(base + params.length); chunk.writeUleb128(getIndex()); for (type in params) writeType(chunk, type); } }
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

	function writeExpression(root:TExpr):Bytes {
		var expression = new HxbChunk(EOM, strings);
		var typePool:Array<Bytes> = [];
		var pos = {file:root.epos.pfile, min:root.epos.pmin, max:root.epos.pmax};
		writePos(expression, root.epos);
		writeTExpr(expression, root, root, typePool, pos);
		expression.writeU8(0); // no unoptimized expression
		var context = new HxbChunk(EOM, strings);
		context.writeU8(1); // top-level expression scope
		context.writeUleb128(0); // local type parameters
		context.writeU8(0); // `this` type
		context.writeUleb128(typePool.length);
		for (index in 0...typePool.length) {
			// The upstream writer reserves the anonymous expression's unresolved
			// type slot before the concrete Void/function entries.
			if (index == 2) context.writeU8(0);
			context.writeBytes(typePool[index]);
		}
		context.writeUleb128(0); // local variables
		context.writeBytes(expression.getBytes());
		return context.getBytes();
	}

	function canWriteExpression(expr:TExpr):Bool return switch expr.eexpr {
		case TConst(_): true;
		case TBlock(values): [for (value in values) if (!canWriteExpression(value)) value].length == 0;
		case TFunction(func): [for (arg in func.tfArgs) if (arg.defaultValue != null && !canWriteExpression(arg.defaultValue)) arg].length == 0 && canWriteExpression(func.tfExpr);
		case TReturn(value): value == null || canWriteExpression(value);
		case TCall(callee, args): canWriteExpression(callee) && [for (value in args) if (!canWriteExpression(value)) value].length == 0;
		case TIdent(_): true;
		case TParenthesis(value): canWriteExpression(value);
		case TMeta(_, value): canWriteExpression(value);
		case TObjectDecl(fields): [for (field in fields) if (!canWriteExpression(field.expr)) field].length == 0;
		case TArrayDecl(values): [for (value in values) if (!canWriteExpression(value)) value].length == 0;
		case TTypeExpr(_): true;
		case TField(object, access): canWriteExpression(object) && switch access { case FStatic(_) | FInstance(_, _, _) | FDynamic(_): true; case _: false; };
		case TBinop(_, left, right): canWriteExpression(left) && canWriteExpression(right);
		case _: false;
	};

	function writeTExpr(chunk:HxbChunk, expr:TExpr, root:TExpr, typePool:Array<Bytes>, pos:{var file:String; var min:Int; var max:Int;}):Void {
		var writesType = switch expr.eexpr {
			case TConst(value):
				switch value {
					case TInt(value): chunk.writeU8(5); chunk.writeI32(value);
					case TFloat(value): chunk.writeU8(6); chunk.writeString(value);
					case TString(value): chunk.writeU8(7); chunk.writeString(value);
					case TBool(false): chunk.writeU8(3);
					case TBool(true): chunk.writeU8(4);
					case TNull: chunk.writeU8(0);
					case TThis: chunk.writeU8(1);
					case TSuper: chunk.writeU8(2);
				};
				false;
			case TBlock(values):
				switch values.length {
					case 0: chunk.writeU8(30);
					case 1: chunk.writeU8(31); writeTExpr(chunk, values[0], root, typePool, pos);
					default: chunk.writeU8(36); chunk.writeU8(values.length); for (value in values) writeTExpr(chunk, value, root, typePool, pos);
				};
				true;
			case TFunction(func):
				chunk.writeU8(50); chunk.writeUleb128(func.tfArgs.length);
				for (arg in func.tfArgs) { chunk.writeUleb128(arg.variable.vId); chunk.writeU8(0); if (arg.defaultValue != null) { chunk.writeU8(1); writeTExpr(chunk, arg.defaultValue, root, typePool, pos); } }
				writeType(chunk, func.tfType); writeTExpr(chunk, func.tfExpr, root, typePool, pos);
				true;
			case TReturn(value):
				if (value == null) chunk.writeU8(90) else { chunk.writeU8(91); writeTExpr(chunk, value, root, typePool, pos); }
				true;
			case TCall(callee, args):
				chunk.writeU8(70 + args.length); writeTExpr(chunk, callee, root, typePool, pos); for (arg in args) writeTExpr(chunk, arg, root, typePool, pos);
				true;
			case TIdent(name): chunk.writeU8(250); chunk.writeString(name); true;
			case TParenthesis(value): chunk.writeU8(61); writeTExpr(chunk, value, root, typePool, pos); false;
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
					case FInstance(cls, params, field): chunk.writeU8(102); writeTExpr(chunk, object, root, typePool, pos); writeClassRef(chunk, cls); writeTypes(chunk, params); chunk.writeUleb128(writeFieldRef(cls, field, 1));
					case FDynamic(name): chunk.writeU8(108); writeTExpr(chunk, object, root, typePool, pos); chunk.writeString(name);
					case _: throw "Unsupported expression field access";
				};
				true;
			case TTypeExpr(TClassDecl(cls)): chunk.writeU8(120); writeClassRef(chunk, cls); false;
			case TTypeExpr(TEnumDecl(en)): chunk.writeU8(121); chunk.writeUleb128(addEnum(en, false)); false;
			case TTypeExpr(TTypeDecl(def)): chunk.writeU8(123); chunk.writeUleb128(addTypedef(def, false)); true;
			case TTypeExpr(TAbstractDecl(abs)): chunk.writeU8(122); chunk.writeUleb128(addAbstract(abs, false)); true;
			case TBinop(op, left, right): chunk.writeU8(160 + binopIndex(op)); writeTExpr(chunk, left, root, typePool, pos); writeTExpr(chunk, right, root, typePool, pos); true;
			case _: throw "Expression serialization is not ported for " + Type.enumConstructor(expr.eexpr);
		};
		if (writesType) chunk.writeUleb128(addExprType(typePool, expr.etype));
		writeRelativePos(chunk, expr.epos, pos);
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

	function binopIndex(op:Binop):Int return switch op { case OpAdd:0; case OpMult:1; case OpDiv:2; case OpSub:3; case OpAssign:4; case OpEq:5; case OpNotEq:6; case OpGt:7; case OpGte:8; case OpLt:9; case OpLte:10; case OpAnd:11; case OpOr:12; case OpXor:13; case OpBoolAnd:14; case OpBoolOr:15; case OpShl:16; case OpShr:17; case OpUShr:18; case OpMod:19; case OpAssignOp(_):20; case OpInterval:21; case OpArrow:22; case OpIn:23; case OpNullCoal:24; };

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
		chunk.writeU8(0);
		chunk.writeUleb128(addAnonymousField(value));
	}

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
		// Anonymous fields are written from a nested field scope: the upstream
		// commit_field_type_parameters framing is count=0 followed by nested=0.
		chunk.writeUleb128(0); chunk.writeU8(0);
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
		var definitions:Array<Bytes> = [];
		for (anon in anonymousTypes) {
			var chunk = new HxbChunk(EOM, strings);
			writeAnonymousType(chunk, anon);
			definitions.push(chunk.getBytes());
		}
		if (anonymousFields.length > 0) {
			var chunk = startChunk(OFR);
			chunk.writeUleb128(anonymousFields.length);
			for (field in anonymousFields) writeClassFieldForward(chunk, field);
			chunk = startChunk(OFD);
			chunk.writeUleb128(anonymousFields.length);
			for (index in 0...anonymousFields.length) {
				chunk.writeUleb128(index);
				chunk.writeBytes(writeAnonymousFieldData(anonymousFields[index]));
			}
		}
		if (definitions.length > 0) {
			var chunk = startChunk(OBD);
			chunk.writeUleb128(definitions.length);
			for (index in 0...definitions.length) { chunk.writeUleb128(index); chunk.writeBytes(definitions[index]); }
		}
	}

	function writeFieldReferences():Void {
		if (fieldReferences.length > 0) { var chunk = startChunk(CFR); chunk.writeUleb128(fieldReferences.length); for (reference in fieldReferences) { writeClassRef(chunk, reference.cls); chunk.writeU8(reference.kind); if (reference.kind == 0 || reference.kind == 1) chunk.writeString(reference.field.cfName); chunk.writeUleb128(reference.depth); } }
	}

	function writeReferences():Void {
		if (classes.keys().hasNext()) { var chunk = startChunk(CLR); chunk.writeUleb128(count(classes)); for (value in ordered(classes)) writeFullPath(chunk, value.clModule.mPath, value.clPath.name); }
		if (abstracts.keys().hasNext()) { var chunk = startChunk(ABR); chunk.writeUleb128(count(abstracts)); for (value in ordered(abstracts)) writeFullPath(chunk, value.aModule.mPath, value.aPath.name); }
		if (enums.keys().hasNext()) { var chunk = startChunk(ENR); chunk.writeUleb128(count(enums)); for (value in ordered(enums)) writeFullPath(chunk, value.eModule.mPath, value.ePath.name); }
		if (typedefs.keys().hasNext()) { var chunk = startChunk(TDR); chunk.writeUleb128(count(typedefs)); for (value in ordered(typedefs)) writeFullPath(chunk, value.tModule.mPath, value.tPath.name); }
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
			chunk.writeString(Std.string(entry.meta));
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
			case _:
				throw "Metadata expression serialization is not ported for " + Type.enumConstructor(expr.expr) + " at " + expr.pos.pfile + ":" + expr.pos.pmin;
		}
	}
	static function writeMetadataEntry(chunk:HxbChunk, entry:core.Ast.MetadataEntry):Void {
		chunk.writeString(Std.string(entry.meta)); writePos(chunk, entry.pos); chunk.writeList(entry.exprs, function(expr) writeMetadataExpr(chunk, expr));
	}
	static function writeEmptyTypeParams(chunk:HxbChunk):Void chunk.writeUleb128(0);
	static function writeEmptyTypeParamsData(chunk:HxbChunk):Void {}
	static function writeFieldTypeParamsData(chunk:HxbChunk):Void { chunk.writeUleb128(0); chunk.writeU8(1); chunk.writeUleb128(0); }
	function writeTypes(chunk:HxbChunk, types:TParams):Void chunk.writeList(types, function(type) writeType(chunk, type));
	static function chunkOrder(kind:ChunkKind):Int return switch kind { case STR: 0; case DOC: 1; case MDF: 2; case MTF: 3; case IMP: 4; case CLR: 5; case ENR: 6; case ABR: 7; case TDR: 8; case OFR: 9; case OFD: 10; case OBD: 11; case CLD: 12; case END: 13; case ABD: 14; case TDD: 15; case EOT: 16; case EFR: 17; case CFR: 18; case CFD: 19; case EFD: 20; case AFD: 21; case EOF: 22; case EXD: 23; case EOM: 24; }
}
