/*
 *  This file is part of SwfLib
 *  Copyright (c)2004 Nicolas Cannasse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
 */

package libs.swflib;

import haxe.io.Bytes;
import libs.extlib.IO;
import libs.extlib.IO.Input;
import libs.extlib.IO.Output;
import libs.swflib.Swf;

// port: haxe/libs/swflib/actionScript.ml (AS2 actions of SWF libraries).
// `action_string` (a disassembly printer) has no caller in the compiler and is
// not translated.
class ActionScript {
	static function assertFalse():Dynamic throw new core.ds.Failure("assert false");

	// port: OCaml strings are bytes: the length of the UTF-8 encoding.
	static inline function slen(s:String):Int return Bytes.ofString(s).length;

	public static function push_item_length(i:PushItem):Int return switch i {
		case PString(s): slen(s) + 1;
		case PFloat(_): 4;
		case PNull: 0;
		case PUndefined: 0;
		case PReg(_): 1;
		case PBool(_): 1;
		case PDouble(_): 8;
		case PInt(_): 4;
		case PStack(_): 1;
		case PStack2(_): 2;
	}

	static function push_item_id(i:PushItem):Int return switch i {
		case PString(s): 0;
		case PFloat(_): 1;
		case PNull: 2;
		case PUndefined: 3;
		case PReg(_): 4;
		case PBool(_): 5;
		case PDouble(_): 6;
		case PInt(_): 7;
		case PStack(_): 8;
		case PStack2(_): 9;
	}

	// port: the opcodes/opcodes_rev tables of short_op_codes (opcodes_names only
	// serves action_string).
	static function opcode_of(op:Action):Null<Int> return switch op {
		case AEnd: 0x00;
		case ANextFrame: 0x04;
		case APrevFrame: 0x05;
		case APlay: 0x06;
		case AStop: 0x07;
		case AToggleHighQuality: 0x08;
		case AStopSounds: 0x09;
		case AAddNum: 0x0A;
		case ASubtract: 0x0B;
		case AMultiply: 0x0C;
		case ADivide: 0x0D;
		case ACompareNum: 0x0E;
		case AEqualNum: 0x0F;
		case ALogicalAnd: 0x10;
		case ALogicalOr: 0x11;
		case ANot: 0x12;
		case AStringEqual: 0x13;
		case AStringLength: 0x14;
		case ASubString: 0x15;
		case APop: 0x17;
		case AToInt: 0x18;
		case AEval: 0x1C;
		case ASet: 0x1D;
		case ATellTarget: 0x20;
		case AStringAdd: 0x21;
		case AGetProperty: 0x22;
		case ASetProperty: 0x23;
		case ADuplicateMC: 0x24;
		case ARemoveMC: 0x25;
		case ATrace: 0x26;
		case AStartDrag: 0x27;
		case AStopDrag: 0x28;
		case AThrow: 0x2A;
		case ACast: 0x2B;
		case AImplements: 0x2C;
		case AFSCommand2: 0x2D;
		case ARandom: 0x30;
		case AMBStringLength: 0x31;
		case AOrd: 0x32;
		case AChr: 0x33;
		case AGetTimer: 0x34;
		case AMBStringSub: 0x35;
		case AMBOrd: 0x36;
		case AMBChr: 0x37;
		case ADeleteObj: 0x3A;
		case ADelete: 0x3B;
		case ALocalAssign: 0x3C;
		case ACall: 0x3D;
		case AReturn: 0x3E;
		case AMod: 0x3F;
		case ANew: 0x40;
		case ALocalVar: 0x41;
		case AInitArray: 0x42;
		case AObject: 0x43;
		case ATypeOf: 0x44;
		case ATargetPath: 0x45;
		case AEnum: 0x46;
		case AAdd: 0x47;
		case ACompare: 0x48;
		case AEqual: 0x49;
		case AToNumber: 0x4A;
		case AToString: 0x4B;
		case ADup: 0x4C;
		case ASwap: 0x4D;
		case AObjGet: 0x4E;
		case AObjSet: 0x4F;
		case AIncrement: 0x50;
		case ADecrement: 0x51;
		case AObjCall: 0x52;
		case ANewMethod: 0x53;
		case AInstanceOf: 0x54;
		case AEnum2: 0x55;
		case AAnd: 0x60;
		case AOr: 0x61;
		case AXor: 0x62;
		case AShl: 0x63;
		case AShr: 0x64;
		case AAsr: 0x65;
		case APhysEqual: 0x66;
		case AGreater: 0x67;
		case AStringGreater: 0x68;
		case AExtends: 0x69;
		case ACallFrame: 0x9E; /* special case */
		case _: null;
	}

