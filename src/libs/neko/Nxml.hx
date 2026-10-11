package libs.neko;

import libs.neko.Nast;

// port: haxe/libs/neko/nxml.ml

/*
 *  Neko NXML for OCaml
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
enum Xml {
	Node(name:String, att:Array<{a:String, v:String}>, childs:Array<Xml>);
	CData(s:String);
}

class Nxml {
	public static function node(name:String, att:Array<{a:String, v:String}>, childs:Array<Xml>):Xml return Node(name, att, childs);

	static function toXmlRec(p2:Pos, ast:Expr):Xml {
		var e = ast.decl, p = ast.pos;
		var name = "";
		var aval:Null<String> = null;
		var childs:Array<Xml> = [];
		switch e {
			case EConst(c):
				switch c {
					case True | False | Null | This | Builtin(_) | Ident(_):
						name = "v";
						aval = Nast.sConstant(c);
					case Int(i):
						name = "i";
						aval = Std.string(i);
					case Float(s):
						name = "f";
						aval = s;
					case String(s):
						name = "s";
						aval = s;
					case Int32(i):
						name = "i";
						aval = Std.string(i);
				}
			case EBlock(el):
				name = "b";
				childs = el.map(toXmlRec.bind(p));
			case EParenthesis(e):
				name = "p";
				childs = [toXmlRec(p, e)];
			case EField(e, f):
				name = "g";
				aval = f;
				childs = [toXmlRec(p, e)];
			case ECall(e, el):
				name = "c";
				childs = [toXmlRec(p, e)].concat(el.map(toXmlRec.bind(p)));
			case EArray(a, b):
				name = "a";
				childs = [toXmlRec(p, a), toXmlRec(p, b)];
			case EVars(vl):
				name = "var";
				childs = vl.map(v -> node("v", [{a: "v", v: v.name}], (v.expr == null ? [] : [toXmlRec(p, v.expr)])));
			case EWhile(econd, e, NormalWhile):
				name = "while";
				childs = [toXmlRec(p, econd), toXmlRec(p, e)];
			case EWhile(econd, e, DoWhile):
				name = "do";
				childs = [toXmlRec(p, e), toXmlRec(p, econd)];
			case EIf(cond, e, eelse):
				name = "if";
				childs = [toXmlRec(p, cond), toXmlRec(p, e)].concat(eelse == null ? [] : [toXmlRec(p, eelse)]);
			case ETry(e1, v, e2):
				name = "try";
				aval = v;
				childs = [toXmlRec(p, e1), toXmlRec(p, e2)];
			case EFunction(args, e):
				name = "function";
				aval = args.join(":");
				childs = [toXmlRec(p, e)];
			case EBinop(op, e1, e2):
				name = "o";
				aval = op;
				childs = [toXmlRec(p, e1), toXmlRec(p, e2)];
			case EReturn(e):
				name = "return";
				childs = (e == null ? [] : [toXmlRec(p, e)]);
			case EBreak(e):
				name = "break";
				childs = (e == null ? [] : [toXmlRec(p, e)]);
			case EContinue:
				name = "continue";
			case ENext(e1, e2):
				name = "next";
				childs = [toXmlRec(p, e1), toXmlRec(p, e2)];
			case EObject(fl):
				name = "object";
				childs = fl.map(f -> node("v", [{a: "v", v: f.name}], [toXmlRec(p, f.expr)]));
			case ELabel(v):
				name = "label";
				aval = v;
			case ESwitch(e, cases, def):
				name = "switch";
				var cases = cases.map(c -> node("case", [], [toXmlRec(p, c.e1), toXmlRec(p, c.e2)]));
				childs = [toXmlRec(p, e)].concat(def == null ? cases : [node("default", [], [toXmlRec(p, def)])].concat(cases));
			case ENeko(s):
				name = "neko";
				childs = [CData(s)];
		}
		var pos = (if (p.psource != p2.psource) [{a: "p", v: p.psource + ":" + Std.string(p.pline)}] else if (p.pline != p2.pline)
			[{a: "p", v: Std.string(p.pline)}] else []);
		var aval = (aval == null ? [] : [{a: "v", v: aval}]);
		return node(name, pos.concat(aval), childs);
	}

	public static function toXml(ast:Expr):Xml return toXmlRec(Nast.nullPos, ast);

	static function attributes(att:Array<{a:String, v:String}>):String return att.map(x -> " " + x.a + "=\"" + Nast.escape(x.v) + "\"").join("");

	static function writeFmtRec(tabs:String, ch:haxe.io.Output, x:Xml):Void {
		switch x {
			case CData(s):
				IO.nwriteString(ch, tabs + "<![CDATA[" + s + "]]>");
			case Node(name, att, childs):
				IO.nwriteString(ch, tabs + "<" + name + attributes(att));
				switch childs {
					case []:
						IO.nwriteString(ch, "/>");
					case l:
						IO.nwriteString(ch, ">\n");
						for (x in l) {
							writeFmtRec(tabs + " ", ch, x);
							IO.writeByte(ch, '\n'.code);
						}
						IO.nwriteString(ch, tabs + "</" + name + ">");
				}
		}
	}

	public static function writeFmt(ch:haxe.io.Output, x:Xml):Void writeFmtRec("", ch, node("nxml", [], [x]));

	static function writeRec(ch:haxe.io.Output, x:Xml):Void {
		switch x {
			case CData(s):
				IO.nwriteString(ch, "<![CDATA[" + s + "]]>");
			case Node(name, att, childs):
				IO.nwriteString(ch, "<" + name + attributes(att));
				switch childs {
					case []:
						IO.nwriteString(ch, "/>");
					case l:
						IO.nwriteString(ch, ">");
						for (x in l) writeRec(ch, x);
						IO.nwriteString(ch, "</" + name + ">");
				}
		}
	}

	public static function write(ch:haxe.io.Output, x:Xml):Void writeRec(ch, node("nxml", [], [x]));
}
