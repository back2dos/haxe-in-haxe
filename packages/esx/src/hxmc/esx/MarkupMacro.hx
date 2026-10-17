package hxmc.esx;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.ExprTools;

// The markup macro: a markup literal (Haxe's parser gives
// @:markup "<...>", the source as written from its "<") becomes
//
//   new hxmc.esx.Esx(hxmc.esx.gen.T<n>.template, [value, ...])
//
// where T<n> is a class defined for the literal whose static final
// template is the static part (elements, attributes, text) and the values
// are the holes' expressions in order: {expr} children and attribute
// values, spreads, and components' factories (() -> Name({props})). The
// expressions inside a literal are parsed at their positions in the file
// (errors point into the markup) and transformed in turn, so markup nests
// through them ({[for (i in items) <li>{i}</li>]}).
class MarkupMacro {
	static var count = 0;

	// the Markup interface's build macro: every field's literals
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (fn.expr != null): fn.expr = transform(fn.expr);
				case FVar(t, e) if (e != null): f.kind = FVar(t, transform(e));
				case FProp(g, s, t, e) if (e != null): f.kind = FProp(g, s, t, transform(e));
				case _:
			}
		return fields;
	}

	// e with its markup literals compiled
	public static function transform(e:Expr):Expr
		return switch e.expr {
			case EMeta({name: ":markup"}, {expr: EConst(CString(s))}): compile(s, e.pos);
			case _: e.map(transform);
		}

	// --- one literal ---

	static function compile(src:String, pos:Position):Expr {
		var info = Context.getPosInfos(pos);
		var p = new Parser(src, info.file, info.min);
		var root = p.document();
		var holes:Array<Expr> = [];
		var tree = node(root, holes, info.file, info.min);
		var name = "T" + (count++) + "_" + StringTools.hex(haxe.crypto.Crc32.make(haxe.io.Bytes.ofString(info.file + ":" + info.min)), 8);
		var line = lineOf(info.file, info.min);
		var source = haxe.io.Path.withoutDirectory(info.file) + ":" + line;
		var td = macro class $name {
			public static final template:hxmc.esx.Template = new hxmc.esx.Template($tree, $v{holes.length}, $v{source});
		};
		td.pack = ["hxmc", "esx", "gen"];
		td.pos = pos;
		td.meta = [{name: ":noCompletion", pos: pos}, {name: ":keep", pos: pos}];
		Context.defineType(td);
		var path:TypePath = {pack: ["hxmc", "esx", "gen"], name: name};
		var values = [for (h in holes) macro($h : Any)];
		var tpl = macro $p{["hxmc", "esx", "gen", name, "template"]};
		return macro @:pos(pos) new hxmc.esx.Esx($tpl, ([$a{values}] : Array<Any>));
	}

	// the TNode construction of a parsed node; its holes appended
	static function node(n:PNode, holes:Array<Expr>, file:String, base:Int):Expr {
		inline function str(s:String)
			return macro $v{s};
		return switch n.kind {
			case PText(t):
				macro new hxmc.esx.Template.TNode(hxmc.esx.Template.TKind.Text, ${str(t)}, null, null, -1);
			case PExpr(code, at):
				var e = expr(code, file, base + at);
				if (e == null) return null;
				holes.push(e);
				macro new hxmc.esx.Template.TNode(hxmc.esx.Template.TKind.Hole, null, null, null, $v{holes.length - 1});
			case PFragment(children):
				var cs = [for (c in children) node(c, holes, file, base)].filter(c -> c != null);
				macro new hxmc.esx.Template.TNode(hxmc.esx.Template.TKind.Fragment, null, null, [$a{cs}], -1);
			case PElement(name, attrs, children, at) if (isComponent(name)):
				// a factory calling the component with its props
				var fields:Array<ObjectField> = [];
				for (a in attrs) {
					var ap = position(file, base + a.at, a.name.length);
					var v = switch a.value {
						case AStatic(s): macro @:pos(ap) $v{s};
						case AFlag: macro @:pos(ap) true;
						case AExpr(code, at): expr(code, file, base + at, true);
						case ASpread(_, at): Context.error("markup: a component's props cannot be spread", position(file, base + at, 3));
					}
					// (name_pos: the field name's position, which the compiler reads though ObjectField does not declare it)
					var field:Dynamic = {field: a.name, expr: v, quotes: ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(a.name) ? Unquoted : Quoted, name_pos: ap};
					fields.push(field);
				}
				var kids = [for (c in children) if (!c.kind.match(PExpr(_, _)) || exprNotEmpty(c)) c];
				if (kids.length > 0) {
					// (the content, its own literal: an Esx)
					var sub:Array<Expr> = [];
					var fnode = node({kind: PFragment(kids)}, sub, file, base);
					var cname = "T" + (count++) + "_c";
					var line = lineOf(file, base + at);
					var td = macro class $cname {
						public static final template:hxmc.esx.Template = new hxmc.esx.Template($fnode, $v{sub.length}, $v{haxe.io.Path.withoutDirectory(file) + ":" + line});
					};
					td.pack = ["hxmc", "esx", "gen"];
					td.meta = [{name: ":noCompletion", pos: Context.currentPos()}, {name: ":keep", pos: Context.currentPos()}];
					Context.defineType(td);
					var tpl = macro $p{["hxmc", "esx", "gen", cname, "template"]};
					var subValues = [for (h in sub) macro($h : Any)];
					fields.push({field: "children", expr: macro new hxmc.esx.Esx($tpl, ([$a{subValues}] : Array<Any>))});
				}
				var p = position(file, base + at, name.length + 1);
				var callee = macro @:pos(p) $p{name.split(".")};
				var props = {expr: EObjectDecl(fields), pos: p};
				var call = {expr: ECall(callee, [props]), pos: p};
				holes.push({expr: EFunction(FAnonymous, {args: [], ret: macro :Any, expr: {expr: EReturn(call), pos: p}}), pos: p});
				macro new hxmc.esx.Template.TNode(hxmc.esx.Template.TKind.Component, ${str(name)}, null, null, $v{holes.length - 1});
			case PElement(name, attrs, children, _):
				var as = [
					for (a in attrs)
						switch a.value {
							case AStatic(s):
								macro new hxmc.esx.Template.TAttr(hxmc.esx.Template.TAttrKind.Static, ${str(a.name)}, ${str(s)}, -1);
							case AFlag:
								macro new hxmc.esx.Template.TAttr(hxmc.esx.Template.TAttrKind.Flag, ${str(a.name)}, null, -1);
							case AExpr(code, at):
								holes.push(expr(code, file, base + at, true));
								macro new hxmc.esx.Template.TAttr(hxmc.esx.Template.TAttrKind.Dynamic, ${str(a.name)}, null, $v{holes.length - 1});
							case ASpread(code, at):
								holes.push(expr(code, file, base + at, true));
								macro new hxmc.esx.Template.TAttr(hxmc.esx.Template.TAttrKind.Spread, null, null, $v{holes.length - 1});
						}
				];
				var cs = [for (c in children) node(c, holes, file, base)].filter(c -> c != null);
				macro new hxmc.esx.Template.TNode(hxmc.esx.Template.TKind.Element, ${str(name)}, [$a{as}], [$a{cs}], -1);
		}
	}

	static function exprNotEmpty(c:PNode):Bool
		return switch c.kind {
			case PExpr(code, _): StringTools.trim(stripComments(code)) != "";
			case _: true;
		}

	static function isComponent(name:String):Bool {
		var last = name.split(".").pop();
		return name.indexOf(".") >= 0 || (last.length > 0 && last.charAt(0) == last.charAt(0).toUpperCase() && last.charAt(0) != last.charAt(0).toLowerCase());
	}

	// an embedded expression, parsed at its place in the file and
	// transformed (null: empty, or only comments)
	static function expr(code:String, file:String, at:Int, required = false):Null<Expr> {
		if (StringTools.trim(stripComments(code)) == "") {
			if (required) Context.error("markup: an empty expression", position(file, at - 1, code.length + 2));
			return null;
		}
		var e = Context.parseInlineString(code, position(file, at, code.length));
		return transform(e);
	}

	static function stripComments(s:String):String
		return ~/\/\*[\s\S]*?\*\//g.replace(~/\/\/[^\n]*/g.replace(s, ""), "");

	public static function position(file:String, min:Int, len:Int):Position
		return Context.makePosition({file: file, min: min, max: min + len});

	static final lineCache = new Map<String, Array<Int>>();

	static function lineOf(file:String, offset:Int):Int {
		var starts = lineCache.get(file);
		if (starts == null) {
			starts = [0];
			var content = try sys.io.File.getContent(file) catch (e:Dynamic) "";
			for (i in 0...content.length)
				if (content.charCodeAt(i) == "\n".code) starts.push(i + 1);
			lineCache.set(file, starts);
		}
		var line = 1;
		for (i in 0...starts.length)
			if (starts[i] <= offset) line = i + 1;
		return line;
	}
}

