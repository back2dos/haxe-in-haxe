package backend;

import backend.Ir;
import core.Ast.Binop;
import core.Ast.Unop;
import core.TType;
import core.MetaList.StrictMeta;
import core.TFunctions;

using core.TFunctions;

// Lowers the filtered typed AST (the data HXB serializes) of everything
// reachable from `main` to the IR (hxc/README.md).
//
// Representation (see Ir.hx): Int/Bool/Float and haxe.Int64 unboxed;
// everything else is a pointer. Generics are erased: a type parameter is Dynamic (RAny), and values
// are converted (boxed, unboxed, wrapped in adapter closures) where a declared
// type and a use-site type differ: calls, returns, field and enum-argument
// access (FnLower.coerce).
class Lower {
	var prog = new Program();
	var classes = new Map<TClass, ClassInfo>();
	var enums = new Map<TEnum, EnumInfo>();
	var funcs = new Map<TClassField, FuncInfo>();
	var ctors = new Map<TClass, FuncInfo>();
	var pending:Array<() -> Void> = [];
	var tclasses:Array<TClass> = [];
	var root:ClassInfo;
	var usedSelectors = new Map<String, Int>();
	public var defaults = new Map<FuncInfo, Array<Null<TExpr>>>();

	public function new() {
		root = new ClassInfo("Object", "Object", null);
		prog.classes.push(root);
	}

	public static function program(main:TClass, types:Array<core.TType.ModuleType>):Program {
		var l = new Lower();
		var mainField = main.clStatics.get("main");
		l.prog.main = l.staticFunc(main, mainField);
		l.drain();
		l.finish();
		// static initializers run in the order of com.types, which
		// Finalization.sortTypes arranged for static initialization
		var order = new Map<TClass, Int>();
		for (i in 0...types.length)
			switch types[i] {
				case TClassDecl(c): order.set(c, i);
				case _:
			}
		var pos = (fi:FuncInfo) -> {
			var c = l.initOf.get(fi);
			c != null && order.exists(c) ? order.get(c) : types.length;
		};
		l.prog.inits.sort((a, b) -> pos(a) - pos(b));
		if (survey) l.writeSurvey();
		return l.prog;
	}

	// ---- survey mode (HXC_SURVEY=file): record unsupported constructs, keep going

	public static var survey = Sys.getEnv("HXC_SURVEY") != null;
	public var errors = new Map<String, {count:Int, example:String}>();
	public var natives = new Map<String, Int>(); // runtime functions called, with counts

	public function record(e:LowerError, fn:String) {
		var r = errors.get(e.msg);
		if (r == null) errors.set(e.msg, {count: 1, example: fn + " " + e.where}) else r.count++;
	}

	function writeSurvey() {
		var keys = [for (k in errors.keys()) k];
		keys.sort((a, b) -> errors.get(b).count - errors.get(a).count);
		var out = new StringBuf();
		for (k in keys)
			out.add('${errors.get(k).count}\t$k\t${errors.get(k).example}\n');
		var ns = [for (k in natives.keys()) k];
		ns.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		out.add('\n${ns.length} natives:\n');
		for (k in ns)
			out.add('${natives.get(k)}\t$k\n');
		out.add('\n${prog.funcs.length} functions, ${prog.classes.length} classes, ${prog.enums.length} enums, ${prog.shapes.length} shapes, ${prog.lambdas.length} lambdas\n');
		sys.io.File.saveContent(Sys.getEnv("HXC_SURVEY"), out.toString());
	}

	public function guarded(fi:FuncInfo, f:() -> Void):() -> Void {
		return () -> try f() catch (e:LowerError) {
			if (!survey) throw e.toString();
			record(e, fi.name);
			fi.body = [SThrow(ENull(TRef(RAny)))];
		}
	}

	public function fail(msg:String):Dynamic
		throw new LowerError(msg, "");

	public function native(name:String):String {
		natives.set(name, (natives.exists(name) ? natives.get(name) : 0) + 1);
		return name;
	}

