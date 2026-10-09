package backend;

// EXPERIMENTAL (bench/WASM-BACKEND.md): the typed IR shared by the WasmGC and C
// emitters. Statements are structured (no gotos); expressions are pure except
// as the right-hand side of SSet/SExpr, so evaluation order and GC safepoints
// are explicit and identical on both targets.

enum Ty {
	TI32;
	TF64;
	TVoid;
	TRef(r:RefTy);
}

enum RefTy {
	RObj(c:ClassInfo); // class instance (interfaces use the root object type)
	REnum(e:EnumInfo);
	RCtor(c:CtorInfo); // a specific enum constructor (after a tag test)
	RArr(elem:Ty);
	RClos(s:SigInfo);
	RBox(t:Ty); // captured mutable local
	RAny;
}

class ClassInfo {
	public var id:Int; // preorder number: subclasses are in [id, lastDescendant]
	public var lastDescendant:Int;
	public var name:String;
	public var sup:Null<ClassInfo>;
	public var fields:Array<{name:String, ty:Ty}> = []; // including inherited, slot 0 = class id
	public var methods:Map<String, FuncInfo> = new Map(); // own implementations
	public var ctor:Null<FuncInfo>;
	public var tindex:Int = -1;

	public function new(name, sup) {
		this.name = name;
		this.sup = sup;
	}

	public function fieldIndex(n:String):Int {
		for (i in 0...fields.length)
			if (fields[i].name == n) return i;
		throw 'no field $n in $name';
	}

	public function findMethod(n:String):Null<FuncInfo> {
		var c = this;
		while (c != null) {
			var m = c.methods.get(n);
			if (m != null) return m;
			c = c.sup;
		}
		return null;
	}
}

class EnumInfo {
	public var name:String;
	public var ctors:Array<CtorInfo> = [];

	public function new(name)
		this.name = name;
}

class CtorInfo {
	public var en:EnumInfo;
	public var name:String;
	public var tag:Int;
	public var params:Array<Ty>; // slot 0 = tag, params from slot 1
	public var global:Int = -1; // singleton for constructors without arguments
	public var tindex:Int = -1;

	public function new(en, name, tag, params) {
		this.en = en;
		this.name = name;
		this.tag = tag;
		this.params = params;
	}
}

class SigInfo {
	public var id:Int;
	public var args:Array<Ty>;
	public var ret:Ty;

	public function new(id, args, ret) {
		this.id = id;
		this.args = args;
		this.ret = ret;
	}
}

// A closure environment type: the captured values after the code pointer.
class LambdaInfo {
	public var id:Int;
	public var sig:SigInfo;
	public var captures:Array<Local>;
	public var fn:FuncInfo;
	public var tindex:Int = -1;

	public function new(id, sig, captures, fn) {
		this.id = id;
		this.sig = sig;
		this.captures = captures;
		this.fn = fn;
	}
}

class Local {
	public var id:Int;
	public var name:String;
	public var ty:Ty;

	public function new(id, name, ty) {
		this.id = id;
		this.name = name;
		this.ty = ty;
	}
}

class FuncInfo {
	public var name:String;
	public var args:Array<Local> = [];
	public var ret:Ty = TVoid;
	public var locals:Array<Local> = [];
	public var body:Array<Stmt> = [];
	public var selfClass:Null<ClassInfo>; // instance method: args[0] is `this`, typed as the root object
	public var lambda:Null<LambdaInfo>; // closure body: args[0] is the closure
	public var dispatchSel:Int = -1;
	public var hasTry:Bool = false;

	public function new(name)
		this.name = name;
}