	static final opcodes_rev:Map<Int, Action> = {
		var h = new Map<Int, Action>();
		for (op in [
			AEnd, ANextFrame, APrevFrame, APlay, AStop, AToggleHighQuality, AStopSounds, AAddNum, ASubtract, AMultiply, ADivide, ACompareNum,
			AEqualNum, ALogicalAnd, ALogicalOr, ANot, AStringEqual, AStringLength, ASubString, APop, AToInt, AEval, ASet, ATellTarget, AStringAdd,
			AGetProperty, ASetProperty, ADuplicateMC, ARemoveMC, ATrace, AStartDrag, AStopDrag, AThrow, ACast, AImplements, AFSCommand2, ARandom,
			AMBStringLength, AOrd, AChr, AGetTimer, AMBStringSub, AMBOrd, AMBChr, ADeleteObj, ADelete, ALocalAssign, ACall, AReturn, AMod, ANew,
			ALocalVar, AInitArray, AObject, ATypeOf, ATargetPath, AEnum, AAdd, ACompare, AEqual, AToNumber, AToString, ADup, ASwap, AObjGet,
			AObjSet, AIncrement, ADecrement, AObjCall, ANewMethod, AInstanceOf, AEnum2, AAnd, AOr, AXor, AShl, AShr, AAsr, APhysEqual, AGreater,
			AStringGreater, AExtends, ACallFrame
		])
			h.set(opcode_of(op), op);
		h;
	};

	public static function action_id(a:Action):Int return switch a {
		case AGotoFrame(_): 0x81;
		case AGetURL(_): 0x83;
		case ASetReg(_): 0x87;
		case AStringPool(_): 0x88;
		case AWaitForFrame(_): 0x8A;
		case ASetTarget(_): 0x8B;
		case AGotoLabel(_): 0x8C;
		case AWaitForFrame2(_): 0x8D;
		case AFunction2(_): 0x8E;
		case ATry(_): 0x8F;
		case AWith(_): 0x94;
		case APush(_): 0x96;
		case AJump(_): 0x99;
		case AGetURL2(_): 0x9A;
		case AFunction(_): 0x9B;
		case ACondJump(_): 0x9D;
		case AGotoFrame2(_): 0x9F;
		case AUnknown(id, _): id;
		case op:
			switch opcode_of(op) {
				case null: Swf.error("Unknown opcode id");
				case id: id;
			}
	}

	static function action_data_length(a:Action):Int return switch a {
		case AGotoFrame(_):
			2;
		case AGetURL(url, target):
			2 + slen(url) + slen(target);
		case ASetReg(_):
			1;
		case AStringPool(strs):
			var acc = 2;
			for (item in strs) acc = acc + 1 + slen(item);
			acc;
		case AWaitForFrame(_):
			3;
		case AFunction2(f):
			var base = slen(f.f2_name) + 1 + 2 + 1 + 2 + 2;
			var acc = base;
			for (a in f.f2_args) acc = acc + 2 + slen(a.s);
			acc;
		case ASetTarget(target):
			slen(target) + 1;
		case AGotoLabel(label):
			slen(label) + 1;
		case AWaitForFrame2(_):
			1;
		case ATry(t):
			1 + 6 + (switch t.tr_style {
				case TryVariable(n): slen(n) + 1;
				case TryRegister(_): 1;
			});
		case AWith(_):
			2; /* the string does not count in length */
		case APush(items):
			var acc = 0;
			for (item in items) acc = acc + 1 + push_item_length(item);
			acc;
		case AJump(_):
			2;
		case AGetURL2(_):
			1;
		case AFunction(f):
			var acc = 4;
			for (s in [f.f_name].concat(f.f_args)) acc = acc + 1 + slen(s);
			acc;
		case ACondJump(_):
			2;
		case AGotoFrame2(_, id):
			1 + (if (id == null) 0 else 2);
		case AUnknown(_, data):
			data.length;
		case _:
			0;
	}

