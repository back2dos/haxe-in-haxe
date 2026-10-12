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

import haxe.io.Bytes;
import core.ds.OcamlHash;
import core.ds.OcamlHash.OcamlValue;
import core.ds.OcamlHashtbl;
import generators.jvm.JvmGlobals;
import generators.jvm.JvmSignature;

// port: key of the `inner_classes` table: `((string list * string) * string)`.
@:structInit class InnerClassKey {
	public final path:JPath;
	public final name:String;
}

/* High-level constant pool */
class JvmConstantPool {
	// port: decodes the UTF-8 bytes of the string as extlib's UTF8.iter does.
	public static function utf8jvm(input:String):Bytes {
		var channel = new OutputBytes();
		var b = Bytes.ofString(input);
		var i = 0;
		var len = b.length;
		while (i < len) {
			var n = b.get(i);
			var code;
			if (n < 0x80) {
				code = n;
				i += 1;
			} else if (n <= 0xDF) {
				code = ((n - 0xC0) << 6) | (0x7F & b.get(i + 1));
				i += 2;
			} else if (n <= 0xEF) {
				code = ((n - 0xE0) << 12) | ((0x7F & b.get(i + 1)) << 6) | (0x7F & b.get(i + 2));
				i += 3;
			} else {
				code = ((n - 0xF0) << 18) | ((0x7F & b.get(i + 1)) << 12) | ((0x7F & b.get(i + 2)) << 6) | (0x7F & b.get(i + 3));
				i += 4;
			}
			if (code > 0 && code <= 0x7F) {
				channel.writeByte(code);
				/* includes null byte: */
			} else if (code <= 0x7FF) {
				channel.writeByte(0xC0 | (code >>> 6));
				channel.writeByte(0x80 | (code & 0x3F));
			} else if (code <= 0xFFFF) {
				channel.writeByte(0xE0 | (code >>> 12));
				channel.writeByte(0x80 | ((code >>> 6) & 0x3F));
				channel.writeByte(0x80 | (code & 0x3F));
			} else {
				channel.writeByte(0xED);
				channel.writeByte(0xA0 | ((code >>> 16) - 1));
				channel.writeByte(0x80 | ((code >>> 10) & 0x3F));
				channel.writeByte(0xED);
				channel.writeByte(0xB0 | ((code >>> 6) & 0x0F));
				channel.writeByte(0x80 | (code & 0x3F));
			}
		}
		return channel.closeOut();
	}

	final pool:Array<JvmConstant> = [];
	// port: `lut` is keyed by the constant itself (OCaml structural equality); constKey
	// encodes a constant up to that equality. It is only used for lookups.
	final lut:haxe.ds.StringMap<Int> = new haxe.ds.StringMap();
	final luti:haxe.ds.IntMap<Int> = new haxe.ds.IntMap();
	var nextIndex = 1;
	var closed = false;
	final innerClasses:OcamlHashtbl<InnerClassKey, Int> = new OcamlHashtbl(function(k:InnerClassKey) return OcamlHash.hash(OBlock(0, [
		JvmSignature.ocamlValueOfPath(k.path),
		OString(k.name)
	])), function(a:InnerClassKey, b:InnerClassKey) return JvmSignature.pathEq(a.path, b.path) && a.name == b.name);

	public function new() {}

	// port: OCaml's compare treats 0.0 and -0.0 as equal, as well as all NaNs.
	static function floatKey(f:Float):String {
		if (f == 0) return "0";
		if (Math.isNaN(f)) return "nan";
		var i64 = haxe.io.FPHelper.doubleToI64(f);
		return i64.high + ":" + i64.low;
	}

	static function constKey(const:JvmConstant):String return switch const {
		case ConstUtf8(s): "u" + s;
		case ConstInt(i): "i" + i;
		case ConstFloat(f): "f" + floatKey(f);
		case ConstLong(i): "l" + i.high + ":" + i.low;
		case ConstDouble(f): "d" + floatKey(f);
		case ConstClass(i): "c" + i;
		case ConstString(i): "s" + i;
		case ConstFieldref(i1, i2): "F" + i1 + ":" + i2;
		case ConstMethodref(i1, i2): "M" + i1 + ":" + i2;
		case ConstInterfaceMethodref(i1, i2): "I" + i1 + ":" + i2;
		case ConstNameAndType(i1, i2): "N" + i1 + ":" + i2;
		case ConstMethodHandle(i1, i2): "H" + i1 + ":" + i2;
		case ConstMethodType(i): "T" + i;
		case ConstInvokeDynamic(i1, i2): "D" + i1 + ":" + i2;
	}

	public function add(const:JvmConstant):Int {
		var key = constKey(const);
		var found = lut.get(key);
		if (found != null) return found;
		if (closed) throw new core.ds.Failure("assert");
		var i = nextIndex;
		nextIndex = nextIndex + 1;
		pool.push(const);
		lut.set(key, i);
		luti.set(i, pool.length - 1);
		return switch const {
			case ConstDouble(_) | ConstLong(_):
				nextIndex = nextIndex + 1;
				i;
			case _:
				i;
		}
	}

