package libs.swflib;

import libs.swflib.As3;
import libs.swflib.As3hl;

// port: haxe/libs/swflib/as3hlparse.ml, the parts the generator reaches:
// stack_delta and the FLATTEN section. The hl -> as3 `parse` direction reads
// SWF libraries and is not ported.
class As3hlparse {
	static function assertFalse():Dynamic throw new core.ds.Failure("assert false");

	public static function stack_delta(op:HlOpcode):Int return switch op {
		case HBreakPoint: 0;
		case HNop: 0;
		case HThrow: -1;
		case HGetSuper(_): 0;
		case HSetSuper(_): -2;
		case HDxNs(_): 0;
		case HDxNsLate: -1;
		case HRegKill(_): 0;
		case HLabel: 0;
		case HJump(cond, _):
			(switch cond {
				case J3Always: 0;
				case J3True | J3False: -1;
				case _: -2;
			});
		case HSwitch(_): -1;
		case HPushWith: -1;
		case HPopScope: 0;
		case HForIn: -1;
		case HHasNext: -1;
		case HNull | HUndefined: 1;
		case HForEach: -1;
		case HSmallInt(_) | HInt(_) | HTrue | HFalse | HString(_) | HIntRef(_) | HUIntRef(_) | HFunction(_) | HFloat(_) | HNaN: 1;
		case HPop: -1;
		case HDup: 1;
		case HSwap: 0;
		case HScope: -1;
		case HNamespace(_): 1;
		case HNext(_): 1;
		case HCallStack(n): -(n + 1);
		case HConstruct(n): -n;
		case HCallMethod(_, n): -n;
		case HCallStatic(_, n): -n;
		case HCallSuper(_, n): -n;
		case HCallProperty(_, n): -n;
		case HRetVoid: 0;
		case HRet: -1;
		case HConstructSuper(n): -(n + 1);
		case HConstructProperty(_, n): -n;
		case HCallPropLex(_, n): -n;
		case HCallSuperVoid(_, n): -(n + 1);
		case HCallPropVoid(_, n): -(n + 1);
		case HApplyType(n): -n;
		case HObject(n): -(n * 2) + 1;
		case HArray(n): -n + 1;
		case HNewBlock: 1;
		case HClassDef(_): 0;
		case HGetDescendants(_): 0;
		case HCatch(_): 1;
		case HFindPropStrict(_): 1;
		case HFindProp(_): 1;
		case HFindDefinition(_): 1;
		case HGetLex(_): 1;
		case HSetProp(_): -2;
		case HReg(_): 1;
		case HSetReg(_) | HSetThis: -1;
		case HGetGlobalScope | HGetScope(_): 1;
		case HGetProp(_): 0;
		case HInitProp(_): -2;
		case HDeleteProp(_): -1; /* true/false */
		case HGetSlot(_): 0;
		case HSetSlot(_): -2;
		case HToString | HToXml | HToXmlAttr | HToInt | HToUInt | HToNumber | HToObject | HAsAny | HAsType(_) | HIsType(_) | HAsObject | HAsString | HToBool: 0;
		case HCheckIsXml: 0;
		case HCast(_): 0;
		case HTypeof: 0;
		case HInstanceOf: -1;
		case HIncrReg(_) | HDecrReg(_) | HIncrIReg(_) | HDecrIReg(_): 0;
		case HThis: 1;
		case HDebugReg(_) | HDebugLine(_) | HBreakPointLine(_) | HTimestamp | HDebugFile(_): 0;
		case HOp(op):
			(switch op {
				case A3ONeg | A3OINeg | A3OIncr | A3ODecr | A3ONot | A3OBitNot | A3OIIncr | A3OIDecr: 0;
				case A3OMemGet8 | A3OMemGet16 | A3OMemGet32 | A3OMemGetFloat | A3OMemGetDouble | A3OSign1 | A3OSign8 | A3OSign16: 0;
				case A3OMemSet8 | A3OMemSet16 | A3OMemSet32 | A3OMemSetFloat | A3OMemSetDouble: -2;
				case _: -1;
			});
		case HUnk(_): assertFalse();
	}

	/* ************************************************************************ */
	/*			FLATTEN															*/
	/* ************************************************************************ */
	static function new_lookup<H, I>(f:FlattenCtx->H->I, key:H->String):Lookup<H, I> return new Lookup(f, key);

