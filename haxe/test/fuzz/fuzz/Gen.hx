package fuzz;

import fuzz.Ast;

typedef LocalVar = {
	name:String,
	t:Ty,
	mutable:Bool,
	/** A function value whose calls cannot form a cycle: a final local or a parameter. **/
	callable:Bool,
}

class Ctx {
	public var module:String;
	public var cls:Null<ClassDef>;
	public var isStatic:Bool = true;

	/** User functions with an index below this may be called. **/
	public var maxIndex:Int;

	/** Only tier-0 functions may be called (tier-0 bodies, lambdas, constructors). **/
	public var tier0:Bool;

	public var lambda:Int = 0;
	public var loop:Int = 0;
	public var ret:Ty;
	public var vars:Array<LocalVar> = [];

	/** Array variables being iterated by an enclosing `for`; not mutated. **/
	public var iterating:Array<String> = [];

	/** Remaining statements for the body being generated. **/
	public var budget:Int;

	public var inCtor:Bool = false;

	/** Inline functions cannot return early. **/
	public var noEarlyReturn:Bool = false;

	/** Classes whose construction is allowed (constructors construct only earlier classes). **/
	public var maxClass:Int = 1 << 30;

	/** Inside an override: `super.name(...)` may be called. **/
	public var superFn:Null<FnDef>;

	public function new(module, ret, maxIndex, tier0, budget) {
		this.module = module;
		this.ret = ret;
		this.maxIndex = maxIndex;
		this.tier0 = tier0;
		this.budget = budget;
	}
}

/**
	Type-directed generator of deterministic, terminating Haxe programs.

	Termination: user functions form a DAG by index (a body only calls lower
	indices), tier-0 functions and lambdas only call tier-0 functions, and
	function values are only called through final locals and parameters (or,
	from tier-1 code, fields assigned lambdas). Loops are bounded, and every
	function body and loop iteration calls `H.tick()`, which throws `H.Fuel`
	once a global budget is exhausted.

	Determinism: no clocks, randomness or hashing. With `portable` the program
	also avoids behavior the Haxe targets legitimately disagree on (Int
	overflow, float formatting, map iteration order, enum and object printing,
	`>>>`, non-ASCII strings), so its output can be compared across targets.
**/
class Gen {
	public static var FEATURES = [
		"classes", "inherit", "interfaces", "abstractclass", "enums", "anon", "abstracts", "enumabs", "generics", "closures", "maps", "strings", "floats",
		"switch", "patterns", "exceptions", "loops", "props", "statics", "using", "inline", "optargs", "rest", "modules", "dynamic", "nulls", "arrays",
		"comprehension", "interp", "bits", "sideeffects", "localfn", "unicode", "casts", "stringbuf", "bind"
	];

	var r:Rng;
	var portable:Bool;
	var size:Int;
	var feats:Map<String, Bool> = new Map();

	var classes:Array<ClassDef> = [];
	var enums:Array<EnumDef> = [];
	var anons:Array<AnonDef> = [];
	var abss:Array<AbsDef> = [];
	var eabss:Array<EnumAbsDef> = [];
	var fns:Array<FnDef> = [];
	var box:ClassDef;
	var mainCls:ClassDef;
	var extCls:ClassDef;
	var modules:Array<String> = ["Main"];
	var decls:Map<String, Array<Node>> = new Map();
	var tier0Next = 1;
	var tier1Next = 1000;
	var counter = 0;
	var bodies:Array<() -> Void> = [];
	var classOrder:Map<String, Int> = new Map();

	public function new(seed:Int, portable:Bool, size:Int, forced:Map<String, Bool>) {
		r = new Rng(seed);
		this.portable = portable;
		this.size = size;
		// swarm testing: each program enables a random subset of the features
		for (f in FEATURES)
			feats.set(f, forced.exists(f) ? forced.get(f) : r.chance(75));
		if (portable) {
			feats.set("unicode", false);
			feats.set("dynamic", false);
			// operand evaluation order is unspecified: Eval and JS differ on `f() + (++x)`
			feats.set("sideeffects", false);
		}
	}

	inline function on(f:String):Bool
		return feats.get(f) == true;

	function fresh(prefix:String):String
		return prefix + (counter++);

	public static function generate(seed:Int, portable:Bool, size:Int, forced:Map<String, Bool>, mutatePercent = 0):Program {
		var g = new Gen(seed, portable, size, forced);
		var p = g.run(seed);
		if (mutatePercent > 0 && g.r.chance(mutatePercent))
			g.mutate(p);
		return p;
	}

	/**
		Breaks the program with one error, so that both compilers must reject it
		with the same diagnostics: a value of the wrong type, an unknown
		identifier or field, or a call with an extra argument.
	**/
	function mutate(p:Program) {
		var exprs:Array<Node> = [];
		function visit(n:Node) {
			if (n.ty != null && !n.pinned)
				exprs.push(n);
			for (part in n.parts)
				switch part {
					case N(c): visit(c);
					case B(b):
						for (i in b.items)
							visit(i);
					case S(_):
				}
		}
		for (m in p.modules)
			for (i in m.body.items)
				visit(i);
		if (exprs.length == 0)
			return;
		var n = r.pick(exprs);
		var src = Printer.node(n, 0);
		var kind = r.int(4);
		n.parts = switch kind {
			case 0:
				var wrong = switch n.ty {
					case TInt | TFloat: "\"oops\"";
					case TString: "12";
					case TBool: "0";
					default: "true";
				}
				[S(wrong)];
			case 1: [S("undefinedName" + r.int(3))];
			case 2: [S("(")].concat(n.parts).concat([S(").noSuchField")]);
			default: [S("H.id(")].concat(n.parts).concat([S(", 1)")]);
		}
		p.features.push("mutated:" + ["type", "ident", "field", "arity"][kind] + " " + (src.length > 60 ? src.substr(0, 60) + "..." : src));
	}

	function run(seed:Int):Program {
		var p = new Program(seed);
		for (f in FEATURES)
			if (on(f))
				p.features.push(f);
		if (on("modules")) {
			modules.push("p.M1");
			if (r.chance(60))
				modules.push("p.q.M2");
		}
		for (m in modules)
			decls.set(m, []);
		mainCls = new ClassDef("Main", "Main");
		extCls = new ClassDef("Ext", "p.Ext");
		declareTypes();
		declareFunctions();
		for (b in bodies)
			b();
		var sections = [];
		var nsec = 2 + r.int(size + 1);
		var startNode = new Node([S("H.out(\"start\");")]);
		startNode.pinned = true;
		var mainBody = [startNode];
		for (i in 0...nsec) {
			var name = "section" + i;
			var fn = new FnDef(name, mainCls, true, [], TVoid, 100000 + i, false);
			sections.push(fnDecl(fn, false));
			mainBody.push(new Node([S("try " + name + "() catch (e:Dynamic) H.out(\"" + name + " threw \" + H.exn(e));")]));
		}
		mainBody.push(new Node([S("H.out(\"fuel \" + H.fuel);")]));
		var mainFn = new Node([S("public static function main():Void "), B(new Block(mainBody))]);
		mainFn.pinned = true;
		var members = decls.get("Main.members");
		if (members == null)
			members = [];
		var mainDecl = new Node([
			S("class Main "),
			B(new Block([for (m in members) m].concat(sections).concat([mainFn])))
		]);
		mainDecl.pinned = true;
		decls.get("Main").push(mainDecl);
		// modules
		var imports = "import H;\n";
		for (m in modules)
			if (m != "Main")
				imports += "import " + m + ";\n";
		if (on("using"))
			imports += "using p.Ext;\n";
		if (on("using") && on("strings"))
			imports += "using StringTools;\n";
		for (m in modules) {
			var path = m.split(".").join("/") + ".hx";
			var parts = m.split(".");
			var pack = parts.slice(0, parts.length - 1).join(".");
			var header = (pack == "" ? "" : "package " + pack + ";\n\n") + (m == "Main" ? "" : "import Main;\n") + imports;
			var items = decls.get(m);
			if (m != "Main") {
				// a type named after the module, so that `import p.M1;` names a type
				var mt = new Node([S("class " + parts[parts.length - 1] + " {}")]);
				mt.pinned = true;
				items.unshift(mt);
			}
			p.modules.push(new Module(path, header, new Block(items, false)));
		}
		var extItems = decls.get("p.Ext.members");
		var extDecl = new Node([S("class Ext "), B(new Block(extItems == null ? [] : extItems))]);
		extDecl.pinned = true;
		p.modules.push(new Module("p/Ext.hx", "package p;\n\nimport Main;\n" + imports.split("using p.Ext;\n").join(""), new Block([extDecl], false)));
		p.modules.push(new Module("H.hx", "", helpers()));
		return p;
	}

	/** The runtime support module: every member is a node, so the reducer can drop unused ones. **/
	function helpers():Block {
		function m(src:String):Node
			return new Node([S(src)]);
		var members = [
			m("public static var fuel:Int = 20000;"),
			m("public static function tick():Void {\n\tif (--fuel < 0)\n\t\tthrow new Fuel();\n}"),
			m("public static function out(s:String):Void {\n\t#if js\n\tjs.Syntax.code(\"console.log({0})\", s);\n\t#elseif flash\n\ttrace(s);\n\t#else\n\tSys.println(s);\n\t#end\n}"),
			m("public static function nz(i:Int):Int\n\treturn i == 0 ? 1 : i;"),
			m("public static function ix(i:Int, len:Int):Int {\n\tif (len <= 0)\n\t\treturn 0;\n\tvar r = i % len;\n\treturn r < 0 ? r + len : r;\n}"),
			m("public static function at<T>(a:Array<T>, i:Int, d:T):T\n\treturn a.length == 0 ? d : a[ix(i, a.length)];"),
			m("public static function lim(i:Int):Int\n\treturn i < 0 ? 0 : i > 6 ? 6 : i;"),
			m("public static function w(i:Int):Int\n\treturn i & 0xFFFFFF;"),
			m("public static function cap(s:String):String\n\treturn s.length > 1000 ? s.substr(0, 1000) : s;"),
			m("public static function capa<T>(a:Array<T>):Array<T>\n\treturn a.length > 1000 ? a.slice(0, 1000) : a;"),
			m("public static function cf(f:Float):Float\n\treturn Math.isNaN(f) ? 0 : f > 1e6 ? 1e6 : f < -1e6 ? -1e6 : f;"),
			m("public static function fmt(f:Float):String {\n\tif (Math.isNaN(f))\n\t\treturn \"nan\";\n\tif (!Math.isFinite(f))\n\t\treturn f > 0 ? \"inf\" : \"-inf\";\n\tif (Math.abs(f) > 1e9)\n\t\treturn \"big\";\n\treturn Std.string(Math.fround(f * 100.0) / 100.0);\n}"),
			m("public static function exn(e:Dynamic):String {\n\tif (Std.isOfType(e, Fuel))\n\t\treturn \"fuel\";\n\tif (Std.isOfType(e, String) || Std.isOfType(e, Int) || Std.isOfType(e, Bool))\n\t\treturn Std.string(e);\n\tif (Std.isOfType(e, Err))\n\t\treturn \"Err\" + (e : Err).errCode;\n\treturn \"other\";\n}"),
			m("public static function id<T>(x:T):T\n\treturn x;"),
			m("public static function apply<T, U>(x:T, f:T->U):U\n\treturn f(x);"),
			m("@:generic public static function first<T>(a:Array<T>, d:T):T\n\treturn a.length > 0 ? a[0] : d;"),
		];
		var h = new Node([S("class H "), B(new Block(members))]);
		h.pinned = true;
		return new Block([
			h,
			m("class Fuel {\n\tpublic function new() {}\n}"),
			m("class Err extends haxe.Exception {\n\tpublic var errCode:Int;\n\n\tpublic function new(code:Int) {\n\t\tsuper(\"err\" + code);\n\t\tthis.errCode = code;\n\t}\n}"),
			m("class Box<T> {\n\tpublic var value:T;\n\n\tpublic function new(v:T) {\n\t\tvalue = v;\n\t}\n\n\tpublic function get():T\n\t\treturn value;\n\n\tpublic function map<U>(f:T->U):Box<U>\n\t\treturn new Box(f(value));\n}"),
		], false);
	}