	public static function cname(pack:Array<String>, name:String):String
		return pack.concat([name]).join("_");

	public static function nativeName(c:TClass):String
		return cname(c.clPath.pack, c.clPath.name);

	public static function moduleOf(c:TClass):String
		return core.Globals.sTypePath(c.clModule.mPath);

	// the name of the next closure created in `owner`: stable while other functions change
	public static function lambdaName(owner:FuncInfo):String
		return owner.name + "__lambda" + owner.nlambdas++;

	public static function isCore(c:TClass, name:String):Bool
		return c.clPath.pack.length == 0 && c.clPath.name == name;

	var methodsDone = 0; // classes whose every method is lowered

	function drain() {
		while (true) {
			while (pending.length > 0)
				pending.shift()();
			// all methods of every class seen: structural and dynamic access
			// (Iterator.hasNext, Reflect) reach them through the method tables;
			// DCE already removed the unused ones
			while (methodsDone < tclasses.length) {
				var tc = tclasses[methodsDone++];
				for (f in tc.clOrderedFields)
					if (f.cfKind.match(Method(MethNormal | MethInline)) && funcOf(f) != null && !f.hasClassFieldFlag(CfExtern))
						method(tc, f);
			}
			while (pending.length > 0)
				pending.shift()();
			// every implementation of a dispatched selector, in every class seen so far
			var more = false;
			for (name => sel in usedSelectors)
				for (tc in tclasses.copy()) {
					var f = tc.clFields.get(name);
					if (f != null && f.cfExpr != null && !tc.hasClassFlag(CInterface)) {
						var fi = method(tc, f);
						if (fi.dispatchSel < 0) {
							fi.dispatchSel = sel;
							more = true;
						}
					}
				}
			if (!more && pending.length == 0) break;
		}
	}

	function finish() {
		// preorder class ids, so subclass tests are range checks
		var next = 0;
		var children = new Map<ClassInfo, Array<ClassInfo>>();
		for (c in prog.classes)
			if (c.sup != null) {
				if (!children.exists(c.sup)) children.set(c.sup, []);
				children.get(c.sup).push(c);
			}
		function visit(c:ClassInfo) {
			c.id = next++;
			if (children.exists(c)) for (d in children.get(c)) visit(d);
			c.lastDescendant = next - 1;
		}
		visit(root);
		prog.classes.sort((a, b) -> a.id - b.id);
	}

	// ---- types

	public function ty(t:T):Ty {
		var t = TFunctions.followWithoutNull(t);
		return switch t {
			case TMono(_): TRef(RAny);
			case TAbstract(a, params):
				var isStd = a.aPath.pack.length == 0;
				switch a.aPath.name {
					case "Int" if (isStd): TI32;
					case "Bool" if (isStd): TBool;
					case "Float" if (isStd): TF64;
					case "Void" if (isStd): TVoid;
					case "Null" if (isStd):
						var inner = ty(params[0]);
						Ir.isScalar(inner) ? TRef(RNull(inner)) : inner;
					case "Any" if (isStd): TRef(RAny);
					case "Class" | "Enum" if (isStd): TRef(RType);
					case "EnumValue" if (isStd): TRef(REnum(null));
					case "UInt" if (isStd): TI32;
					case "I64" if (a.aPath.pack.join(".") == "hxc"): TI64;
					case _:
						if (core.Meta.has(CoreType, a.aMeta)) fail("core type " + a.aPath.name);
						ty(core.Abstract.getUnderlyingType(a, params));
				}
			case TInst(c, params):
				switch c.clKind {
					case KTypeParameter(_): TRef(RAny);
					case _:
						if (isCore(c, "String")) TRef(RStr);
						else if (isCore(c, "Array")) TRef(RArr(ty(params[0])));
						else if (c.hasClassFlag(CInterface)) TRef(RObj(classInfo(c)));
						else if (c.hasClassFlag(CExtern)) TRef(RNative(nativeName(c)));
						else TRef(RObj(classInfo(c)));
				}
			case TEnum(e, _): TRef(REnum(enumInfo(e)));
			case TFun(s): TRef(RClos(prog.sig([for (a in s.args) ty(a.type)], ty(s.ret))));
			case TAnon(an):
				switch an.aStatus {
					case ClassStatics(_) | EnumStatics(_) | AbstractStatics(_): TRef(RType);
					case _: TRef(RAnon);
				}
			case TDynamic(_): TRef(RAny);
			case _: TRef(RAny);
		}
	}