	public function get(i:Int):JvmConstant {
		var j = luti.get(i);
		if (j == null) throw core.ds.NotFound.raise();
		return pool[j];
	}

	function sTypePath(p:JPath):String return p.pack.length == 0 ? p.name : p.pack.join("/") + "/" + p.name;

	public function addType(s:String):Int {
		var offset = add(ConstUtf8(s));
		return add(ConstClass(offset));
	}

	public function addPath(path:JPath):Int {
		var s = sTypePath(path);
		var offset = addType(s);
		if (path.name.indexOf("$") >= 0 && !StringTools.startsWith(s, "[")) {
			// port: ExtString.String.split splits at the first occurrence
			var idx = path.name.indexOf("$");
			var name1 = path.name.substr(0, idx), name2 = path.name.substr(idx + 1);
			innerClasses.replace({path: {pack: path.pack, name: name1}, name: name2}, offset);
		}
		return offset;
	}

	public function addString(s:String):Int return add(ConstUtf8(s));

	public function addConstString(s:String):Int {
		var offset = addString(s);
		return add(ConstString(offset));
	}

	public function addNameAndType(name:String, jsig:JSignature, fieldKind:FieldKind):Int {
		var offsetName = addString(name);
		var offsetDesc = addString((if (fieldKind == FKField) JvmSignature.generateSignature else JvmSignature.generateMethodSignature)(false, jsig));
		return add(ConstNameAndType(offsetName, offsetDesc));
	}

	public function addField(path:JPath, name:String, jsig:JSignature, fieldKind:FieldKind):Int {
		var offsetClass = addPath(path);
		var offsetInfo = addNameAndType(name, jsig, fieldKind);
		var const = switch fieldKind {
			case FKField: ConstFieldref(offsetClass, offsetInfo);
			case FKMethod: ConstMethodref(offsetClass, offsetInfo);
			case FKInterfaceMethod: ConstInterfaceMethodref(offsetClass, offsetInfo);
		}
		return add(const);
	}

	public function getInnerClasses():OcamlHashtbl<InnerClassKey, Int> return innerClasses;

	function writeI64(ch:OutputBytes, i64:haxe.Int64):Void {
		ch.writeRealI32(i64.low);
		ch.writeRealI32(i64.high);
	}

	function write(ch:OutputBytes):Void {
		ch.writeUi16(nextIndex);
		for (const in pool) switch const {
			case ConstUtf8(s):
				ch.writeByte(1);
				var b = utf8jvm(s);
				ch.writeUi16(b.length);
				ch.nwrite(b);
			case ConstInt(i32):
				ch.writeByte(3);
				ch.writeRealI32(i32);
			case ConstFloat(f):
				ch.writeByte(4);
				if (Math.isNaN(f)) ch.writeRealI32(0x7f800001) else if (!Math.isFinite(f)) {
					if (f > 0.0) ch.writeRealI32(0x7f800000) else ch.writeRealI32(0xff800000);
				} else ch.writeRealI32(haxe.io.FPHelper.floatToI32(f));
			case ConstLong(i64):
				ch.writeByte(5);
				// port: `write_i64` here is IO.BigEndian.write_i64 (high word first), not the
				// private method above, which upstream never calls.
				ch.writeRealI32(i64.high);
				ch.writeRealI32(i64.low);
			case ConstDouble(d):
				ch.writeByte(6);
				ch.writeDouble(d);
			case ConstClass(offset):
				ch.writeByte(7);
				ch.writeUi16(offset);
			case ConstString(offset):
				ch.writeByte(8);
				ch.writeUi16(offset);
			case ConstFieldref(offset1, offset2):
				ch.writeByte(9);
				ch.writeUi16(offset1);
				ch.writeUi16(offset2);
			case ConstMethodref(offset1, offset2):
				ch.writeByte(10);
				ch.writeUi16(offset1);
				ch.writeUi16(offset2);
			case ConstInterfaceMethodref(offset1, offset2):
				ch.writeByte(11);
				ch.writeUi16(offset1);
				ch.writeUi16(offset2);
			case ConstNameAndType(offset1, offset2):
				ch.writeByte(12);
				ch.writeUi16(offset1);
				ch.writeUi16(offset2);
			case ConstMethodHandle(i, offset):
				ch.writeByte(15);
				ch.writeByte(i);
				ch.writeUi16(offset);
			case ConstMethodType(offset):
				ch.writeByte(16);
				ch.writeUi16(offset);
			case ConstInvokeDynamic(offset1, offset2):
				ch.writeByte(18);
				ch.writeUi16(offset1);
				ch.writeUi16(offset2);
		}
	}

	public function close():Bytes {
		closed = true;
		var ch = new OutputBytes();
		write(ch);
		return ch.closeOut();
	}
}