	// ------------------------------------------------------------------
	// declarations

	function pickModule():String
		return r.pick(modules);

	function addDecl(module:String, n:Node)
		decls.get(module).push(n);

	function declareTypes() {
		box = new ClassDef("Box", "H");
		box.template = "Box";
		box.params = ["T"];
		if (on("enums"))
			for (_ in 0...1 + r.int(3))
				declareEnum();
		if (on("anon"))
			for (_ in 0...1 + r.int(2))
				declareAnon();
		if (on("abstracts"))
			declareAbstract();
		if (on("enumabs"))
			declareEnumAbs();
		if (on("classes")) {
			var nifaces = on("interfaces") ? r.int(3) : 0;
			for (_ in 0...nifaces)
				declareInterface();
			for (_ in 0...2 + r.int(size + 2))
				declareClass();
		}
	}

	/** A type usable as an enum argument, a field or a parameter (no functions or late types). **/
	function simpleType(depth = 0):Ty {
		var w = [30, on("floats") ? 10 : 0, 12, on("strings") ? 20 : 4, depth < 1 && on("arrays") ? 6 : 0, enums.length > 0 && depth < 1 ? 6 : 0];
		return switch r.weighted(w) {
			case 0: TInt;
			case 1: TFloat;
			case 2: TBool;
			case 3: TString;
			case 4: TArray(simpleType(depth + 1));
			case 5: TEnum(r.pick(enums));
			default: TInt;
		}
	}

	function declareEnum() {
		var e = new EnumDef(fresh("E"), pickModule());
		var n = 1 + r.int(4);
		for (i in 0...n) {
			var args = [];
			if (i > 0 || r.chance(30))
				for (_ in 0...r.int(3)) {
					// recursive arguments only after the first, argument-free constructor
					var t = i > 0 && r.chance(15) ? TEnum(e) : simpleType(1);
					args.push({name: fresh("a"), t: t});
				}
			if (i == 0)
				args = [];
			e.ctors.push({name: e.name + String.fromCharCode(65 + i), args: args});
		}
		enums.push(e);
		var items = [];
		for (c in e.ctors)
			items.push(new Node([
				S(c.name + (c.args.length == 0 ? "" : "(" + [for (a in c.args) a.name + ":" + Types.str(a.t)].join(", ") + ")") + ";")
			]));
		var block = new Block(items);
		addDecl(e.module, new Node([S("enum " + e.name + " "), B(block)]));
	}

	function declareAnon() {
		var a = new AnonDef(fresh("S"), pickModule());
		for (_ in 0...1 + r.int(3))
			a.fields.push({name: fresh("x"), t: simpleType(1)});
		anons.push(a);
		addDecl(a.module, new Node([S("typedef " + a.name + " = {" + [for (f in a.fields) f.name + ":" + Types.str(f.t)].join(", ") + "};")]));
	}

	function declareAbstract() {
		var a = new AbsDef(fresh("A"), pickModule());
		abss.push(a);
		var t = a.name;
		var src = 'abstract $t(Int) from Int to Int {\n'
			+ '\tpublic inline function new(i:Int)\n\t\tthis = i;\n\n'
			+ '\tpublic function get():Int\n\t\treturn this;\n\n'
			+ '\tpublic var twice(get, never):Int;\n\n'
			+ '\tfunction get_twice():Int\n\t\treturn ${portable ? "H.w(this * 2)" : "this * 2"};\n\n'
			+ '\t@:op(A + B) public static function add(a:$t, b:$t):$t\n\t\treturn new $t(${portable ? "H.w(a.get() + b.get())" : "a.get() + b.get()"});\n\n'
			+ '\t@:op(A * B) public static function mul(a:$t, b:$t):$t\n\t\treturn new $t(${portable ? "H.w(a.get() * b.get())" : "a.get() * b.get()"});\n\n'
			+ '\t@:op(-A) public static function neg(a:$t):$t\n\t\treturn new $t(-a.get());\n}';
		addDecl(a.module, new Node([S(src)]));
	}

	function declareEnumAbs() {
		var a = new EnumAbsDef(fresh("K"), pickModule());
		var n = 2 + r.int(3);
		for (i in 0...n)
			a.values.push({name: a.name + String.fromCharCode(65 + i), v: i * (1 + r.int(3)) + (i > 0 ? 1 : 0) * i});
		// distinct values
		for (i in 0...a.values.length)
			a.values[i].v = i * 3 + 1;
		eabss.push(a);
		var items = [for (v in a.values) new Node([S("var " + v.name + " = " + v.v + ";")])];
		addDecl(a.module, new Node([S("enum abstract " + a.name + "(Int) to Int "), B(new Block(items))]));
	}

	function newFn(name:String, owner:ClassDef, isStatic:Bool, args:Array<ArgDef>, ret:Ty, tier0:Bool):FnDef {
		var idx = tier0 ? tier0Next++ : tier1Next++;
		var f = new FnDef(name, owner, isStatic, args, ret, idx, tier0);
		return f;
	}

	function randArgs(n:Int, allowOpt:Bool, simple = false):Array<ArgDef> {
		var args:Array<ArgDef> = [];
		for (i in 0...n) {
			var t = simple ? simpleType() : paramType();
			var opt = 0;
			if (allowOpt && i == n - 1 && on("optargs") && r.chance(30) && Types.isBasic(t))
				opt = r.chance(50) ? 1 : 2;
			args.push({name: fresh("a"), t: opt == 1 ? TNull(t) : t, opt: opt});
		}
		if (allowOpt && on("rest") && r.chance(10) && (args.length == 0 || args[args.length - 1].opt == 0))
			args.push({name: fresh("r"), t: TInt, opt: 0, rest: true});
		return args;
	}

	function paramType():Ty {
		if (r.chance(70))
			return simpleType();
		return valueType(1);
	}

	function retType():Ty {
		if (r.chance(15))
			return TVoid;
		return r.chance(70) ? simpleType() : valueType(1);
	}

	function declareInterface() {
		var c = new ClassDef(fresh("I"), pickModule());
		c.isInterface = true;
		for (_ in 0...1 + r.int(2)) {
			var f = newFn(fresh("m"), c, false, randArgs(r.int(3), false), retType(), r.chance(40));
			f.isAbstract = true;
			c.methods.push(f);
		}
		classes.push(c);
		classOrder.set(c.name, classes.length);
		var items = [
			for (m in c.methods)
				new Node([S("function " + m.name + "(" + argList(m.args) + "):" + Types.str(m.ret) + ";")])
		];
		addDecl(c.module, new Node([S("interface " + c.name + " "), B(new Block(items))]));
	}

	function declareClass() {
		var c = new ClassDef(fresh("C"), pickModule());
		var concrete = [for (k in classes) if (!k.isInterface) k];
		if (on("inherit") && concrete.length > 0 && r.chance(50)) {
			c.sup = r.pick(concrete);
			c.sup.subs.push(c);
		}
		var ifs = [for (k in classes) if (k.isInterface) k];
		if (ifs.length > 0 && r.chance(60))
			c.ifaces.push(r.pick(ifs));
		if (on("abstractclass") && r.chance(20))
			c.isAbstract = true;
		classes.push(c);
		var order = classes.length;
		classOrder.set(c.name, order);
		// fields
		for (_ in 0...r.int(4)) {
			var isStatic = on("statics") && r.chance(25);
			var t = isStatic ? simpleType() : (r.chance(80) ? simpleType() : valueType(1));
			// the constructor initializes fields, and constructs only earlier classes
			if (!constructibleBefore(t, c))
				t = simpleType();
			var f = new FieldDef(fresh("f"), t, isStatic, !isStatic && r.chance(20));
			if (on("props") && !isStatic && !f.isFinal && r.chance(25))
				f.isProp = true;
			c.fields.push(f);
		}
		if (on("closures") && r.chance(30))
			c.fields.push(new FieldDef(fresh("cb"), TFun([TInt], TInt), false, false));
		// simple types only: constructing an argument must not need this class
		c.ctorArgs = randArgs(r.int(3), false, true);
		var supArgs = c.sup == null ? [] : c.sup.ctorArgs;
		var members:Array<Node> = [];
		// implementations of interface and abstract methods
		var inherited = c.sup == null ? [] : c.sup.allMethods();
		var required = [];
		for (i in c.ifaces)
			for (m in i.allMethods())
				if (!Lambda.exists(inherited, x -> x.name == m.name && !x.isAbstract))
					required.push(m);
		for (m in inherited)
			if (m.isAbstract && !Lambda.exists(required, x -> x.name == m.name))
				required.push(m);
		var methods:Array<FnDef> = [];
		for (m in required) {
			var f = new FnDef(m.name, c, false, m.args, m.ret, m.index, m.tier0);
			if (c.isAbstract && !m.owner.isInterface && r.chance(50))
				continue; // stays abstract
			if (c.isAbstract && m.owner.isInterface && r.chance(30)) {
				f.isAbstract = true;
			}
			methods.push(f);
		}
		// overrides
		for (m in inherited)
			if (!m.isAbstract && !m.owner.isInterface && r.chance(35) && !Lambda.exists(methods, x -> x.name == m.name)) {
				var f = new FnDef(m.name, c, false, m.args, m.ret, m.index, m.tier0);
				methods.push(f);
			}
		// new methods
		for (_ in 0...r.int(size + 2)) {
			var isStatic = on("statics") && r.chance(25);
			var f = newFn(fresh("m"), c, isStatic, randArgs(r.int(3), true), retType(), r.chance(45));
			if (c.isAbstract && !isStatic && r.chance(30))
				f.isAbstract = true;
			if (isStatic && f.tier0 && on("inline") && r.chance(30))
				f.isInline = true;
			methods.push(f);
		}
		c.methods = methods;
		if (!c.isAbstract)
			for (m in c.allMethods())
				if (m.isAbstract) {
					// a concrete class must implement everything
					var f = new FnDef(m.name, c, false, m.args, m.ret, m.index, m.tier0);
					c.methods.push(f);
				}
		// generate bodies later, once every signature exists
		var node = new Node([S("")]);
		addDecl(c.module, node);
		bodies.push(() -> {
			var head = (c.isAbstract ? "abstract " : "") + "class " + c.name;
			if (c.sup != null)
				head += " extends " + c.sup.name;
			if (c.ifaces.length > 0)
				head += " implements " + [for (i in c.ifaces) i.name].join(" implements ");
			for (f in c.fields)
				members.push(fieldDecl(c, f));
			members.push(ctorDecl(c, supArgs, order));
			for (m in c.methods)
				members.push(fnDecl(m, false));
			node.parts = [S(head + " "), B(new Block(members))];
		});
	}

	function constructibleBefore(t:Ty, c:ClassDef):Bool {
		return switch t {
			case TInst(k, _) if (k.template == null): Lambda.exists(concreteSubs(k), x -> x != c);
			case TArray(t) | TNull(t) | TMap(_, t): constructibleBefore(t, c);
			case TInst(_, [t]): constructibleBefore(t, c);
			default: true;
		}
	}