	public function classInfo(c:TClass):ClassInfo {
		var ci = classes.get(c);
		if (ci != null) return ci;
		if (c.hasClassFlag(CExtern)) fail("extern class " + c.clPath.name + " used as a class");
		if (c.hasClassFlag(CInterface)) {
			// interfaces have no layout: values are any object
			ci = new ClassInfo(core.Globals.sTypePath(c.clPath), nativeName(c), null);
			ci.isInterface = true;
			classes.set(c, ci);
			prog.interfaces.push(ci);
			return ci;
		}
		var sup = c.clSuper != null ? classInfo(c.clSuper.cls) : root;
		ci = new ClassInfo(core.Globals.sTypePath(c.clPath), nativeName(c), sup);
		classes.set(c, ci);
		tclasses.push(c);
		ci.ifaces = sup.ifaces.copy();
		for (i in c.clImplements)
			addIface(ci, i.cls);
		prog.classes.push(ci);
		for (f in sup.fields)
			ci.fields.push(f);
		var own = [];
		for (f in c.clOrderedFields)
			switch f.cfKind {
				case Var(v) if (isPhysical(c, f, v)):
					var slot = {name: f.cfName, ty: null};
					ci.fields.push(slot);
					own.push({slot: slot, f: f});
				// a dynamic method's current function (null until first use or assignment, see FnLower.dynMethod)
				case Method(MethDynamic) if (!Lambda.exists(ci.fields, x -> x.name == f.cfName)):
					var slot = {name: f.cfName, ty: null};
					ci.fields.push(slot);
					own.push({slot: slot, f: f});
				case _:
			}
		// field types may refer back to this class
		for (o in own)
			o.slot.ty = ty(o.f.cfType);
		return ci;
	}

	function addIface(ci:ClassInfo, i:TClass) {
		var ii = classInfo(i);
		if (ci.ifaces.indexOf(ii) < 0) ci.ifaces.push(ii);
		for (j in i.clImplements)
			addIface(ci, j.cls);
	}

	// a var field with storage (not a property with only accessor methods):
	// tFunctions.ml is_physical_var_field, but inline vars have no storage
	static function isPhysical(c:TClass, f:TClassField, v:VarKind):Bool {
		return switch [v.vRead, v.vWrite] {
			case [AccInline, _]: false;
			case [AccNormal | AccNo, _] | [_, AccNormal | AccNo]: true;
			case _: core.Meta.has(IsVar, f.cfMeta);
		}
	}

	public function enumInfo(e:TEnum):EnumInfo {
		var ei = enums.get(e);
		if (ei != null) return ei;
		ei = new EnumInfo(core.Globals.sTypePath(e.ePath), cname(e.ePath.pack, e.ePath.name));
		enums.set(e, ei);
		prog.enums.push(ei);
		for (name in e.eNames) {
			var ef = e.eConstrs.get(name);
			ei.ctors.push(new CtorInfo(ei, name, ef.efIndex, []));
		}
		ei.ctors.sort((a, b) -> a.tag - b.tag);
		for (name in e.eNames) {
			var ef = e.eConstrs.get(name);
			var ci = ei.ctors[ef.efIndex];
			switch TFunctions.follow(ef.efType) {
				case TFun(s):
					ci.params = [for (a in s.args) ty(a.type)];
					ci.paramNames = [for (a in s.args) a.name];
				case _:
					ci.global = prog.globals.length;
					prog.globals.push({ty: TRef(RCtor(ci)), init: ci, name: ei.cname + "_" + ci.name});
			}
		}
		return ei;
	}

	public function ctorInfo(ef:TEnumField, en:TEnum):CtorInfo
		return enumInfo(en).ctors[ef.efIndex];