	static function new_index_lookup<H, I>(l:Array<H>, f:FlattenCtx->H->I):IndexLookup<H, I> {
		var a:Array<Null<I>> = [];
		for (_ in l) a.push(null);
		return new IndexLookup(l, a, f);
	}

	static function lookup_array<H, I>(l:Lookup<H, I>):Array<I> return l.a.copy();

	static function lookup_index_array<H, I>(l:IndexLookup<H, I>):Array<I> {
		return [for (x in l.ordered_array) if (x == null) assertFalse() else x];
	}

	static function lookup<H, I>(ctx:FlattenCtx, l:Lookup<H, I>, item:H):Index {
		var k = l.key(item);
		var idx = l.h.get(k);
		if (idx == null) {
			var i = l.a.length;
			/* set dummy value for recursion */
			l.a.push(null);
			l.h.set(k, i + 1);
			l.a[i] = l.f(ctx, item);
			idx = i + 1;
		}
		return idx;
	}

	static function lookup_index_nz<H, I>(ctx:FlattenCtx, l:IndexLookup<H, I>, item:H):IndexNz {
		var idx = -1;
		for (n in 0...l.ordered_list.length) if (l.ordered_list[n] == item) {
			idx = n;
			break;
		}
		if (idx < 0) assertFalse();
		if (l.ordered_array[idx] == null) {
			/* set dummy value for recursion */
			l.ordered_array[idx] = cast l.dummy;
			l.ordered_array[idx] = l.map_f(ctx, item);
		}
		return idx;
	}

	static function lookup_nz<H, I>(ctx:FlattenCtx, l:Lookup<H, I>, item:H):IndexNz return lookup(ctx, l, item) - 1;

	static function lookup_ident(ctx:FlattenCtx, i:HlIdent):Index return lookup(ctx, ctx.fidents, i);

	static function lookup_name(ctx:FlattenCtx, n:HlName):Index return lookup(ctx, ctx.fnames, n);

	static function lookup_method(ctx:FlattenCtx, m:HlMethod):IndexNz return lookup_index_nz(ctx, ctx.fmethods, m);

	static function lookup_class(ctx:FlattenCtx, c:HlClass):IndexNz return lookup_index_nz(ctx, ctx.fclasses, c);

	static inline function opt<A, B>(f:FlattenCtx->A->B, ctx:FlattenCtx, x:Null<A>):Null<B> return x == null ? null : f(ctx, x);

	// port: OCaml evaluates constructor arguments, tuples and record fields
	// (in declaration order) right to left; the lookups in this section keep
	// that order, which decides the pool indices.
	static function flatten_namespace(ctx:FlattenCtx, ns:HlNamespace):As3Namespace return switch ns {
		case HNPrivate(i): A3NPrivate(opt(lookup_ident, ctx, i));
		case HNPublic(i): A3NPublic(opt(lookup_ident, ctx, i));
		case HNInternal(i): A3NInternal(opt(lookup_ident, ctx, i));
		case HNProtected(i): A3NProtected(lookup_ident(ctx, i));
		case HNNamespace(i): A3NNamespace(lookup_ident(ctx, i));
		case HNExplicit(i): A3NExplicit(lookup_ident(ctx, i));
		case HNStaticProtected(i): A3NStaticProtected(opt(lookup_ident, ctx, i));
	}

	static function flatten_ns_set(ctx:FlattenCtx, n:HlNsSet):As3NsSet return [for (ns in n) lookup(ctx, ctx.fnamespaces, ns)];

	static function flatten_name(ctx:FlattenCtx, n:HlName):As3MultiName return switch n {
		case HMPath(pack, i):
			var ns = HNPublic(switch pack {
				case []: null;
				case l: l.join(".");
			});
			var nsi = lookup(ctx, ctx.fnamespaces, ns);
			A3MName(lookup_ident(ctx, i), nsi);
		case HMName(i, n):
			var nsi = lookup(ctx, ctx.fnamespaces, n);
			A3MName(lookup_ident(ctx, i), nsi);
		case HMNSAny(i): A3MNSAny(lookup_ident(ctx, i));
		case HMAny: A3MAny;
		case HMMultiName(i, ns):
			var nsi = lookup(ctx, ctx.fnsets, ns);
			A3MMultiName(opt(lookup_ident, ctx, i), nsi);
		case HMRuntimeName(i): A3MRuntimeName(lookup_ident(ctx, i));
		case HMRuntimeNameLate: A3MRuntimeNameLate;
		case HMMultiNameLate(ns): A3MMultiNameLate(lookup(ctx, ctx.fnsets, ns));
		case HMAttrib(n): A3MAttrib(flatten_name(ctx, n));
		case HMParams(i, nl):
			var pl = [for (n in nl) lookup_name(ctx, n)];
			A3MParams(lookup_name(ctx, i), pl);
	}