	function fieldDecl(c:ClassDef, f:FieldDef):Node {
		var t = Types.str(f.t);
		if (f.isStatic)
			return new Node([S("public static var " + f.name + ":" + t + " = "), N(constExpr(f.t)), S(";")]);
		if (f.isProp) {
			var back = "_" + f.name;
			return new Node([
				S("var " + back + ":" + t + ";\n\npublic var " + f.name + "(get, set):" + t + ";\n\nfunction get_" + f.name + "():" + t + "\n\treturn "
					+ back + ";\n\nfunction set_" + f.name + "(v:" + t + "):" + t + "\n\treturn " + back + " = v;")
			]);
		}
		return new Node([S("public " + (f.isFinal ? "final " : "var ") + f.name + ":" + t + ";")]);
	}

	/** Literal-only expression (static initializers). **/
	function constExpr(t:Ty):Node {
		return switch t {
			case TInt: lit(TInt);
			case TFloat: lit(TFloat);
			case TBool: lit(TBool);
			case TString: lit(TString);
			default: e(t, [S(defaultSrc(t))]);
		}
	}

	function argList(args:Array<ArgDef>):String {
		return [
			for (a in args)
				if (a.rest == true) "..." + a.name + ":" + Types.str(a.t) else if (a.opt == 1) "?" + a.name + ":" + Types.str(a.t) else if (a.opt == 2)
					a.name + ":" + Types.str(a.t) + " = " + defaultLiteral(a.t) else a.name + ":" + Types.str(a.t)
		].join(", ");
	}

	function defaultLiteral(t:Ty):String {
		return switch t {
			case TInt: Std.string(r.range(-3, 9));
			case TFloat: "1.5";
			case TBool: "true";
			case TString: "\"d\"";
			default: "null";
		}
	}

	function ctorDecl(c:ClassDef, supArgs:Array<ArgDef>, order:Int):Node {
		var ctx = new Ctx(c.module, TVoid, 0, true, 2);
		ctx.cls = c;
		ctx.isStatic = false;
		ctx.inCtor = true;
		ctx.maxClass = order;
		for (a in c.ctorArgs)
			ctx.vars.push({name: a.name, t: a.t, mutable: true, callable: true});
		var stmts:Array<Node> = [];
		if (c.sup != null) {
			var s = new Node([S("super("), ]);
			callArgs(s, supArgs, ctx, 1);
			s.parts.push(S(");"));
			s.pinned = true;
			stmts.push(s);
		}
		for (f in c.fields) {
			if (f.isStatic)
				continue;
			var target = f.isProp ? "_" + f.name : f.name;
			var init = switch f.t {
				case TFun(_, _): lambda(f.t, ctx, 1);
				default: expr(f.t, ctx, 1);
			}
			var s = new Node([S("this." + target + " = "), N(init), S(";")]);
			// final fields must be initialized; others may be reduced away
			s.pinned = f.isFinal;
			stmts.push(s);
		}
		return new Node([S("public function new(" + argList(c.ctorArgs) + ") "), B(new Block(stmts))]);
	}

	function declareFunctions() {
		var n0 = 2 + r.int(size + 2);
		for (_ in 0...n0) {
			var f = newFn(fresh("fn"), mainCls, true, randArgs(r.int(4), true), retType(), true);
			if (on("inline") && r.chance(25))
				f.isInline = true;
			fns.push(f);
			addMember("Main.members", f);
		}
		var n1 = 2 + r.int(size + 3);
		for (_ in 0...n1) {
			var f = newFn(fresh("fn"), mainCls, true, randArgs(r.int(4), true), retType(), false);
			fns.push(f);
			addMember("Main.members", f);
		}
		if (on("using")) {
			for (_ in 0...1 + r.int(3)) {
				var first = r.pick([TInt, TString, TArray(TInt)]);
				var args:Array<ArgDef> = [{name: fresh("a"), t: first, opt: 0}].concat(randArgs(r.int(2), false));
				var f = newFn(fresh("ext"), extCls, true, args, simpleType(), true);
				fns.push(f);
				addMember("p.Ext.members", f);
			}
		}
		for (c in classes)
			for (m in c.methods)
				if (!fns.contains(m))
					fns.push(m);
	}

	function addMember(key:String, f:FnDef) {
		var list = decls.get(key);
		if (list == null) {
			list = [];
			decls.set(key, list);
		}
		var node = new Node([S("")]);
		list.push(node);
		bodies.push(() -> node.parts = fnDecl(f, false).parts);
	}

	function fnDecl(f:FnDef, pinned:Bool):Node {
		var mods = (f.owner.isInterface ? "" : "public ") + (f.isStatic ? "static " : "") + (f.isInline ? "inline " : "");
		var isOverride = !f.isStatic && f.owner.sup != null && Lambda.exists(f.owner.sup.allMethods(), m -> m.name == f.name && !m.isAbstract);
		if (isOverride)
			mods = "override " + mods;
		var head = mods + "function " + f.name + "(" + argList(f.args) + "):" + Types.str(f.ret);
		if (f.isAbstract)
			return new Node([S("abstract " + head + ";")]);
		var ctx = new Ctx(f.owner.module, f.ret, f.index, f.tier0, 3 + r.int(4 + size));
		ctx.cls = f.owner;
		ctx.isStatic = f.isStatic;
		ctx.noEarlyReturn = f.isInline;
		if (isOverride)
			ctx.superFn = Lambda.find(f.owner.sup.allMethods(), m -> m.name == f.name);
		for (a in f.args)
			ctx.vars.push({
				name: a.rest == true ? a.name + ".toArray()" : a.name,
				t: a.rest == true ? TArray(TInt) : a.t,
				mutable: a.rest != true,
				callable: a.rest != true
			});
		// function entries tick for the fuel count only (calls form a DAG): the reducer may drop them
		var stmts = [new Node([S("H.tick();")])];
		body(stmts, ctx, 3);
		if (f.ret != TVoid) {
			var rs = new Node([S("return "), N(expr(f.ret, ctx, 3)), S(";")]);
			rs.pinned = true;
			stmts.push(rs);
		}
		var n = new Node([S(head + " "), B(new Block(stmts))]);
		n.pinned = pinned;
		return n;
	}

	// ------------------------------------------------------------------
	// types of values

	function inhabited(t:Ty):Bool {
		return switch t {
			case TInst(c, _): c.template != null || concreteSubs(c).length > 0;
			case TVoid: false;
			case TArray(t) | TNull(t): inhabited(t);
			case TFun(_, ret): ret == TVoid || inhabited(ret);
			default: true;
		}
	}

	function concreteSubs(c:ClassDef):Array<ClassDef> {
		return [for (k in classes) if (!k.isInterface && !k.isAbstract && k.isSubOf(c)) k];
	}

	/** Any value type, for locals. **/
	function valueType(depth:Int):Ty {
		var w = [
			30, on("floats") ? 8 : 0, 10, on("strings") ? 16 : 0, on("arrays") && depth < 2 ? 8 : 0, classes.length > 0 ? 10 : 0,
			enums.length > 0 ? 8 : 0, anons.length > 0 ? 5 : 0, abss.length > 0 ? 4 : 0, eabss.length > 0 ? 3 : 0,
			on("closures") && depth < 2 ? 5 : 0, on("maps") && depth < 2 ? 4 : 0, on("generics") && depth < 2 ? 4 : 0, on("nulls") ? 3 : 0
		];
		var t = switch r.weighted(w) {
			case 0: TInt;
			case 1: TFloat;
			case 2: TBool;
			case 3: TString;
			case 4: TArray(valueType(depth + 1));
			case 5: TInst(r.pick(classes), []);
			case 6: TEnum(r.pick(enums));
			case 7: TAnon(r.pick(anons));
			case 8: TAbs(r.pick(abss));
			case 9: TEnumAbs(r.pick(eabss));
			case 10: TFun([for (_ in 0...r.int(3)) simpleType(1)], r.chance(15) ? TVoid : simpleType(1));
			case 11: TMap(r.chance(60) ? TString : TInt, valueType(depth + 1));
			case 12: TInst(box, [valueType(depth + 1)]);
			case 13: TNull(TInt);
			default: TInt;
		}
		if (!inhabited(t))
			return TInt;
		return t;
	}

	// ------------------------------------------------------------------
	// expressions

	inline function e(t:Ty, parts:Array<Part>):Node
		return new Node(parts, t);

	public static function defaultSrc(t:Ty):String {
		return switch t {
			case TInt: "0";
			case TFloat: "0.0";
			case TBool: "false";
			case TString: "\"\"";
			case TArray(t): "([] : Array<" + Types.str(t) + ">)";
			case TInst(c, [p]) if (c.template == "Box"): "new Box<" + Types.str(p) + ">(" + defaultSrc(p) + ")";
			case TNull(_) | TDyn | TInst(_, _): "null";
			case TFun(args, ret):
				var i = 0;
				"(" + [for (a in args) "_" + (i++) + ":" + Types.str(a)].join(", ") + ") -> " + (ret == TVoid ? "{}" : defaultSrc(ret));
			case TEnum(e):
				var c = e.ctors[0];
				e.name + "." + c.name;
			case TAnon(a): "{" + [for (f in a.fields) f.name + ": " + defaultSrc(f.t)].join(", ") + "}";
			case TAbs(a): "new " + a.name + "(0)";
			case TEnumAbs(a): a.name + "." + a.values[0].name;
			case TMap(k, v): "new Map<" + Types.str(k) + ", " + Types.str(v) + ">()";
			case TVoid: "{}";
		}
	}

	function lit(t:Ty):Node {
		return switch t {
			case TInt:
				var s = if (portable) Std.string(r.range(-20, 300)) else switch r.int(10) {
					case 0: "0x" + StringTools.hex(r.int(0x10000));
					case 1: r.pick(["0x7FFFFFFF", "0xFFFFFFFF", "-2147483647", "65535", "0x80000000"]);
					case 2: Std.string(r.next());
					default: Std.string(r.range(-20, 300));
				}
				e(TInt, [S(s.charAt(0) == "-" ? "(" + s + ")" : s)]);
			case TFloat:
				var s = r.pick(["0.5", "1.25", "-2.5", "3.0", "1e3", "0.1", "100.75", "2.5e-3", "7.0", "1e-7", "123456.789"]);
				if (!portable && r.chance(10))
					s = r.pick(["1e21", "1.7976931348623157e308", "5e-324", "0.30000000000000004", "1e100"]);
				e(TFloat, [S(s.charAt(0) == "-" ? "(" + s + ")" : s)]);
			case TBool: e(TBool, [S(r.chance(50) ? "true" : "false")]);
			case TString: e(TString, [S(strLit())]);
			default: e(t, [S(defaultSrc(t))]);
		}
	}

	function strLit():String {
		var pool = ["", "a", "ab", "abc", "Haxe", "x,y,z", "hello world", "  pad  ", "A-B-C", "0", "42", "-7", "q", "zz"];
		if (on("unicode"))
			pool = pool.concat(["é", "日本語", "\\u{1F600}", "ünï", "\\x41\\x42", "\\t", "\\n", "\\\\", "\\\"q\\\"", "a\\rb"]);
		else
			pool = pool.concat(["\\t", "\\n", "\\\\", "\\\"q\\\"", "$$"]);
		var s = r.pick(pool);
		if (s == "$$")
			return "'$$'";
		return "\"" + s + "\"";
	}

	function vars(t:Ty, ctx:Ctx, ?mutableOnly:Bool):Array<LocalVar> {
		return [
			for (v in ctx.vars)
				if (Types.assignable(v.t, t) && (mutableOnly != true || v.mutable) && !(mutableOnly == true && ctx.iterating.contains(v.name))) v
		];
	}

