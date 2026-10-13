package hxmc;

import backend.EmitC;
import backend.Ir;

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
		e.prepare();
	}

	public inline function id(name:String):Int
		return e.ids.get(name);

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
