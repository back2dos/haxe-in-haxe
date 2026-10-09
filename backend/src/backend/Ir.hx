package backend;

// EXPERIMENTAL (bench/WASM-BACKEND.md): the typed IR between the typed AST and
// the C emitter. Statements are structured (no gotos); expressions are pure
// except as the right-hand side of SSet/SExpr, so evaluation order and GC
// points are explicit.

enum Ty {
	TI32;
	TBool; // an i32 at run time; kept apart so boxing and Std.string know it
	TF64;
	TVoid;
	TRef(r:RefTy);
}

enum RefTy {
	RObj(c:ClassInfo); // class instance (interfaces use the root object type)
	REnum(e:Null<EnumInfo>); // enum value; null: any enum (EnumValue)
	RCtor(c:CtorInfo); // a specific enum constructor (after a tag test)
	RArr(elem:Ty); // the runtime array also records its element kind (§ arrays in rt.h)
	RClos(s:SigInfo);
	RBox(t:Ty); // captured mutable local
	RNull(t:Ty); // Null<Int>, Null<Float>, Null<Bool>: a Dynamic box or null
	RStr;
	RAnon; // anonymous structure, any shape: fields found through the type's field table
	RAny; // Dynamic, type parameters, Any
	RType; // Class<T> / Enum<T>: a runtime type descriptor
	RNative(path:String); // instance of an extern class, implemented by the runtime
}

class ClassInfo {
	public var id:Int; // preorder number: subclasses are in [id, lastDescendant]
	public var lastDescendant:Int;
	public var name:String; // Haxe dot path
	public var cname:String; // C identifier prefix
	public var sup:Null<ClassInfo>;
	public var fields:Array<{name:String, ty:Ty}> = []; // including inherited (the class is the header's type index)
	public var methods:Map<String, FuncInfo> = new Map(); // own implementations
	public var ctor:Null<FuncInfo>;
	public var tindex:Int = -1;
	public var isInterface = false;
	public var ifaces:Array<ClassInfo> = []; // implemented interfaces, including inherited ones
	// statics reachable through the class value (Dynamic access, Reflect): set once the class is used as a value
	public var statics:Null<Array<{name:String, clos:Null<LambdaInfo>, global:Int}>> = null;

	public function new(name, cname, sup) {
		this.name = name;
		this.cname = cname;
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
	public var cname:String;
	public var ctors:Array<CtorInfo> = [];
	public var tindex:Int = -1; // the enum's own descriptor (Enum<T> values)

	public function new(name, cname) {
		this.name = name;
		this.cname = cname;
	}
}

class CtorInfo {
	public var en:EnumInfo;
	public var name:String;
	public var tag:Int;
	public var params:Array<Ty>; // from slot 0: the tag is the header's type index (rt.h)
	public var paramNames:Array<String> = [];
	public var global:Int = -1; // singleton for constructors without arguments
	public var tindex:Int = -1;

	public function new(en, name, tag, params) {
		this.en = en;
		this.name = name;
		this.tag = tag;
		this.params = params;
	}
}

// An anonymous structure layout: the fields of an object literal, sorted by name.
class ShapeInfo {
	public var id:Int;
	public var fields:Array<{name:String, ty:Ty}>; // slot 0 = dynamic overflow fields, then these
	public var tindex:Int = -1;

	public function new(id, fields) {
		this.id = id;
		this.fields = fields;
	}

	public function slot(name:String):Int {
		for (i in 0...fields.length)
			if (fields[i].name == name) return i + 1;
		return -1;
	}
}

// A function signature by C representation: i (Int), b (Bool), f (Float),
// p (any reference), v (Void). Closures of the same representation are
// interchangeable; others need an adapter (FnLower.coerce).
class SigInfo {
	public var id:Int;
	public var args:Array<Ty>;
	public var ret:Ty;
	public var key:String;

