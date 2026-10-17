package hxmc;

import core.Ast;

// The interface of a parsed module, as a hash (the module cache's early
// cutoff, ModuleCache.hx): its declarations as parsed (the conditions
// evaluated) without what its users cannot see of them, the bodies of the
// functions whose type is written out: not inline, not a macro, not
// @:generic (nor in a @:generic class: an instance copies the bodies), the
// arguments and the return type given (a constructor returns Void), in a
// class without build macros (@:build, @:autoBuild, @:genericBuild, which
// may read them). Everything else is in it: names, access, metadata, types,
// the other bodies (inline functions are copied into their callers), the
// initial values of variables and properties, the arguments' default
// values. Positions are not, except those of the expressions it keeps: an
// inlined body keeps its positions in the caller (an edit before it that
// changes its offsets changes the interface). Documentation is not.
class ModuleInterface {
	final b = new StringBuf();
	var keepPos = false;

	function new() {}

	// (a class's fields, once per class: the same order for every instance)
	static final classFields = new Map<String, Array<String>>();
	static final classFieldsMutex = new sys.thread.Mutex();

	static function fieldsOf(c:Class<Dynamic>):Array<String> {
		var n = Type.getClassName(c);
		classFieldsMutex.acquire();
		var l = classFields.get(n);
		if (l == null) {
			l = Type.getInstanceFields(c);
			classFields.set(n, l);
		}
		classFieldsMutex.release();
		return l;
	}

	public static function hash(decls:Array<TypeDecl>):String {
		var w = new ModuleInterface();
		for (d in decls)
			w.decl(d);
		// (two 64-bit hashes of the text)
		var text = w.b.toString();
		return Fingerprint.hash(text) + Fingerprint.hash("i" + text);
	}

	static function hasMeta(meta:Metadata, names:Array<core.MetaList.StrictMeta>):Bool {
		for (n in names)
			if (core.Meta.has(n, meta)) return true;
		return false;
	}

	static final BUILD:Array<core.MetaList.StrictMeta> = [Build, AutoBuild, GenericBuild, Generic, MultiType, Remove];

	function decl(d:TypeDecl) {
		switch d.definition {
			case EClass(c):
				b.add("C");
				typeHead(c.name, c.params, c.meta);
				value(c.flags);
				var strip = !hasMeta(c.meta, BUILD);
				for (f in c.data)
					field(f.cffName.name, [for (a in f.cffAccess) a.access], f.cffMeta, f.cffKind, strip);
			case EAbstract(a):
				b.add("A");
				typeHead(a.name, a.params, a.meta);
				value(a.flags);
				var strip = !hasMeta(a.meta, BUILD);
				for (f in a.data)
					field(f.cffName.name, [for (x in f.cffAccess) x.access], f.cffMeta, f.cffKind, strip);
			case EStatic(s):
				b.add("S");
				typeHead(s.name, s.params, s.meta);
				field(s.name.name, [for (x in s.flags) x.access], s.meta, s.data, true);
			case _:
				// (enums, typedefs, imports, usings: all of it)
				b.add("D");
				value(d.definition);
		}
		b.add(";\n");
	}

	function typeHead(name:PlacedName, params:Array<TypeParam>, meta:Metadata) {
		b.add(name.name);
		value(params);
		value(meta);
	}

	function field(name:String, access:Array<Access>, meta:Metadata, kind:ClassFieldKind, strip:Bool) {
		b.add("\n.");
		b.add(name);
		value(access);
		value(meta);
		switch kind {
			case FFun(f) if (f.fExpr != null && strip && strippable(name, access, meta, f)):
				b.add("F");
				value(f.fParams);
				value(f.fArgs);
				value(f.fType);
				b.add("{}");
			case FFun(f):
				b.add("F");
				value(f.fParams);
				value(f.fArgs);
				value(f.fType);
				expr(f.fExpr);
			case FVar(t, e):
				b.add("V");
				value(t);
				expr(e);
			case FProp(get, set, t, e):
				b.add("P");
				value(get);
				value(set);
				value(t);
				expr(e);
		}
	}

	static function strippable(name:String, access:Array<Access>, meta:Metadata, f:Func):Bool {
		if (access.indexOf(AInline) >= 0 || access.indexOf(AMacro) >= 0 || access.indexOf(AExtern) >= 0) return false;
		if (hasMeta(meta, [Generic, Extern, Build])) return false;
		if (f.fType == null && name != "new") return false;
		for (a in f.fArgs)
			if (a.type == null) return false;
		return true;
	}

	// an expression it keeps: with its positions
	function expr(e:Null<Expr>) {
		var k = keepPos;
		keepPos = true;
		value(e);
		keepPos = k;
	}

	// a value of the syntax tree (enums, structures, arrays, strings and
	// numbers), positions only where they are kept, no documentation
	function value(v:Dynamic) {
		switch Type.typeof(v) {
			case TNull:
				b.add("n");
			case TEnum(_):
				b.add("e");
				b.add(Type.enumConstructor(v));
				b.add("(");
				for (x in Type.enumParameters(v))
					value(x);
				b.add(")");
			case TClass(c) if (c == std.String):
				var s:String = v;
				b.add("s");
				b.add(s.length);
				b.add(":");
				b.add(s);
			case TClass(c) if (c == cast std.Array):
				var a:Array<Dynamic> = v;
				b.add("[");
				for (x in a)
					value(x);
				b.add("]");
			case TClass(c) if (c == core.Globals.Pos):
				if (keepPos) {
					var p:core.Globals.Pos = v;
					b.add("@");
					b.add(p.pmin);
					b.add("-");
					b.add(p.pmax);
				}
			case TClass(c) if (c == DocBlock):
			case TClass(c):
				b.add("{");
				for (f in fieldsOf(c)) {
					var x = Reflect.field(v, f);
					if (Reflect.isFunction(x)) continue;
					value(x);
				}
				b.add("}");
			case TObject:
				var fs = Reflect.fields(v);
				fs.sort(Reflect.compare);
				b.add("{");
				for (f in fs) {
					b.add(f);
					b.add("=");
					value(Reflect.field(v, f));
				}
				b.add("}");
			case TBool:
				b.add(v ? "t" : "f");
			case TInt | TFloat:
				b.add("i");
				b.add(Std.string(v));
			case _:
				b.add("?");
		}
	}
}