	/** Fields readable in the current context: `this.f` and `C.f`. **/
	function fieldRefs(t:Ty, ctx:Ctx, writable:Bool):Array<String> {
		var res = [];
		if (ctx.cls != null && !ctx.isStatic && !ctx.inCtor)
			for (f in ctx.cls.allFields())
				if (!f.isStatic && (writable ? Types.eq(f.t, t) : Types.assignable(f.t, t)) && (!writable || !f.isFinal) && !f.t.match(TFun(_, _)))
					res.push("this." + f.name);
		if (on("statics"))
			for (c in classes)
				for (f in c.fields)
					if (f.isStatic && (writable ? Types.eq(f.t, t) : Types.assignable(f.t, t)))
						res.push(c.name + "." + f.name);
		return res;
	}

	/** Functions callable from `ctx` whose return type fits `t` (null: any, for statements). **/
	function callable(t:Null<Ty>, ctx:Ctx):Array<FnDef> {
		var res = [];
		for (f in fns) {
			if (f.isAbstract && f.owner.isInterface == false && f.isStatic)
				continue;
			if (f.index >= ctx.maxIndex)
				continue;
			if ((ctx.tier0 || ctx.lambda > 0) && !f.tier0)
				continue;
			if (t != null && (f.ret == TVoid || !Types.assignable(f.ret, t)))
				continue;
			if (!f.isStatic && !inhabited(TInst(f.owner, [])))
				continue;
			if (!f.isStatic && f.owner.template == null && ctx.inCtor)
				continue;
			res.push(f);
		}
		return res;
	}

	function callArgs(n:Node, args:Array<ArgDef>, ctx:Ctx, d:Int) {
		var first = true;
		for (a in args) {
			if (a.rest == true) {
				for (_ in 0...r.int(3)) {
					if (!first)
						n.parts.push(S(", "));
					first = false;
					n.parts.push(N(expr(TInt, ctx, d)));
				}
				continue;
			}
			if (a.opt != 0 && r.chance(40))
				break;
			if (!first)
				n.parts.push(S(", "));
			first = false;
			n.parts.push(N(expr(a.opt == 1 ? switch a.t {
				case TNull(t): t;
				default: a.t;
			} : a.t, ctx, d)));
		}
	}

	function call(f:FnDef, ctx:Ctx, d:Int):Node {
		var n = e(f.ret, []);
		var args = f.args;
		if (f.owner == extCls && on("using") && ctx.module != "p.Ext" && r.chance(60)) {
			n.parts.push(S("("));
			n.parts.push(N(expr(args[0].t, ctx, d - 1)));
			n.parts.push(S(")." + f.name + "("));
			callArgs(n, args.slice(1), ctx, d - 1);
			n.parts.push(S(")"));
			return n;
		}
		if (f.isStatic) {
			var prefix = f.owner == mainCls && ctx.cls == mainCls && r.chance(50) ? "" : f.owner.name + ".";
			n.parts.push(S(prefix + f.name + "("));
		} else if (ctx.cls != null && !ctx.isStatic && !ctx.inCtor && ctx.cls.isSubOf(f.owner) && r.chance(70)) {
			n.parts.push(S((r.chance(50) ? "this." : "") + f.name + "("));
		} else {
			n.parts.push(S("("));
			n.parts.push(N(expr(TInst(f.owner, []), ctx, d - 1)));
			n.parts.push(S(")." + f.name + "("));
		}
		callArgs(n, args, ctx, d - 1);
		n.parts.push(S(")"));
		return n;
	}

	/** An expression of type `t` (or a subtype). **/
	public function expr(t:Ty, ctx:Ctx, d:Int):Node {
		if (d < -3 && !Types.isBasic(t) && !t.match(TInst(_, _)))
			return e(t, [S(defaultSrc(t))]);
		if (d <= 0 || r.chance(10)) {
			var vs = vars(t, ctx);
			if (vs.length > 0 && r.chance(70))
				return e(t, [S(r.pick(vs).name)]);
			if (Types.isBasic(t))
				return lit(t);
		}
		// generic producers that work for any type
		var w = [
			60, // type specific
			vars(t, ctx).length > 0 ? 25 : 0,
			fieldRefs(t, ctx, false).length > 0 ? 10 : 0,
			callable(t, ctx).length > 0 && d > 1 ? 15 : 0,
			d > 1 ? 6 : 0, // ternary
			d > 1 && on("switch") ? 4 : 0,
			d > 1 && on("generics") ? 3 : 0,
			d > 1 && on("closures") ? 3 : 0, // call of a function value
			d > 1 ? 2 : 0, // block expression
			d > 1 && on("casts") ? 2 : 0,
		];
		switch r.weighted(w) {
			case 1:
				return e(t, [S(r.pick(vars(t, ctx)).name)]);
			case 2:
				return e(t, [S(r.pick(fieldRefs(t, ctx, false)))]);
			case 3:
				return call(r.pick(callable(t, ctx)), ctx, d);
			case 4:
				return exact(t, e(t, [S("("), N(expr(TBool, ctx, d - 1)), S(" ? "), N(expr(t, ctx, d - 1)), S(" : "), N(expr(t, ctx, d - 1)), S(")")]));
			case 5:
				return exact(t, switchExpr(t, ctx, d));
			case 6:
				switch r.int(3) {
					case 0:
						return e(t, [S("H.id("), N(expr(t, ctx, d - 1)), S(")")]);
					case 1:
						var s = simpleType(1);
						var x = fresh("v");
						var inner = withVar(ctx, x, s, false, () -> expr(t, ctx, d - 1));
						return e(t, [S("H.apply("), N(expr(s, ctx, d - 1)), S(", (" + x + ":" + Types.str(s) + ") -> "), N(inner), S(")")]);
					default:
						var bt = TInst(box, [t]);
						return e(t, [S("("), N(expr(bt, ctx, d - 1)), S(r.chance(50) ? ").get()" : ").value")]);
				}
			case 7:
				var fv = [for (v in ctx.vars) if (v.callable) switch v.t {
					case TFun(_, ret) if (ret != TVoid && Types.assignable(ret, t)): v;
					default: continue;
				}];
				if (fv.length > 0) {
					var v = r.pick(fv);
					var args = switch v.t {
						case TFun(a, _): a;
						default: [];
					};
					var n = e(t, [S(v.name + "(")]);
					for (i in 0...args.length) {
						if (i > 0)
							n.parts.push(S(", "));
						n.parts.push(N(expr(args[i], ctx, d - 1)));
					}
					n.parts.push(S(")"));
					return n;
				}
			case 8:
				var x = fresh("v");
				var s = simpleType(1);
				var init = expr(s, ctx, d - 1);
				var inner = withVar(ctx, x, s, true, () -> expr(t, ctx, d - 1));
				return e(t, [S("({ var " + x + " = "), N(init), S("; "), N(inner), S("; })")]);
			case 9:
				return e(t, [S("(cast ("), N(expr(t, ctx, d - 1)), S(") : " + Types.str(t) + ")")]);
			default:
		}
		return typed(t, ctx, d);
	}

	function withVar<T>(ctx:Ctx, name:String, t:Ty, mutable:Bool, f:() -> T):T {
		ctx.vars.push({name: name, t: t, mutable: mutable, callable: !mutable});
		var res = f();
		ctx.vars.pop();
		return res;
	}

	function intBinop(ctx:Ctx, d:Int):Node {
		var a = expr(TInt, ctx, d - 1);
		var b = expr(TInt, ctx, d - 1);
		var ops = ["+", "-", "*", "%"];
		if (on("bits"))
			ops = ops.concat(["&", "|", "^", "<<", ">>"]).concat(portable ? [] : [">>>"]);
		var op = r.pick(ops);
		return switch op {
			case "%":
				e(TInt, [S("("), N(a), S(" % H.nz("), N(b), S("))")]);
			case "<<" | ">>" | ">>>":
				e(TInt, [S("("), N(a), S(" " + op + " ("), N(b), S(" & " + (portable ? "15" : "31") + "))")]);
			case "*" if (portable):
				e(TInt, [S("H.w("), N(a), S(" * "), N(b), S(")")]);
			default:
				e(TInt, [S("("), N(a), S(" " + op + " "), N(b), S(")")]);
		}
	}

	function floatArg(ctx:Ctx, d:Int):Node {
		var f = expr(TFloat, ctx, d - 1);
		return portable ? e(TFloat, [S("H.cf("), N(f), S(")")]) : f;
	}

	function typed(t:Ty, ctx:Ctx, d:Int):Node {
		return switch t {
			case TInt: intExpr(ctx, d);
			case TFloat: floatExpr(ctx, d);
			case TBool: boolExpr(ctx, d);
			case TString: stringExpr(ctx, d);
			case TArray(et): arrayExpr(et, ctx, d);
			case TNull(inner):
				if (r.chance(30)) e(t, [S("null")]) else expr(inner, ctx, d - 1);
			case TFun(_, _): lambda(t, ctx, d);
			case TInst(c, ps):
				if (c == box) {
					// Box<T> is invariant: an argument of a subtype would infer another type
					var exact = !Types.isBasic(ps[0]) || ps[0] == TFloat || r.chance(30);
					var n = e(t, [S(exact ? "new Box<" + Types.str(ps[0]) + ">(" : "new Box(")]);
					n.parts.push(N(expr(ps[0], ctx, d - 1)));
					n.parts.push(S(")"));
					return n;
				}
				var subs = [for (k in concreteSubs(c)) if (classOrder.get(k.name) < ctx.maxClass) k];
				if (subs.length == 0)
					return e(t, [S("null")]);
				var k = r.pick(subs);
				var n = e(t, [S("new " + k.name + "(")]);
				callArgs(n, k.ctorArgs, ctx, d - 1);
				n.parts.push(S(")"));
				n;
			case TEnum(en): enumValue(en, ctx, d);
			case TAnon(a):
				var fs = a.fields.copy();
				if (r.chance(50))
					r.shuffle(fs);
				var n = e(t, [S("{")]);
				for (i in 0...fs.length) {
					n.parts.push(S((i > 0 ? ", " : "") + fs[i].name + ": "));
					n.parts.push(N(expr(fs[i].t, ctx, d - 1)));
				}
				n.parts.push(S("}"));
				var res = e(t, [S("("), N(n), S(" : " + a.name + ")")]);
				res;
			case TAbs(a):
				switch r.int(5) {
					case 0: e(t, [S("("), N(expr(TInt, ctx, d - 1)), S(" : " + a.name + ")")]);
					case 1 if (d > 1): e(t, [S("("), N(expr(t, ctx, d - 1)), S(r.pick([" + ", " * "])), N(expr(t, ctx, d - 1)), S(")")]);
					case 2 if (d > 1): e(t, [S("(-"), N(expr(t, ctx, d - 1)), S(")")]);
					default: e(t, [S("new " + a.name + "("), N(expr(TInt, ctx, d - 1)), S(")")]);
				}
			case TEnumAbs(a): e(t, [S(a.name + "." + r.pick(a.values).name)]);
			case TMap(k, v):
				if (r.chance(50)) {
					var n = e(t, [S("[")]);
					var keys = [];
					for (i in 0...1 + r.int(3)) {
						var key = k == TString ? "\"k" + i + "\"" : Std.string(i * 7 - 3);
						keys.push(key);
						n.parts.push(S((i > 0 ? ", " : "") + key + " => "));
						n.parts.push(N(expr(v, ctx, d - 1)));
					}
					n.parts.push(S("]"));
					e(t, [S("("), N(n), S(" : " + Types.str(t) + ")")]);
				} else
					e(t, [S(defaultSrc(t))]);
			case TDyn: expr(TInt, ctx, d);
			case TVoid: e(t, [S("{}")]);
		}
	}