	static function flatten_meta(ctx:FlattenCtx, m:HlMetadata):As3Metadata {
		var data = [
			for (d in m.hlmeta_data) {
				var v = lookup_ident(ctx, d.v);
				{k: opt(lookup_ident, ctx, d.k), v: v};
			}
		];
		return {
			meta3_name: lookup_ident(ctx, m.hlmeta_name),
			meta3_data: data,
		};
	}

	static function flatten_value(ctx:FlattenCtx, v:HlValue):As3Value return switch v {
		case HVNone: A3VNone;
		case HVNull: A3VNull;
		case HVBool(b): A3VBool(b);
		case HVString(s): A3VString(lookup_ident(ctx, s));
		case HVInt(i): A3VInt(lookup(ctx, ctx.fints, i));
		case HVUInt(i): A3VUInt(lookup(ctx, ctx.fuints, i));
		case HVFloat(f): A3VFloat(lookup(ctx, ctx.ffloats, f));
		case HVNamespace(n, ns): A3VNamespace(n, lookup(ctx, ctx.fnamespaces, ns));
	}

	static function flatten_field(ctx:FlattenCtx, f:HlField):As3Field {
		var metas = switch f.hlf_metas {
			case null: null;
			case a: [for (m in a) lookup_nz(ctx, ctx.fmetas, m)];
		};
		var kind = switch f.hlf_kind {
			case HFMethod(m):
				A3FMethod({
					m3_type: lookup_method(ctx, m.hlm_type),
					m3_final: m.hlm_final,
					m3_override: m.hlm_override,
					m3_kind: m.hlm_kind,
				});
			case HFVar(v):
				var value = flatten_value(ctx, v.hlv_value);
				var t = opt(lookup_name, ctx, v.hlv_type);
				A3FVar({
					v3_type: t,
					v3_value: value,
					v3_const: v.hlv_const,
				});
			case HFFunction(f):
				A3FFunction(lookup_method(ctx, f));
			case HFClass(c):
				A3FClass(lookup_class(ctx, c));
		};
		var name = lookup_name(ctx, f.hlf_name);
		return {
			f3_name: name,
			f3_slot: f.hlf_slot,
			f3_kind: kind,
			f3_metas: metas,
		};
	}

	static function flatten_class(ctx:FlattenCtx, c:HlClass):{cl:As3Class, st:As3Static} {
		var st_fields = [for (f in c.hlc_static_fields) flatten_field(ctx, f)];
		var st_method = lookup_method(ctx, c.hlc_static_construct);
		var st:As3Static = {
			st3_method: st_method,
			st3_fields: st_fields,
		};
		var fields = [for (f in c.hlc_fields) flatten_field(ctx, f)];
		var construct = lookup_method(ctx, c.hlc_construct);
		var impls = [for (n in c.hlc_implements) lookup_name(ctx, n)];
		var namespace = opt((ctx, ns) -> lookup(ctx, ctx.fnamespaces, ns), ctx, c.hlc_namespace);
		var sup = opt(lookup_name, ctx, c.hlc_super);
		var name = lookup_name(ctx, c.hlc_name);
		var cl:As3Class = {
			cl3_name: name,
			cl3_super: sup,
			cl3_sealed: c.hlc_sealed,
			cl3_final: c.hlc_final,
			cl3_interface: c.hlc_interface,
			cl3_namespace: namespace,
			cl3_implements: impls,
			cl3_construct: construct,
			cl3_fields: fields,
		};
		return {cl: cl, st: st};
	}