	static function action_length(a:Action):Int {
		var len = (if (action_id(a) >= 0x80) 3 else 1);
		return len + action_data_length(a);
	}

	public static function actions_length(acts:Actions):Int {
		var acc = action_length(AEnd);
		for (a in acts) acc = acc + action_length(a);
		return acc;
	}

	static function read_mm_double(ch:Input):Float {
		var i1 = IO.readRealI32(ch);
		var i2 = IO.readRealI32(ch);
		// port: Int64.float_of_bits (i2 unsigned in the low word, i1 the high word).
		return haxe.io.FPHelper.i64ToDouble(i2, i1);
	}

	static function write_mm_double(ch:Output, f:Float):Void {
		var i64 = haxe.io.FPHelper.doubleToI64(f);
		IO.writeRealI32(ch, i64.high);
		IO.writeRealI32(ch, i64.low);
	}

	static function read_string_max(ch:Input, len:Int):String {
		var b = new haxe.io.BytesBuffer();
		function loop(l:Int):String {
			if (l == 0) {
				var s = b.getBytes();
				return s.sub(0, s.length - 1).toString();
			} else {
				var c = IO.read(ch);
				if (c == 0)
					return b.getBytes().toString()
				else {
					b.addByte(c);
					return loop(l - 1);
				}
			}
		}
		return loop(len);
	}

	static function parse_push_item(ch:Input, len:Int):PushItem {
		var id = IO.readByte(ch);
		return switch id {
			case 0: PString(read_string_max(ch, len));
			case 1: PFloat(IO.readRealI32(ch));
			case 2: PNull;
			case 3: PUndefined;
			case 4: PReg(IO.readByte(ch));
			case 5: PBool(IO.readByte(ch) != 0);
			case 6: PDouble(read_mm_double(ch));
			case 7: PInt(IO.readRealI32(ch));
			case 8: PStack(IO.readByte(ch));
			case 9: PStack2(IO.readUi16(ch));
			case _: Swf.error("Unknown PUSH item id : " + id);
		}
	}

	static function parse_push_items(ch:Input, len:Int):Array<PushItem> {
		if (len < 0) Swf.error("PUSH parse overflow");
		if (len == 0)
			return []
		else {
			var item = parse_push_item(ch, len);
			return [item].concat(parse_push_items(ch, len - 1 - push_item_length(item)));
		}
	}

	static function read_strings(ch:Input, n:Int):Array<String> {
		var l = [];
		for (_ in 0...n) l.push(IO.readString(ch));
		return l;
	}

	static function parse_function_decl(ch:Input):FunctionDecl {
		var name = IO.readString(ch);
		var nargs = IO.readUi16(ch);
		var args = read_strings(ch, nargs);
		var clen = IO.readUi16(ch);
		return {
			f_name: name,
			f_args: args,
			f_codelen: clen,
		};
	}

	static function parse_f2_flags(n:Int):Array<Func2Flags> {
		var flags = [];
		var v = 1;
		function add_flag(f:Func2Flags) {
			if (n & v != 0) flags.unshift(f);
			v = v << 1;
		}
		for (f in [
			ThisRegister,
			ThisNoVar,
			ArgumentsRegister,
			ArgumentsNoVar,
			SuperRegister,
			SuperNoVar,
			RootRegister,
			ParentRegister,
			GlobalRegister
		])
			add_flag(f);
		return flags;
	}