	function intExpr(ctx:Ctx, d:Int):Node {
		var w = [
			15, // literal
			d > 1 ? 30 : 0, // binop
			d > 1 ? 4 : 0, // unary
			on("strings") ? 5 : 0, // string length / indexOf
			on("arrays") ? 5 : 0, // array length / at / indexOf
			on("floats") ? 4 : 0, // Std.int, floor
			on("strings") ? 3 : 0, // charCodeAt
			3, // parseInt
			on("sideeffects") && vars(TInt, ctx, true).length > 0 ? 5 : 0,
			enums.length > 0 ? 2 : 0,
			abss.length > 0 ? 3 : 0,
			eabss.length > 0 ? 2 : 0,
			on("maps") ? 2 : 0,
			anons.length > 0 ? 3 : 0,
			on("closures") ? 2 : 0, // Lambda.count / fold
			d > 1 ? 2 : 0, // if expression
			2, // Reflect.compare
		];
		return switch r.weighted(w) {
			case 0: lit(TInt);
			case 1: intBinop(ctx, d);
			case 2:
				e(TInt, [S(r.pick(on("bits") ? ["(-", "(~"] : ["(-"])), N(expr(TInt, ctx, d - 1)), S(")")]);
			case 3:
				switch r.int(3) {
					case 0: e(TInt, [S("("), N(expr(TString, ctx, d - 1)), S(").length")]);
					case 1: e(TInt, [S("("), N(expr(TString, ctx, d - 1)), S(").indexOf("), N(expr(TString, ctx, d - 1)), S(")")]);
					default: e(TInt, [S("("), N(expr(TString, ctx, d - 1)), S(").lastIndexOf("), N(expr(TString, ctx, d - 1)), S(")")]);
				}
			case 4:
				var et = simpleType(1);
				switch r.int(3) {
					case 0: e(TInt, [S("("), N(expr(TArray(et), ctx, d - 1)), S(").length")]);
					case 1: e(TInt, [S("H.at("), N(expr(TArray(TInt), ctx, d - 1)), S(", "), N(expr(TInt, ctx, d - 1)), S(", 0)")]);
					default:
						if (Types.isBasic(et) && et != TFloat)
							e(TInt, [S("("), N(expr(TArray(et), ctx, d - 1)), S(").indexOf("), N(expr(et, ctx, d - 1)), S(")")]);
						else
							e(TInt, [S("("), N(expr(TArray(et), ctx, d - 1)), S(").length")]);
				}
			case 5:
				var f = r.pick(["Std.int(", "Math.floor(", "Math.ceil(", "Math.round("]);
				e(TInt, [S(f), N(floatArg(ctx, d)), S(")")]);
			case 6:
				var s = expr(TString, ctx, d - 1);
				var i = expr(TInt, ctx, d - 1);
				if (portable)
					e(TInt, [S("({ var _s = "), N(s), S("; var _c = _s.charCodeAt(H.ix("), N(i), S(", _s.length)); _c == null ? -1 : _c; })")]);
				else
					e(TInt, [S("(("), N(s), S(").charCodeAt("), N(i), S(") ?? -1)")]);
			case 7:
				if (portable || r.chance(50))
					e(TInt, [S("(Std.parseInt(Std.string("), N(expr(TInt, ctx, d - 1)), S(")) ?? 0)")]);
				else
					e(TInt, [S("(Std.parseInt("), N(expr(TString, ctx, d - 1)), S(") ?? 0)")]);
			case 8:
				var v = r.pick(vars(TInt, ctx, true)).name;
				var op = r.pick(["++" + v, "--" + v, v + "++", v + "--", v + " += 3", v + " -= 1", v + " = 5"]);
				e(TInt, [S("(" + op + ")")]);
			case 9:
				var en = r.pick(enums);
				e(TInt, [S("Type.enumIndex("), N(enumValue(en, ctx, d - 1)), S(")")]);
			case 10:
				var a = r.pick(abss);
				switch r.int(3) {
					case 0: e(TInt, [S("("), N(expr(TAbs(a), ctx, d - 1)), S(").get()")]);
					case 1: e(TInt, [S("("), N(expr(TAbs(a), ctx, d - 1)), S(").twice")]);
					default: e(TInt, [S("("), N(expr(TAbs(a), ctx, d - 1)), S(" : Int)")]);
				}
			case 11:
				var a = r.pick(eabss);
				e(TInt, [S("("), N(expr(TEnumAbs(a), ctx, d - 1)), S(" : Int)")]);
			case 12:
				var k = r.chance(50) ? TString : TInt;
				var m = expr(TMap(k, TInt), ctx, d - 1);
				e(TInt, [S("(("), N(m), S(").get("), N(mapKey(k, ctx, d)), S(") ?? 0)")]);
			case 13:
				var cands = [for (a in anons) for (f in a.fields) if (Types.assignable(f.t, TInt)) {a: a, f: f}];
				if (cands.length == 0)
					lit(TInt);
				else {
					var c = r.pick(cands);
					e(TInt, [S("("), N(expr(TAnon(c.a), ctx, d - 1)), S(")." + c.f.name)]);
				}
			case 14:
				var arr = expr(TArray(TInt), ctx, d - 1);
				var x = fresh("v");
				if (r.chance(50)) {
					var c = withVar(ctx, x, TInt, false, () -> boolExpr(ctx, d - 1));
					e(TInt, [S("Lambda.count("), N(arr), S(", " + x + " -> "), N(c), S(")")]);
				} else {
					var acc = fresh("v");
					var body = withVar(ctx, x, TInt, false, () -> withVar(ctx, acc, TInt, false, () -> intExpr(ctx, d - 1)));
					var b = portable ? e(TInt, [S("H.w("), N(body), S(")")]) : body;
					e(TInt, [S("Lambda.fold("), N(arr), S(", (" + x + ":Int, " + acc + ":Int) -> "), N(b), S(", 0)")]);
				}
			case 15:
				e(TInt, [S("(if ("), N(expr(TBool, ctx, d - 1)), S(") "), N(expr(TInt, ctx, d - 1)), S(" else "), N(expr(TInt, ctx, d - 1)), S(")")]);
			case 16:
				var ct = on("strings") && r.chance(50) ? TString : TInt;
				e(TInt, [S("Reflect.compare("), N(expr(ct, ctx, d - 1)), S(", "), N(expr(ct, ctx, d - 1)), S(")")]);
			default: lit(TInt);
		}
	}

	function mapKey(k:Ty, ctx:Ctx, d:Int):Node {
		if (r.chance(70))
			return e(k, [S(k == TString ? "\"k" + r.int(4) + "\"" : Std.string(r.int(4) * 7 - 3))]);
		return expr(k, ctx, d - 1);
	}

	function floatExpr(ctx:Ctx, d:Int):Node {
		var w = [20, d > 1 ? 30 : 0, 10, d > 1 ? 8 : 0, d > 1 ? 8 : 0, portable ? 0 : 3, 2];
		return switch r.weighted(w) {
			case 0: lit(TFloat);
			case 1:
				var op = r.pick(["+", "-", "*", "/"]);
				var a = expr(r.chance(70) ? TFloat : TInt, ctx, d - 1);
				var b = expr(r.chance(70) ? TFloat : TInt, ctx, d - 1);
				e(TFloat, [S("("), N(a), S(" " + op + " "), N(b), S(")")]);
			case 2: e(TFloat, [N(expr(TInt, ctx, d - 1))]);
			case 3:
				var f = r.pick(["Math.sqrt(Math.abs(", "Math.abs(", "Math.ffloor(", "Math.fceil("]);
				var close = f.indexOf("sqrt") >= 0 ? "))" : ")";
				e(TFloat, [S(f), N(expr(TFloat, ctx, d - 1)), S(close)]);
			case 4:
				e(TFloat, [S(r.pick(["Math.min(", "Math.max("])), N(expr(TFloat, ctx, d - 1)), S(", "), N(expr(TFloat, ctx, d - 1)), S(")")]);
			case 5:
				switch r.int(4) {
					case 0: e(TFloat, [S("Math.sin("), N(expr(TFloat, ctx, d - 1)), S(")")]);
					case 1: e(TFloat, [S("Math.pow("), N(expr(TFloat, ctx, d - 1)), S(", 2)")]);
					case 2: e(TFloat, [S("Math.PI")]);
					default: e(TFloat, [S("Std.parseFloat("), N(expr(TString, ctx, d - 1)), S(")")]);
				}
			case 6:
				e(TFloat, [S("Std.parseFloat(\"" + r.pick(["1.5", "-0.25", "3", "12.5"]) + "\")")]);
			default: lit(TFloat);
		}
	}

	function boolExpr(ctx:Ctx, d:Int):Node {
		var w = [10, d > 1 ? 25 : 0, d > 1 ? 12 : 0, d > 1 ? 4 : 0, on("arrays") ? 3 : 0, on("strings") ? 3 : 0, on("maps") ? 2 : 0,
			classes.length > 0 ? 2 : 0, enums.length > 0 && on("patterns") ? 3 : 0, on("floats") ? 1 : 0];
		return switch r.weighted(w) {
			case 0: lit(TBool);
			case 1:
				var ct = r.pick([TInt, TInt, on("floats") ? TFloat : TInt, on("strings") ? TString : TInt]);
				var ops = ["==", "!=", "<", "<=", ">", ">="];
				e(TBool, [S("("), N(expr(ct, ctx, d - 1)), S(" " + r.pick(ops) + " "), N(expr(ct, ctx, d - 1)), S(")")]);
			case 2:
				e(TBool, [S("("), N(expr(TBool, ctx, d - 1)), S(r.pick([" && ", " || "])), N(expr(TBool, ctx, d - 1)), S(")")]);
			case 3: e(TBool, [S("!"), N(expr(TBool, ctx, d - 1))]);
			case 4:
				e(TBool, [S("("), N(expr(TArray(TInt), ctx, d - 1)), S(").contains("), N(expr(TInt, ctx, d - 1)), S(")")]);
			case 5:
				var f = r.pick(["StringTools.startsWith(", "StringTools.endsWith(", "StringTools.contains("]);
				e(TBool, [S(f), N(expr(TString, ctx, d - 1)), S(", "), N(expr(TString, ctx, d - 1)), S(")")]);
			case 6:
				var k = r.chance(50) ? TString : TInt;
				e(TBool, [S("("), N(expr(TMap(k, valueType(2)), ctx, d - 1)), S(").exists("), N(mapKey(k, ctx, d)), S(")")]);
			case 7:
				var c = r.pick(classes);
				var subs = [for (k in classes) if (k.isSubOf(c) || c.isSubOf(k)) k];
				var k = r.pick(subs);
				if (r.chance(60) || !k.isSubOf(c))
					e(TBool, [S("Std.isOfType("), N(expr(TInst(c, []), ctx, d - 1)), S(", " + k.name + ")")]);
				else
					e(TBool, [S("(Std.downcast(("), N(expr(TInst(c, []), ctx, d - 1)), S(" : " + c.name + "), " + k.name + ") != null)")]);
			case 8:
				var en = r.pick(enums);
				var c = r.pick(en.ctors);
				var pat = c.name + (c.args.length == 0 ? "" : "(" + [for (_ in c.args) "_"].join(", ") + ")");
				e(TBool, [S("("), N(enumValue(en, ctx, d - 1)), S(").match(" + pat + ")")]);
			case 9: e(TBool, [S("Math.isNaN("), N(expr(TFloat, ctx, d - 1)), S(")")]);
			default: lit(TBool);
		}
	}