	static function flatten_opcode(ctx:FlattenCtx, i:Int, op:HlOpcode):As3Opcode return switch op {
		case HBreakPoint: A3BreakPoint;
		case HNop: A3Nop;
		case HThrow: A3Throw;
		case HGetSuper(n): A3GetSuper(lookup_name(ctx, n));
		case HSetSuper(n): A3SetSuper(lookup_name(ctx, n));
		case HDxNs(s): A3DxNs(lookup_ident(ctx, s));
		case HDxNsLate: A3DxNsLate;
		case HRegKill(r): A3RegKill(r);
		case HLabel: A3Label;
		case HJump(j, n):
			ctx.fjumps.unshift(i);
			A3Jump(j, n);
		case HSwitch(n, l):
			ctx.fjumps.unshift(i);
			A3Switch(n, l);
		case HPushWith: A3PushWith;
		case HPopScope: A3PopScope;
		case HForIn: A3ForIn;
		case HHasNext: A3HasNext;
		case HNull: A3Null;
		case HUndefined: A3Undefined;
		case HForEach: A3ForEach;
		case HSmallInt(n): A3SmallInt(n);
		case HInt(n): A3Int(n);
		case HTrue: A3True;
		case HFalse: A3False;
		case HNaN: A3NaN;
		case HPop: A3Pop;
		case HDup: A3Dup;
		case HSwap: A3Swap;
		case HString(s): A3String(lookup_ident(ctx, s));
		case HIntRef(i): A3IntRef(lookup(ctx, ctx.fints, i));
		case HUIntRef(i): A3UIntRef(lookup(ctx, ctx.fuints, i));
		case HFloat(f): A3Float(lookup(ctx, ctx.ffloats, f));
		case HScope: A3Scope;
		case HNamespace(n): A3Namespace(lookup(ctx, ctx.fnamespaces, n));
		case HNext(r1, r2): A3Next(r1, r2);
		case HFunction(m): A3Function(lookup_method(ctx, m));
		case HCallStack(n): A3CallStack(n);
		case HConstruct(n): A3Construct(n);
		case HCallMethod(s, n): A3CallMethod(s, n);
		case HCallStatic(m, n): A3CallStatic(lookup_method(ctx, m) + 1, n);
		case HCallSuper(i, n): A3CallSuper(lookup_name(ctx, i), n);
		case HCallProperty(i, n): A3CallProperty(lookup_name(ctx, i), n);
		case HRetVoid: A3RetVoid;
		case HRet: A3Ret;
		case HConstructSuper(n): A3ConstructSuper(n);
		case HConstructProperty(i, n): A3ConstructProperty(lookup_name(ctx, i), n);
		case HCallPropLex(i, n): A3CallPropLex(lookup_name(ctx, i), n);
		case HCallSuperVoid(i, n): A3CallSuperVoid(lookup_name(ctx, i), n);
		case HCallPropVoid(i, n): A3CallPropVoid(lookup_name(ctx, i), n);
		case HApplyType(n): A3ApplyType(n);
		case HObject(n): A3Object(n);
		case HArray(n): A3Array(n);
		case HNewBlock: A3NewBlock;
		case HClassDef(c): A3ClassDef(lookup_class(ctx, c));
		case HGetDescendants(i): A3GetDescendants(lookup_name(ctx, i));
		case HCatch(n): A3Catch(n);
		case HFindPropStrict(i): A3FindPropStrict(lookup_name(ctx, i));
		case HFindProp(i): A3FindProp(lookup_name(ctx, i));
		case HFindDefinition(i): A3FindDefinition(lookup_name(ctx, i));
		case HGetLex(i): A3GetLex(lookup_name(ctx, i));
		case HSetProp(i): A3SetProp(lookup_name(ctx, i));
		case HReg(r): A3Reg(r);
		case HSetReg(r): A3SetReg(r);
		case HGetGlobalScope: A3GetGlobalScope;
		case HGetScope(n): A3GetScope(n);
		case HGetProp(n): A3GetProp(lookup_name(ctx, n));
		case HInitProp(n): A3InitProp(lookup_name(ctx, n));
		case HDeleteProp(n): A3DeleteProp(lookup_name(ctx, n));
		case HGetSlot(s): A3GetSlot(s);
		case HSetSlot(s): A3SetSlot(s);
		case HToString: A3ToString;
		case HToXml: A3ToXml;
		case HToXmlAttr: A3ToXmlAttr;
		case HToInt: A3ToInt;
		case HToUInt: A3ToUInt;
		case HToNumber: A3ToNumber;
		case HToBool: A3ToBool;
		case HToObject: A3ToObject;
		case HCheckIsXml: A3CheckIsXml;
		case HCast(n): A3Cast(lookup_name(ctx, n));
		case HAsAny: A3AsAny;
		case HAsString: A3AsString;
		case HAsType(n): A3AsType(lookup_name(ctx, n));
		case HAsObject: A3AsObject;
		case HIncrReg(r): A3IncrReg(r);
		case HDecrReg(r): A3DecrReg(r);
		case HTypeof: A3Typeof;
		case HInstanceOf: A3InstanceOf;
		case HIsType(t): A3IsType(lookup_name(ctx, t));
		case HIncrIReg(r): A3IncrIReg(r);
		case HDecrIReg(r): A3DecrIReg(r);
		case HThis: A3This;
		case HSetThis: A3SetThis;
		case HDebugReg(i, r, l): A3DebugReg(lookup_ident(ctx, i), r, l);
		case HDebugLine(l): A3DebugLine(l);
		case HDebugFile(f): A3DebugFile(lookup_ident(ctx, f));
		case HBreakPointLine(n): A3BreakPointLine(n);
		case HTimestamp: A3Timestamp;
		case HOp(op): A3Op(op);
		case HUnk(c): A3Unk(c);
	}

