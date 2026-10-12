/*
 * IO - Abstract input/output
 * Copyright (C) 2003 Nicolas Cannasse
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version,
 * with the special exception on linking described in file LICENSE.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

package libs.neko;

// port: the ExtLib `IO` output functions (extlib 1.8.0, src/IO.ml, little-endian)
// used by the Neko writers, over a `haxe.io.Output`. Strings are byte strings
// (see Nast): each character is written as one byte.
class Overflow extends haxe.Exception {
	public function new(what:String) super("IO.Overflow(\"" + what + "\")");
}

class IO {
	public static inline function writeByte(o:haxe.io.Output, n:Int):Void o.writeByte(n & 0xFF);

	public static function nwriteString(o:haxe.io.Output, s:String):Void for (i in 0...s.length) o.writeByte(StringTools.fastCodeAt(s, i) & 0xFF);

	public static function writeString(o:haxe.io.Output, s:String):Void {
		nwriteString(o, s);
		o.writeByte(0);
	}

	public static function writeUi16(o:haxe.io.Output, n:Int):Void {
		if (n < 0 || n > 0xFFFF) throw new Overflow("write_ui16");
		writeByte(o, n);
		writeByte(o, n >>> 8);
	}

	// port: OCaml ints are 63 bits; the port's values that reach here are already 32-bit,
	// so the write_i32 range check cannot fail.
	public static function writeI32(o:haxe.io.Output, n:Int):Void {
		writeByte(o, n);
		writeByte(o, n >>> 8);
		writeByte(o, n >>> 16);
		writeByte(o, n >>> 24);
	}

	public static function writeRealI32(o:haxe.io.Output, n:Int):Void {
		writeByte(o, n);
		writeByte(o, n >>> 8);
		writeByte(o, n >>> 16);
		writeByte(o, n >>> 24);
	}
}