	function stringExpr(ctx:Ctx, d:Int):Node {
		var w = [
			15, d > 1 ? 15 : 0, d > 1 && on("interp") ? 8 : 0, 10, on("strings") ? 12 : 0, on("arrays") ? 4 : 0, on("strings") ? 5 : 0,
			on("stringbuf") && d > 1 ? 3 : 0, enums.length > 0 && !portable ? 2 : 0, on("using") && on("strings") ? 3 : 0
		];
		return switch r.weighted(w) {
			case 0: lit(TString);
			case 1:
				var o = r.pick([TString, TString, TInt, TBool]);
				var a = expr(TString, ctx, d - 1);
				var b = expr(o, ctx, d - 1);
				r.chance(50) ? e(TString, [S("("), N(a), S(" + "), N(b), S(")")]) : e(TString, [S("("), N(b), S(" + "), N(a), S(")")]);
			case 2:
				var n = e(TString, [S("'")]);
				for (i in 0...1 + r.int(3)) {
					n.parts.push(S(r.pick(["", "x", " = ", "<", "-"])));
					n.parts.push(S("${"));
					n.parts.push(N(toStr(r.pick([TInt, TString, TBool]), ctx, d - 1)));
					n.parts.push(S("}"));
				}
				n.parts.push(S("'"));
				n;
			case 3: toStr(r.pick([TInt, TBool, on("floats") ? TFloat : TInt, TString]), ctx, d - 1);
			case 4:
				var s = expr(TString, ctx, d - 1);
				switch r.int(7) {
					case 0: e(TString, [S("("), N(s), S(").toUpperCase()")]);
					case 1: e(TString, [S("("), N(s), S(").toLowerCase()")]);
					case 2: e(TString, [S("("), N(s), S(").substr("), N(smallInt(ctx, d)), S(", "), N(smallInt(ctx, d)), S(")")]);
					case 3: e(TString, [S("("), N(s), S(").substring("), N(smallInt(ctx, d)), S(", "), N(smallInt(ctx, d)), S(")")]);
					case 4: e(TString, [S("("), N(s), S(").charAt("), N(smallInt(ctx, d)), S(")")]);
					case 5: e(TString, [S("StringTools.trim("), N(s), S(")")]);
					default:
						e(TString, [S("StringTools.replace("), N(s), S(", \"" + r.pick(["a", "b", ",", " "]) + "\", "), N(expr(TString, ctx, d - 1)), S(")")]);
				}
			case 5:
				var et = r.pick([TInt, TString, TBool]);
				e(TString, [S("("), N(expr(TArray(et), ctx, d - 1)), S(").join(\"" + r.pick([",", "", " ", "|"]) + "\")")]);
			case 6:
				switch r.int(3) {
					case 0: e(TString, [S("StringTools.lpad("), N(expr(TString, ctx, d - 1)), S(", \"*\", "), N(smallInt(ctx, d)), S(")")]);
					case 1: e(TString, [S("StringTools.hex(("), N(expr(TInt, ctx, d - 1)), S(") & 0xFFFF, 4)")]);
					default: e(TString, [S("String.fromCharCode(65 + (("), N(expr(TInt, ctx, d - 1)), S(") & 15))")]);
				}
			case 7:
				var sb = fresh("sb");
				var n = e(TString, [S("({ var " + sb + " = new StringBuf(); ")]);
				for (_ in 0...1 + r.int(3)) {
					n.parts.push(S(sb + ".add("));
					n.parts.push(N(toStr(r.pick([TInt, TString, TBool]), ctx, d - 1)));
					n.parts.push(S("); "));
				}
				if (r.chance(50))
					n.parts.push(S(sb + ".addChar(" + (65 + r.int(26)) + "); "));
				n.parts.push(S(sb + ".toString(); })"));
				n;
			case 8: e(TString, [S("Std.string("), N(enumValue(r.pick(enums), ctx, d - 1)), S(")")]);
			case 9:
				e(TString, [S("("), N(expr(TString, ctx, d - 1)), S(").replace(\"a\", \"b\")")]);
			default: lit(TString);
		}
	}

	function smallInt(ctx:Ctx, d:Int):Node {
		if (r.chance(60))
			return e(TInt, [S(Std.string(r.range(portable ? 0 : -2, 6)))]);
		var i = expr(TInt, ctx, d - 1);
		return portable ? e(TInt, [S("H.lim("), N(i), S(")")]) : e(TInt, [S("("), N(i), S(" & 7)")]);
	}

	/** A String showing a value of type t; with `portable` only for types every target prints alike. **/
	function toStr(t:Ty, ctx:Ctx, d:Int):Node {
		var v = expr(t, ctx, d);
		return switch t {
			case TString: v;
			case TFloat if (portable): e(TString, [S("H.fmt("), N(v), S(")")]);
			default: e(TString, [S("Std.string("), N(v), S(")")]);
		}
	}

	function printable(t:Ty):Bool {
		if (!portable)
			return t != TVoid && !t.match(TFun(_, _) | TMap(_, _));
		return switch t {
			case TInt | TBool | TString | TFloat: true;
			case TEnumAbs(_) | TAbs(_): true;
			case TArray(TInt | TString | TBool): true;
			default: false;
		}
	}

	function show(t:Ty, ctx:Ctx, d:Int):Node {
		var v = expr(t, ctx, d);
		return switch t {
			case TString: v;
			case TFloat if (portable): e(TString, [S("H.fmt("), N(v), S(")")]);
			case TAbs(_) | TEnumAbs(_): e(TString, [S("Std.string(("), N(v), S(" : Int))")]);
			case TArray(_) if (portable): e(TString, [S("("), N(v), S(").join(\",\")")]);
			default: e(TString, [S("Std.string("), N(v), S(")")]);
		}
	}

	function arrayExpr(et:Ty, ctx:Ctx, d:Int):Node {
		var t = TArray(et);
		var w = [20, on("comprehension") && d > 1 ? 8 : 0, on("closures") && d > 1 ? 8 : 0, d > 1 ? 6 : 0, et == TString && on("strings") ? 4 : 0];
		return switch r.weighted(w) {
			case 1:
				var x = fresh("i");
				if (r.chance(50)) {
					var body = withVar(ctx, x, TInt, false, () -> expr(et, ctx, d - 1));
					exactArray(et, e(t, [S("[for (" + x + " in 0..." + r.int(5) + ") "), N(body), S("]")]));
				} else {
					var src = simpleType(1);
					var arr = expr(TArray(src), ctx, d - 1);
					ctx.vars.push({name: x, t: src, mutable: false, callable: false});
					var cond = boolExpr(ctx, d - 1);
					var body = expr(et, ctx, d - 1);
					ctx.vars.pop();
					exactArray(et, e(t, [S("[for (" + x + " in "), N(arr), S(") if ("), N(cond), S(") "), N(body), S("]")]));
				}
			case 2:
				var x = fresh("v");
				if (r.chance(50)) {
					var src = simpleType(1);
					var arr = expr(TArray(src), ctx, d - 1);
					var body = withVar(ctx, x, src, false, () -> expr(et, ctx, d - 1));
					if (!(et == TInt || et == TString || et == TBool))
						body = e(et, [S("("), N(body), S(" : " + Types.str(et) + ")")]);
					e(t, [S("("), N(arr), S(").map((" + x + ":" + Types.str(src) + ") -> "), N(body), S(")")]);
				} else {
					var arr = expr(t, ctx, d - 1);
					var cond = withVar(ctx, x, et, false, () -> boolExpr(ctx, d - 1));
					e(t, [S("("), N(arr), S(").filter(" + x + " -> "), N(cond), S(")")]);
				}
			case 3:
				switch r.int(3) {
					case 0: e(t, [S("("), N(expr(t, ctx, d - 1)), S(").concat("), N(expr(t, ctx, d - 1)), S(")")]);
					case 1: e(t, [S("("), N(expr(t, ctx, d - 1)), S(").slice("), N(smallInt(ctx, d)), S(", "), N(smallInt(ctx, d)), S(")")]);
					default: e(t, [S("("), N(expr(t, ctx, d - 1)), S(").copy()")]);
				}
			case 4:
				e(t, [S("("), N(expr(TString, ctx, d - 1)), S(").split(\"" + r.pick([",", " ", "-", "a"]) + "\")")]);
			default:
				var n = r.int(4);
				if (n == 0)
					return e(t, [S("([] : " + Types.str(t) + ")")]);
				var node = e(t, [S("[")]);
				for (i in 0...n) {
					if (i > 0)
						node.parts.push(S(", "));
					node.parts.push(N(expr(et, ctx, d - 1)));
				}
				node.parts.push(S("]"));
				exactArray(et, node);
		}
	}

	/** Branches of a subtype (or Int for Float) would give a conditional another type than `t`. **/
	function exact(t:Ty, n:Node):Node {
		if (t == TInt || t == TString || t == TBool)
			return n;
		return e(t, [S("("), N(n), S(" : " + Types.str(t) + ")")]);
	}

	/** Arrays are invariant: elements of a subtype (or Int for Float) would infer another type. **/
	function exactArray(et:Ty, n:Node):Node {
		if (et == TInt || et == TString || et == TBool)
			return n;
		return e(n.ty, [S("("), N(n), S(" : " + Types.str(n.ty) + ")")]);
	}

	function enumValue(en:EnumDef, ctx:Ctx, d:Int):Node {
		var t = TEnum(en);
		var vs = vars(t, ctx);
		if (vs.length > 0 && r.chance(30))
			return e(t, [S(r.pick(vs).name)]);
		var cands = d <= 1 ? [for (c in en.ctors) if (!Lambda.exists(c.args, a -> a.t.match(TEnum(_)))) c] : en.ctors;
		if (cands.length == 0)
			cands = [en.ctors[0]];
		var c = r.pick(cands);
		var qual = en.module == ctx.module && r.chance(50) ? "" : en.name + ".";
		var n = e(t, [S(qual + c.name)]);
		if (c.args.length > 0) {
			n.parts.push(S("("));
			for (i in 0...c.args.length) {
				if (i > 0)
					n.parts.push(S(", "));
				n.parts.push(N(expr(c.args[i].t, ctx, d - 1)));
			}
			n.parts.push(S(")"));
		}
		return n;
	}