// --- the markup's own syntax ---

enum PKind {
	PElement(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int);
	PFragment(children:Array<PNode>);
	PText(text:String);
	PExpr(code:String, at:Int);
}

typedef PNode = {kind:PKind};
typedef PAttr = {name:String, value:PValue, at:Int};

enum PValue {
	AStatic(s:String);
	AFlag;
	AExpr(code:String, at:Int);
	ASpread(code:String, at:Int);
}

// A recursive-descent parser of a markup literal: elements, fragments,
// attributes (name="text", name='text', name={expr}, name, {...expr}),
// text with entities, {expr} children (balanced braces, strings and
// comments skipped); errors at their offset in the file
class Parser {
	final s:String;
	final file:String;
	final base:Int;
	var i = 0;

	public function new(s:String, file:String, base:Int) {
		this.s = s;
		this.file = file;
		this.base = base;
	}

	function error(msg:String, at:Int, len = 1):Dynamic
		return Context.error("markup: " + msg, MarkupMacro.position(file, base + at, len));

	public function document():PNode {
		var n = element();
		skipSpace();
		if (i < s.length) error("one root element (wrap several in <>...</>)", i);
		return n;
	}

	function element():PNode {
		var start = i;
		expect("<");
		var name = readName();
		if (name == "") {
			expect(">");
			var children = content("");
			return {kind: PFragment(children)};
		}
		var attrs:Array<PAttr> = [];
		while (true) {
			skipSpace();
			if (i >= s.length) error("unterminated <" + name + ">", start, name.length + 1);
			var c = s.charAt(i);
			if (c == "/") {
				i++;
				expect(">");
				return {kind: PElement(name, attrs, [], start + 1)};
			}
			if (c == ">") {
				i++;
				break;
			}
			if (c == "{") {
				var at = i;
				var code = braces();
				var t = StringTools.trim(code);
				if (!StringTools.startsWith(t, "...")) error("an attribute is name={expr}; {...expr} spreads", at, code.length + 2);
				var off = code.indexOf("...") + 3;
				attrs.push({name: "...", value: ASpread(code.substr(off), at + 1 + off), at: at});
				continue;
			}
			var anAt = i;
			var an = readName();
			if (an == "") error("an attribute name", i);
			skipSpace();
			if (i < s.length && s.charAt(i) == "=") {
				i++;
				skipSpace();
				var q = s.charAt(i);
				if (q == '"' || q == "'") {
					var e = s.indexOf(q, i + 1);
					if (e < 0) error("unterminated attribute value", i);
					attrs.push({name: an, value: AStatic(Entities.decode(s.substring(i + 1, e))), at: anAt});
					i = e + 1;
				} else if (q == "{") {
					var at = i + 1;
					var code = braces();
					attrs.push({name: an, value: AExpr(code, at), at: anAt});
				} else error("an attribute value: \"text\" or {expr}", i);
			} else attrs.push({name: an, value: AFlag, at: anAt});
		}
		var children = content(name);
		return {kind: PElement(name, attrs, children, start + 1)};
	}

