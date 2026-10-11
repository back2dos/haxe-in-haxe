/*
 * Copyright (C)2005-2016 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package generators;

import core.ds.Failure;
import generators.Hlcode;
import generators.Hlcode.*;

// port: only `check` (used by genhl with -D hl-check) is translated; the
// interpreter itself (create, add_code, ...) is not ported and Genhl fails
// explicitly on -D interp.
class Hlinterp {
	public static function check(comerror:String->core.Globals.Pos->Void, code:Code):Void {
		var ftypes = [for (_ in 0...code.natives.length + code.functions.length) HVoid];
		var isNativeFun = new haxe.ds.IntMap<Bool>();

		function checkFun(f:Fundecl):Void {
			var pos = 0;
			function error(msg:String):Void {
				var dpos = f.debug[pos].pos;
				var msg = "Check failure at fun@" + f.findex + " @" + hex(pos) + " - " + msg;
				comerror(msg, dpos);
			}
			function errorFail(msg:String):Dynamic {
				error(msg);
				throw new Failure(msg);
			}
			var targs, tret;
			switch f.ftype {
				case HFun(args, ret):
					targs = args;
					tret = ret;
				case _:
					targs = core.Globals.die("", "hlinterp.ml");
					tret = null;
			}
			function rtype(i:Int):Ttype {
				if (i >= 0 && i < f.regs.length) return f.regs[i];
				var p = new ClassProto("OUT_OF_BOUNDS:" + i, 0);
				return HObj(p);
			}
			function check(t1:Ttype, t2:Ttype):Void {
				if (!safeCast(t1, t2)) error(tstr(t1) + " should be " + tstr(t2));
			}
			function regInf(r:Int):String return "Register " + r + "(" + tstr(rtype(r)) + ")";
			function reg(r:Int, t:Ttype):Void {
				if (!safeCast(rtype(r), t)) error(regInf(r) + " should be " + tstr(t) + " and not " + tstr(rtype(r)));
			}
			function numeric(r:Int):Void {
				if (!isNumber(rtype(r))) error(regInf(r) + " should be numeric");
			}
			function int(r:Int):Void {
				if (!isInt(rtype(r))) error(regInf(r) + " should be integral");
			}
			function float(r:Int):Void {
				if (!isFloat(rtype(r))) error(regInf(r) + " should be float");
			}
			function call(f:Int, args:Array<Int>, r:Int):Void {
				switch ftypes[f] {
					case HFun(targs, tret):
						if (args.length != targs.length) error(tstr(HFun([for (a in args) rtype(a)], rtype(r))) + " should be " + tstr(ftypes[f]));
						if (args.length != targs.length) throw new core.ds.InvalidArgument("List.iter2");
						for (i in 0...args.length) reg(args[i], targs[i]);
						check(tret, rtype(r));
					case _:
						core.Globals.die("", "hlinterp.ml");
				}
			}
			function canJump(delta:Int):Void {
				if (pos + 1 + delta < 0 || pos + 1 + delta >= f.code.length) error("Jump outside function bounds");
				if (delta < 0 && !f.code[pos + 1 + delta].match(OLabel(0))) error("Jump back without Label");
			}
			function isObj(r:Int):Void {
				switch rtype(r) {
					case HObj(_):
					case _: error(regInf(r) + " should be object");
				}
			}
			function isEnum(r:Int):Void {
				switch rtype(r) {
					case HEnum(_):
					case _: error(regInf(r) + " should be enum");
				}
			}
			function isDyn(r:Int):Void {
				if (!isDynamic(rtype(r))) error(regInf(r) + " should be castable to dynamic");
			}
			function getField(r:Int, p:ClassProto, fid:Int):Ttype {
				return try resolveField(p, fid).t catch (_:core.ds.NotFound) errorFail(regInf(r) + " does not have field " + fid);
			}
			function tfield(o:Int, fid:Int, proto:Bool):Ttype {
				if (fid < 0) error(regInf(o) + " does not have " + (if (proto) "proto " else "") + "field " + fid);
				return switch rtype(o) {
					case HObj(p):
						if (proto) ftypes[p.pvirtuals[fid]] else getField(o, p, fid);
					case HStruct(p) if (!proto):
						getField(o, p, fid);
					case HVirtual(v) if (!proto):
						v.vfields[fid].t;
					case _:
						isObj(o);
						HVoid;
				}
			}
			function iter2(rl:Array<Int>, tl:Array<Ttype>):Void {
				if (rl.length != tl.length) throw new core.ds.InvalidArgument("List.iter2");
				for (i in 0...rl.length) reg(rl[i], tl[i]);
			}
			for (i in 0...targs.length) reg(i, targs[i]);
			for (i in 0...f.code.length) {
				var op = f.code[i];
				pos = i;
				switch op {
					case OMov(a, b):
						reg(b, rtype(a));
					case OInt(r, i):
						if (i < 0 || i >= code.ints.length) throw new core.ds.InvalidArgument("index out of bounds");
						int(r);
					case OFloat(r, i):
						if (!tEq(rtype(r), HF32)) reg(r, HF64);
						if (i < 0 || i >= code.floats.length) error("float outside range");
					case OBool(r, _):
						reg(r, HBool);
					case OString(r, i):
						reg(r, HBytes);
						if (i < 0 || i >= code.strings.length) error("string outside range");
					case OBytes(r, i):
						reg(r, HBytes);
						if (i < 0 || i >= code.bytes.length) error("bytes outside range");
					case ONull(r):
						var t = rtype(r);
						if (!isNullable(t)) error(tstr(t) + " is not nullable");
					case OAdd(r, a, b) | OSub(r, a, b) | OMul(r, a, b) | OSDiv(r, a, b) | OUDiv(r, a, b) | OSMod(r, a, b) | OUMod(r, a, b):
						numeric(r);
						reg(a, rtype(r));
						reg(b, rtype(r));
					case ONeg(r, a):
						numeric(r);
						reg(a, rtype(r));
					case OShl(r, a, b) | OSShr(r, a, b) | OUShr(r, a, b) | OAnd(r, a, b) | OOr(r, a, b) | OXor(r, a, b):
						int(r);
						reg(a, rtype(r));
						reg(b, rtype(r));
					case OIncr(r):
						int(r);
					case ODecr(r):
						int(r);
					case ONot(a, b):
						reg(a, HBool);
						reg(b, HBool);
					case OCall0(r, f):
						call(f, [], r);
					case OCall1(r, f, a):
						call(f, [a], r);
					case OCall2(r, f, a, b):
						call(f, [a, b], r);
					case OCall3(r, f, a, b, c):
						call(f, [a, b, c], r);
					case OCall4(r, f, a, b, c, d):
						call(f, [a, b, c, d], r);
					case OCallN(r, f, rl):
						call(f, rl, r);
					case OCallThis(r, m, rl):
						switch tfield(0, m, true) {
							case HFun(args, tret) if (args.length > 0 && args.length - 1 == rl.length):
								reg(0, args[0]);
								iter2(rl, args.slice(1));
								check(tret, rtype(r));
							case t:
								check(t, HFun([rtype(0)].concat([for (r in rl) rtype(r)]), rtype(r)));
						}
					case OCallMethod(r, m, rl):
						if (rl.length == 0) core.Globals.die("", "hlinterp.ml");
						var obj = rl[0], rl2 = rl.slice(1);
						function checkArgs(targs:Array<Ttype>, tret:Ttype, rl:Array<Int>):Bool {
							if (targs.length != rl.length) return false;
							iter2(rl, targs);
							check(tret, rtype(r));
							return true;
						}
						switch rtype(obj) {
							case HVirtual(v):
								var t = v.vfields[m].t;
								switch t {
									case HMethod(args, ret) if (checkArgs(args, ret, rl2)):
									case _: check(t, HMethod([for (r in rl) rtype(r)], rtype(r)));
								}
							case _:
								var t = tfield(obj, m, true);
								switch t {
									case HFun(args, ret) if (checkArgs(args, ret, rl)):
									case _: check(t, HFun([for (r in rl) rtype(r)], rtype(r)));
								}
						}
					case OCallClosure(r, f, rl):
						switch rtype(f) {
							case HFun(targs, tret) if (targs.length == rl.length):
								iter2(rl, targs);
								check(tret, rtype(r));
							case HDyn:
								for (r in rl) rtype(r);
							case _:
								reg(f, HFun([for (r in rl) rtype(r)], rtype(r)));
						}
					case OGetGlobal(r, g):
						if (!safeCast(code.globals[g], rtype(r))) reg(r, code.globals[g]);
					case OSetGlobal(g, r):
						reg(r, code.globals[g]);
					case ORet(r):
						reg(r, tret);
					case OJTrue(r, delta) | OJFalse(r, delta):
						reg(r, HBool);
						canJump(delta);
					case OJNull(r, delta) | OJNotNull(r, delta):
						if (!isNullable(rtype(r))) reg(r, HDyn);
						canJump(delta);
					case OJUGte(a, b, delta) | OJULt(a, b, delta) | OJSGte(a, b, delta) | OJSLt(a, b, delta) | OJSGt(a, b, delta) | OJSLte(a, b, delta) |
						OJNotLt(a, b, delta) | OJNotGte(a, b, delta):
						if (!safeCast(rtype(a), rtype(b))) reg(b, rtype(a));
						canJump(delta);
					case OJEq(a, b, delta) | OJNotEq(a, b, delta):
						switch [rtype(a), rtype(b)] {
							case [HObj(_) | HVirtual(_), HObj(_) | HVirtual(_)]:
							case [HDyn | HFun(_), HDyn | HFun(_)]:
							case [ta, tb] if (safeCast(tb, ta)):
							case _: reg(a, rtype(b));
						}
						canJump(delta);
					case OJAlways(d):
						canJump(d);
					case OToDyn(r, a):
						/* we can still use OToDyn on nullable if we want to turn them into dynamic */
						if (isDynamic(rtype(a))) reg(a, HI32); /* don't wrap as dynamic types that can safely be cast to it */
						if (!tEq(rtype(r), HDyn)) reg(r, HNull(rtype(a)));
					case OToSFloat(a, b) | OToUFloat(a, b):
						float(a);
						switch rtype(b) {
							case HF32 | HF64:
							case _: int(b);
						}
					case OToInt(a, b):
						int(a);
						switch rtype(b) {
							case HF32 | HF64:
							case _: int(b);
						}
					case OLabel(_):
					case ONew(r):
						switch rtype(r) {
							case HDynObj | HVirtual(_) | HStruct(_):
							case _: isObj(r);
						}
					case OField(r, o, fid):
						check(tfield(o, fid, false), rtype(r));
					case OSetField(o, fid, r):
						reg(r, tfield(o, fid, false));
					case OGetThis(r, fid):
						check(tfield(0, fid, false), rtype(r));
					case OSetThis(fid, r):
						reg(r, tfield(0, fid, false));
					case OStaticClosure(r, f):
						reg(r, ftypes[f]);
					case OVirtualClosure(r, o, fid):
						switch rtype(o) {
							case HObj(_):
								switch tfield(o, fid, true) {
									case HFun(tl, tret) if (tl.length > 0):
										reg(o, tl[0]);
										reg(r, HFun(tl.slice(1), tret));
									case _:
										core.Globals.die("", "hlinterp.ml");
								}
							case _:
								isObj(o);
						}
					case OInstanceClosure(r, f, arg):
						switch ftypes[f] {
							case HFun(tl, tret) if (tl.length > 0):
								var t = tl[0];
								reg(arg, t);
								if (!isNullable(t)) error(regInf(r) + " should be nullable");
								reg(r, HFun(tl.slice(1), tret));
							case _:
								core.Globals.die("", "hlinterp.ml");
						}
					case OThrow(r):
						reg(r, HDyn);
					case ORethrow(r):
						reg(r, HDyn);
					case OGetArray(v, a, i):
						switch rtype(a) {
							case HAbstract("hl_carray", _, _) | HArray(_):
							case _: reg(a, HArray(HDyn));
						}
						reg(i, HI32);
						rtype(v);
					case OGetUI8(r, b, p) | OGetUI16(r, b, p):
						reg(r, HI32);
						reg(b, HBytes);
						reg(p, HI32);
					case OGetMem(r, b, p):
						var t = rtype(r);
						switch getGroup(t) {
							case GInt | GFloat if (typeSizeBits(t) >= 2):
							case _: error(regInf(r) + " should be numeric");
						}
						reg(b, HBytes);
						reg(p, HI32);
					case OSetUI8(r, p, v) | OSetUI16(r, p, v):
						reg(r, HBytes);
						reg(p, HI32);
						reg(v, HI32);
					case OSetMem(r, p, v):
						reg(r, HBytes);
						reg(p, HI32);
						var t = rtype(v);
						switch getGroup(t) {
							case GInt | GFloat if (typeSizeBits(t) >= 2):
							case _: error(regInf(r) + " should be numeric");
						}
					case OSetArray(a, i, v):
						switch rtype(a) {
							case HAbstract("hl_carray", _, _) | HArray(_):
							case _: reg(a, HArray(HDyn));
						}
						reg(i, HI32);
						rtype(v);
					case OUnsafeCast(a, b) | OSafeCast(a, b):
						rtype(a);
						rtype(b);
					case OArraySize(r, a):
						reg(r, HI32);
					case OType(r, _):
						reg(r, HType);
					case OGetType(r, v):
						reg(r, HType);
						isDyn(v);
					case OGetTID(r, v):
						reg(r, HI32);
						reg(v, HType);
					case OUnref(v, r):
						switch rtype(r) {
							case HRef(t): check(t, rtype(v));
							case _: reg(r, HRef(rtype(v)));
						}
					case ORef(r, v) | OSetref(r, v):
						switch rtype(r) {
							case HRef(t): reg(v, t);
							case _: reg(r, HRef(rtype(v)));
						}
					case OToVirtual(r, v):
						switch rtype(r) {
							case HVirtual(_):
							case _: reg(r, HVirtual(new VirtualProto()));
						}
						switch rtype(v) {
							case HObj(_) | HDynObj | HDyn | HVirtual(_):
							case _: reg(v, HDynObj);
						}
					case ODynGet(v, r, f) | ODynSet(r, f, v):
						if (f < 0 || f >= code.strings.length) throw new core.ds.InvalidArgument("index out of bounds");
						rtype(v);
						switch rtype(r) {
							case HObj(_) | HDyn | HDynObj | HVirtual(_):
							case _: reg(r, HDynObj);
						}
					case OMakeEnum(r, index, pl):
						switch rtype(r) {
							case HEnum(e):
								var fl = e.efields[index].args;
								if (fl.length != pl.length) error("MakeEnum has " + pl.length + " params while " + fl.length + " are required");
								iter2(pl, fl);
							case _:
								isEnum(r);
						}
					case OEnumAlloc(r, index):
						switch rtype(r) {
							case HEnum(e):
								if (index < 0 || index >= e.efields.length) throw new core.ds.InvalidArgument("index out of bounds");
							case _:
								isEnum(r);
						}
					case OEnumIndex(r, v):
						if (!tEq(rtype(v), HDyn)) isEnum(v);
						reg(r, HI32);
					case OEnumField(r, e, f, i):
						switch rtype(e) {
							case HEnum(e):
								var tl = e.efields[f].args;
								check(tl[i], rtype(r));
							case _:
								isEnum(e);
						}
					case OSetEnumField(e, i, r):
						switch rtype(e) {
							case HEnum(e):
								var tl = e.efields[0].args;
								check(rtype(r), tl[i]);
							case _:
								isEnum(e);
						}
					case OSwitch(r, idx, eend):
						reg(r, HI32);
						for (d in idx) canJump(d);
						if (eend + 1 + i != f.code.length) canJump(eend);
					case ONullCheck(r):
						rtype(r);
					case OTrap(r, idx):
						reg(r, HDyn);
						canJump(idx);
					case OEndTrap(_):
					case OAssert(_):
					case ORefData(r, d):
						switch rtype(r) {
							case HRef(t):
								reg(d, HArray(t));
							case _:
								reg(d, HArray(HDyn));
								reg(r, HRef(HDyn));
						}
					case ORefOffset(r, r2, off):
						switch rtype(r2) {
							case HRef(_):
							case _: reg(r2, HRef(HDyn));
						}
						reg(r, rtype(r2));
						reg(off, HI32);
					case ONop(_):
					case OPrefetch(r, f, _):
						if (f == 0) rtype(r) else tfield(r, f - 1, false);
					case OAsm(_, _, r):
						if (r > 0) rtype(r - 1);
					case OCatch(_):
				}
			}
			/* TODO : check that all path correctly initialize NULL values and reach a return */
		}
		for (fd in code.functions) {
			if (fd.findex >= ftypes.length) throw new Failure("Invalid function index " + fd.findex);
			if (!tEq(ftypes[fd.findex], HVoid)) throw new Failure("Duplicate function bind " + fd.findex + " " + fundeclName(fd));
			ftypes[fd.findex] = fd.ftype;
		}
		for (n in code.natives) {
			if (n.findex >= ftypes.length)
				throw new Failure("Invalid native function index " + n.findex + " for " + code.strings[n.lib] + "@" + code.strings[n.name]);
			if (!tEq(ftypes[n.findex], HVoid)) throw new Failure("Duplicate native function bind " + n.findex);
			isNativeFun.set(n.findex, true);
			ftypes[n.findex] = n.t;
		}
		/* TODO : check that no object type has a virtual native in his proto */
		for (f in code.functions) checkFun(f);
	}
}