	function lambda(t:Ty, ctx:Ctx, d:Int):Node {
		var args = switch t {
			case TFun(a, _): a;
			default: [];
		};
		var ret = switch t {
			case TFun(_, r): r;
			default: TVoid;
		};
		// calls through existing function values or tier-0 static functions
		if (r.chance(25)) {
			var vs = [for (v in ctx.vars) if (v.callable && Types.eq(v.t, t)) v];
			if (vs.length > 0)
				return e(t, [S(r.pick(vs).name)]);
			var fs = [
				for (f in fns)
					if (f.isStatic && f.tier0 && !f.isInline && f.owner != extCls && f.index < ctx.maxIndex && f.args.length == args.length
						&& !Lambda.exists(f.args, a -> a.opt != 0 || a.rest == true) && Types.eq(TFun([for (a in f.args) a.t], f.ret), t)) f
			];
			if (fs.length > 0) {
				var f = r.pick(fs);
				return e(t, [S(f.owner.name + "." + f.name)]);
			}
			if (on("bind")) {
				var fs = [
					for (f in fns)
						if (f.isStatic && f.tier0 && !f.isInline && f.owner != extCls && f.index < ctx.maxIndex && f.args.length == args.length + 1
							&& !Lambda.exists(f.args, a -> a.opt != 0 || a.rest == true) && Types.eq(TFun([for (a in f.args.slice(1)) a.t], f.ret), t)) f
				];
				if (fs.length > 0) {
					var f = r.pick(fs);
					return e(t, [S(f.owner.name + "." + f.name + ".bind("), N(expr(f.args[0].t, ctx, d - 1)), S(")")]);
				}
			}
		}
		var names = [for (_ in args) fresh("p")];
		var mark = ctx.vars.length;
		for (i in 0...args.length)
			ctx.vars.push({name: names[i], t: args[i], mutable: false, callable: true});
		var saved = ctx.ret;
		var savedNoReturn = ctx.noEarlyReturn;
		ctx.noEarlyReturn = false;
		var savedLoop = ctx.loop;
		var savedIter = ctx.iterating;
		ctx.lambda++;
		ctx.ret = ret;
		ctx.loop = 0;
		ctx.iterating = [];
		var sig = "(" + [for (i in 0...args.length) names[i] + ":" + Types.str(args[i])].join(", ") + ")";
		var res:Node;
		if (ret != TVoid && r.chance(60)) {
			res = e(t, [S(sig + " -> "), N(expr(ret, ctx, d - 1))]);
		} else {
			var stmts = [];
			var tk = new Node([S("H.tick();")]);
			tk.pinned = true;
			stmts.push(tk);
			var savedBudget = ctx.budget;
			ctx.budget = 1 + r.int(3);
			body(stmts, ctx, d - 1);
			ctx.budget = savedBudget;
			if (ret != TVoid) {
				var rs = new Node([S("return "), N(expr(ret, ctx, d - 1)), S(";")]);
				rs.pinned = true;
				stmts.push(rs);
			}
			res = e(t, [S("function" + sig + ":" + Types.str(ret) + " "), B(new Block(stmts))]);
		}
		ctx.lambda--;
		ctx.ret = saved;
		ctx.noEarlyReturn = savedNoReturn;
		ctx.loop = savedLoop;
		ctx.iterating = savedIter;
		ctx.vars.splice(mark, ctx.vars.length - mark);
		return res;
	}

	function switchExpr(t:Ty, ctx:Ctx, d:Int):Node {
		var n = e(t, [S("switch ")]);
		var cases:Array<Node> = [];
		switchSubject(ctx, d, n, cases, () -> expr(t, ctx, d - 1));
		return e(t, [S("("), N(n), S(")")]);
	}

	/**
		Builds `switch (subject) { cases }` into `n`; `body` produces each case
		body (an expression for switch expressions, a block for statements).
		Pattern variables are in scope while the body is generated.
	**/
	function switchSubject(ctx:Ctx, d:Int, n:Node, cases:Array<Node>, body:() -> Node):Void {
		var kinds = [10, on("strings") ? 5 : 0, enums.length > 0 ? 12 : 0, eabss.length > 0 ? 4 : 0, 2, on("patterns") && on("arrays") ? 3 : 0,
			on("patterns") && anons.length > 0 ? 2 : 0];
		var addCase = (pat:String, binds:Array<LocalVar>) -> {
			for (b in binds)
				ctx.vars.push(b);
			var bd = body();
			for (_ in binds)
				ctx.vars.pop();
			cases.push(new Node([S("case " + pat + ": "), N(bd), S(";")]));
		}
		var needDefault = true;
		switch r.weighted(kinds) {
			case 1:
				n.parts.push(S("("));
				n.parts.push(N(expr(TString, ctx, d - 1)));
				n.parts.push(S(") "));
				addCase("\"a\" | \"b\"", []);
				addCase("\"Haxe\"", []);
				if (r.chance(50))
					addCase("\"\"", []);
			case 2:
				var en = r.pick(enums);
				n.parts.push(S("("));
				n.parts.push(N(enumValue(en, ctx, d - 1)));
				n.parts.push(S(") "));
				var guarded = false;
				for (c in en.ctors) {
					if (r.chance(15) && cases.length > 0)
						continue;
					var binds:Array<LocalVar> = [];
					var pats = [];
					for (a in c.args) {
						if (r.chance(30)) {
							pats.push("_");
							continue;
						}
						switch a.t {
							case TEnum(inner) if (on("patterns") && r.chance(30)):
								var ic = r.pick(inner.ctors);
								pats.push(ic.name + (ic.args.length == 0 ? "" : "(" + [for (_ in ic.args) "_"].join(", ") + ")"));
								guarded = true;
							case TInt if (on("patterns") && r.chance(20)):
								pats.push(Std.string(r.int(3)) + " | " + Std.string(3 + r.int(3)));
								guarded = true;
							default:
								var x = fresh("c");
								binds.push({name: x, t: a.t, mutable: false, callable: false});
								pats.push(x);
						}
					}
					var pat = c.name + (c.args.length == 0 ? "" : "(" + pats.join(", ") + ")");
					if (on("patterns") && binds.length > 0 && binds[0].t == TInt && r.chance(25)) {
						pat += " if (" + binds[0].name + " > " + r.int(5) + ")";
						guarded = true;
					}
					addCase(pat, binds);
				}
				// exhaustive without a default when every constructor is matched unconditionally
				needDefault = guarded || cases.length < en.ctors.length || r.chance(30);
			case 3:
				var a = r.pick(eabss);
				n.parts.push(S("("));
				n.parts.push(N(expr(TEnumAbs(a), ctx, d - 1)));
				n.parts.push(S(") "));
				for (v in a.values)
					addCase(a.name + "." + v.name, []);
				needDefault = r.chance(30);
			case 4:
				n.parts.push(S("("));
				n.parts.push(N(expr(TBool, ctx, d - 1)));
				n.parts.push(S(") "));
				addCase("true", []);
				addCase("false", []);
				needDefault = false;
			case 5:
				// an array literal subject would be matched as a tuple
				n.parts.push(S("(H.id("));
				n.parts.push(N(expr(TArray(TInt), ctx, d - 1)));
				n.parts.push(S(")) "));
				addCase("[]", []);
				var x = fresh("c");
				addCase("[" + x + "]", [{name: x, t: TInt, mutable: false, callable: false}]);
				var y = fresh("c");
				addCase("[_, " + y + "]", [{name: y, t: TInt, mutable: false, callable: false}]);
			case 6:
				var a = r.pick(anons);
				n.parts.push(S("("));
				n.parts.push(N(expr(TAnon(a), ctx, d - 1)));
				n.parts.push(S(") "));
				var f = a.fields[0];
				var x = fresh("c");
				switch f.t {
					case TInt: addCase("{" + f.name + ": 1 | 2}", []);
					case TBool: addCase("{" + f.name + ": true}", []);
					default:
				}
				addCase("{" + f.name + ": " + x + "}", [{name: x, t: f.t, mutable: false, callable: false}]);
				needDefault = false;
			default:
				n.parts.push(S("("));
				n.parts.push(N(expr(TInt, ctx, d - 1)));
				n.parts.push(S(") "));
				addCase("0", []);
				addCase(Std.string(1 + r.int(3)) + " | " + Std.string(4 + r.int(3)), []);
				if (on("patterns") && r.chance(40)) {
					var x = fresh("c");
					addCase(x + " if (" + x + " > 10)", [{name: x, t: TInt, mutable: false, callable: false}]);
				}
		}
		if (needDefault)
			addCase("_", []);
		n.parts.push(B(new Block(cases)));
	}

	// ------------------------------------------------------------------
	// statements

	function body(stmts:Array<Node>, ctx:Ctx, d:Int) {
		while (ctx.budget > 0) {
			ctx.budget--;
			stmts.push(stmt(ctx, d));
		}
	}

	function block(ctx:Ctx, d:Int, n:Int):Block {
		var mark = ctx.vars.length;
		var stmts = [];
		var saved = ctx.budget;
		ctx.budget = n;
		body(stmts, ctx, d);
		ctx.budget = saved;
		ctx.vars.splice(mark, ctx.vars.length - mark);
		return new Block(stmts);
	}

	function stmt(ctx:Ctx, d:Int):Node {
		var nested = d > 1;
		var w = [
			25, // var
			15, // assignment
			18, // out
			nested ? 8 : 0, // if
			nested && on("loops") ? 6 : 0, // for range
			nested && on("loops") ? 3 : 0, // while
			nested && on("loops") && on("arrays") ? 4 : 0, // for over array
			nested && on("switch") ? 6 : 0,
			nested && on("exceptions") ? 4 : 0,
			callable(null, ctx).length > 0 ? 10 : 0, // call statement
			ctx.loop > 0 ? 3 : 0, // break / continue
			on("arrays") ? 4 : 0, // array mutation
			on("maps") ? 3 : 0, // map mutation
			nested && on("localfn") ? 3 : 0, // local function
			nested && on("loops") ? 1 : 0, // do-while
			ctx.ret != TVoid && nested && !ctx.noEarlyReturn ? 2 : 0, // early return
			nested ? 2 : 0, // nested block
			on("loops") && on("maps") && !portable && nested ? 1 : 0, // map iteration
			nested && on("dynamic") ? 1 : 0,
		];
		return switch r.weighted(w) {
			case 0: varDecl(ctx, d);
			case 1: assign(ctx, d);
			case 2: outStmt(ctx, d);
			case 3:
				var c = expr(TBool, ctx, d - 1);
				var then = block(ctx, d - 1, 1 + r.int(3));
				if (r.chance(50)) {
					var els = block(ctx, d - 1, 1 + r.int(2));
					new Node([S("if ("), N(c), S(") "), B(then), S(" else "), B(els)]);
				} else
					new Node([S("if ("), N(c), S(") "), B(then)]);
			case 4:
				var x = fresh("i");
				var lo = r.chance(70) ? "0" : Std.string(r.int(3));
				// a literal range must not go backwards
				var hi = r.chance(60) ? e(TInt, [S(Std.string(Std.parseInt(lo) + r.int(5)))]) : e(TInt, [S("H.lim("), N(expr(TInt, ctx, d - 1)), S(")")]);
				ctx.vars.push({name: x, t: TInt, mutable: false, callable: false});
				var b = loopBody(ctx, d);
				ctx.vars.pop();
				new Node([S("for (" + x + " in " + lo + "..."), N(hi), S(") "), B(b)]);
			case 5:
				var c = fresh("w");
				var cond = expr(TBool, ctx, d - 1);
				var b = loopBody(ctx, d, c + "++;");
				new Node([S("var " + c + " = 0;\n"), S("while (" + c + " < " + (1 + r.int(5)) + " && "), N(cond), S(") "), B(b)]);
			case 6:
				var et = simpleType(1);
				var x = fresh("x");
				var arrVars = vars(TArray(et), ctx);
				var src = arrVars.length > 0 && r.chance(60) ? e(TArray(et), [S(r.pick(arrVars).name)]) : expr(TArray(et), ctx, d - 1);
				var srcName = switch src.parts[0] {
					case S(s): s;
					default: "";
				};
				ctx.iterating.push(srcName);
				if (r.chance(25)) {
					var k = fresh("k");
					ctx.vars.push({name: k, t: TInt, mutable: false, callable: false});
					ctx.vars.push({name: x, t: et, mutable: false, callable: false});
					var b = loopBody(ctx, d);
					ctx.vars.pop();
					ctx.vars.pop();
					ctx.iterating.pop();
					new Node([S("for (" + k + " => " + x + " in "), N(src), S(") "), B(b)]);
				} else {
					ctx.vars.push({name: x, t: et, mutable: false, callable: false});
					var b = loopBody(ctx, d);
					ctx.vars.pop();
					ctx.iterating.pop();
					new Node([S("for (" + x + " in "), N(src), S(") "), B(b)]);
				}
			case 7:
				var n = new Node([S("switch ")]);
				switchSubject(ctx, d, n, [], () -> new Node([B(block(ctx, d - 1, 1 + r.int(2)))]));
				n.parts.push(S(""));
				n;
			case 8: tryStmt(ctx, d);
			case 9:
				var f = r.pick(callable(null, ctx));
				new Node([N(call(f, ctx, d)), S(";")]);
			case 10:
				new Node([S("if ("), N(expr(TBool, ctx, d - 1)), S(") " + (r.chance(50) ? "break;" : "continue;"))]);
			case 11: arrayStmt(ctx, d);
			case 12:
				var k = r.chance(60) ? TString : TInt;
				var vt = simpleType(1);
				var mt = TMap(k, vt);
				var vs = vars(mt, ctx);
				if (vs.length == 0)
					varDecl(ctx, d, mt);
				else {
					var m = r.pick(vs).name;
					if (r.chance(70))
						new Node([S(m + ".set("), N(mapKey(k, ctx, d)), S(", "), N(expr(vt, ctx, d - 1)), S(");")]);
					else
						new Node([S(m + ".remove("), N(mapKey(k, ctx, d)), S(");")]);
				}
			case 13: localFn(ctx, d);
			case 14:
				var c = fresh("w");
				var b = loopBody(ctx, d, c + "++;");
				new Node([S("var " + c + " = 0;\n"), S("do "), B(b), S(" while (" + c + " < " + (1 + r.int(4)) + " && "), N(expr(TBool, ctx, d - 1)), S(");")]);
			case 15:
				new Node([S("if ("), N(expr(TBool, ctx, d - 1)), S(") return "), N(expr(ctx.ret, ctx, d - 1)), S(";")]);
			case 16:
				new Node([B(block(ctx, d - 1, 1 + r.int(3)))]);
			case 17:
				var mt = TMap(TString, TInt);
				var k = fresh("k");
				var v = fresh("v");
				var m = expr(mt, ctx, d - 1);
				ctx.vars.push({name: k, t: TString, mutable: false, callable: false});
				ctx.vars.push({name: v, t: TInt, mutable: false, callable: false});
				var b = loopBody(ctx, d);
				ctx.vars.pop();
				ctx.vars.pop();
				new Node([S("for (" + k + " => " + v + " in "), N(m), S(") "), B(b)]);
			case 18:
				var x = fresh("dyn");
				var a = anons.length > 0 ? r.pick(anons) : null;
				if (a != null)
					new Node([
						S("{ var " + x + ":Dynamic = "),
						N(expr(TAnon(a), ctx, d - 1)),
						S("; H.out(\"dyn \" + Std.string(" + x + "." + a.fields[0].name + ") + \" \" + Std.string(Reflect.field(" + x + ", \"" + a.fields[0].name
							+ "\"))); }")
					]);
				else
					new Node([S("{ var " + x + ":Dynamic = "), N(expr(TInt, ctx, d - 1)), S("; H.out(\"dyn \" + Std.string(" + x + " + 1)); }")]);
			default: outStmt(ctx, d);
		}
	}

