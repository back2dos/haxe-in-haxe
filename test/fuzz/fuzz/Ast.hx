package fuzz;

/**
	The generated program as a tree of source templates.

	Every expression, statement and declaration is a `Node`: a list of literal
	source strings, child nodes and child blocks. Expression nodes carry their
	type, so the reducer can replace any of them with a default value of that
	type or with a child of the same type, and remove any element of a block,
	without knowing what construct the node is.
**/
enum Part {
	S(s:String);
	N(n:Node);
	B(b:Block);
}

class Node {
	public var parts:Array<Part>;

	/** Type of an expression node; null for statements and declarations. **/
	public var ty:Null<Ty>;

	/** Pinned nodes are never removed or replaced by the reducer. **/
	public var pinned:Bool = false;

	public function new(parts:Array<Part>, ?ty:Ty) {
		this.parts = parts;
		this.ty = ty;
	}
}

class Block {
	public var items:Array<Node>;

	/** Printed as `{ ... }` with one item per line; otherwise items are separated by blank lines. **/
	public var braces:Bool;

	public function new(items:Array<Node>, braces = true) {
		this.items = items;
		this.braces = braces;
	}
}

class Module {
	/** Path relative to the source root, e.g. `p/M1.hx`. **/
	public var path:String;

	public var header:String;
	public var body:Block;

	public function new(path:String, header:String, body:Block) {
		this.path = path;
		this.header = header;
		this.body = body;
	}
}

class Program {
	public var modules:Array<Module> = [];
	public var seed:Int;

	/** Generator features this program was built with (swarm testing). **/
	public var features:Array<String> = [];

	public function new(seed:Int) {
		this.seed = seed;
	}

	public function files():Array<{path:String, text:String}> {
		return [for (m in modules) {path: m.path, text: Printer.module(m)}];
	}
}

enum Ty {
	TInt;
	TFloat;
	TBool;
	TString;
	TVoid;
	TDyn;
	TArray(t:Ty);
	TNull(t:Ty);
	TFun(args:Array<Ty>, ret:Ty);
	TInst(c:ClassDef, params:Array<Ty>);
	TEnum(e:EnumDef);
	TAnon(a:AnonDef);
	TAbs(a:AbsDef);
	TEnumAbs(a:EnumAbsDef);
	TMap(k:Ty, v:Ty);
}

class FnDef {
	public var name:String;
	public var owner:ClassDef;
	public var isStatic:Bool;
	public var args:Array<ArgDef>;
	public var ret:Ty;
	public var index:Int;
	public var tier0:Bool;
	public var isInline:Bool = false;

	/** Declared in an interface or as `abstract`: no body here. **/
	public var isAbstract:Bool = false;

	public function new(name, owner, isStatic, args, ret, index, tier0) {
		this.name = name;
		this.owner = owner;
		this.isStatic = isStatic;
		this.args = args;
		this.ret = ret;
		this.index = index;
		this.tier0 = tier0;
	}
}

typedef ArgDef = {
	name:String,
	t:Ty,
	/** 0: required, 1: `?name`, 2: default value **/
	opt:Int,
	?rest:Bool
}

class FieldDef {
	public var name:String;
	public var t:Ty;
	public var isStatic:Bool;
	public var isFinal:Bool;

	/** Property with get/set accessors over a backing field. **/
	public var isProp:Bool = false;

	public function new(name, t, isStatic, isFinal) {
		this.name = name;
		this.t = t;
		this.isStatic = isStatic;
		this.isFinal = isFinal;
	}
}

class ClassDef {
	public var name:String;
	public var module:String;
	public var sup:Null<ClassDef>;
	public var ifaces:Array<ClassDef> = [];
	public var isInterface:Bool = false;
	public var isAbstract:Bool = false;
	public var fields:Array<FieldDef> = [];
	public var methods:Array<FnDef> = [];
	public var ctorArgs:Array<ArgDef> = [];

	/** Builtin template classes (Box) use hand-written sources. **/
	public var template:Null<String>;

	public var params:Array<String> = [];
	public var subs:Array<ClassDef> = [];

	public function new(name, module) {
		this.name = name;
		this.module = module;
	}

	public function allFields():Array<FieldDef> {
		var r = sup == null ? [] : sup.allFields();
		return r.concat(fields);
	}

	/** Methods visible on instances, overriding entries replaced by the most derived one. **/
	public function allMethods():Array<FnDef> {
		var r:Array<FnDef> = [];
		for (i in ifaces)
			for (m in i.allMethods())
				r.push(m);
		if (sup != null)
			for (m in sup.allMethods())
				r.push(m);
		for (m in methods) {
			if (m.isStatic)
				continue;
			var found = false;
			for (i in 0...r.length)
				if (r[i].name == m.name) {
					r[i] = m;
					found = true;
				}
			if (!found)
				r.push(m);
		}
		return r;
	}