	// ---- functions

	static function funcOf(cf:TClassField):TFunc
		return cf.cfExpr == null ? null : switch cf.cfExpr.eexpr {
			case TFunction(tf): tf;
			case _: null;
		}

	// argument and return representation of a function: the signature callers see
	function signature(fi:FuncInfo, tf:TFunc, self:Null<Ty>) {
		var id = 0;
		if (self != null) fi.args.push(new Local(id++, "this0", self));
		for (a in tf.tfArgs)
			fi.args.push(new Local(id++, a.variable.vName, ty(a.variable.vType)));
		fi.ret = ty(tf.tfType);
		var ds = [for (a in tf.tfArgs) a.defaultValue];
		if (self != null) ds.unshift(null);
		defaults.set(fi, ds);
	}

	public function staticFunc(c:TClass, cf:TClassField):FuncInfo {
		var fi = funcs.get(cf);
		if (fi != null) return fi;
		var tf = funcOf(cf);
		if (tf == null) fail("static " + cf.cfName + " is not a function");
		fi = new FuncInfo(nativeName(c) + "_" + cf.cfName, moduleOf(c));
		funcs.set(cf, fi);
		prog.funcs.push(fi);
		signature(fi, tf, null);
		pending.push(guarded(fi, () -> new FnLower(this, fi, null, null).run(tf)));
		return fi;
	}

	// The declaration a method overrides or implements: its signature is the one
	// every implementation of the selector shares.
	public function rootDecl(c:TClass, name:String):TClassField {
		var best:TClassField = null;
		function visit(k:TClass) {
			if (k == null) return;
			var f = k.clFields.get(name);
			if (f != null) best = f;
			if (k.clSuper != null) visit(k.clSuper.cls);
			for (i in k.clImplements)
				visit(i.cls);
		}
		visit(c);
		return best;
	}

	public function method(c:TClass, cf:TClassField):FuncInfo {
		var fi = funcs.get(cf);
		if (fi != null) return fi;
		var tf = funcOf(cf);
		if (tf == null) fail("method " + cf.cfName + " is not a function");
		var ci = classInfo(c);
		fi = new FuncInfo(nativeName(c) + "_" + cf.cfName, moduleOf(c));
		fi.selfClass = ci;
		funcs.set(cf, fi);
		ci.methods.set(cf.cfName, fi);
		prog.funcs.push(fi);
		// shared signature: the root declaration's (generic parameters are Dynamic there)
		var decl = rootDecl(c, cf.cfName);
		var dtf = decl != null ? funcOf(decl) : null;
		if (dtf != null && dtf.tfArgs.length == tf.tfArgs.length) {
			signature(fi, dtf, TRef(RObj(root)));
		} else if (decl != null && dtf == null) {
			// interface or abstract declaration without a body: use its type
			switch TFunctions.follow(decl.cfType) {
				case TFun(s) if (s.args.length == tf.tfArgs.length):
					var id = 0;
					fi.args.push(new Local(id++, "this0", TRef(RObj(root))));
					for (a in s.args)
						fi.args.push(new Local(id++, a.name, ty(a.type)));
					fi.ret = ty(s.ret);
					var ds:Array<Null<TExpr>> = [null];
					for (a in tf.tfArgs) ds.push(a.defaultValue);
					defaults.set(fi, ds);
				case _: signature(fi, tf, TRef(RObj(root)));
			}
		} else signature(fi, tf, TRef(RObj(root)));
		pending.push(guarded(fi, () -> new FnLower(this, fi, ci, null).run(tf)));
		return fi;
	}

