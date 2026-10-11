package libs.swflib;

import libs.extlib.IO;
import libs.extlib.IO.Output;
import libs.swflib.As3;

// port: the writer side of haxe/libs/swflib/as3code.ml (length, write). The
// f_int_length/f_int_write hooks that As3parse installs are direct calls.
class As3code {
	static inline function int_length(i:Int):Int return As3parse.int_length(i);

	static inline function write_int(ch:Output, i:Int):Void As3parse.write_int(ch, i);

	static inline function write_index(ch:Output, i:Index):Void write_int(ch, i);

	static inline function write_index_nz(ch:Output, i:IndexNz):Void write_int(ch, i);

	static inline function write_byte(ch:Output, n:Int):Void IO.writeByte(ch, n);

	static inline function write_signed_byte(ch:Output, n:Int):Void IO.writeByte(ch, n);

	static final max_i24 = (1 << 23) - 1;

	static function write_i24(ch:Output, n:Int):Void {
		if (n < -max_i24 || n > max_i24) throw new core.ds.Failure("assert false");
		var n = (if (n & (1 << 23) != 0) n + (1 << 24) else n);
		write_byte(ch, n);
		write_byte(ch, n >> 8);
		write_byte(ch, n >> 16);
	}

	static function op_id(op:As3Op):Int return switch op {
		case A3OAs: 0x87;
		case A3ONeg: 0x90;
		case A3OIncr: 0x91;
		/* 0x92 : REGINCR */
		case A3ODecr: 0x93;
		/* 0x94 : REGDECR */
		/* 0x95 : TYPEOF */
		case A3ONot: 0x96;
		case A3OBitNot: 0x97;
		case A3OAdd: 0xA0;
		case A3OSub: 0xA1;
		case A3OMul: 0xA2;
		case A3ODiv: 0xA3;
		case A3OMod: 0xA4;
		case A3OShl: 0xA5;
		case A3OShr: 0xA6;
		case A3OUShr: 0xA7;
		case A3OAnd: 0xA8;
		case A3OOr: 0xA9;
		case A3OXor: 0xAA;
		case A3OEq: 0xAB;
		case A3OPhysEq: 0xAC;
		case A3OLt: 0xAD;
		case A3OLte: 0xAE;
		case A3OGt: 0xAF;
		case A3OGte: 0xB0;
		case A3OIs: 0xB3;
		case A3OIn: 0xB4;
		case A3OIIncr: 0xC0;
		case A3OIDecr: 0xC1;
		case A3OINeg: 0xC4;
		case A3OIAdd: 0xC5;
		case A3OISub: 0xC6;
		case A3OIMul: 0xC7;
		case A3OMemGet8: 0x35;
		case A3OMemGet16: 0x36;
		case A3OMemGet32: 0x37;
		case A3OMemGetFloat: 0x38;
		case A3OMemGetDouble: 0x39;
		case A3OMemSet8: 0x3A;
		case A3OMemSet16: 0x3B;
		case A3OMemSet32: 0x3C;
		case A3OMemSetFloat: 0x3D;
		case A3OMemSetDouble: 0x3E;
		case A3OSign1: 0x50;
		case A3OSign8: 0x51;
		case A3OSign16: 0x52;
	}

