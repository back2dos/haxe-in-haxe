package hxmc;

import backend.EmitC;
import backend.Ir;
import backend.EmitC.Refs;

// The program-wide facts hxmc shares with hxc's C emitter, computed by
// EmitC.prepare exactly as for C: no-GC functions, cold sites, type indices
// and object layouts, field ids, the names and values of ids, string literal
// names, and the C text of every function (hybrid builds use it for what
// hxmc does not compile). Native code and C agree on every number this way.
@:access(backend.EmitC)
class Prep {
	public var e:EmitC;
	public var p:Program;

	public function new(p:Program) {
		this.p = p;
		e = new EmitC(p);
		e.single = false;
		// EmitC.prepare without writing the C of every function
		for (f in p.funcs)
			e.byCName.set(e.cname(f), f);
		e.findNoGc();
		e.markCold();
		e.assignTypes();
		e.collectNames();
		e.assignNames();
	}

	// the C of a function (development builds: the functions not compiled natively)
	public function cBody(f:FuncInfo):{text:String, refs:Refs} {
		var r = e.bodies.get(f);
		if (r != null) return r;
		var saved = e.b;
		e.b = new StringBuf();
		e.refs = new Refs();
		e.func(f);
		r = {text: e.b.toString(), refs: e.refs};
		e.bodies.set(f, r);
		e.b = saved;
		return r;
	}

	public inline function id(name:String):Int
		return e.ids.get(name);

	// Program-wide numbers are referenced by name in machine code (absolute
	// symbols DataGen defines, as hxc's ids.h names them), so a module's code
	// does not change when another module adds a type, field or global:
	// the symbol of a type index (null for the runtime's fixed ones)
	public function tySym(tindex:Int):Null<String>
		return tindex < Abi.T_FIRST ? null : e.typeNames[tindex];

	public function fidSym(name:String):String {
		e.fid(name);
		return e.fidNames.get(name);
	}

	public function sigSym(s:SigInfo):String
		return e.sigNames[s.id];

	// 8 * the rt_globals index of a reference global
	public function globalOffSym(g:Int):String
		return "GIOFF_" + e.globalNames[g].substr(3);

	// the type object (Class<T>/Enum<T> value) of a type
	public function typeObjSym(tindex:Int):String
		return "TYOBJ_" + (tindex < Abi.T_FIRST ? Std.string(tindex) : e.typeNames[tindex].substr(3));

	// a class's last descendant minus its type index (instance tests)
	public function spanSym(c:ClassInfo):String
		return "TYSPAN_" + e.typeNames[c.tindex].substr(3);

	// the value of a type index as EmitC writes it
	public inline function fid(name:String):Int
		return e.fid(name);

	public function strSym(s:String):String {
		var n = e.strNames.get(s);
		if (n == null) {
			e.refs = new Refs();
			e.str(s);
			n = e.strNames.get(s);
		}
		return n;
	}

	public function funcSym(f:FuncInfo):String
		return e.cname(f);

	public function selectorSym(sel:Int):String
		return e.selNames[sel];

	// rt_globals index of a reference global, or the symbol of a scalar one
	public function globalIndex(g:Int):Int
		return g;

	public function scalarGlobalSym(g:Int):String
		return e.scalarGlobal(g);

	public function sigId(s:SigInfo):Int
		return s.id;

	public function roots(f:FuncInfo):backend.EmitC.Roots
		return backend.EmitC.Roots.analyze(f);
}