	public function ctor(c:TClass):FuncInfo {
		var fi = ctors.get(c);
		if (fi != null) return fi;
		var ci = classInfo(c);
		fi = new FuncInfo(nativeName(c) + "_new", moduleOf(c));
		ci.ctor = fi;
		ctors.set(c, fi);
		prog.funcs.push(fi);
		if (c.clConstructor == null) {
			// no constructor: the parent's, or nothing
			signature(fi, {tfArgs: [], tfType: null, tfExpr: null}, TRef(RObj(ci)));
			fi.ret = TVoid;
			return fi;
		}
		var tf = funcOf(c.clConstructor);
		signature(fi, tf, TRef(RObj(ci)));
		fi.ret = TVoid;
		pending.push(guarded(fi, () -> new FnLower(this, fi, ci, null).run(tf, true)));
		return fi;
	}

	// `name` and `module`: a name that stays the same when unrelated code changes
	// (Lower.lambdaName for closures in a function body, else derived from what
	// the closure forwards to) and the module whose C file holds it
	public function newLambda(sig:SigInfo, captures:Array<Local>, body:FnLower->Void, name:String, module:String):LambdaInfo {
		var fi = new FuncInfo(name, module);
		var li = new LambdaInfo(prog.lambdas.length, sig, captures, fi);
		fi.lambda = li;
		fi.args.push(new Local(0, "clos", TRef(RClos(sig))));
		for (i in 0...sig.args.length)
			fi.args.push(new Local(i + 1, "a" + i, sig.args[i]));
		fi.ret = sig.ret;
		prog.lambdas.push(li);
		prog.funcs.push(fi);
		pending.push(guarded(fi, () -> body(new FnLower(this, fi, null, li))));
		return li;
	}

	// a closure calling a static function (the function used as a value)
	var staticClosures = new Map<FuncInfo, LambdaInfo>();

	// the class is used as a value: its statics become reachable dynamically
	public function reflectStatics(c:TClass) {
		if (c.hasClassFlag(CExtern) || c.hasClassFlag(CInterface)) return;
		var ci = classInfo(c);
		if (ci.statics != null) return;
		ci.statics = [];
		for (cf in c.clOrderedStatics)
			switch cf.cfKind {
				case Method(MethNormal | MethInline) if (funcOf(cf) != null):
					ci.statics.push({name: cf.cfName, clos: staticClosure(staticFunc(c, cf)), global: -1});
				case Var(v) if (isPhysical(c, cf, v) && !v.vRead.match(AccInline)):
					ci.statics.push({name: cf.cfName, clos: null, global: staticVar(c, cf)});
				case _:
			}
	}

	public function staticClosure(f:FuncInfo):LambdaInfo {
		var li = staticClosures.get(f);
		if (li != null) return li;
		var sig = prog.sig([for (a in f.args) a.ty], f.ret);
		li = newLambda(sig, [], fl -> fl.forward(f, null), f.name + "__sclos", f.module);
		staticClosures.set(f, li);
		return li;
	}

	var hostClosures = new Map<String, LambdaInfo>();

	// a closure calling a runtime function (an extern static used as a value)
	public function hostClosure(name:String, sig:SigInfo, ?self:Ty):LambdaInfo {
		var li = hostClosures.get(name);
		if (li != null) return li;
		li = newLambda(sig, self == null ? [] : [new Local(-1, "self", self)], fl -> fl.forwardHost(name), name + "__hclos", "_closures");
		hostClosures.set(name, li);
		return li;
	}

	var ctorClosures = new Map<CtorInfo, LambdaInfo>();

	public function ctorClosure(ci:CtorInfo, sig:SigInfo):LambdaInfo {
		var li = ctorClosures.get(ci);
		if (li != null) return li;
		li = newLambda(sig, [], fl -> fl.forwardCtor(ci), ci.en.cname + "_" + ci.name + "__cclos", "_closures");
		ctorClosures.set(ci, li);
		return li;
	}

	// a closure over `this` calling a method (obj.method used as a value)
	var boundClosures = new Map<FuncInfo, LambdaInfo>();

	public function boundClosure(f:FuncInfo, dispatch:Null<{sel:Int, sig:SigInfo}>, owner:FuncInfo):LambdaInfo {
		var li = boundClosures.get(f);
		if (li != null && dispatch == null) return li;
		var args = [for (i in 1...f.args.length) f.args[i].ty];
		var sig = prog.sig(args, f.ret);
		var self = new Local(-1, "self", TRef(RObj(root)));
		li = newLambda(sig, [self], fl -> fl.forward(f, dispatch), dispatch == null ? f.name + "__bound" : lambdaName(owner), dispatch == null ? f.module : owner.module);
		if (dispatch == null) boundClosures.set(f, li);
		return li;
	}

