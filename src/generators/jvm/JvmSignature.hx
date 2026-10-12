/*
	The Haxe Compiler
	Copyright (C) 2005-2019  Haxe Foundation

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

package generators.jvm;

import generators.jvm.JvmGlobals;
import core.ds.OcamlHash.OcamlValue;

// port: `jpath = (string list) * string`, the same shape as Globals.path.
typedef JPath = core.Globals.GlobalTypePath;

enum JWildcard {
	WExtends; /* + */
	WSuper; /* -  */
	WNone;
}

// port: the constructors of jtype_argument and jsignature carry a J prefix: TType, TInt,
// TArray, ... would clash with the typed AST's constructors in the generator.
enum JTypeArgument {
	JTType(w:JWildcard, s:JSignature);
	JTAny; /* * */
}

enum JSignature {
	JByte; /* B */
	JChar; /* C */
	JDouble; /* D */
	JFloat; /* F */
	JInt; /* I */
	JLong; /* J */
	JShort; /* S */
	JBool; /* Z */
	JObject(path:JPath, params:Array<JTypeArgument>); /* L Classname */
	JObjectInner(pack:Array<String>, inners:Array<{name:String, params:Array<JTypeArgument>}>); /* L Classname ClassTypeSignatureSuffix */
	JArray(jsig:JSignature, size:Null<Int>); /* [ */
	JMethod(args:Array<JSignature>, ret:Null<JSignature>); /* ( */
	JTypeParameter(name:String); /* T */
	JUninitialized(i:Null<Int>);
}

/* ( jsignature list ) ReturnDescriptor (| V | jsignature) */
class JvmSignature {
	// port: OCaml's structural equality (`=`) on paths and signatures.
	public static function pathEq(p1:JPath, p2:JPath):Bool {
		if (p1.name != p2.name || p1.pack.length != p2.pack.length) return false;
		for (i in 0...p1.pack.length) if (p1.pack[i] != p2.pack[i]) return false;
		return true;
	}

	public static function argEq(a1:JTypeArgument, a2:JTypeArgument):Bool return switch [a1, a2] {
		case [JTAny, JTAny]: true;
		case [JTType(w1, s1), JTType(w2, s2)]: w1 == w2 && jsigEq(s1, s2);
		case _: false;
	}

	public static function argsEq(l1:Array<JTypeArgument>, l2:Array<JTypeArgument>):Bool {
		if (l1.length != l2.length) return false;
		for (i in 0...l1.length) if (!argEq(l1[i], l2[i])) return false;
		return true;
	}

	public static function jsigsEq(l1:Array<JSignature>, l2:Array<JSignature>):Bool {
		if (l1.length != l2.length) return false;
		for (i in 0...l1.length) if (!jsigEq(l1[i], l2[i])) return false;
		return true;
	}

	public static function jsigOptEq(s1:Null<JSignature>, s2:Null<JSignature>):Bool {
		return if (s1 == null) s2 == null else if (s2 == null) false else jsigEq(s1, s2);
	}

	public static function jsigEq(s1:JSignature, s2:JSignature):Bool return switch [s1, s2] {
		case [JByte, JByte] | [JChar, JChar] | [JDouble, JDouble] | [JFloat, JFloat] | [JInt, JInt] | [JLong, JLong] | [JShort, JShort] | [JBool, JBool]:
			true;
		case [JObject(p1, a1), JObject(p2, a2)]:
			pathEq(p1, p2) && argsEq(a1, a2);
		case [JObjectInner(p1, i1), JObjectInner(p2, i2)]:
			if (p1.length != p2.length || i1.length != i2.length) false else {
				var r = true;
				for (i in 0...p1.length) if (p1[i] != p2[i]) r = false;
				for (i in 0...i1.length) if (i1[i].name != i2[i].name || !argsEq(i1[i].params, i2[i].params)) r = false;
				r;
			}
		case [JArray(j1, n1), JArray(j2, n2)]:
			jsigEq(j1, j2) && n1 == n2;
		case [JMethod(a1, r1), JMethod(a2, r2)]:
			jsigsEq(a1, a2) && jsigOptEq(r1, r2);
		case [JTypeParameter(n1), JTypeParameter(n2)]:
			n1 == n2;
		case [JUninitialized(i1), JUninitialized(i2)]:
			i1 == i2;
		case _:
			false;
	}

