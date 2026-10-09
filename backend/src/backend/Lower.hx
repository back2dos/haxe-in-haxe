package backend;

import backend.Ir;
import core.Ast;
import core.TType;
import core.TFunctions;

using core.TFunctions;

// EXPERIMENTAL (bench/WASM-BACKEND.md): lowers the filtered typed AST (the data
// HXB serializes) of the functions reachable from `main` to the shared IR.
// Covers the subset the prototype benchmark uses: Int/Bool, classes with
// single inheritance, interfaces, enums, Array<T>, closures, exceptions.
class Lower {
	var prog = new Program();
	var classes = new Map<TClass, ClassInfo>();
	var enums = new Map<TEnum, EnumInfo>();
	var statics = new Map<TClassField, FuncInfo>();
	var ctors = new Map<TClass, FuncInfo>();
	var lowered = new Map<FuncInfo, Bool>();
	var pending:Array<() -> Void> = [];
	var tclasses:Array<TClass> = [];
	var root:ClassInfo;
	var usedSelectors = new Map<String, Int>();

	public function new() {
		root = new ClassInfo("Obj", null);
		root.fields.push({name: "__cid", ty: TI32});
		prog.classes.push(root);
	}

	public static function program(main:TClass):Program {
		var l = new Lower();
		var mainField = main.clStatics.get("main");
		l.prog.main = l.staticFunc(main, mainField);
		l.drain();
		l.finish();
		return l.prog;
	}

	function fail(msg:String, ?p:core.Globals.Pos):Dynamic
		throw "backend prototype: " + msg + (p != null ? ' (${p.pfile}:${p.pmin})' : "");