	// a closure converting between two closure representations
	var adapters = new Map<String, LambdaInfo>();

	public function adapter(from:SigInfo, to:SigInfo):LambdaInfo {
		var key = from.key + ">" + to.key;
		var li = adapters.get(key);
		if (li != null) return li;
		var inner = new Local(-1, "inner", TRef(RClos(from)));
		li = newLambda(to, [inner], fl -> fl.adapt(from), "adapt__" + from.key + "__" + to.key, "_closures");
		adapters.set(key, li);
		return li;
	}

	var staticVars = new Map<TClassField, Int>();

	// a class static variable: a global, initialized by the static initializer
	public function staticVar(c:TClass, cf:TClassField):Int {
		var g = staticVars.get(cf);
		if (g != null) return g;
		var t = ty(cf.cfType); // first: it may register globals itself (enum constructors)
		g = prog.globals.length;
		prog.globals.push({ty: t, init: null, name: nativeName(c) + "_" + cf.cfName});
		staticVars.set(cf, g);
		initClass(c);
		return g;
	}

	var initialized = new Map<TClass, Bool>();
	var initOf = new Map<FuncInfo, TClass>();

	// static variable initializers and __init__ of a class, run at startup
	// (in the order of com.types, see `program`)
	function initClass(c:TClass) {
		if (initialized.exists(c)) return;
		initialized.set(c, true);
		var fi = new FuncInfo(nativeName(c) + "__init", moduleOf(c));
		prog.funcs.push(fi);
		prog.inits.push(fi);
		initOf.set(fi, c);
		pending.push(guarded(fi, () -> new FnLower(this, fi, null, null).runInit(c)));
	}

	public function rootClass():ClassInfo
		return root;

	public function getProgram():Program
		return prog;

	public function lookupMethod(c:TClass, name:String):Null<{cls:TClass, field:TClassField}> {
		var k = c;
		while (k != null) {
			var f = k.clFields.get(name);
			if (f != null && f.cfExpr != null) return {cls: k, field: f};
			k = k.clSuper != null ? k.clSuper.cls : null;
		}
		return null;
	}

	// virtual unless no known subclass overrides it
	public function needsDispatch(c:TClass, name:String):Bool {
		if (c.hasClassFlag(CInterface)) return true;
		var f = c.clFields.get(name);
		if (f != null && f.hasClassFieldFlag(CfFinal)) return false;
		for (d in tclasses)
			if (d != c && isSubclass(d, c) && d.clFields.exists(name) && d.clFields.get(name).cfExpr != null) return true;
		// a subclass loaded later may still override: dispatch if any descendant is known to the typer
		for (d in c.clDescendants)
			if (d.clFields.exists(name) && d.clFields.get(name).cfExpr != null) return true;
		return false;
	}

	static function isSubclass(d:TClass, c:TClass):Bool {
		var k = d;
		while (k != null) {
			if (k == c) return true;
			k = k.clSuper != null ? k.clSuper.cls : null;
		}
		return false;
	}

	public function selector(name:String, sig:SigInfo):Int {
		var s = usedSelectors.get(name);
		if (s != null) return s;
		s = prog.selectors.length;
		prog.selectors.push({name: name, sig: sig});
		usedSelectors.set(name, s);
		return s;
	}

	public function superOf(ci:ClassInfo):TClass {
		for (tc => c in classes)
			if (c == ci) return tc.clSuper != null ? tc.clSuper.cls : null;
		return null;
	}
}

class LowerError {
	public var msg:String;
	public var where:String;

	public function new(msg, where) {
		this.msg = msg;
		this.where = where;
	}

	public function toString()
		return "backend: " + msg + (where != "" ? " (" + where + ")" : "");
}