	public static function length(op:As3Opcode):Int return switch op {
		case A3SmallInt(_): 2;
		case A3Construct(n) | A3Object(n) | A3RegKill(n) | A3Catch(n) | A3IncrReg(n) | A3DecrReg(n) | A3IncrIReg(n) | A3DecrIReg(n) | A3Array(n) | A3Int(n) |
			A3CallStack(n) | A3ConstructSuper(n) | A3BreakPointLine(n) | A3ApplyType(n) | A3DebugLine(n):
			1 + int_length(n);
		case A3GetSlot(s) | A3SetSlot(s):
			1 + int_length(s);
		case A3ClassDef(n):
			1 + int_length(n);
		case A3DxNs(f) | A3String(f) | A3DebugFile(f):
			1 + int_length(f);
		case A3IntRef(f):
			1 + int_length(f);
		case A3UIntRef(f):
			1 + int_length(f);
		case A3Float(f):
			1 + int_length(f);
		case A3Function(f):
			1 + int_length(f);
		case A3Namespace(f):
			1 + int_length(f);
		case A3GetProp(f) | A3InitProp(f) | A3DeleteProp(f) | A3FindPropStrict(f) | A3FindProp(f) | A3FindDefinition(f) | A3GetLex(f) | A3SetProp(f) | A3Cast(f) |
			A3GetSuper(f) | A3GetDescendants(f) | A3SetSuper(f):
			1 + int_length(f);
		case A3Op(_) | A3Undefined | A3Null | A3True | A3False | A3NaN | A3RetVoid | A3Ret | A3Pop | A3Dup | A3Swap | A3AsAny | A3ToString | A3ToXml | A3ToXmlAttr |
			A3ToInt | A3ToUInt | A3ToNumber | A3ToBool | A3ToObject | A3AsString | A3AsObject | A3This | A3Throw | A3Nop | A3Typeof | A3InstanceOf | A3Scope |
			A3ForIn | A3NewBlock | A3ForEach | A3PopScope | A3CheckIsXml | A3Label | A3BreakPoint | A3PushWith | A3HasNext | A3SetThis | A3Timestamp | A3DxNsLate |
			A3Unk(_):
			1;
		case A3AsType(n) | A3IsType(n):
			1 + int_length(n);
		case A3DebugReg(name, reg, line): 1 + 1 + int_length(name) + 1 + int_length(line);
		case A3GetGlobalScope: 1;
		case A3GetScope(n): 1 + int_length(n);
		case A3Reg(n) | A3SetReg(n): if (n >= 1 && n <= 3) 1 else (1 + int_length(n));
		case A3CallSuper(f, n) | A3CallProperty(f, n) | A3ConstructProperty(f, n) | A3CallPropLex(f, n) | A3CallPropVoid(f, n) | A3CallSuperVoid(f, n):
			1 + int_length(n) + int_length(f);
		case A3CallMethod(f, n):
			1 + int_length(n) + int_length(f);
		case A3CallStatic(f, n):
			1 + int_length(n) + int_length(f);
		case A3Jump(_): 4;
		case A3Next(a, b): 1 + int_length(a) + int_length(b);
		case A3Switch(_, cases):
			var ncases = cases.length;
			1 + 3 + int_length(ncases - 1) + 3 * ncases;
	}