	static function parse_function_decl2(ch:Input):FunctionDecl2 {
		var name = IO.readString(ch);
		var nargs = IO.readUi16(ch);
		var nregs = IO.readByte(ch);
		var flags = parse_f2_flags(IO.readUi16(ch));
		var args = [];
		for (_ in 0...nargs) {
			var r = IO.readByte(ch);
			var s = IO.readString(ch);
			args.push({r: r, s: s});
		}
		var clen = IO.readUi16(ch);
		return {
			f2_name: name,
			f2_args: args,
			f2_flags: flags,
			f2_codelen: clen,
			f2_nregs: nregs,
		};
	}

	static function parse_action(ch:Input):Action {
		var id = IO.readByte(ch);
		var len = (if (id >= 0x80) IO.readUi16(ch) else 0);
		var len = (if (len == 0xFFFF) 0 else len);
		var act = (switch id {
			case 0x81:
				AGotoFrame(IO.readUi16(ch));
			case 0x83:
				var url = IO.readString(ch);
				var target = IO.readString(ch);
				AGetURL(url, target);
			case 0x87:
				ASetReg(IO.readByte(ch));
			case 0x88:
				var nstrs = IO.readUi16(ch);
				AStringPool(read_strings(ch, nstrs));
			case 0x8A:
				var frame = IO.readUi16(ch);
				var skip = IO.readByte(ch);
				AWaitForFrame(frame, skip);
			case 0x8B:
				ASetTarget(IO.readString(ch));
			case 0x8C:
				AGotoLabel(IO.readString(ch));
			case 0x8D:
				AWaitForFrame2(IO.readByte(ch));
			case 0x8E:
				AFunction2(parse_function_decl2(ch));
			case 0x8F:
				var flags = IO.readByte(ch);
				var tsize = IO.readUi16(ch);
				var csize = IO.readUi16(ch);
				var fsize = IO.readUi16(ch);
				var tstyle = (if (flags & 4 == 0) TryVariable(IO.readString(ch)) else TryRegister(IO.readByte(ch)));
				ATry({
					tr_style: tstyle,
					tr_trylen: tsize,
					tr_catchlen: (if (flags & 1 == 0) null else csize),
					tr_finallylen: (if (flags & 2 == 0) null else fsize),
				});
			case 0x94:
				var size = IO.readUi16(ch);
				AWith(size);
			case 0x96:
				APush(parse_push_items(ch, len));
			case 0x99:
				AJump(IO.readI16(ch));
			case 0x9A:
				AGetURL2(IO.readByte(ch));
			case 0x9B:
				AFunction(parse_function_decl(ch));
			case 0x9D:
				ACondJump(IO.readI16(ch));
			case 0x9E:
				ACallFrame;
			case 0x9F:
				var flags = IO.readByte(ch);
				var play = flags & 1 != 0;
				var delta = (if (flags & 2 == 0) null else IO.readUi16(ch));
				AGotoFrame2(play, delta);
			case _:
				switch opcodes_rev.get(id) {
					case null:
						Sys.print("Unknown Action 0x" + StringTools.hex(id, 2) + " (" + len + ")\n");
						AUnknown(id, IO.nread(ch, len));
					case op:
						op;
				}
		});
		/*	let len2 = action_data_length act in
			if len <> len2 then error (sprintf "Datalen mismatch for action 0x%.2X (%d != %d)" id len len2);
		 */
		return act;
	}

	static function size_to_jump_index(acts:Actions, curindex:Int, size:Int):Int {
		var delta = 0;
		var size = size;
		if (size >= 0) {
			while (size > 0) {
				delta++;
				size = size - action_length(acts[curindex + delta]);
				if (size < 0) Swf.error("Unaligned code");
			}
		} else {
			while (size < 0) {
				size = size + action_length(acts[curindex + delta]);
				if (size > 0) Swf.error("Unaligned code");
				delta--;
			}
		}
		return delta;
	}