	public function isSubOf(c:ClassDef):Bool {
		if (c == this)
			return true;
		if (sup != null && sup.isSubOf(c))
			return true;
		for (i in ifaces)
			if (i.isSubOf(c))
				return true;
		return false;
	}
}

class EnumDef {
	public var name:String;
	public var module:String;
	public var ctors:Array<{name:String, args:Array<{name:String, t:Ty}>}> = [];

	public function new(name, module) {
		this.name = name;
		this.module = module;
	}
}

class AnonDef {
	public var name:String;
	public var module:String;
	public var fields:Array<{name:String, t:Ty}> = [];

	public function new(name, module) {
		this.name = name;
		this.module = module;
	}
}

class AbsDef {
	public var name:String;
	public var module:String;

	public function new(name, module) {
		this.name = name;
		this.module = module;
	}
}

class EnumAbsDef {
	public var name:String;
	public var module:String;
	public var values:Array<{name:String, v:Int}> = [];

	public function new(name, module) {
		this.name = name;
		this.module = module;
	}
}

class Types {
	public static function str(t:Ty):String {
		return switch t {
			case TInt: "Int";
			case TFloat: "Float";
			case TBool: "Bool";
			case TString: "String";
			case TVoid: "Void";
			case TDyn: "Dynamic";
			case TArray(t): "Array<" + str(t) + ">";
			case TNull(t): "Null<" + str(t) + ">";
			case TFun(args, ret):
				var r = str(ret);
				if (ret.match(TFun(_, _)))
					r = "(" + r + ")";
				"(" + [for (a in args) str(a)].join(", ") + ") -> " + r;
			case TInst(c, ps): c.name + (ps.length == 0 ? "" : "<" + [for (p in ps) str(p)].join(", ") + ">");
			case TEnum(e): e.name;
			case TAnon(a): a.name;
			case TAbs(a): a.name;
			case TEnumAbs(a): a.name;
			case TMap(k, v): "Map<" + str(k) + ", " + str(v) + ">";
		}
	}

	public static function eq(a:Ty, b:Ty):Bool
		return str(a) == str(b);

	/** Whether a value of `from` can be used where `to` is expected (without casts). **/
	public static function assignable(from:Ty, to:Ty):Bool {
		if (eq(from, to))
			return true;
		return switch [from, to] {
			case [TInt, TFloat]: true;
			case [TInst(a, []), TInst(b, [])]: a.isSubOf(b);
			case [_, TNull(t)]: assignable(from, t);
			case [_, TDyn]: true;
			default: false;
		}
	}

	public static function isBasic(t:Ty):Bool {
		return switch t {
			case TInt | TFloat | TBool | TString: true;
			default: false;
		}
	}
}

class Printer {
	public static function module(m:Module):String {
		var b = new StringBuf();
		b.add(m.header);
		for (i in 0...m.body.items.length) {
			if (i > 0 || m.header != "")
				b.add("\n");
			b.add(node(m.body.items[i], 0));
			b.add("\n");
		}
		return b.toString();
	}

	public static function node(n:Node, indent:Int):String {
		var b = new StringBuf();
		write(b, n, indent);
		return b.toString();
	}

	static function write(b:StringBuf, n:Node, indent:Int):Void {
		for (p in n.parts)
			switch p {
				case S(s):
					// continuation lines of multi-line parts are indented like the node
					if (indent > 0 && s.indexOf("\n") >= 0) {
						var lines = s.split("\n");
						for (i in 0...lines.length) {
							if (i > 0)
								b.add("\n" + (lines[i] == "" ? "" : tabs(indent)));
							b.add(lines[i]);
						}
					} else
						b.add(s);
				case N(c):
					write(b, c, indent);
				case B(bl):
					writeBlock(b, bl, indent);
			}
	}

	static function tabs(n:Int):String {
		var s = "";
		for (_ in 0...n)
			s += "\t";
		return s;
	}

	static function writeBlock(b:StringBuf, bl:Block, indent:Int):Void {
		if (!bl.braces) {
			for (i in 0...bl.items.length) {
				if (i > 0)
					b.add("\n\n" + tabs(indent));
				write(b, bl.items[i], indent);
			}
			return;
		}
		if (bl.items.length == 0) {
			b.add("{}");
			return;
		}
		b.add("{\n");
		for (it in bl.items) {
			b.add(tabs(indent + 1));
			write(b, it, indent + 1);
			b.add("\n");
		}
		b.add(tabs(indent) + "}");
	}
}