	static function flatten_code(ctx:FlattenCtx, hcode:Array<HlOpcode>, trys:Array<HlTryCatch>):{code:Array<As3Opcode>, trys:Array<As3TryCatch>} {
		var positions = [for (_ in 0...hcode.length + 1) 0];
		var pos = 0;
		var old = ctx.fjumps;
		ctx.fjumps = [];
		var code = [];
		for (i in 0...hcode.length) {
			var op = flatten_opcode(ctx, i, hcode[i]);
			pos = pos + As3code.length(op);
			positions[i + 1] = pos;
			code.push(op);
		}
		/* patch jumps */
		for (j in ctx.fjumps) {
			code[j] = switch code[j] {
				case A3Jump(jc, n):
					A3Jump(jc, positions[j + n] - positions[j + 1]);
				case A3Switch(n, infos):
					A3Switch(positions[j + n] - positions[j], [for (n in infos) positions[j + n] - positions[j]]);
				case _: assertFalse();
			}
		}
		/* patch trys */
		var trys = [
			for (t in trys) {
				// port: right-to-left record field evaluation (tc3_name first).
				var name = opt(lookup_name, ctx, t.hltc_name);
				var type = opt(lookup_name, ctx, t.hltc_type);
				({
					tc3_start: positions[t.hltc_start],
					tc3_end: positions[t.hltc_end],
					tc3_handle: positions[t.hltc_handle],
					tc3_type: type,
					tc3_name: name,
				} : As3TryCatch);
			}
		];
		ctx.fjumps = old;
		return {code: code, trys: trys};
	}

	static function flatten_function(ctx:FlattenCtx, f:HlFunction, mid:IndexNz):As3Function {
		var r = flatten_code(ctx, f.hlf_code, f.hlf_trys);
		// port: right-to-left record field evaluation: fun3_locals, the last field, after the code (a let).
		var locals = [
			for (l in f.hlf_locals) {
				var t = opt(lookup_name, ctx, l.type);
				var name = lookup_name(ctx, l.name);
				({
					f3_name: name,
					f3_slot: l.slot,
					f3_kind: A3FVar({v3_type: t, v3_value: A3VNone, v3_const: l.const}),
					f3_metas: null,
				} : As3Field);
			}
		];
		return {
			fun3_id: mid,
			fun3_stack_size: f.hlf_stack_size,
			fun3_nregs: f.hlf_nregs,
			fun3_init_scope: f.hlf_init_scope,
			fun3_max_scope: f.hlf_max_scope,
			fun3_code: r.code,
			fun3_trys: r.trys,
			fun3_locals: locals,
		};
	}

	static function flatten_method(ctx:FlattenCtx, m:HlMethod):As3MethodType {
		var mid = lookup_method(ctx, m);
		switch m.hlmt_function {
			case null:
			case f:
				var x = flatten_function(ctx, f, mid);
				ctx.ffunctions.unshift(x);
		}
		// port: right-to-left record field evaluation.
		var pnames = opt((ctx, l:Array<Null<HlIdent>>) -> [for (i in l) opt(lookup_ident, ctx, i)], ctx, m.hlmt_pnames);
		var dparams = opt((ctx, l:Array<HlValue>) -> [for (v in l) flatten_value(ctx, v)], ctx, m.hlmt_dparams);
		var debug_name = opt(lookup_ident, ctx, m.hlmt_debug_name);
		var args = [for (a in m.hlmt_args) opt(lookup_name, ctx, a)];
		var ret = opt(lookup_name, ctx, m.hlmt_ret);
		return {
			mt3_ret: ret,
			mt3_args: args,
			mt3_native: m.hlmt_native,
			mt3_var_args: m.hlmt_var_args,
			mt3_arguments_defined: m.hlmt_arguments_defined,
			mt3_uses_dxns: m.hlmt_uses_dxns,
			mt3_new_block: m.hlmt_new_block,
			mt3_unused_flag: m.hlmt_unused_flag,
			mt3_debug_name: debug_name,
			mt3_dparams: dparams,
			mt3_pnames: pnames,
		};
	}