	// port: the OCaml runtime representation of a jsignature, for the polymorphic Hashtbl.hash.
	public static function ocamlValueOfPath(p:JPath):core.ds.OcamlHash.OcamlValue return core.ds.OcamlHash.ofPath(p.pack, p.name);

	public static function ocamlValueOfArg(a:JTypeArgument):core.ds.OcamlHash.OcamlValue return switch a {
		case JTType(w, s): OBlock(0, [OInt(w.getIndex()), ocamlValueOfJsig(s)]);
		case JTAny: OInt(0);
	}

	static function ocamlValueOfOption<A>(o:Null<A>, f:A->core.ds.OcamlHash.OcamlValue):core.ds.OcamlHash.OcamlValue {
		return o == null ? OInt(0) : OBlock(0, [f(o)]);
	}

	public static function ocamlValueOfJsig(s:JSignature):core.ds.OcamlHash.OcamlValue {
		var ofList = core.ds.OcamlHash.ofList;
		return switch s {
			case JByte: OInt(0);
			case JChar: OInt(1);
			case JDouble: OInt(2);
			case JFloat: OInt(3);
			case JInt: OInt(4);
			case JLong: OInt(5);
			case JShort: OInt(6);
			case JBool: OInt(7);
			case JObject(path, params): OBlock(0, [ocamlValueOfPath(path), ofList(params.map(ocamlValueOfArg))]);
			case JObjectInner(pack, inners):
				OBlock(1, [
					ofList([for (p in pack) OString(p)]),
					ofList([for (i in inners) OBlock(0, [OString(i.name), ofList(i.params.map(ocamlValueOfArg))])])
				]);
			case JArray(jsig, size): OBlock(2, [ocamlValueOfJsig(jsig), ocamlValueOfOption(size, function(i) return OInt(i))]);
			case JMethod(args, ret): OBlock(3, [OBlock(0, [ofList(args.map(ocamlValueOfJsig)), ocamlValueOfOption(ret, ocamlValueOfJsig)])]);
			case JTypeParameter(name): OBlock(4, [OString(name)]);
			case JUninitialized(i): OBlock(5, [ocamlValueOfOption(i, function(i) return OInt(i))]);
		}
	}

	// port: a string determining a jsignature up to structural equality, for lookup tables.
	public static function jsigKey(s:JSignature):String return sSignatureKind(s);

	public static function hasTypeParameter(s:JSignature):Bool return switch s {
		case JTypeParameter(_): true;
		case JArray(jsig, _): hasTypeParameter(jsig);
		case JObject(_, jsigs): Lambda.exists(jsigs, function(a) return switch a {
				case JTType(_, jsig): hasTypeParameter(jsig);
				case _: false;
			});
		case _: false;
	}

	public static function equalsAtRuntime(jsig1:JSignature, jsig2:JSignature):Bool return switch [jsig1, jsig2] {
		case [JByte, JByte] | [JChar, JChar] | [JDouble, JDouble] | [JFloat, JFloat] | [JInt, JInt] | [JLong, JLong] | [JShort, JShort] | [JBool, JBool] | [JObjectInner(_), JObjectInner(_)] | [JArray(_), JArray(_)] | [JMethod(_), JMethod(_)] | [JTypeParameter(_), JTypeParameter(_)] | [JUninitialized(_), JUninitialized(_)]:
			true;
		case [JObject(path1, _), JObject(path2, _)]:
			pathEq(path1, path2);
		case [JObject(path, _), JTypeParameter(_)] | [JTypeParameter(_), JObject(path, _)]:
			pathEq(path, NativeSignatures.objectPath);
		case _: false;
	}

	public static function sWildcard(w:JWildcard):String return switch w {
		case WExtends: "WExtends";
		case WSuper: "WSuper";
		case WNone: "WNone";
	}

	static function sJPath(p:JPath):String return p.pack.length == 0 ? p.name : p.pack.join(".") + "." + p.name;