	public static function parse_actions(ch:Input):Actions {
		var acts:Actions = [];
		while (true) {
			switch parse_action(ch) {
				case AEnd:
					break;
				case AUnknown(0xFF, data) if (data.length == 0):
					acts.push(APlay);
					acts.push(APlay);
					acts.push(APlay);
				case a:
					acts.push(a);
			}
		}
		/* process jump indexes */
		function process_jump(curindex:Int, a:Action) {
			switch a {
				case AJump(size):
					var index = size_to_jump_index(acts, curindex, size);
					acts[curindex] = AJump(index);
				case ACondJump(size):
					var index = size_to_jump_index(acts, curindex, size);
					acts[curindex] = ACondJump(index);
				case AFunction(f):
					var index = size_to_jump_index(acts, curindex, f.f_codelen);
					acts[curindex] = AFunction({f_name: f.f_name, f_args: f.f_args, f_codelen: index});
				case AFunction2(f):
					var index = size_to_jump_index(acts, curindex, f.f2_codelen);
					acts[curindex] = AFunction2({
						f2_name: f.f2_name,
						f2_flags: f.f2_flags,
						f2_args: f.f2_args,
						f2_nregs: f.f2_nregs,
						f2_codelen: index
					});
				case AWith(size):
					var index = size_to_jump_index(acts, curindex, size);
					acts[curindex] = AWith(index);
				case ATry(t):
					var tindex = size_to_jump_index(acts, curindex, t.tr_trylen);
					var cindex = (switch t.tr_catchlen {
						case null: null;
						case size: size_to_jump_index(acts, curindex + tindex, size);
					});
					var findex = (switch t.tr_finallylen {
						case null: null;
						case size: size_to_jump_index(acts, curindex + tindex + (switch cindex {
								case null: 0;
								case i: i;
							}), size);
					});
					acts[curindex] = ATry({
						tr_style: t.tr_style,
						tr_trylen: tindex,
						tr_catchlen: cindex,
						tr_finallylen: findex
					});
				case _:
			}
		}
		// port: DynArray.iteri reads each element when it reaches it.
		for (i in 0...acts.length) process_jump(i, acts[i]);
		return acts;
	}

	static function jump_index_to_size(acts:Actions, curindex:Int, target:Int):Int {
		var size = 0;
		if (target >= 0) {
			for (i in 1...target + 1) size = size + action_length(acts[curindex + i]);
		} else {
			var i = 0;
			while (i >= target + 1) {
				size = size - action_length(acts[curindex + i]);
				i--;
			}
		}
		return size;
	}

	static function write_strings(ch:Output, l:Array<String>):Void {
		for (s in l) IO.writeString(ch, s);
	}

	static function write_push_item_data(ch:Output, i:PushItem):Void {
		switch i {
			case PString(s):
				IO.writeString(ch, s);
			case PFloat(f):
				IO.writeRealI32(ch, f);
			case PNull:
			case PUndefined:
			case PReg(r):
				IO.writeByte(ch, r);
			case PBool(b):
				IO.writeByte(ch, if (b) 1 else 0);
			case PDouble(f):
				write_mm_double(ch, f);
			case PInt(n):
				IO.writeRealI32(ch, n);
			case PStack(index):
				IO.writeByte(ch, index);
			case PStack2(index):
				IO.writeUi16(ch, index);
		}
	}

	static function f2_flags_value(flags:Array<Func2Flags>):Int {
		function fval(f:Func2Flags):Int return switch f {
			case ThisRegister: 1;
			case ThisNoVar: 2;
			case ArgumentsRegister: 4;
			case ArgumentsNoVar: 8;
			case SuperRegister: 16;
			case SuperNoVar: 32;
			case RootRegister: 64;
			case ParentRegister: 128;
			case GlobalRegister: 256;
		}
		var n = 0;
		for (f in flags) n = n | fval(f);
		return n;
	}

