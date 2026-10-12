/*
 *  Neko AST for OCaml
 *  Copyright (c)2005 Nicolas Cannasse
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

package libs.neko;

// port: haxe/libs/neko/nast.ml (the Neko AST). OCaml strings are byte strings: every
// string held by this AST is a Haxe string whose characters are bytes (0..255), so that
// lengths, substrings, hashing and comparisons are byte-wise as upstream. The writers
// output each character as one byte. Producers (genneko) encode their UTF-8 text once.

/*
 *  Neko AST for OCaml
 *  Copyright (c)2005 Nicolas Cannasse
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
@:structInit final class Pos {
	public final psource:String;
	public final pline:Int;

	public inline function new(psource:String, pline:Int) {
		this.psource = psource;
		this.pline = pline;
	}

	// port: OCaml structural equality on the record.
	public inline function equals(p:Pos):Bool return psource == p.psource && pline == p.pline;
}

enum Constant {
	True;
	False;
	Null;
	This;
	Int(i:Int);
	Float(s:String);
	String(s:String);
	Builtin(s:String);
	Ident(s:String);
	Int32(i:Int);
}

enum WhileFlag {
	NormalWhile;
	DoWhile;
}

enum ExprDecl {
	EConst(c:Constant);
	EBlock(el:Array<Expr>);
	EParenthesis(e:Expr);
	EField(e:Expr, f:String);
	ECall(e:Expr, el:Array<Expr>);
	EArray(e1:Expr, e2:Expr);
	EVars(vl:Array<{name:String, expr:Null<Expr>}>);
	EWhile(e1:Expr, e2:Expr, flag:WhileFlag);
	EIf(e:Expr, e1:Expr, e2:Null<Expr>);
	ETry(e:Expr, v:String, e2:Expr);
	EFunction(params:Array<String>, e:Expr);
	EBinop(op:String, e1:Expr, e2:Expr);
	EReturn(e:Null<Expr>);
	EBreak(e:Null<Expr>);
	EContinue;
	ENext(e1:Expr, e2:Expr);
	EObject(fl:Array<{name:String, expr:Expr}>);
	ELabel(l:String);
	ESwitch(e:Expr, cases:Array<{e1:Expr, e2:Expr}>, def:Null<Expr>);
	ENeko(s:String);
}

// port: `expr = expr_decl * pos`.
@:structInit final class Expr {
	public final decl:ExprDecl;
	public final pos:Pos;

	public inline function new(decl:ExprDecl, pos:Pos) {
		this.decl = decl;
		this.pos = pos;
	}
}

class Nast {
	public static inline function pos(e:Expr):Pos return e.pos;

	public static final nullPos:Pos = {pline: 0, psource: "<null pos>"};

	public static function mkCall(v:Expr, args:Array<Expr>, p:Pos):Expr return new Expr(ECall(v, args), p);

	public static function mkCall0(v:Expr, p:Pos):Expr return new Expr(ECall(v, []), p);

	public static function mkCall1(v:Expr, a:Expr, p:Pos):Expr return new Expr(ECall(v, [a]), p);

	public static function mkIdent(i:String, p:Pos):Expr return new Expr(EConst(Ident(i)), p);

	public static function mkBuiltin(b:String, p:Pos):Expr return new Expr(EConst(Builtin(b)), p);

	public static function mkInt(i:Int, p:Pos):Expr return new Expr(EConst(Int(i)), p);

	public static function mkString(s:String, p:Pos):Expr return new Expr(EConst(String(s)), p);

	public static function mkBinop(op:String, e1:Expr, e2:Expr, p:Pos):Expr return new Expr(EBinop(op, e1, e2), p);

	public static function map(f:Expr->Expr, ep:Expr):Expr {
		var decl = switch ep.decl {
			case EBlock(el): EBlock(el.map(f));
			case EParenthesis(e): EParenthesis(f(e));
			case EField(e, s): EField(f(e), s);
			case ECall(e, el): ECall(f(e), el.map(f));
			case EArray(e1, e2): EArray(f(e1), f(e2));
			case EVars(vl): EVars(vl.map(v -> {name: v.name, expr: v.expr == null ? null : f(v.expr)}));
			case EWhile(e1, e2, flag): EWhile(f(e1), f(e2), flag);
			case EIf(e, e1, e2): EIf(f(e), f(e1), e2 == null ? null : f(e2));
			case ETry(e, ident, e2): ETry(f(e), ident, f(e2));
			case EFunction(params, e): EFunction(params, f(e));
			case EBinop(op, e1, e2): EBinop(op, f(e1), f(e2));
			case EReturn(e) if (e != null): EReturn(f(e));
			case EBreak(e) if (e != null): EBreak(f(e));
			case ENext(e1, e2): ENext(f(e1), f(e2));
			case EObject(fl): EObject(fl.map(fe -> {name: fe.name, expr: f(fe.expr)}));
			case ESwitch(e, cases, def): ESwitch(f(e), cases.map(c -> {e1: f(c.e1), e2: f(c.e2)}), def == null ? null : f(def));
			case EReturn(_) | EBreak(_) | EContinue | ENeko(_) | ELabel(_) | EConst(_): ep.decl;
		}
		return new Expr(decl, ep.pos);
	}

	public static function iter(f:Expr->Void, ep:Expr):Void {
		switch ep.decl {
			case EBlock(el):
				for (e in el) f(e);
			case EParenthesis(e):
				f(e);
			case EField(e, s):
				f(e);
			case ECall(e, el):
				f(e);
				for (e in el) f(e);
			case EArray(e1, e2):
				f(e1);
				f(e2);
			case EVars(vl):
				for (v in vl) if (v.expr != null) f(v.expr);
			case EWhile(e1, e2, _):
				f(e1);
				f(e2);
			case EIf(e, e1, e2):
				f(e);
				f(e1);
				if (e2 != null) f(e2);
			case ETry(e1, _, e2):
				f(e1);
				f(e2);
			case EFunction(_, e):
				f(e);
			case EBinop(_, e1, e2):
				f(e1);
				f(e2);
			case EReturn(e) if (e != null):
				f(e);
			case EBreak(e) if (e != null):
				f(e);
			case ENext(e1, e2):
				f(e1);
				f(e2);
			case EObject(fl):
				for (fe in fl) f(fe.expr);
			case ESwitch(e, cases, def):
				f(e);
				for (c in cases) {
					f(c.e1);
					f(c.e2);
				}
				if (def != null) f(def);
			case EReturn(_) | EBreak(_) | EContinue | ENeko(_) | ELabel(_) | EConst(_):
		}
	}

	public static inline function isPrintable(c:Int):Bool return c >= 32 && c <= 126;

	public static function escape(s:String):String {
		var b = new StringBuf();
		for (i in 0...s.length) {
			switch StringTools.fastCodeAt(s, i) {
				case '\n'.code:
					b.add("\\n");
				case '\t'.code:
					b.add("\\t");
				case '\r'.code:
					b.add("\\r");
				case '\\'.code:
					b.add("\\\\");
				case c if (c == '"'.code || !isPrintable(c)):
					// port: Printf "\\%.3d"
					b.add("\\" + StringTools.lpad(Std.string(c), "0", 3));
				case c:
					b.addChar(c);
			}
		}
		return b.toString();
	}

	public static function sConstant(c:Constant):String return switch c {
		case True: "true";
		case False: "false";
		case Null: "null";
		case This: "this";
		case Int(i): Std.string(i);
		case Float(s): s;
		case String(s): "\"" + escape(s) + "\"";
		case Builtin(s): "$" + s;
		case Ident(s): s;
		case Int32(i): Std.string(i);
	}
}
