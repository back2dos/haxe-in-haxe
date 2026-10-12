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
import generators.jvm.JvmSignature;

// port: JvmVerificationTypeInfo.t
enum VerificationTypeInfo {
	VTop;
	VInteger;
	VFloat;
	VDouble;
	VLong;
	VNull;
	VUninitializedThis;
	VObject(i:JvmConstantPoolIndex);
	VUninitialized(i:Int);
}

class JvmVerificationTypeInfo {
	public static function ofSignature(pool:JvmConstantPool, jsig:JSignature):VerificationTypeInfo return switch jsig {
		case JByte | JChar | JBool | JShort | JInt: VInteger;
		case JFloat: VFloat;
		case JLong: VLong;
		case JDouble: VDouble;
		case JObject(path, _): VObject(pool.addPath(path));
		case JMethod(_): VObject(pool.addPath(NativeSignatures.haxeFunctionPath));
		case JArray(_): VObject(pool.addPath({pack: [], name: JvmSignature.generateSignature(false, jsig)}));
		case JTypeParameter(_): VObject(pool.addPath({pack: ["java", "lang"], name: "Object"}));
		case JUninitialized(i) if (i != null): VUninitialized(i);
		case JUninitialized(_): VUninitializedThis;
		case _: core.Globals.die("", "generators/jvm/jvmVerificationTypeInfo.ml");
	}

	public static function toString(vtt:VerificationTypeInfo):String return switch vtt {
		case VTop: "top";
		case VInteger: "integer";
		case VFloat: "float";
		case VLong: "long";
		case VDouble: "double";
		case VNull: "null";
		case VUninitializedThis: "uninitializedThis";
		case VObject(i): "object " + i;
		case VUninitialized(i): "uninitializedVariable " + i;
	}

	// port: OCaml's structural equality on verification types (used on frame locals).
	public static function eq(a:VerificationTypeInfo, b:VerificationTypeInfo):Bool return switch [a, b] {
		case [VObject(i1), VObject(i2)]: i1 == i2;
		case [VUninitialized(i1), VUninitialized(i2)]: i1 == i2;
		case _: a.getIndex() == b.getIndex() && a.getIndex() != 7 && a.getIndex() != 8;
	}

	public static function listEq(a:Array<VerificationTypeInfo>, b:Array<VerificationTypeInfo>):Bool {
		if (a.length != b.length) return false;
		for (i in 0...a.length) if (!eq(a[i], b[i])) return false;
		return true;
	}
}