	public static function sSignatureKind(s:JSignature):String return switch s {
		case JByte: "TByte";
		case JChar: "TChar";
		case JDouble: "TDouble";
		case JFloat: "TFloat";
		case JInt: "TInt";
		case JLong: "TLong";
		case JShort: "TShort";
		case JBool: "TBool";
		case JObject(path, params): 'TObject(${sJPath(path)},[${params.map(sSignatureParamKind).join(",")}])';
		// port: upstream prints just "TObjectInner"; its contents are added so jsigKey stays injective.
		case JObjectInner(pack, inners):
			'TObjectInner(${pack.join("/")},[${[for (i in inners) i.name + "<" + i.params.map(sSignatureParamKind).join(",") + ">"].join(",")}])';
		case JArray(jsig, io): 'TArray(${sSignatureKind(jsig)},${io == null ? "None" : Std.string(io)})';
		case JMethod(jsigs, jsig): 'TMethod([${jsigs.map(sSignatureKind).join(",")}],${jsig == null ? "None" : sSignatureKind(jsig)})';
		case JTypeParameter(name): 'TTypeParameter($name)';
		case JUninitialized(io): 'TUninitilaized(${io == null ? "None" : Std.string(io)})';
	}

	public static function sSignatureParamKind(a:JTypeArgument):String return switch a {
		case JTAny: "TAny";
		case JTType(wc, jsig): 'TType(${sWildcard(wc)},${sSignatureKind(jsig)})';
	}

	public static function encodePath(p:JPath):String return p.pack.concat([p.name]).join("/");

	public static function writeParam(full:Bool, ch:OutputBytes, param:JTypeArgument):Void {
		switch param {
			case JTAny:
				JvmGlobals.writeByte(ch, "*".code);
			case JTType(w, s):
				switch w {
					case WExtends: JvmGlobals.writeByte(ch, "+".code);
					case WSuper: JvmGlobals.writeByte(ch, "-".code);
					case WNone:
				}
				writeSignature(full, ch, NativeSignatures.getBoxedType(s));
		}
	}

	public static function writeSignature(full:Bool, ch:OutputBytes, jsig:JSignature):Void {
		switch jsig {
			case JByte:
				JvmGlobals.writeByte(ch, "B".code);
			case JChar:
				JvmGlobals.writeByte(ch, "C".code);
			case JDouble:
				JvmGlobals.writeByte(ch, "D".code);
			case JFloat:
				JvmGlobals.writeByte(ch, "F".code);
			case JInt:
				JvmGlobals.writeByte(ch, "I".code);
			case JLong:
				JvmGlobals.writeByte(ch, "J".code);
			case JShort:
				JvmGlobals.writeByte(ch, "S".code);
			case JBool:
				JvmGlobals.writeByte(ch, "Z".code);
			case JObject(path, params):
				JvmGlobals.writeByte(ch, "L".code);
				JvmGlobals.writeString(ch, encodePath(path));
				if (params.length > 0 && full) {
					JvmGlobals.writeByte(ch, "<".code);
					for (p in params) writeParam(full, ch, p);
					JvmGlobals.writeByte(ch, ">".code);
				}
				JvmGlobals.writeByte(ch, ";".code);
			case JObjectInner(pack, inners):
				JvmGlobals.writeByte(ch, "L".code);
				for (p in pack) {
					JvmGlobals.writeString(ch, p);
					JvmGlobals.writeByte(ch, "/".code);
				}
				var first = true;
				for (inner in inners) {
					if (first) first = false else JvmGlobals.writeByte(ch, ".".code);
					JvmGlobals.writeString(ch, inner.name);
					if (inner.params.length > 0) {
						JvmGlobals.writeByte(ch, "<".code);
						for (p in inner.params) writeParam(full, ch, p);
						JvmGlobals.writeByte(ch, ">".code);
					}
				}
				JvmGlobals.writeByte(ch, ";".code);
			case JArray(s, size):
				JvmGlobals.writeByte(ch, "[".code);
				if (size != null) JvmGlobals.writeString(ch, Std.string(size));
				writeSignature(full, ch, s);
			case JMethod(_):
				writeSignature(full, ch, NativeSignatures.haxeFunctionSig);
			case JTypeParameter(name):
				if (full) {
					JvmGlobals.writeByte(ch, "T".code);
					JvmGlobals.writeString(ch, name);
					JvmGlobals.writeByte(ch, ";".code);
				} else
					JvmGlobals.writeString(ch, "Ljava/lang/Object;");
			case JUninitialized(io):
				JvmGlobals.writeString(ch, "uninitialized");
				if (io == null) JvmGlobals.writeString(ch, " this") else JvmGlobals.writeString(ch, '($io)');
		}
	}