	function drain() {
		while (true) {
			while (pending.length > 0)
				pending.shift()();
			// every implementation of a dispatched selector, in every class seen so far
			var more = false;
			for (name => sel in usedSelectors)
				for (tc in tclasses) {
					var f = tc.clFields.get(name);
					if (f != null && f.cfExpr != null) {
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
		// preorder class ids, so subclass tests are range checks in C
		var next = 0;
		function visit(c:ClassInfo) {
			c.id = next++;
			for (d in prog.classes)
				if (d.sup == c) visit(d);
			c.lastDescendant = next - 1;
		}
		visit(root);
		prog.classes.sort((a, b) -> a.id - b.id);
	}

	// ---- types

	public function ty(t:T):Ty {
		var t = TFunctions.follow(t);
		return switch t {
			case TAbstract(a, params):
				switch a.aPath.name {
					case "Int" | "Bool" if (a.aPath.pack.length == 0): TI32;
					case "Float" if (a.aPath.pack.length == 0): TF64;
					case "Void" if (a.aPath.pack.length == 0): TVoid;
					case "Null" if (a.aPath.pack.length == 0):
						var inner = ty(params[0]);
						if (!Ir.isRef(inner)) fail("Null<basic type> needs boxing (not in the prototype)");
						inner;
					case _: fail("unsupported abstract " + a.aPath.name);
				}
			case TInst(c, params):
				if (c.clPath.pack.length == 0 && c.clPath.name == "Array") TRef(RArr(ty(params[0])));
				else if (c.hasClassFlag(CInterface)) TRef(RObj(root));
				else TRef(RObj(classInfo(c)));
			case TEnum(e, _): TRef(REnum(enumInfo(e)));
			case TFun(s): TRef(RClos(prog.sig([for (a in s.args) ty(a.type)], ty(s.ret))));
			case TDynamic(_): TRef(RAny);
			case _: fail("unsupported type " + core.TPrinting.sType(core.TPrinting.printContext(), t));
		}
	}

	function classInfo(c:TClass):ClassInfo {
		var ci = classes.get(c);
		if (ci != null) return ci;
		if (c.hasClassFlag(CExtern)) fail("extern class " + c.clPath.name);
		var sup = c.clSuper != null ? classInfo(c.clSuper.cls) : root;
		ci = new ClassInfo(c.clPath.name, sup);
		classes.set(c, ci);
		tclasses.push(c);
		prog.classes.push(ci);
		for (f in sup.fields)
			ci.fields.push(f);
		for (f in c.clOrderedFields)
			switch f.cfKind {
				case Var(_): ci.fields.push({name: f.cfName, ty: null});
				case Method(_):
			}
		// field types may refer back to this class
		for (f in c.clOrderedFields)
			switch f.cfKind {
				case Var(_): ci.fields[ci.fieldIndex(f.cfName)].ty = ty(f.cfType);
				case Method(_):
			}
		return ci;
	}

	function enumInfo(e:TEnum):EnumInfo {
		var ei = enums.get(e);
		if (ei != null) return ei;
		ei = new EnumInfo(e.ePath.name);
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
				case TFun(s): ci.params = [for (a in s.args) ty(a.type)];
				case _:
					ci.global = prog.globals.length;
					prog.globals.push({ty: TRef(RCtor(ci)), init: ci});
			}
		}
		return ei;
	}

	function ctorOf(ef:TEnumField, en:TEnum):CtorInfo
		return enumInfo(en).ctors[ef.efIndex];

	// ---- functions

	function staticFunc(c:TClass, cf:TClassField):FuncInfo {
		var fi = statics.get(cf);
		if (fi != null) return fi;
		fi = new FuncInfo(c.clPath.name + "_" + cf.cfName);
		statics.set(cf, fi);
		prog.funcs.push(fi);
		var tf = switch cf.cfExpr.eexpr {
			case TFunction(tf): tf;
			case _: fail("static " + cf.cfName + " is not a function");
		};
		pending.push(() -> new FnLower(this, fi, null, null).run(tf));
		return fi;
	}

	public function method(c:TClass, cf:TClassField):FuncInfo {
		var fi = statics.get(cf);
		if (fi != null) return fi;
		var ci = classInfo(c);
		fi = new FuncInfo(c.clPath.name + "_" + cf.cfName);
		fi.selfClass = ci;
		statics.set(cf, fi);
		ci.methods.set(cf.cfName, fi);
		prog.funcs.push(fi);
		var tf = switch cf.cfExpr.eexpr {
			case TFunction(tf): tf;
			case _: fail("method " + cf.cfName + " is not a function");
		};
		pending.push(() -> new FnLower(this, fi, ci, null).run(tf));
		return fi;
	}

	public function ctor(c:TClass):FuncInfo {
		var fi = ctors.get(c);
		if (fi != null) return fi;
		var ci = classInfo(c);
		fi = new FuncInfo(c.clPath.name + "_new");
		ci.ctor = fi;
		ctors.set(c, fi);
		prog.funcs.push(fi);
		if (c.clConstructor == null) fail("class without constructor " + c.clPath.name);
		var tf = switch c.clConstructor.cfExpr.eexpr {
			case TFunction(tf): tf;
			case _: fail("constructor");
		};
		pending.push(() -> new FnLower(this, fi, ci, null).run(tf, true));
		return fi;
	}

	public function newLambda(sig:SigInfo, captures:Array<Local>, tf:TFunc, boxed:Map<Int, Bool>, outer:Map<Int, Local>):LambdaInfo {
		var fi = new FuncInfo("lambda" + prog.lambdas.length);
		var li = new LambdaInfo(prog.lambdas.length, sig, captures, fi);
		fi.lambda = li;
		prog.lambdas.push(li);
		prog.funcs.push(fi);
		pending.push(() -> {
			var fl = new FnLower(this, fi, null, li);
			fl.boxed = boxed;
			fl.run(tf);
		});
		return li;
	}

	public function rootClass():ClassInfo
		return root;

	public function getProgram():Program
		return prog;

	public function lookupMethod(c:TClass, name:String):{cls:TClass, field:TClassField} {
		var k = c;
		while (k != null) {
			var f = k.clFields.get(name);
			if (f != null && f.cfExpr != null) return {cls: k, field: f};
			k = k.clSuper != null ? k.clSuper.cls : null;
		}
		return fail("no implementation of " + name);
	}

	// virtual unless no known subclass overrides it
	public function needsDispatch(c:TClass, name:String):Bool {
		if (c.hasClassFlag(CInterface)) return true;
		for (d in tclasses)
			if (d != c && isSubclass(d, c) && d.clFields.exists(name) && d.clFields.get(name).cfExpr != null) return true;
		return false;
	}

	function isSubclass(d:TClass, c:TClass):Bool {
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

	public function classOf(c:TClass):ClassInfo
		return classInfo(c);

	public function ctorInfo(ef:TEnumField, en:TEnum):CtorInfo
		return ctorOf(ef, en);
}

// Lowers one function body.
class FnLower {
	var l:Lower;
	var fi:FuncInfo;
	var self:Null<ClassInfo>;
	var lambda:Null<LambdaInfo>;
	var locals = new Map<Int, Local>();
	public var boxed:Map<Int, Bool>;
	var thisLocal:Null<Local>;
	var out:Array<Stmt>;
	var nextLocal = 0;

	public function new(l, fi, self, lambda) {
		this.l = l;
		this.fi = fi;
		this.self = self;
		this.lambda = lambda;
	}

	function fail(msg:String, ?e:TExpr):Dynamic
		throw "backend prototype: " + msg + " in " + fi.name + (e != null ? ' (${e.epos.pfile}:${e.epos.pmin})' : "");

	function newLocal(name:String, t:Ty):Local {
		var lo = new Local(nextLocal++, name, t);
		fi.locals.push(lo);
		return lo;
	}

	function arg(name:String, t:Ty):Local {
		var lo = new Local(nextLocal++, name, t);
		fi.args.push(lo);
		return lo;
	}

	public function run(tf:TFunc, isCtor = false) {
		if (boxed == null) boxed = Boxing.analyze(tf.tfExpr, tf.tfArgs.map(a -> a.variable));
		out = fi.body;
		var root = l.rootClass();
		if (self != null) {
			if (isCtor) {
				thisLocal = arg("this", TRef(RObj(self)));
			} else {
				var t0 = arg("this0", TRef(RObj(root)));
				thisLocal = newLocal("this", TRef(RObj(self)));
				out.push(SSet(thisLocal, ECast(thisLocal.ty, ELocal(t0))));
			}
		}
		var closArg = lambda != null ? arg("clos", TRef(RClos(lambda.sig))) : null;
		var argLocals = [];
		for (a in tf.tfArgs) {
			var v = a.variable;
			var t = l.ty(v.vType);
			var lo = arg(v.vName, t);
			argLocals.push({v: v, lo: lo, t: t});
		}
		fi.ret = l.ty(tf.tfType);
		if (lambda != null) {
			for (i in 0...lambda.captures.length) {
				var c = lambda.captures[i];
				var lo = newLocal(c.name, c.ty);
				locals.set(c.id, lo); // captures are keyed by the outer TVar id
				out.push(SSet(lo, ECapture(lambda, i, ELocal(closArg))));
			}
		}
		for (a in argLocals) {
			if (boxed.exists(a.v.vId)) {
				var b = newLocal(a.v.vName + "_box", TRef(RBox(a.t)));
				out.push(SSet(b, ENewBox(a.t, ELocal(a.lo))));
				locals.set(a.v.vId, b);
			} else locals.set(a.v.vId, a.lo);
		}
		stmt(tf.tfExpr);
	}

	// ---- helpers

	function isBoxed(v:TVar):Bool
		return boxed.exists(v.vId);

	function local(v:TVar, e:TExpr):Local {
		var lo = locals.get(v.vId);
		if (lo == null) fail("unknown local " + v.vName, e);
		return lo;
	}

	function block(f:() -> Void):Array<Stmt> {
		var saved = out;
		out = [];
		f();
		var r = out;
		out = saved;
		return r;
	}

	function temp(t:Ty, e:Ex):Ex {
		var lo = newLocal("t", t);
		out.push(SSet(lo, e));
		return ELocal(lo);
	}

	static function isConst(e:Ex):Bool
		return switch e {
			case EInt(_) | ENull(_) | EGlobal(_, _): true;
			case _: false;
		}

	// lowers operands left to right; spills earlier ones when a later one has side effects
	function operands(es:Array<TExpr>):Array<Ex> {
		var r = [];
		for (e in es) {
			var before = out.length;
			var x = value(e);
			// earlier operands that read locals a later statement might change
			if (out.length != before) {
				var spills = [];
				for (i in 0...r.length)
					if (!isConst(r[i])) {
						var lo = newLocal("s", exTy(r[i], es[i]));
						spills.push(SSet(lo, r[i]));
						r[i] = ELocal(lo);
					}
				for (j in 0...spills.length)
					out.insert(before + j, spills[j]);
			}
			r.push(x);
		}
		return r;
	}

	function exTy(x:Ex, e:TExpr):Ty
		return l.ty(e.etype);

	function asLocal(x:Ex, t:Ty):Local {
		return switch x {
			case ELocal(lo): lo;
			case _:
				var lo = newLocal("a", t);
				out.push(SSet(lo, x));
				lo;
		}
	}

	static function strip(e:TExpr):TExpr
		return switch e.eexpr {
			case TParenthesis(e1) | TMeta(_, e1): strip(e1);
			case TCast(e1, null): strip(e1);
			case _: e;
		}

	// ---- statements

	function stmt(e:TExpr) {
		switch e.eexpr {
			case TBlock(es):
				for (x in es)
					stmt(x);
			case TParenthesis(e1) | TMeta(_, e1):
				stmt(e1);
			case TVar(v, init):
				var t = l.ty(v.vType);
				if (isBoxed(v)) {
					var b = newLocal(v.vName + "_box", TRef(RBox(t)));
					var x = init != null ? value(init) : defaultValue(t);
					locals.set(v.vId, b);
					out.push(SSet(b, ENewBox(t, x)));
				} else {
					var lo = newLocal(v.vName, t);
					if (init != null) {
						var x = rhs(init);
						locals.set(v.vId, lo);
						out.push(SSet(lo, coerce(x, l.ty(init.etype), t)));
					} else {
						locals.set(v.vId, lo);
						out.push(SSet(lo, defaultValue(t)));
					}
				}
			case TIf(c, a, b):
				var cx = value(c);
				out.push(SIf(cx, block(() -> stmt(a)), b != null ? block(() -> stmt(b)) : []));
			case TWhile(c, body, NormalWhile):
				out.push(SLoop(block(() -> {
					var cx = value(c);
					out.push(SIf(ENot(cx), [SBreak], []));
					stmt(body);
				})));
			case TWhile(_, _, DoWhile):
				fail("do-while", e);
			case TSwitch(sw):
				switchStmt(sw, null);
			case TTry(body, catches):
				tryStmt(body, catches, null);
			case TReturn(null):
				out.push(SReturn(null));
			case TReturn(r):
				var x = value(r);
				out.push(SReturn(coerce(x, l.ty(r.etype), fi.ret)));
			case TBreak:
				out.push(SBreak);
			case TContinue:
				out.push(SContinue);
			case TThrow(x):
				out.push(SThrow(value(x)));
			case TCall(_, _) | TNew(_, _, _) | TBinop(OpAssign | OpAssignOp(_), _, _) | TUnop(Increment | Decrement, _, _):
				var x = rhs(e);
				switch x {
					case ECall(_) | ECallDispatch(_) | ECallClos(_) | ECallHost(_) | ENewObj(_) | ENewEnum(_) | ENewArr(_) | ENewClos(_) | ENewBox(_):
						out.push(SExpr(x));
					case _:
				}
			case _:
				value(e);
		}
	}

	function defaultValue(t:Ty):Ex
		return switch t {
			case TI32: EInt(0);
			case TRef(_): ENull(t);
			case _: fail("default value of " + t);
		}

	// assigns the value of a branch to `target` (null: statement)
	function branch(e:TExpr, target:Null<Local>):Array<Stmt> {
		return block(() -> {
			if (target == null) stmt(e) else {
				var x = value(e);
				if (!isNoValue(e)) out.push(SSet(target, coerce(x, l.ty(e.etype), target.ty)));
			}
		});
	}

	static function isNoValue(e:TExpr):Bool
		return switch strip(e).eexpr {
			case TThrow(_) | TReturn(_) | TBreak | TContinue: true;
			case _: false;
		}

	function switchStmt(sw:TSwitch, target:Null<Local>) {
		var subj = value(sw.switchSubject);
		var allInt = true;
		for (c in sw.switchCases)
			for (p in c.casePatterns)
				if (!strip(p).eexpr.match(TConst(TInt(_)))) allInt = false;
		var def = sw.switchDefault != null ? branch(sw.switchDefault, target) : [];
		if (allInt) {
			var cases = [];
			for (c in sw.switchCases)
				cases.push({
					values: [
						for (p in c.casePatterns)
							switch strip(p).eexpr {
								case TConst(TInt(i)): i;
								case _: 0;
							}
					],
					body: branch(c.caseExpr, target)
				});
			out.push(SSwitch(subj, cases, def));
		} else {
			// if-chain on equality
			var s = asLocal(subj, l.ty(sw.switchSubject.etype));
			var chain = def;
			var i = sw.switchCases.length;
			while (i-- > 0) {
				var c = sw.switchCases[i];
				var body = branch(c.caseExpr, target);
				var conds = [];
				var pre = block(() -> {
					for (p in c.casePatterns)
						conds.push(value(p));
				});
				var cond:Ex = null;
				for (cx in conds) {
					var eq = EBin(Ir.isRef(s.ty) ? RefEq : Eq, ELocal(s), cx);
					cond = cond == null ? eq : EBin(Or, cond, eq);
				}
				chain = pre.concat([SIf(cond, body, chain)]);
			}
			for (x in chain)
				out.push(x);
		}
	}

	function tryStmt(body:TExpr, catches:Array<{variable:TVar, expr:TExpr}>, target:Null<Local>) {
		fi.hasTry = true;
		var b = branch(body, target);
		var cs = [];
		for (c in catches) {
			var t = l.ty(c.variable.vType);
			var ci = switch t {
				case TRef(RObj(ci)) if (ci != l.rootClass()): ci;
				case TRef(RAny): null;
				case _: fail("catch type");
			};
			var lo = newLocal(c.variable.vName, ci == null ? TRef(RAny) : t);
			locals.set(c.variable.vId, lo);
			cs.push({c: ci, l: lo, body: branch(c.expr, target)});
		}
		out.push(STry(b, cs));
	}

	// ---- values

	function coerce(x:Ex, from:Ty, to:Ty):Ex {
		return switch [from, to] {
			case [TRef(RObj(a)), TRef(RObj(b))] if (a != b && !isSubclass(a, b)): ECast(to, x);
			case [TRef(RAny), TRef(r)] if (!r.match(RAny)): ECast(to, x);
			case _: x;
		}
	}

	static function isSubclass(a:ClassInfo, b:ClassInfo):Bool {
		var k = a;
		while (k != null) {
			if (k == b) return true;
			k = k.sup;
		}
		return false;
	}

	// a pure expression; side effects go to `out`
	function value(e:TExpr):Ex {
		var x = rhs(e);
		return switch x {
			case ECall(_) | ECallDispatch(_) | ECallClos(_) | ECallHost(_) | ENewObj(_) | ENewEnum(_) | ENewArr(_) | ENewClos(_) | ENewBox(_):
				var t = l.ty(e.etype);
				if (t == TVoid) {
					out.push(SExpr(x));
					EInt(0);
				} else temp(t, x);
			case _: x;
		}
	}

	// an expression that may be a call or allocation at the top
	function rhs(e:TExpr):Ex {
		return switch e.eexpr {
			case TConst(TInt(i)): EInt(i);
			case TConst(TBool(b)): EInt(b ? 1 : 0);
			case TConst(TNull): ENull(l.ty(e.etype));
			case TConst(TThis):
				if (thisLocal == null) fail("this outside a method", e);
				ELocal(thisLocal);
			case TConst(c): fail("constant " + c, e);
			case TLocal(v):
				var lo = local(v, e);
				isBoxed(v) ? EBoxGet(l.ty(v.vType), ELocal(lo)) : ELocal(lo);
			case TParenthesis(e1) | TMeta(_, e1): rhs(e1);
			case TCast(e1, null):
				var x = rhs(e1);
				coerce(x, l.ty(e1.etype), l.ty(e.etype));
			case TField(obj, FInstance(c, _, cf)):
				if (c.clPath.pack.length == 0 && c.clPath.name == "Array" && cf.cfName == "length") EArrLen(value(obj));
				else switch cf.cfKind {
					case Var(_):
						var ci = l.classOf(c);
						EField(ci, ci.fieldIndex(cf.cfName), value(obj));
					case Method(_): fail("method closure", e);
				}
			case TField(_, FEnum(en, ef)):
				var ci = l.ctorInfo(ef, en);
				if (ci.global < 0) fail("constructor as value", e);
				EGlobal(ci.global, TRef(RCtor(ci)));
			case TField(_, _): fail("field access kind", e);
			case TEnumIndex(e1): EEnumTag(value(e1));
			case TEnumParameter(e1, ef, i):
				var en = switch TFunctions.follow(e1.etype) {
					case TEnum(en, _): en;
					case _: fail("enum parameter of non-enum", e);
				};
				EEnumParam(l.ctorInfo(ef, en), i, value(e1));
			case TArray(a, i):
				var xs = operands([a, i]);
				EArrGet(l.ty(e.etype), xs[0], xs[1]);
			case TBinop(op, a, b): binop(op, a, b, e);
			case TUnop(op, flag, e1): unop(op, flag, e1, e);
			case TCall(f, args): call(f, args, e);
			case TNew(c, _, args):
				var ci = l.classOf(c);
				var ctor = l.ctor(c);
				var xs = operands(args);
				var obj = temp(TRef(RObj(ci)), ENewObj(ci));
				out.push(SExpr(ECall(ctor, [obj].concat(xs))));
				obj;
			case TArrayDecl(vs):
				var elem = switch l.ty(e.etype) {
					case TRef(RArr(t)): t;
					case _: fail("array type", e);
				};
				ENewArr(elem, operands(vs));
			case TFunction(tf): closure(tf, e);
			case TBlock(es):
				if (es.length == 0) EInt(0) else {
					for (i in 0...es.length - 1)
						stmt(es[i]);
					rhs(es[es.length - 1]);
				}
			case TIf(c, a, b) if (b != null):
				var t = l.ty(e.etype);
				var cx = value(c);
				var lo = newLocal("r", t);
				out.push(SIf(cx, branch(a, lo), branch(b, lo)));
				ELocal(lo);
			case TSwitch(sw):
				var t = l.ty(e.etype);
				if (t == TVoid) {
					switchStmt(sw, null);
					EInt(0);
				} else {
					var lo = newLocal("r", t);
					switchStmt(sw, lo);
					ELocal(lo);
				}
			case TTry(body, catches):
				var t = l.ty(e.etype);
				var lo = t == TVoid ? null : newLocal("r", t);
				tryStmt(body, catches, lo);
				lo == null ? EInt(0) : ELocal(lo);
			case TThrow(_) | TReturn(_) | TBreak | TContinue | TIf(_, _, _) | TWhile(_, _, _) | TVar(_, _):
				stmt(e);
				EInt(0);
			case _: fail("expression " + e.eexpr.getName(), e);
		}
	}

	function binop(op:Binop, a:TExpr, b:TExpr, e:TExpr):Ex {
		inline function arith(op:Binop):BinOp
			return switch op {
				case OpAdd: Add;
				case OpSub: Sub;
				case OpMult: Mul;
				case OpMod: Mod;
				case OpAnd: And;
				case OpOr: Or;
				case OpXor: Xor;
				case OpShl: Shl;
				case OpShr: Shr;
				case OpUShr: UShr;
				case _: fail("operator " + op, e);
			}
		switch op {
			case OpAssign:
				return assign(a, () -> rhs(b), l.ty(b.etype), e);
			case OpAssignOp(op2):
				var bop = arith(op2);
				return assign(a, null, null, e, (cur) -> EBin(bop, cur, value(b)));
			case OpBoolAnd | OpBoolOr:
				var lo = newLocal("c", TI32);
				out.push(SSet(lo, value(a)));
				var rest = block(() -> out.push(SSet(lo, value(b))));
				out.push(op == OpBoolAnd ? SIf(ELocal(lo), rest, []) : SIf(ELocal(lo), [], rest));
				return ELocal(lo);
			case OpEq | OpNotEq | OpLt | OpLte | OpGt | OpGte:
				var ta = l.ty(a.etype);
				if (ta == TF64) fail("Float comparison", e);
				var xs = operands([a, b]);
				var ref = Ir.isRef(ta) || Ir.isRef(l.ty(b.etype));
				var o = switch op {
					case OpEq: ref ? RefEq : Eq;
					case OpNotEq: ref ? RefNe : Ne;
					case OpLt: Lt;
					case OpLte: Le;
					case OpGt: Gt;
					case _: Ge;
				};
				return EBin(o, xs[0], xs[1]);
			case OpDiv:
				return fail("Float division", e);
			case _:
				if (l.ty(e.etype) != TI32) fail("non-Int arithmetic", e);
				var xs = operands([a, b]);
				return EBin(arith(op), xs[0], xs[1]);
		}
	}

	// lhs = value / lhs = update(lhs); returns the new value
	function assign(lhs:TExpr, value:Null<() -> Ex>, vty:Null<Ty>, e:TExpr, ?update:Ex->Ex):Ex {
		switch strip(lhs).eexpr {
			case TLocal(v):
				var lo = local(v, e);
				var t = l.ty(v.vType);
				if (isBoxed(v)) {
					var x = update != null ? update(EBoxGet(t, ELocal(lo))) : coerce(asPure(value(), t), vty, t);
					var xv = isConst(x) ? x : ELocal(asLocal(x, t));
					out.push(SBoxSet(t, ELocal(lo), xv));
					return xv;
				}
				var x = update != null ? update(ELocal(lo)) : coerce(value(), vty, t);
				out.push(SSet(lo, x));
				return ELocal(lo);
			case TField(obj, FInstance(c, _, cf)):
				var ci = l.classOf(c);
				var idx = ci.fieldIndex(cf.cfName);
				var o = ELocal(asLocal(this.value(obj), l.ty(obj.etype)));
				var x = update != null ? update(EField(ci, idx, o)) : coerce(asPure(value(), l.ty(lhs.etype)), vty, ci.fields[idx].ty);
				var t = ci.fields[idx].ty;
				var v = isConst(x) ? x : ELocal(asLocal(x, t));
				out.push(SSetField(ci, idx, o, v));
				return v;
			case TArray(a, i):
				var t = l.ty(lhs.etype);
				var al = asLocal(this.value(a), l.ty(a.etype));
				var ix = ELocal(asLocal(this.value(i), TI32));
				var x = update != null ? update(EArrGet(t, ELocal(al), ix)) : asPure(value(), t);
				var v = isConst(x) ? x : ELocal(asLocal(x, t));
				out.push(SArrSet(t, al, ix, v));
				return v;
			case _:
				return fail("assignment target", e);
		}
	}

	function asPure(x:Ex, t:Ty):Ex
		return switch x {
			case ECall(_) | ECallDispatch(_) | ECallClos(_) | ECallHost(_) | ENewObj(_) | ENewEnum(_) | ENewArr(_) | ENewClos(_) | ENewBox(_): temp(t, x);
			case _: x;
		}

	function unop(op:Unop, flag:UnopFlag, e1:TExpr, e:TExpr):Ex {
		return switch op {
			case Increment | Decrement:
				var bop = op == Increment ? Add : Sub;
				if (flag == Prefix) assign(e1, null, null, e, (cur) -> EBin(bop, cur, EInt(1))) else {
					var old = newLocal("old", TI32);
					assign(e1, null, null, e, (cur) -> {
						out.push(SSet(old, cur));
						EBin(bop, ELocal(old), EInt(1));
					});
					ELocal(old);
				}
			case Not: ENot(value(e1));
			case Neg: EBin(Sub, EInt(0), value(e1));
			case NegBits: EBin(Xor, value(e1), EInt(-1));
			case Spread: fail("spread", e);
		}
	}

	function call(f:TExpr, args:Array<TExpr>, e:TExpr):Ex {
		switch strip(f).eexpr {
			case TField(_, FStatic(c, cf)):
				if (c.hasClassFlag(CExtern)) return ECallHost(c.clPath.name + "_" + cf.cfName, operands(args));
				return ECall(@:privateAccess l.staticFunc(c, cf), operands(args));
			case TField({eexpr: TConst(TSuper)}, FInstance(c, _, cf)):
				var impl = l.lookupMethod(c, cf.cfName);
				return ECall(l.method(impl.cls, impl.field), [ELocal(thisLocal)].concat(operands(args)));
			case TConst(TSuper):
				var c = superClassOf(e);
				return ECall(l.ctor(c), [ELocal(thisLocal)].concat(operands(args)));
			case TField(obj, FInstance(c, _, cf)):
				if (c.clPath.pack.length == 0 && c.clPath.name == "Array") {
					if (cf.cfName != "push") fail("Array." + cf.cfName, e);
					var xs = operands([obj].concat(args));
					var t = switch l.ty(obj.etype) {
						case TRef(RArr(t)): t;
						case _: fail("array", e);
					};
					var al = asLocal(xs[0], l.ty(obj.etype));
					out.push(SArrPush(t, al, xs[1]));
					return EArrLen(ELocal(al));
				}
				var xs = operands([obj].concat(args));
				if (l.needsDispatch(c, cf.cfName)) {
					var s = switch TFunctions.follow(cf.cfType) {
						case TFun(s): s;
						case _: fail("method type", e);
					};
					var sig = l.getProgram().sig([TRef(RObj(l.rootClass()))].concat([for (a in s.args) l.ty(a.type)]), l.ty(s.ret));
					return ECallDispatch(l.selector(cf.cfName, sig), sig, xs);
				}
				var impl = l.lookupMethod(c, cf.cfName);
				return ECall(l.method(impl.cls, impl.field), xs);
			case TField(_, FEnum(en, ef)):
				return ENewEnum(l.ctorInfo(ef, en), operands(args));
			case _:
				switch l.ty(f.etype) {
					case TRef(RClos(s)):
						var xs = operands([f].concat(args));
						return ECallClos(s, xs[0], xs.slice(1));
					case _:
						return fail("call target " + strip(f).eexpr.getName(), e);
				}
		}
	}

	function superClassOf(e:TExpr):TClass {
		for (tc => ci in @:privateAccess l.classes)
			if (ci == self) return tc.clSuper.cls;
		return fail("super", e);
	}

	function closure(tf:TFunc, e:TExpr):Ex {
		var free = Boxing.freeVars(tf);
		var caps = [];
		var capVals = [];
		for (v in free) {
			var lo = locals.get(v.vId);
			if (lo == null) continue;
			caps.push(new Local(v.vId, v.vName, lo.ty));
			capVals.push(ELocal(lo));
		}
		var sig = switch l.ty(e.etype) {
			case TRef(RClos(s)): s;
			case _: fail("closure type", e);
		};
		var li = l.newLambda(sig, caps, tf, boxed, locals);
		return ENewClos(li, capVals);
	}
}

// Which locals are captured by a closure and also assigned after their
// declaration: those live in a heap box shared by all closures.
class Boxing {
	public static function analyze(body:TExpr, args:Array<TVar>):Map<Int, Bool> {
		var captured = new Map<Int, Bool>();
		var assigned = new Map<Int, Bool>();
		function walk(e:TExpr, depth:Int, declDepth:Map<Int, Int>) {
			switch e.eexpr {
				case TVar(v, init):
					declDepth.set(v.vId, depth);
					if (init != null) walk(init, depth, declDepth);
				case TLocal(v):
					var d = declDepth.get(v.vId);
					if (d != null && d < depth) captured.set(v.vId, true);
				case TBinop(OpAssign | OpAssignOp(_), {eexpr: TLocal(v)}, rhs):
					assigned.set(v.vId, true);
					var d = declDepth.get(v.vId);
					if (d != null && d < depth) captured.set(v.vId, true);
					walk(rhs, depth, declDepth);
				case TUnop(Increment | Decrement, _, {eexpr: TLocal(v)}):
					assigned.set(v.vId, true);
					var d = declDepth.get(v.vId);
					if (d != null && d < depth) captured.set(v.vId, true);
				case TFunction(tf):
					for (a in tf.tfArgs)
						declDepth.set(a.variable.vId, depth + 1);
					walk(tf.tfExpr, depth + 1, declDepth);
				case TTry(b, cs):
					walk(b, depth, declDepth);
					for (c in cs) {
						declDepth.set(c.variable.vId, depth);
						walk(c.expr, depth, declDepth);
					}
				case _:
					core.Texpr.iter(x -> walk(x, depth, declDepth), e);
			}
		}
		var decl = new Map<Int, Int>();
		for (a in args)
			decl.set(a.vId, 0);
		walk(body, 0, decl);
		var r = new Map<Int, Bool>();
		for (id in captured.keys())
			if (assigned.exists(id)) r.set(id, true);
		return r;
	}

	public static function freeVars(tf:TFunc):Array<TVar> {
		var declared = new Map<Int, Bool>();
		for (a in tf.tfArgs)
			declared.set(a.variable.vId, true);
		var seen = new Map<Int, Bool>();
		var r = [];
		function walk(e:TExpr) {
			switch e.eexpr {
				case TVar(v, init):
					declared.set(v.vId, true);
					if (init != null) walk(init);
				case TLocal(v):
					if (!declared.exists(v.vId) && !seen.exists(v.vId)) {
						seen.set(v.vId, true);
						r.push(v);
					}
				case TFunction(tf2):
					for (a in tf2.tfArgs)
						declared.set(a.variable.vId, true);
					walk(tf2.tfExpr);
				case TTry(b, cs):
					walk(b);
					for (c in cs) {
						declared.set(c.variable.vId, true);
						walk(c.expr);
					}
				case _:
					core.Texpr.iter(walk, e);
			}
		}
		walk(tf.tfExpr);
		return r;
	}
}