	static function write_action_data(acts:Actions, curindex:Int, ch:Output, a:Action):Void {
		switch a {
			case AGotoFrame(frame):
				IO.writeUi16(ch, frame);
			case AGetURL(url, target):
				IO.writeString(ch, url);
				IO.writeString(ch, target);
			case ASetReg(reg):
				IO.writeByte(ch, reg);
			case AStringPool(strs):
				IO.writeUi16(ch, strs.length);
				write_strings(ch, strs);
			case AWaitForFrame(frame, skip):
				IO.writeUi16(ch, frame);
				IO.writeByte(ch, skip);
			case ASetTarget(target):
				IO.writeString(ch, target);
			case AGotoLabel(label):
				IO.writeString(ch, label);
			case AWaitForFrame2(n):
				IO.writeByte(ch, n);
			case AFunction2(f):
				IO.writeString(ch, f.f2_name);
				IO.writeUi16(ch, f.f2_args.length);
				IO.writeByte(ch, f.f2_nregs);
				IO.writeUi16(ch, f2_flags_value(f.f2_flags));
				for (a in f.f2_args) {
					IO.writeByte(ch, a.r);
					IO.writeString(ch, a.s);
				}
				var size = jump_index_to_size(acts, curindex, f.f2_codelen);
				IO.writeUi16(ch, size);
			case ATry(t):
				var tsize = jump_index_to_size(acts, curindex, t.tr_trylen);
				var csize = (switch t.tr_catchlen {
					case null: 0;
					case idx: jump_index_to_size(acts, curindex + t.tr_trylen, idx);
				});
				var fsize = (switch t.tr_finallylen {
					case null: 0;
					case idx: jump_index_to_size(acts, curindex + t.tr_trylen + (switch t.tr_catchlen {
							case null: 0;
							case n: n;
						}), idx);
				});
				var flags = (if (t.tr_catchlen != null) 1 else 0) | (if (t.tr_finallylen != null) 2 else 0) | (switch t.tr_style {
					case TryRegister(_): 4;
					case TryVariable(_): 0;
				});
				IO.writeByte(ch, flags);
				IO.writeUi16(ch, tsize);
				IO.writeUi16(ch, csize);
				IO.writeUi16(ch, fsize);
				switch t.tr_style {
					case TryVariable(v):
						IO.writeString(ch, v);
					case TryRegister(r):
						IO.writeByte(ch, r);
				}
			case AWith(target):
				var size = jump_index_to_size(acts, curindex, target);
				IO.writeUi16(ch, size);
			case APush(items):
				for (item in items) {
					IO.writeByte(ch, push_item_id(item));
					write_push_item_data(ch, item);
				}
			case AJump(target):
				var size = jump_index_to_size(acts, curindex, target);
				IO.writeI16(ch, size);
			case AGetURL2(n):
				IO.writeByte(ch, n);
			case AFunction(f):
				IO.writeString(ch, f.f_name);
				IO.writeUi16(ch, f.f_args.length);
				write_strings(ch, f.f_args);
				var size = jump_index_to_size(acts, curindex, f.f_codelen);
				IO.writeUi16(ch, size);
			case ACondJump(target):
				var size = jump_index_to_size(acts, curindex, target);
				IO.writeI16(ch, size);
			case AGotoFrame2(play, null):
				IO.writeByte(ch, if (play) 1 else 0);
			case AGotoFrame2(play, delta):
				IO.writeByte(ch, if (play) 3 else 2);
				IO.writeUi16(ch, delta);
			case ACallFrame:
			case AUnknown(_, data):
				IO.nwrite(ch, data);
			case _:
				assertFalse();
		}
	}

	static function write_action(acts:Actions, curindex:Int, ch:Output, a:Action):Void {
		var id = action_id(a);
		var len = action_data_length(a);
		if (id < 0x80 && len > 0) Swf.error("Invalid Action Written");
		IO.writeByte(ch, id);
		if (len > 0 || id >= 0x80) {
			IO.writeUi16(ch, len);
			write_action_data(acts, curindex, ch, a);
		}
	}

	public static function write_actions(ch:Output, acts:Actions):Void {
		for (index in 0...acts.length) write_action(acts, index, ch, acts[index]);
		write_action(acts, acts.length, ch, AEnd);
	}
}