	static function flatten_static(ctx:FlattenCtx, s:HlStatic):As3Static {
		// port: right-to-left record field evaluation.
		var fields = [for (f in s.hls_fields) flatten_field(ctx, f)];
		var method = lookup_method(ctx, s.hls_method);
		return {
			st3_method: method,
			st3_fields: fields,
		};
	}

	static function browse_method(ctx:BrowseCtx, m:HlMethod):Void {
		if (ctx.ml.indexOf(m) < 0) {
			ctx.ml.unshift(m);
			switch m.hlmt_function {
				case null:
				case f:
					for (op in f.hlf_code) switch op {
						case HFunction(f) | HCallStatic(f, _): browse_method(ctx, f);
						case HClassDef(_): /* ignore, should be in fields list anyway */
						case _:
					}
			}
		}
	}

	static function browse_class(ctx:BrowseCtx, c:HlClass):Void {
		if (ctx.cl.indexOf(c) < 0) {
			ctx.cl.unshift(c);
			browse_method(ctx, c.hlc_construct);
			browse_method(ctx, c.hlc_static_construct);
			for (f in c.hlc_fields) browse_field(ctx, f);
			for (f in c.hlc_static_fields) browse_field(ctx, f);
		}
	}

	static function browse_field(ctx:BrowseCtx, f:HlField):Void {
		switch f.hlf_kind {
			case HFMethod(m): browse_method(ctx, m.hlm_type);
			case HFVar(_):
			case HFFunction(m): browse_method(ctx, m);
			case HFClass(c): browse_class(ctx, c);
		}
	}

	public static function flatten(t:HlTag):As3Tag {
		/* collect methods and classes, sort by index and force evaluation in order to keep order */
		var bctx:BrowseCtx = {ml: [], cl: []};
		for (s in t) {
			for (f in s.hls_fields) browse_field(bctx, f);
			browse_method(bctx, s.hls_method);
		}
		var classes = bctx.cl.copy();
		classes.reverse();
		haxe.ds.ArraySort.sort(classes, (c1, c2) -> c1.hlc_index - c2.hlc_index);
		var methods = bctx.ml.copy();
		methods.reverse();
		haxe.ds.ArraySort.sort(methods, (m1, m2) -> m1.hlmt_index - m2.hlmt_index);
		/* done */
		var ctx = new FlattenCtx();
		ctx.fints = new_lookup((_, x:HlInt) -> x, (i:HlInt) -> Std.string(i));
		ctx.fuints = new_lookup((_, x:HlUint) -> x, (i:HlUint) -> Std.string(i));
		ctx.ffloats = new_lookup((_, x:HlFloat) -> x, floatKey);
		ctx.fidents = new_lookup((_, x:HlIdent) -> x, (s:HlIdent) -> s);
		ctx.fnamespaces = new_lookup(flatten_namespace, nsKey);
		ctx.fnsets = new_lookup(flatten_ns_set, nsSetKey);
		ctx.fnames = new_lookup(flatten_name, nameKey);
		ctx.fmetas = new_lookup(flatten_meta, metaKey);
		ctx.fmethods = new_index_lookup(methods, flatten_method);
		ctx.fclasses = new_index_lookup(classes, flatten_class);
		ctx.fjumps = [];
		ctx.ffunctions = [];
		lookup_ident(ctx, "");
		var inits = [for (s in t) flatten_static(ctx, s)];
		var classes = lookup_index_array(ctx.fclasses);
		var functions = ctx.ffunctions.copy();
		functions.reverse();
		return {
			as3_ints: lookup_array(ctx.fints),
			as3_uints: lookup_array(ctx.fuints),
			as3_floats: lookup_array(ctx.ffloats),
			as3_idents: lookup_array(ctx.fidents),
			as3_namespaces: lookup_array(ctx.fnamespaces),
			as3_nsets: lookup_array(ctx.fnsets),
			as3_names: lookup_array(ctx.fnames),
			as3_metadatas: lookup_array(ctx.fmetas),
			as3_method_types: lookup_index_array(ctx.fmethods),
			as3_classes: [for (c in classes) c.cl],
			as3_statics: [for (c in classes) c.st],
			as3_functions: functions,
			as3_inits: inits,
			as3_unknown: "",
		};
	}