	// children until </name>
	function content(name:String):Array<PNode> {
		var out:Array<PNode> = [];
		var text = new StringBuf(), hasText = false;
		function flush() {
			if (!hasText) return;
			var t = Whitespace.clean(text.toString());
			if (t != null) out.push({kind: PText(Entities.decode(t))});
			text = new StringBuf();
			hasText = false;
		}
		while (true) {
			if (i >= s.length) error("unterminated <" + name + ">: no </" + name + ">", 0, name.length + 1);
			var c = s.charAt(i);
			if (c == "<") {
				if (s.charAt(i + 1) == "/") {
					flush();
					var at = i;
					i += 2;
					var closing = readName();
					skipSpace();
					expect(">");
					if (closing != name) error("</" + closing + "> closes <" + name + ">", at, closing.length + 3);
					return out;
				}
				flush();
				out.push(element());
			} else if (c == "{") {
				flush();
				var at = i + 1;
				var code = braces();
				out.push({kind: PExpr(code, at)});
			} else {
				text.add(c);
				hasText = true;
				i++;
			}
		}
	}

	// {...}: the code between the braces (balanced; strings, comments and
	// nested markup's text skipped)
	function braces():String {
		var start = i;
		expect("{");
		var depth = 1;
		while (i < s.length) {
			var c = s.charAt(i);
			switch c {
				case "{":
					depth++;
					i++;
				case "}":
					depth--;
					i++;
					if (depth == 0) return s.substring(start + 1, i - 1);
				case '"' | "'":
					i++;
					while (i < s.length && s.charAt(i) != c) {
						if (s.charAt(i) == "\\") i++;
						i++;
					}
					i++;
				case "/" if (s.charAt(i + 1) == "/"):
					while (i < s.length && s.charAt(i) != "\n")
						i++;
				case "/" if (s.charAt(i + 1) == "*"):
					var e = s.indexOf("*/", i + 2);
					i = e < 0 ? s.length : e + 2;
				case _:
					i++;
			}
		}
		return error("unterminated {", start);
	}