	public static function generateSignature(full:Bool, jsig:JSignature):String {
		var ch = new OutputBytes();
		writeSignature(full, ch, jsig);
		return ch.closeOut().toString();
	}

	public static function generateMethodSignature(full:Bool, jsig:JSignature):String {
		var ch = new OutputBytes();
		switch jsig {
			case JMethod(args, ret):
				JvmGlobals.writeByte(ch, "(".code);
				for (a in args) writeSignature(full, ch, a);
				JvmGlobals.writeByte(ch, ")".code);
				if (ret == null) JvmGlobals.writeByte(ch, "V".code) else writeSignature(full, ch, ret);
			case _:
				writeSignature(full, ch, jsig);
		}
		return ch.closeOut().toString();
	}

	public static function signatureSize(s:JSignature):Int return switch s {
		case JDouble | JLong: 2;
		case _: 1;
	}
}

class NativeSignatures {
	public static final objectPath:JPath = {pack: ["java", "lang"], name: "Object"};
	public static final objectSig = JObject(objectPath, []);

	public static final stringPath:JPath = {pack: ["java", "lang"], name: "String"};
	public static final stringSig = JObject(stringPath, []);

	public static final booleanPath:JPath = {pack: ["java", "lang"], name: "Boolean"};
	public static final booleanSig = JObject(booleanPath, []);

	public static final characterPath:JPath = {pack: ["java", "lang"], name: "Character"};
	public static final characterSig = JObject(characterPath, []);

	public static final methodTypePath:JPath = {pack: ["java", "lang", "invoke"], name: "MethodType"};
	public static final methodTypeSig = JObject(methodTypePath, []);

	public static final methodLookupPath:JPath = {pack: ["java", "lang", "invoke"], name: "MethodHandles$Lookup"};
	public static final methodLookupSig = JObject(methodLookupPath, []);

	public static final callSitePath:JPath = {pack: ["java", "lang", "invoke"], name: "CallSite"};
	public static final callSiteSig = JObject(callSitePath, []);

	public static final javaClassPath:JPath = {pack: ["java", "lang"], name: "Class"};
	public static final javaClassSig = JObject(javaClassPath, [JTType(WNone, objectSig)]);

	public static final haxeJvmPath:JPath = {pack: ["haxe", "jvm"], name: "Jvm"};
	public static final haxeTypePath:JPath = {pack: ["haxe", "root"], name: "Type"};

	public static final haxeDynamicObjectPath:JPath = {pack: ["haxe", "jvm"], name: "DynamicObject"};
	public static final haxeDynamicObjectSig = JObject(haxeDynamicObjectPath, []);

	public static final haxeExceptionPath:JPath = {pack: ["haxe"], name: "Exception"};
	public static final haxeExceptionSig = JObject(haxeExceptionPath, []);

	public static final haxeObjectPath:JPath = {pack: ["haxe", "jvm"], name: "Object"};
	public static final haxeObjectSig = JObject(haxeObjectPath, []);

	public static final throwablePath:JPath = {pack: ["java", "lang"], name: "Throwable"};
	public static final throwableSig = JObject(throwablePath, []);

	public static final exceptionPath:JPath = {pack: ["java", "lang"], name: "Exception"};
	public static final exceptionSig = JObject(exceptionPath, []);

	public static final runtimeExceptionPath:JPath = {pack: ["java", "lang"], name: "RuntimeException"};
	public static final runtimeExceptionSig = JObject(runtimeExceptionPath, []);

	public static final retentionPath:JPath = {pack: ["java", "lang", "annotation"], name: "Retention"};
	public static final retentionSig = JObject(retentionPath, []);

	public static final retentionPolicyPath:JPath = {pack: ["java", "lang", "annotation"], name: "RetentionPolicy"};
	public static final retentionPolicySig = JObject(retentionPolicyPath, []);