	// port: the structural Hashtbl keys of the flatten lookups, as strings that
	// are equal exactly when OCaml's `compare` returns 0 (floats: every NaN is
	// one key, as is 0.0 with -0.0).
	static function floatKey(f:Float):String {
		if (Math.isNaN(f)) return "nan";
		if (f == 0) return "0";
		var i = haxe.io.FPHelper.doubleToI64(f);
		return i.high + ":" + i.low;
	}

	static function optKey(s:Null<String>):String return s == null ? "N" : "S" + s.length + ":" + s;

	static function nsKey(ns:HlNamespace):String return switch ns {
		case HNPrivate(i): "a" + optKey(i);
		case HNPublic(i): "b" + optKey(i);
		case HNInternal(i): "c" + optKey(i);
		case HNProtected(i): "d" + optKey(i);
		case HNNamespace(i): "e" + optKey(i);
		case HNExplicit(i): "f" + optKey(i);
		case HNStaticProtected(i): "g" + optKey(i);
	}

	static function nsSetKey(l:HlNsSet):String return l.length + "[" + [for (ns in l) nsKey(ns)].join(",") + "]";

	static function nameKey(n:HlName):String return switch n {
		case HMPath(pack, name): "P" + pack.length + "(" + [for (p in pack) optKey(p)].join("") + ")" + optKey(name);
		case HMName(i, ns): "N" + optKey(i) + nsKey(ns);
		case HMMultiName(i, ns): "M" + optKey(i) + nsSetKey(ns);
		case HMRuntimeName(i): "R" + optKey(i);
		case HMRuntimeNameLate: "L";
		case HMMultiNameLate(ns): "T" + nsSetKey(ns);
		case HMAttrib(n): "A(" + nameKey(n) + ")";
		case HMParams(n, pl): "X(" + nameKey(n) + ")" + pl.length + "[" + [for (p in pl) nameKey(p)].join(",") + "]";
		case HMNSAny(i): "Y" + optKey(i);
		case HMAny: "Z";
	}

	static function metaKey(m:HlMetadata):String
		return optKey(m.hlmeta_name) + m.hlmeta_data.length + "[" + [for (d in m.hlmeta_data) optKey(d.k) + optKey(d.v)].join(",") + "]";
}

private typedef BrowseCtx = {
	var ml:Array<HlMethod>;
	var cl:Array<HlClass>;
}

private class Lookup<H, I> {
	public final h:Map<String, Int> = new Map();
	public final a:Array<Null<I>> = [];
	public final f:FlattenCtx->H->I;
	public final key:H->String;

	public function new(f, key) {
		this.f = f;
		this.key = key;
	}
}

private class IndexLookup<H, I> {
	public final ordered_list:Array<H>;
	public final ordered_array:Array<Null<I>>;
	public final map_f:FlattenCtx->H->I;
	// port: `Obj.magic 0`, the placeholder that marks an entry as being flattened.
	public final dummy:Dynamic = {};

	public function new(l, a, f) {
		ordered_list = l;
		ordered_array = a;
		map_f = f;
	}
}

@:allow(libs.swflib.As3hlparse)
private class FlattenCtx {
	var fints:Lookup<HlInt, As3Int>;
	var fuints:Lookup<HlUint, As3Uint>;
	var ffloats:Lookup<HlFloat, As3Float>;
	var fidents:Lookup<HlIdent, As3Ident>;
	var fnamespaces:Lookup<HlNamespace, As3Namespace>;
	var fnsets:Lookup<HlNsSet, As3NsSet>;
	var fnames:Lookup<HlName, As3MultiName>;
	var fmetas:Lookup<HlMetadata, As3Metadata>;
	var fmethods:IndexLookup<HlMethod, As3MethodType>;
	var fclasses:IndexLookup<HlClass, {cl:As3Class, st:As3Static}>;
	var ffunctions:Array<As3Function>;
	var fjumps:Array<Int>;

	public function new() {}
}