	function loopBody(ctx:Ctx, d:Int, ?first:String):Block {
		ctx.loop++;
		var mark = ctx.vars.length;
		var stmts = [];
		if (first != null) {
			var f = new Node([S(first)]);
			f.pinned = true;
			stmts.push(f);
		}
		var t = new Node([S("H.tick();")]);
		t.pinned = true;
		stmts.push(t);
		var saved = ctx.budget;
		ctx.budget = 1 + r.int(3);
		body(stmts, ctx, d - 1);
		ctx.budget = saved;
		ctx.vars.splice(mark, ctx.vars.length - mark);
		ctx.loop--;
		return new Block(stmts);
	}

	function varDecl(ctx:Ctx, d:Int, ?forced:Ty):Node {
		var t = forced != null ? forced : valueType(0);
		var x = fresh("v");
		var init = expr(t, ctx, d - 1);
		var isFun = t.match(TFun(_, _));
		var fin = isFun || r.chance(20);
		var annotate = r.chance(50) || init.parts.length == 1 && switch init.parts[0] {
			case S(s): s == "null" || StringTools.startsWith(s, "new Map");
			default: false;
		};
		// literal-typed initializers of a supertype must keep the annotation
		if (!(t == TInt || t == TString || t == TBool))
			annotate = true;
		var n = new Node([S((fin ? "final " : "var ") + x + (annotate ? ":" + Types.str(t) : "") + " = "), N(init), S(";")]);
		ctx.vars.push({name: x, t: t, mutable: !fin, callable: fin});
		return n;
	}

	function assign(ctx:Ctx, d:Int):Node {
		var t = r.chance(60) ? TInt : valueType(0);
		var targets = [for (v in vars(t, ctx, true)) if (Types.eq(v.t, t) && !v.t.match(TFun(_, _))) v.name].concat(fieldRefs(t, ctx, true).filter(f -> {
			true;
		}));
		if (targets.length == 0)
			return varDecl(ctx, d);
		var target = r.pick(targets);
		if (t == TInt && r.chance(40)) {
			var ops = ["+=", "-=", "*="].concat(on("bits") ? ["|=", "&=", "^=", "<<="] : []);
			var op = r.pick(ops);
			if (op == "<<=")
				return portable ? new Node([S(target + " = H.w(" + target + " << ("), N(expr(TInt, ctx, d - 1)), S(" & 7));")]) : new Node([
					S(target + " <<= ("),
					N(expr(TInt, ctx, d - 1)),
					S(" & 7);")
				]);
			if (portable)
				return new Node([S(target + " = H.w(" + target + " " + op.charAt(0) + " "), N(expr(TInt, ctx, d - 1)), S(");")]);
			return new Node([S(target + " " + op + " "), N(expr(TInt, ctx, d - 1)), S(";")]);
		}
		if (t == TInt && r.chance(20))
			return new Node([S(r.pick([target + "++;", target + "--;", "++" + target + ";"]))]);
		// strings and arrays assigned in loops could double every iteration (`s += s`): capped
		if (t == TString && r.chance(30))
			return r.chance(50) ? new Node([S(target + " += " + strLit() + ";")]) : new Node([
				S(target + " = H.cap(" + target + " + "),
				N(expr(TString, ctx, d - 1)),
				S(");")
			]);
		var v = expr(t, ctx, d - 1);
		if (t == TString)
			v = e(t, [S("H.cap("), N(v), S(")")]);
		else if (t.match(TArray(_)))
			v = e(t, [S("H.capa("), N(v), S(")")]);
		if (Printer.node(v, 0) == target)
			v = e(t, [S("H.id("), N(v), S(")")]);
		if (portable && t == TInt)
			return new Node([S(target + " = H.w("), N(v), S(");")]);
		return new Node([S(target + " = "), N(v), S(";")]);
	}

	function outStmt(ctx:Ctx, d:Int):Node {
		var t = valueType(1);
		if (!printable(t) || !inhabited(t))
			t = r.pick([TInt, TString, TBool]);
		var label = "o" + (counter++);
		return new Node([S("H.out(\"" + label + " \" + "), N(show(t, ctx, d - 1)), S(");")]);
	}

	function arrayStmt(ctx:Ctx, d:Int):Node {
		var et = simpleType(1);
		var t = TArray(et);
		var vs = [for (v in vars(t, ctx)) if (Types.eq(v.t, t) && !ctx.iterating.contains(v.name)) v];
		if (vs.length == 0)
			return varDecl(ctx, d, t);
		var a = r.pick(vs).name;
		return switch r.int(7) {
			case 0: new Node([S(a + ".push("), N(expr(et, ctx, d - 1)), S(");")]);
			case 1: new Node([S(a + ".pop();")]);
			case 2: new Node([S("if (" + a + ".length > 0) " + a + "[H.ix("), N(expr(TInt, ctx, d - 1)), S(", " + a + ".length)] = "), N(expr(et, ctx, d - 1)), S(";")]);
			case 3: new Node([S(a + ".reverse();")]);
			case 4: new Node([S(a + ".unshift("), N(expr(et, ctx, d - 1)), S(");")]);
			case 5:
				switch et {
					case TInt: new Node([S(a + ".sort((x, y) -> x - y);")]);
					case TString: new Node([S(a + ".sort(Reflect.compare);")]);
					default: new Node([S(a + ".insert(0, "), N(expr(et, ctx, d - 1)), S(");")]);
				}
			default: new Node([S(a + ".remove("), N(expr(et, ctx, d - 1)), S(");")]);
		}
	}

	function tryStmt(ctx:Ctx, d:Int):Node {
		var mark = ctx.vars.length;
		var stmts = [];
		var saved = ctx.budget;
		ctx.budget = 1 + r.int(3);
		// a conditional throw, first or last (where every local it may use is declared)
		var throwFirst = r.chance(50);
		if (!throwFirst)
			body(stmts, ctx, d - 1);
		ctx.budget = saved;
		var thrown = switch r.int(4) {
			case 0: e(TString, [S("\"boom\"")]);
			case 1: e(TInt, [S(Std.string(r.int(100)))]);
			case 2: e(TDyn, [S("new Err("), N(expr(TInt, ctx, d - 1)), S(")")]);
			default: e(TString, [N(expr(TString, ctx, d - 1))]);
		};
		stmts.push(new Node([S("if ("), N(expr(TBool, ctx, d - 1)), S(") throw "), N(thrown), S(";")]));
		if (throwFirst) {
			ctx.budget = 1 + r.int(3);
			body(stmts, ctx, d - 1);
			ctx.budget = saved;
		}
		ctx.vars.splice(mark, ctx.vars.length - mark);
		var n = new Node([S("try "), B(new Block(stmts))]);
		var catches = r.chance(50) ? ["String", "Int", "Err", "Dynamic"] : ["Err", "haxe.Exception"];
		if (r.chance(30))
			catches = ["Dynamic"];
		for (c in catches) {
			var x = fresh("ex");
			var ct = switch c {
				case "String": TString;
				case "Int": TInt;
				default: TDyn;
			};
			ctx.vars.push({name: x, t: ct, mutable: false, callable: false});
			var b = block(ctx, d - 1, 1 + r.int(2));
			var report = switch c {
				case "Err": new Node([S("H.out(\"caught Err \" + " + x + ".errCode);")]);
				case "haxe.Exception": new Node([S("H.out(\"caught \" + H.exn(" + x + "));")]);
				case "Dynamic": new Node([S("H.out(\"caught \" + H.exn(" + x + "));")]);
				default: new Node([S("H.out(\"caught " + c + " \" + " + x + ");")]);
			};
			b.items.unshift(report);
			ctx.vars.pop();
			n.parts.push(S(" catch (" + x + ":" + c + ") "));
			n.parts.push(B(b));
		}
		return n;
	}

	function localFn(ctx:Ctx, d:Int):Node {
		var name = fresh("lf");
		if (r.chance(35)) {
			// bounded recursion
			var n = fresh("n");
			ctx.lambda++;
			ctx.vars.push({name: n, t: TInt, mutable: false, callable: false});
			var base = expr(TInt, ctx, d - 1);
			var step = expr(TInt, ctx, d - 1);
			ctx.vars.pop();
			ctx.lambda--;
			var w = portable ? "H.w" : "";
			var node = new Node([
				S("function " + name + "(" + n + ":Int):Int {\n\tH.tick();\n\treturn " + n + " <= 0 ? "),
				N(base),
				S(" : " + w + "(" + name + "(" + n + " - 1) + "),
				N(step),
				S(");\n}\n" + "H.out(\"" + name + " \" + " + name + "(" + r.int(6) + "));")
			]);
			return node;
		}
		var t = TFun([for (_ in 0...r.int(3)) simpleType(1)], r.chance(20) ? TVoid : simpleType(1));
		var l = lambda(t, ctx, d);
		ctx.vars.push({name: name, t: t, mutable: false, callable: true});
		return new Node([S("final " + name + ":" + Types.str(t) + " = "), N(l), S(";")]);
	}
}