enum Ex {
	EInt(v:Int);
	ENull(t:Ty);
	ELocal(l:Local);
	EGlobal(g:Int, t:Ty);
	EBin(op:BinOp, a:Ex, b:Ex);
	ENot(a:Ex);
	EField(c:ClassInfo, idx:Int, obj:Ex);
	ECast(t:Ty, e:Ex); // checked downcast on WasmGC, unchecked in C
	EInstOf(c:ClassInfo, e:Ex);
	EEnumTag(e:Ex);
	EEnumParam(c:CtorInfo, idx:Int, e:Ex);
	EArrLen(a:Ex);
	EArrGet(elem:Ty, a:Ex, i:Ex);
	EBoxGet(t:Ty, b:Ex);
	ECapture(l:LambdaInfo, idx:Int, clos:Ex);
	// impure: only as the value of SSet / SExpr
	ECall(f:FuncInfo, args:Array<Ex>);
	ECallDispatch(sel:Int, sig:SigInfo, args:Array<Ex>); // virtual and interface calls
	ECallClos(s:SigInfo, clos:Ex, args:Array<Ex>);
	ECallHost(name:String, args:Array<Ex>);
	ENewObj(c:ClassInfo); // zeroed instance; the constructor is called separately
	ENewEnum(c:CtorInfo, args:Array<Ex>);
	ENewArr(elem:Ty, values:Array<Ex>);
	ENewClos(l:LambdaInfo, captures:Array<Ex>);
	ENewBox(t:Ty, v:Ex);
}

enum BinOp {
	Add;
	Sub;
	Mul;
	Mod;
	And;
	Or;
	Xor;
	Shl;
	Shr;
	UShr;
	Eq;
	Ne;
	Lt;
	Le;
	Gt;
	Ge;
	RefEq;
	RefNe;
}

enum Stmt {
	SSet(l:Local, e:Ex);
	SExpr(e:Ex);
	SSetField(c:ClassInfo, idx:Int, obj:Ex, v:Ex);
	SArrSet(elem:Ty, a:Local, i:Ex, v:Ex);
	SArrPush(elem:Ty, a:Local, v:Ex);
	SBoxSet(t:Ty, b:Ex, v:Ex);
	SIf(c:Ex, a:Array<Stmt>, b:Array<Stmt>);
	SLoop(body:Array<Stmt>); // infinite; left with SBreak
	SBreak;
	SContinue;
	SSwitch(e:Ex, cases:Array<{values:Array<Int>, body:Array<Stmt>}>, def:Array<Stmt>);
	SReturn(e:Null<Ex>);
	SThrow(e:Ex);
	STry(body:Array<Stmt>, catches:Array<{c:Null<ClassInfo>, l:Local, body:Array<Stmt>}>);
}

class Program {
	public var classes:Array<ClassInfo> = [];
	public var enums:Array<EnumInfo> = [];
	public var funcs:Array<FuncInfo> = [];
	public var sigs:Array<SigInfo> = [];
	public var lambdas:Array<LambdaInfo> = [];
	public var selectors:Array<{name:String, sig:SigInfo}> = [];
	public var globals:Array<{ty:Ty, init:Null<CtorInfo>}> = [];
	public var main:FuncInfo;

	public function new() {}

	public function sig(args:Array<Ty>, ret:Ty):SigInfo {
		for (s in sigs)
			if (Ir.sameTys(s.args, args) && Ir.sameTy(s.ret, ret)) return s;
		var s = new SigInfo(sigs.length, args, ret);
		sigs.push(s);
		return s;
	}
}

class Ir {
	public static function sameTy(a:Ty, b:Ty):Bool {
		return switch [a, b] {
			case [TI32, TI32] | [TF64, TF64] | [TVoid, TVoid]: true;
			case [TRef(x), TRef(y)]: sameRef(x, y);
			case _: false;
		}
	}

	public static function sameTys(a:Array<Ty>, b:Array<Ty>):Bool {
		if (a.length != b.length) return false;
		for (i in 0...a.length)
			if (!sameTy(a[i], b[i])) return false;
		return true;
	}

	static function sameRef(a:RefTy, b:RefTy):Bool {
		return switch [a, b] {
			case [RObj(x), RObj(y)]: x == y;
			case [REnum(x), REnum(y)]: x == y;
			case [RCtor(x), RCtor(y)]: x == y;
			case [RArr(x), RArr(y)]: sameTy(x, y);
			case [RClos(x), RClos(y)]: x == y;
			case [RBox(x), RBox(y)]: sameTy(x, y);
			case [RAny, RAny]: true;
			case _: false;
		}
	}

	public static function isRef(t:Ty):Bool
		return t.match(TRef(_));
}
