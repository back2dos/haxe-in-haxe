package libs.neko;

import libs.neko.Nast;
import libs.neko.IO;

// port: haxe/libs/neko/binast.ml

/*
 *  Neko Binary AST for OCaml
 *  Copyright (c)2005-2007 Nicolas Cannasse
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
@:structInit private class Context {
	public final ch:haxe.io.Output;
	public var curfile:String;
	public var curline:Int;
	public var scount:Int;
	public final strings:haxe.ds.StringMap<Int>;
}

class Binast {
	static inline function b(ctx:Context, n:Int):Void IO.writeByte(ctx.ch, n);

	static function writeUi24(ctx:Context, n:Int):Void {
		IO.writeByte(ctx.ch, n);
		IO.writeByte(ctx.ch, n >>> 8);
		IO.writeByte(ctx.ch, n >>> 16);
	}

	static function writeString(ctx:Context, s:String):Void {
		var found = ctx.strings.get(s);
		var x = found == null ? -1 : ctx.scount - found;
		if (found != null && !(x > 0xFF)) {
			b(ctx, x);
		} else {
			ctx.strings.set(s, ctx.scount);
			ctx.scount = ctx.scount + 1;
			b(ctx, 0);
			IO.writeUi16(ctx.ch, s.length);
			IO.nwriteString(ctx.ch, s);
		}
	}

	static function writeConstant(ctx:Context, c:Constant):Void {
		switch c {
			case True:
				b(ctx, 0);
			case False:
				b(ctx, 1);
			case Null:
				b(ctx, 2);
			case This:
				b(ctx, 3);
			case Int(n):
				if (n >= 0 && n <= 0xFF) {
					b(ctx, 4);
					b(ctx, n);
				} else {
					b(ctx, 5);
					IO.writeI32(ctx.ch, n);
				}
			case Float(s):
				b(ctx, 6);
				writeString(ctx, s);
			case String(s):
				b(ctx, 7);
				writeString(ctx, s);
			case Builtin(s):
				b(ctx, 8);
				writeString(ctx, s);
			case Ident(s):
				b(ctx, 9);
				writeString(ctx, s);
			case Int32(n):
				b(ctx, 5); /* same as Int */
				IO.writeRealI32(ctx.ch, n);
		}
	}

	static function writeOp(ctx:Context, op:String):Void {
		b(ctx, switch op {
			case "+": 0;
			case "-": 1;
			case "/": 2;
			case "*": 3;
			case "%": 4;
			case "<<": 5;
			case ">>": 6;
			case ">>>": 7;
			case "|": 8;
			case "&": 9;
			case "^": 10;
			case "==": 11;
			case "!=": 12;
			case ">": 13;
			case ">=": 14;
			case "<": 15;
			case "<=": 16;
			case "=": 17;
			case "&&": 18;
			case "||": 19;
			case "++=": 20;
			case "--=": 21;
			case "+=": 22;
			case "-=": 23;
			case "/=": 24;
			case "*=": 25;
			case "%=": 26;
			case "<<=": 27;
			case ">>=": 28;
			case ">>>=": 29;
			case "|=": 30;
			case "&=": 31;
			case "^=": 32;
			case op: throw new core.ds.Failure("Invalid neko ast op " + op);
		});
	}

	static function writeExprOpt(ctx:Context, e:Null<Expr>):Void {
		if (e == null) {
			b(ctx, 0);
		} else {
			b(ctx, 1);
			writeExpr(ctx, e);
		}
	}

	static function writeExpr(ctx:Context, ep:Expr):Void {
		var p = ep.pos;
		if (p.psource != ctx.curfile) {
			b(ctx, 0);
			writeString(ctx, p.psource);
			writeUi24(ctx, p.pline);
			ctx.curfile = p.psource;
			ctx.curline = p.pline;
		} else if (p.pline != ctx.curline) {
			b(ctx, 1);
			writeUi24(ctx, p.pline);
			ctx.curline = p.pline;
		}
		switch ep.decl {
			case EConst(c):
				b(ctx, 2);
				writeConstant(ctx, c);
			case EBlock(el):
				var n = el.length;
				if (n <= 0xFF) {
					b(ctx, 3);
					b(ctx, n);
				} else {
					b(ctx, 4);
					writeUi24(ctx, n);
				}
				for (e in el) writeExpr(ctx, e);
			case EParenthesis(e):
				b(ctx, 5);
				writeExpr(ctx, e);
			case EField(e, f):
				b(ctx, 6);
				writeExpr(ctx, e);
				writeString(ctx, f);
			case ECall(e, el):
				var n = el.length;
				if (n <= 0xFF) {
					b(ctx, 7);
					writeExpr(ctx, e);
					b(ctx, n);
				} else {
					b(ctx, 28);
					writeExpr(ctx, e);
					writeUi24(ctx, n);
				}
				for (e in el) writeExpr(ctx, e);
			case EArray(e1, e2):
				b(ctx, 8);
				writeExpr(ctx, e1);
				writeExpr(ctx, e2);
			case EVars(vl):
				b(ctx, 9);
				b(ctx, vl.length);
				for (v in vl) {
					writeString(ctx, v.name);
					writeExprOpt(ctx, v.expr);
				}
			case EWhile(e1, e2, NormalWhile):
				b(ctx, 10);
				writeExpr(ctx, e1);
				writeExpr(ctx, e2);
			case EWhile(e1, e2, DoWhile):
				b(ctx, 11);
				writeExpr(ctx, e1);
				writeExpr(ctx, e2);
			case EIf(e1, e2, eo):
				b(ctx, 12);
				writeExpr(ctx, e1);
				writeExpr(ctx, e2);
				writeExprOpt(ctx, eo);
			case ETry(e1, v, e2):
				b(ctx, 13);
				writeExpr(ctx, e1);
				writeString(ctx, v);
				writeExpr(ctx, e2);
			case EFunction(pl, e):
				b(ctx, 14);
				b(ctx, pl.length);
				for (p in pl) writeString(ctx, p);
				writeExpr(ctx, e);
			case EBinop(op, e1, e2):
				b(ctx, 15);
				writeOp(ctx, op);
				writeExpr(ctx, e1);
				writeExpr(ctx, e2);
			case EReturn(null):
				b(ctx, 16);
			case EReturn(e):
				b(ctx, 17);
				writeExpr(ctx, e);
			case EBreak(null):
				b(ctx, 18);
			case EBreak(e):
				b(ctx, 19);
				writeExpr(ctx, e);
			case EContinue:
				b(ctx, 20);
			case ENext(e1, e2):
				b(ctx, 21);
				writeExpr(ctx, e1);
				writeExpr(ctx, e2);
			case EObject(fl):
				var n = fl.length;
				if (n <= 0xFF) {
					b(ctx, 22);
					b(ctx, n);
				} else {
					b(ctx, 23);
					writeUi24(ctx, n);
				}
				for (fe in fl) {
					writeString(ctx, fe.name);
					writeExpr(ctx, fe.expr);
				}
			case ELabel(l):
				b(ctx, 24);
				writeString(ctx, l);
			case ESwitch(e, cases, eo):
				var n = cases.length;
				if (n <= 0xFF) {
					b(ctx, 25);
					b(ctx, n);
				} else {
					b(ctx, 26);
					writeUi24(ctx, n);
				}
				writeExpr(ctx, e);
				for (c in cases) {
					writeExpr(ctx, c.e1);
					writeExpr(ctx, c.e2);
				}
				writeExprOpt(ctx, eo);
			case ENeko(s):
				b(ctx, 27);
				writeUi24(ctx, s.length);
				IO.nwriteString(ctx.ch, s);
		}
	}

	public static function write(ch:haxe.io.Output, e:Expr):Void {
		var ctx:Context = {
			ch: ch,
			curfile: "",
			curline: -1,
			scount: 0,
			strings: new haxe.ds.StringMap(),
		};
		IO.nwriteString(ctx.ch, "NBA\x01");
		writeExpr(ctx, e);
	}
}