	public function new(id, args, ret, key) {
		this.id = id;
		this.args = args;
		this.ret = ret;
		this.key = key;
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
	EF64(v:Float);
	EStr(s:String); // a literal, statically allocated
	ENull(t:Ty);
	ELocal(l:Local);
	EGlobal(g:Int, t:Ty);
	EBin(op:BinOp, a:Ex, b:Ex);
	ENot(a:Ex);
	EConv(op:ConvOp, a:Ex);
	EBox(t:Ty, a:Ex); // scalar -> Dynamic box (cached for small ints)
	EUnbox(t:Ty, a:Ex); // Dynamic or Null<T> -> scalar (null gives 0)
	EField(c:ClassInfo, idx:Int, obj:Ex);
	EAnonGet(name:String, t:Ty, obj:Ex); // structural field read, converted to t
	ECast(t:Ty, e:Ex); // unchecked
	EInstOf(c:ClassInfo, e:Ex);
	EEnumTag(e:Ex, en:Null<EnumInfo>); // en: the value's enum when known
	EEnumParam(c:CtorInfo, idx:Int, e:Ex);
	EArrLen(a:Ex);
	EArrGet(elem:Ty, a:Ex, i:Ex);
	EBoxGet(t:Ty, b:Ex);
	ECapture(l:LambdaInfo, idx:Int, clos:Ex);
	EType(t:TypeRef); // runtime type descriptor (Class<T>, Enum<T> values)
	// impure: only as the value of SSet / SExpr
	ECall(f:FuncInfo, args:Array<Ex>);
	ECallDispatch(sel:Int, sig:SigInfo, args:Array<Ex>); // virtual and interface calls
	ECallClos(s:SigInfo, clos:Ex, args:Array<Ex>);
	ECallAnon(name:String, s:SigInfo, obj:Ex, args:Array<Ex>); // obj.name(args) through a structural type: a method or a closure field
	ECallHost(name:String, args:Array<Ex>, ret:Ty); // runtime function (backend/rt)
	ENewObj(c:ClassInfo); // zeroed instance; the constructor is called separately
	ENewEnum(c:CtorInfo, args:Array<Ex>);
	ENewArr(elem:Ty, values:Array<Ex>);
	ENewClos(l:LambdaInfo, captures:Array<Ex>);
	ENewBox(t:Ty, v:Ex);
	ENewAnon(s:ShapeInfo, values:Array<Ex>);
}

enum TypeRef {
	TRClass(c:ClassInfo);
	TREnum(e:EnumInfo);
	TRBuiltin(name:String); // String, Int, Float, Bool, Array, Dynamic, ...
}

enum ConvOp {
	I2F; // Int -> Float
	F2I; // Float -> Int, truncating (Std.int)
	FNeg;
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
	FAdd;
	FSub;
	FMul;
	FDiv;
	FMod;
	FEq;
	FNe;
	FLt;
	FLe;
	FGt;
	FGe;
}

enum Stmt {
	SSet(l:Local, e:Ex);
	SExpr(e:Ex);
	SSetField(c:ClassInfo, idx:Int, obj:Ex, v:Ex);
	SAnonSet(name:String, t:Ty, obj:Ex, v:Ex);
	SArrSet(elem:Ty, a:Local, i:Ex, v:Ex);
	SArrPush(elem:Ty, a:Local, v:Ex);
	SBoxSet(t:Ty, b:Ex, v:Ex);
	SSetGlobal(g:Int, v:Ex);
	SIf(c:Ex, a:Array<Stmt>, b:Array<Stmt>);
	SLoop(body:Array<Stmt>); // infinite; left with SBreak
	SBreak;
	SContinue;
	SSwitch(e:Ex, cases:Array<{values:Array<Int>, body:Array<Stmt>}>, def:Array<Stmt>);
	SReturn(e:Null<Ex>);
	SThrow(e:Ex);
	STry(body:Array<Stmt>, catches:Array<{test:Null<Ex->Ex>, l:Local, body:Array<Stmt>}>);
}

class Program {
	public var classes:Array<ClassInfo> = [];
	public var interfaces:Array<ClassInfo> = [];
	public var enums:Array<EnumInfo> = [];
	public var shapes:Array<ShapeInfo> = [];
	public var funcs:Array<FuncInfo> = [];
	public var sigs:Array<SigInfo> = [];
	public var lambdas:Array<LambdaInfo> = [];
	public var selectors:Array<{name:String, sig:SigInfo}> = [];
	public var globals:Array<{ty:Ty, init:Null<CtorInfo>, name:String}> = [];
	public var inits:Array<FuncInfo> = []; // static initializers, run before main
	public var main:FuncInfo;

	public function new() {}

	public function sig(args:Array<Ty>, ret:Ty):SigInfo {
		var key = [for (a in args) Ir.repr(a)].join("") + "_" + Ir.repr(ret);
		for (s in sigs)
			if (s.key == key) return s;
		var norm = (t:Ty) -> Ir.isRef(t) ? TRef(RAny) : t;
		var s = new SigInfo(sigs.length, [for (a in args) norm(a)], norm(ret), key);
		sigs.push(s);
		return s;
	}

	public function shape(fields:Array<{name:String, ty:Ty}>):ShapeInfo {
		var fs = fields.copy();
		fs.sort((a, b) -> a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
		for (s in shapes)
			if (s.fields.length == fs.length) {
				var same = true;
				for (i in 0...fs.length)
					if (s.fields[i].name != fs[i].name || Ir.repr(s.fields[i].ty) != Ir.repr(fs[i].ty)) same = false;
				if (same) return s;
			}
		var s = new ShapeInfo(shapes.length, fs);
		shapes.push(s);
		return s;
	}
}

class Ir {
	public static function repr(t:Ty):String
		return switch t {
			case TI32: "i";
			case TBool: "b";
			case TF64: "f";
			case TVoid: "v";
			case TRef(_): "p";
		}

	public static function isRef(t:Ty):Bool
		return t.match(TRef(_));

	public static function isScalar(t:Ty):Bool
		return t == TI32 || t == TBool || t == TF64;
}