	public static function write(ch:Output, op:As3Opcode):Void {
		switch op {
			case A3BreakPoint:
				write_byte(ch, 0x01);
			case A3Nop:
				write_byte(ch, 0x02);
			case A3Throw:
				write_byte(ch, 0x03);
			case A3GetSuper(f):
				write_byte(ch, 0x04);
				write_index(ch, f);
			case A3SetSuper(f):
				write_byte(ch, 0x05);
				write_index(ch, f);
			case A3DxNs(i):
				write_byte(ch, 0x06);
				write_index(ch, i);
			case A3DxNsLate:
				write_byte(ch, 0x07);
			case A3RegKill(n):
				write_byte(ch, 0x08);
				write_int(ch, n);
			case A3Label:
				write_byte(ch, 0x09);
			case A3Jump(k, n):
				write_byte(ch, switch k {
					case J3NotLt: 0x0C;
					case J3NotLte: 0x0D;
					case J3NotGt: 0x0E;
					case J3NotGte: 0x0F;
					case J3Always: 0x10;
					case J3True: 0x11;
					case J3False: 0x12;
					case J3Eq: 0x13;
					case J3Neq: 0x14;
					case J3Lt: 0x15;
					case J3Lte: 0x16;
					case J3Gt: 0x17;
					case J3Gte: 0x18;
					case J3PhysEq: 0x19;
					case J3PhysNeq: 0x1A;
				});
				write_i24(ch, n);
			case A3Switch(def, cases):
				write_byte(ch, 0x1B);
				write_i24(ch, def);
				write_int(ch, cases.length - 1);
				for (c in cases) write_i24(ch, c);
			case A3PushWith:
				write_byte(ch, 0x1C);
			case A3PopScope:
				write_byte(ch, 0x1D);
			case A3ForIn:
				write_byte(ch, 0x1E);
			case A3HasNext:
				write_byte(ch, 0x1F);
			case A3Null:
				write_byte(ch, 0x20);
			case A3Undefined:
				write_byte(ch, 0x21);
			case A3ForEach:
				write_byte(ch, 0x23);
			case A3SmallInt(b):
				write_byte(ch, 0x24);
				write_signed_byte(ch, b);
			case A3Int(i):
				write_byte(ch, 0x25);
				write_int(ch, i);
			case A3True:
				write_byte(ch, 0x26);
			case A3False:
				write_byte(ch, 0x27);
			case A3NaN:
				write_byte(ch, 0x28);
			case A3Pop:
				write_byte(ch, 0x29);
			case A3Dup:
				write_byte(ch, 0x2A);
			case A3Swap:
				write_byte(ch, 0x2B);
			case A3String(s):
				write_byte(ch, 0x2C);
				write_index(ch, s);
			case A3IntRef(i):
				write_byte(ch, 0x2D);
				write_index(ch, i);
			case A3UIntRef(i):
				write_byte(ch, 0x2E);
				write_index(ch, i);
			case A3Float(f):
				write_byte(ch, 0x2F);
				write_index(ch, f);
			case A3Scope:
				write_byte(ch, 0x30);
			case A3Namespace(f):
				write_byte(ch, 0x31);
				write_index(ch, f);
			case A3Next(r1, r2):
				write_byte(ch, 0x32);
				write_int(ch, r1);
				write_int(ch, r2);
			case A3Function(f):
				write_byte(ch, 0x40);
				write_index_nz(ch, f);
			case A3CallStack(n):
				write_byte(ch, 0x41);
				write_int(ch, n);
			case A3Construct(n):
				write_byte(ch, 0x42);
				write_int(ch, n);
			case A3CallMethod(f, n):
				write_byte(ch, 0x43);
				write_int(ch, f);
				write_int(ch, n);
			case A3CallStatic(f, n):
				write_byte(ch, 0x44);
				write_index(ch, f);
				write_int(ch, n);
			case A3CallSuper(f, n):
				write_byte(ch, 0x45);
				write_index(ch, f);
				write_int(ch, n);
			case A3CallProperty(f, n):
				write_byte(ch, 0x46);
				write_index(ch, f);
				write_int(ch, n);
			case A3RetVoid:
				write_byte(ch, 0x47);
			case A3Ret:
				write_byte(ch, 0x48);
			case A3ConstructSuper(n):
				write_byte(ch, 0x49);
				write_int(ch, n);
			case A3ConstructProperty(f, n):
				write_byte(ch, 0x4A);
				write_index(ch, f);
				write_int(ch, n);
			case A3CallPropLex(f, n):
				write_byte(ch, 0x4C);
				write_index(ch, f);
				write_int(ch, n);
			case A3CallSuperVoid(f, n):
				write_byte(ch, 0x4E);
				write_index(ch, f);
				write_int(ch, n);
			case A3CallPropVoid(f, n):
				write_byte(ch, 0x4F);
				write_index(ch, f);
				write_int(ch, n);
			case A3ApplyType(n):
				write_byte(ch, 0x53);
				write_int(ch, n);
			case A3Object(n):
				write_byte(ch, 0x55);
				write_int(ch, n);
			case A3Array(n):
				write_byte(ch, 0x56);
				write_int(ch, n);
			case A3NewBlock:
				write_byte(ch, 0x57);
			case A3ClassDef(f):
				write_byte(ch, 0x58);
				write_index_nz(ch, f);
			case A3GetDescendants(f):
				write_byte(ch, 0x59);
				write_index(ch, f);
			case A3Catch(n):
				write_byte(ch, 0x5A);
				write_int(ch, n);
			case A3FindPropStrict(f):
				write_byte(ch, 0x5D);
				write_index(ch, f);
			case A3FindProp(f):
				write_byte(ch, 0x5E);
				write_index(ch, f);
			case A3FindDefinition(f):
				write_byte(ch, 0x5F);
				write_index(ch, f);
			case A3GetLex(f):
				write_byte(ch, 0x60);
				write_index(ch, f);
			case A3SetProp(f):
				write_byte(ch, 0x61);
				write_index(ch, f);
			case A3Reg(n):
				if (n >= 0 && n < 4)
					write_byte(ch, 0xD0 + n)
				else {
					write_byte(ch, 0x62);
					write_int(ch, n);
				}
			case A3SetReg(n):
				if (n >= 0 && n < 4)
					write_byte(ch, 0xD4 + n)
				else {
					write_byte(ch, 0x63);
					write_int(ch, n);
				}
			case A3GetGlobalScope:
				write_byte(ch, 0x64);
			case A3GetScope(n):
				write_byte(ch, 0x65);
				write_byte(ch, n);
			case A3GetProp(f):
				write_byte(ch, 0x66);
				write_index(ch, f);
			case A3InitProp(f):
				write_byte(ch, 0x68);
				write_index(ch, f);
			case A3DeleteProp(f):
				write_byte(ch, 0x6A);
				write_index(ch, f);
			case A3GetSlot(n):
				write_byte(ch, 0x6C);
				write_int(ch, n);
			case A3SetSlot(n):
				write_byte(ch, 0x6D);
				write_int(ch, n);
			case A3ToString:
				write_byte(ch, 0x70);
			case A3ToXml:
				write_byte(ch, 0x71);
			case A3ToXmlAttr:
				write_byte(ch, 0x72);
			case A3ToInt:
				write_byte(ch, 0x73);
			case A3ToUInt:
				write_byte(ch, 0x74);
			case A3ToNumber:
				write_byte(ch, 0x75);
			case A3ToBool:
				write_byte(ch, 0x76);
			case A3ToObject:
				write_byte(ch, 0x77);
			case A3CheckIsXml:
				write_byte(ch, 0x78);
			case A3Cast(f):
				write_byte(ch, 0x80);
				write_index(ch, f);
			case A3AsAny:
				write_byte(ch, 0x82);
			case A3AsString:
				write_byte(ch, 0x85);
			case A3AsType(n):
				write_byte(ch, 0x86);
				write_index(ch, n);
			case A3AsObject:
				write_byte(ch, 0x89);
			case A3IncrReg(r):
				write_byte(ch, 0x92);
				write_int(ch, r);
			case A3DecrReg(r):
				write_byte(ch, 0x94);
				write_int(ch, r);
			case A3Typeof:
				write_byte(ch, 0x95);
			case A3InstanceOf:
				write_byte(ch, 0xB1);
			case A3IsType(n):
				write_byte(ch, 0xB2);
				write_index(ch, n);
			case A3IncrIReg(r):
				write_byte(ch, 0xC2);
				write_int(ch, r);
			case A3DecrIReg(r):
				write_byte(ch, 0xC3);
				write_int(ch, r);
			case A3This:
				write_byte(ch, 0xD0);
			case A3SetThis:
				write_byte(ch, 0xD4);
			case A3DebugReg(name, reg, line):
				write_byte(ch, 0xEF);
				write_byte(ch, 0x01);
				write_index(ch, name);
				write_byte(ch, reg - 1);
				write_int(ch, line);
			case A3DebugLine(f):
				write_byte(ch, 0xF0);
				write_int(ch, f);
			case A3DebugFile(f):
				write_byte(ch, 0xF1);
				write_index(ch, f);
			case A3BreakPointLine(l):
				write_byte(ch, 0xF2);
				write_int(ch, l);
			case A3Timestamp:
				write_byte(ch, 0xF3);
			case A3Op(op):
				write_byte(ch, op_id(op));
			case A3Unk(x):
				IO.write(ch, x);
		}
	}
}