	public static final javaEnumPath:JPath = {pack: ["java", "lang"], name: "Enum"};

	public static function javaEnumSig(jsig:JSignature):JSignature return JObject(javaEnumPath, [JTType(WNone, jsig)]);

	public static final haxeEnumPath:JPath = {pack: ["haxe", "jvm"], name: "Enum"};

	public static function haxeEnumSig(jsig:JSignature):JSignature return JObject(haxeEnumPath, [JTType(WNone, jsig)]);

	public static final haxeEmptyConstructorPath:JPath = {pack: ["haxe", "jvm"], name: "EmptyConstructor"};
	public static final haxeEmptyConstructorSig = JObject(haxeEmptyConstructorPath, []);

	public static final haxeFunctionPath:JPath = {pack: ["haxe", "jvm"], name: "Function"};
	public static final haxeFunctionSig = JObject(haxeFunctionPath, []);

	public static final haxeCompiledPatternPath:JPath = {pack: ["haxe", "jvm"], name: "CompiledPattern"};
	public static final haxeCompiledPatternSig = JObject(haxeCompiledPatternPath, []);

	public static final haxeEregPath:JPath = {pack: ["haxe", "root"], name: "EReg"};
	public static final haxeEregSig = JObject(haxeEregPath, []);

	public static final voidPath:JPath = {pack: ["java", "lang"], name: "Void"};
	public static final voidSig = JObject(voidPath, []);

	/* numeric */
	public static final numberPath:JPath = {pack: ["java", "lang"], name: "Number"};
	public static final numberSig = JObject(numberPath, []);

	public static final bytePath:JPath = {pack: ["java", "lang"], name: "Byte"};
	public static final byteSig = JObject(bytePath, []);

	public static final shortPath:JPath = {pack: ["java", "lang"], name: "Short"};
	public static final shortSig = JObject(shortPath, []);

	public static final integerPath:JPath = {pack: ["java", "lang"], name: "Integer"};
	public static final integerSig = JObject(integerPath, []);

	public static final longPath:JPath = {pack: ["java", "lang"], name: "Long"};
	public static final longSig = JObject(longPath, []);

	public static final floatPath:JPath = {pack: ["java", "lang"], name: "Float"};
	public static final floatSig = JObject(floatPath, []);

	public static final doublePath:JPath = {pack: ["java", "lang"], name: "Double"};
	public static final doubleSig = JObject(doublePath, []);

	/* compound */
	public static function arraySig(jsig:JSignature):JSignature return JArray(jsig, null);

	public static function methodSig(jsigs:Array<JSignature>, jsig:Null<JSignature>):JSignature return JMethod(jsigs, jsig);

	public static function objectPathSig(path:JPath):JSignature return JObject(path, []);

	public static function getBoxedType(jsig:JSignature):JSignature return switch jsig {
		case JBool: booleanSig;
		case JChar: characterSig;
		case JByte: byteSig;
		case JShort: shortSig;
		case JInt: integerSig;
		case JLong: longSig;
		case JFloat: floatSig;
		case JDouble: doubleSig;
		case _: jsig;
	}

	static inline function isJavaLang(path:JPath):Bool return path.pack.length == 2 && path.pack[0] == "java" && path.pack[1] == "lang";

	public static function getUnboxedType(jsig:JSignature):JSignature return switch jsig {
		case JObject(path, _) if (isJavaLang(path)):
			switch path.name {
				case "Boolean": JBool;
				case "Charcter": JChar;
				case "Byte": JByte;
				case "Short": JShort;
				case "Integer": JInt;
				case "Long": JLong;
				case "Float": JFloat;
				case "Double": JDouble;
				case _: jsig;
			}
		case _: jsig;
	}

	public static function isUnboxed(jsig:JSignature):Bool return switch jsig {
		case JBool | JChar | JByte | JShort | JInt | JLong | JFloat | JDouble:
			true;
		case _:
			false;
	}

	public static function isDynamicAtRuntime(jsig:JSignature):Bool return switch jsig {
		case JObject(path, _) if (isJavaLang(path) && path.name == "Object"):
			true;
		case JTypeParameter(_):
			true;
		case _:
			false;
	}
}