	function readName():String {
		var start = i;
		while (i < s.length) {
			var c = s.charCodeAt(i);
			var ok = (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == ":".code
				|| (i > start && ((c >= "0".code && c <= "9".code) || c == "-".code || c == ".".code));
			if (!ok) break;
			i++;
		}
		return s.substring(start, i);
	}

	function skipSpace() {
		while (i < s.length && StringTools.isSpace(s, i))
			i++;
	}

	function expect(c:String) {
		if (s.substr(i, c.length) != c) error('"$c" expected', i);
		i += c.length;
	}
}

// JSX's rule for text between tags: lines trimmed (the first line's start
// and the last's end kept), lines empty after that dropped, the rest joined
// with one space; null when nothing is left
class Whitespace {
	public static function clean(t:String):Null<String> {
		var lines = t.split("\n");
		var out = [];
		for (k in 0...lines.length) {
			var l = StringTools.replace(lines[k], "\t", " ");
			if (k > 0) l = StringTools.ltrim(l);
			if (k < lines.length - 1) l = StringTools.rtrim(l);
			if (lines.length > 1 && StringTools.trim(l) == "") continue;
			out.push(l);
		}
		var r = out.join(" ");
		return r == "" ? null : r;
	}
}

class Entities {
	public static function decode(s:String):String {
		if (s.indexOf("&") < 0) return s;
		return ~/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g.map(s, r -> {
			var e = r.matched(1);
			if (StringTools.startsWith(e, "#x")) return String.fromCharCode(Std.parseInt("0x" + e.substr(2)));
			if (StringTools.startsWith(e, "#")) return String.fromCharCode(Std.parseInt(e.substr(1)));
			return switch e {
				case "amp": "&";
				case "lt": "<";
				case "gt": ">";
				case "quot": '"';
				case "apos": "'";
				case "nbsp": " ";
				case "lbrace": "{";
				case "rbrace": "}";
				case _: r.matched(0);
			}
		});
	}
}
#end
