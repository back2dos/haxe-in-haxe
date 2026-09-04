package codegen;

import core.TType;
import core.TFunctions;
import core.TUnification;
import core.Meta;
import typing.FieldCallCandidate;
import core.TFunctions.*;
import core.TUnification.*;

// haxe/src/codegen/overloads.ml — mechanical draft; not compile-validated.
class Overloads {
	public static function sameOverloadArgs(t1:T,t2:T,f1:TClassField,f2:TClassField,?getVmtype:T->T):Bool {
		var transform = getVmtype == null ? function(t) return t : getVmtype;
		var eq = function(a,b) return typeIseq(transform(a),transform(b));
		if(f1.cfParams.length != f2.cfParams.length) return false;
		for(i in 0...f1.cfParams.length) {
			var p1=f1.cfParams[i], p2=f2.cfParams[i];
			// Preserve upstream's comparison of the second parameter's constraints to itself.
			if(p1.ttpName != p2.ttpName || !Ast.safeForAll2(eq,getConstraints(p2),getConstraints(p2))) return false;
		}
		function arguments(a:Array<Dynamic>,b:Array<Dynamic>):Bool {
			if(a.length != b.length) return false;
			for(i in 0...a.length) if(!eq(a[i].type,b[i].type)) return false;
			return true;
		}
		t1=follow(applyParams(f1.cfParams,extractParamTypes(f2.cfParams),t1));
		return switch [followWithCoro(t1),followWithCoro(t2)] {
			case [NotCoro(TFun(s1)),NotCoro(TFun(s2))]: arguments(s1.args,s2.args);
			case [Coro(a1,_),Coro(a2,_)]: arguments(a1,a2);
			case _: false;
		}
	}
	public static function collectOverloads(map:T->T,c:TClass,name:String):Array<{type:T,field:TClassField}> {
		var acc:Array<{type:T,field:TClassField}>=[];
		function loop(map:T->T,c:TClass):Void {
			function add(cf:TClassField):Void {
				var t=map(cf.cfType);
				if(!Lambda.exists(acc,function(v) return sameOverloadArgs(t,v.type,cf,v.field))) acc.unshift({type:t,field:cf});
			}
			try {
				var cf=PMap.find(name,c.clFields);
				switch cf.cfKind { case Var(_): case Method(_): add(cf); for(f in cf.cfOverloads) add(f); }
			} catch(_:Not_found) {}
			if(c.clSuper != null) {
				var s=c.clSuper, tl=s.params.map(map);
				loop(function(t) return applyParams(s.c.clParams,tl,map(t)),s.c);
			} else if(hasClassFlag(c,CInterface)) for(s in c.clImplements) {
				var tl=s.params.map(map);
				loop(function(t) return applyParams(s.c.clParams,tl,map(t)),s.c);
			}
		}
		loop(map,c); acc.reverse(); return acc;
	}
}

typedef ConversionRate = {var conversions:Int; var params:Int;}
class Resolution {
	static function nullAbstract(a:Dynamic):Bool return a.aPath.pack.length==0 && a.aPath.name=="Null";
	public static function simplifyT(t:T):T return switch t {
		case TInst(_,_),TEnum(_,_): t;
		case TAbstract(a,[inner]) if(nullAbstract(a)):
			var st=simplifyT(inner);
			switch st { case TAbstract(ab,_) if(Meta.has(CoreType,ab.aMeta)): TAbstract(a,[simplifyT(st)]); case TEnum(_,_): TAbstract(a,[simplifyT(st)]); case _: st; }
		case TAbstract(a,_) if(Meta.has(CoreType,a.aMeta)): t;
		case TAbstract(a,tl): simplifyT(Abstract.getUnderlyingType(a,tl));
		case TType(td,tl): simplifyT(applyTypedef(td,tl));
		case TMono(m): m.tmType == null ? tDynamic : simplifyT(m.tmType);
		case TAnon(_): tDynamic;
		case TDynamic(_),TFun(_): t;
		case TLazy(f): simplifyT(lazyType(f));
	}
	public static function rateTp(a:Array<T>,b:Array<T>):Int {
		var n=0; List.iter2(function(t1,t2) {if(!typeIseq(t1,t2)) n++;},a,b); return n;
	}
	static function rate(c:Int,p:Int):ConversionRate return {conversions:c,params:p};
	public static function rateConv(cacc:Int,tfun:T,targ:T):ConversionRate return switch [simplifyT(tfun),simplifyT(targ)] {
		case [TInst(cf,tlf),TInst(ca,tla)] if(hasClassFlag(cf,CInterface)):
			var cur={acc:0,c:ca,tl:tla}, stack=[cur];
			while(true) {
				if(stack.length==0) {
					var s=cur.c.clSuper; if(s==null) throw new Not_found();
					cur={acc:cur.acc+1,c:s.c,tl:s.params.map(function(t) return applyParams(cur.c.clParams,cur.tl,t))};
					stack=[cur];
				} else {
					var v=stack.shift();
					if(v.c==cf) return rate(cacc+v.acc,rateTp(tlf,v.tl));
					for(s in v.c.clImplements) stack.push({acc:v.acc+1,c:s.c,tl:s.params.map(function(t) return applyParams(v.c.clParams,v.tl,t))});
				}
			}
			throw new Not_found();
		case [TInst(cf,tlf),TInst(ca,tla)]:
			var acc=0;
			while(cf!=ca) {var s=ca.clSuper; if(s==null) throw new Not_found(); tla=s.params.map(function(t) return applyParams(ca.clParams,tla,t)); ca=s.c; acc++;}
			rate(cacc+acc,rateTp(tlf,tla));
		case [TEnum(ef,tlf),TEnum(ea,tla)]: if(ef!=ea) throw new Not_found(); rate(cacc,rateTp(tlf,tla));
		case [TDynamic(_),TDynamic(_)]: rate(cacc,0);
		case [TDynamic(_),_]: rate(OcamlInt.maxInt,0);
		case [TAbstract(a,_),TDynamic(_)] if(Meta.has(CoreType,a.aMeta) && !nullAbstract(a)): rate(cacc+2,0);
		case [_,TDynamic(_)]: rate(cacc+1,0);
		case [TAbstract(a,[tf]),TAbstract(b,[ta])] if(nullAbstract(a) && nullAbstract(b)): rateConv(cacc,tf,ta);
		case [TAbstract(a,[tf]),ta] if(nullAbstract(a)): rateConv(cacc+1,tf,ta);
		case [tf,TAbstract(a,[ta])] if(nullAbstract(a)): rateConv(cacc+1,tf,ta);
		case [TAbstract(af,tlf),TAbstract(aa,tla)]:
			if(af==aa) rate(cacc,rateTp(tlf,tla)); else {
				for(t in af.aFrom) try {return rateConv(cacc+1,applyParams(af.aParams,tlf,t),targ);} catch(_:Not_found) {}
				for(t in aa.aTo) try {return rateConv(cacc+1,tfun,applyParams(aa.aParams,tla,t));} catch(_:Not_found) {}
				throw new Not_found();
			}
		case [TFun(_),TFun(_)]: rate(cacc,0);
		case [TInst(cf,tlf),TFun(_)] if(hasClassFlag(cf,CFunctionalInterface)):
			var sam=core.TOther.TClassTools.getSingularInterfaceField(cf.clOrderedFields);
			if(sam==null) throw new Not_found();
			rateConv(cacc+1,applyParams(cf.clParams,tlf,sam.cfType),targ);
		case _: throw new Not_found();
	}
	static function compareRate(a:ConversionRate,b:ConversionRate):Int return a.conversions<b.conversions ? -1 : a.conversions>b.conversions ? 1 : a.params<b.params ? -1 : a.params>b.params ? 1 : 0;
	public static function isBest(a:Array<ConversionRate>,b:Array<ConversionRate>):Bool {
		return Ast.safeForAll2(function(v1,v2) return compareRate(v1,v2)<=0,a,b) && List.exists2(function(v1,v2) return compareRate(v1,v2)<0,a,b);
	}
	public static function rmDuplicates<A>(acc:Array<FieldCallCandidateData<A>>,rest:Array<FieldCallCandidateData<A>>):Array<FieldCallCandidateData<A>> {
		for(f in rest) if(!Lambda.exists(acc,function(g) return typeIseq(f.fcType,g.fcType))) acc.unshift(f);
		return acc;
	}
	public static function countOptionals(t:T):Int return switch follow(t) { case TFun(s): var n=0; for(a in s.args) if(a.optional) n++; n; case _: 0; }
	public static function fewerOptionals<A>(acc:Array<FieldCallCandidateData<A>>,compatible:Array<FieldCallCandidateData<A>>):Array<FieldCallCandidateData<A>> {
		for(f in compatible) if(acc.length==0) acc=[f]; else {
			var old=countOptionals(acc[0].fcType), next=countOptionals(f.fcType);
			if(old==next) acc.unshift(f); else if(old>next) acc=[f];
		}
		return acc;
	}
	public static function reduceCompatible<A>(compatible:Array<FieldCallCandidateData<A>>):Array<FieldCallCandidateData<A>> {
		compatible=fewerOptionals([],rmDuplicates([],compatible)); if(compatible.length<2) return compatible;
		function rateArg(t:T,e:TExpr):ConversionRate return switch e.eexpr {
			case TMeta(m,_) if(m.name==ImplicitCast): rate(OcamlInt.maxInt-1,0);
			case _: rateConv(0,t,e.etype);
		}
		function mkRate(acc:Array<ConversionRate>,el:Array<TExpr>,args:Array<Dynamic>):{rates:Array<ConversionRate>,rest:Bool} {
			if(el.length==0 && args.length==0) return {rates:acc,rest:false};
			if(el.length>0 && args.length>0 && args[0].optional) return mkRate(acc,el.slice(1),args.slice(1));
			if(args.length==1 && ExtType.isRest(follow(args[0].type))) {
				var t=switch follow(args[0].type) { case TAbstract(a,[t]) if(a.aPath.pack.join(".")=="haxe" && a.aPath.name=="Rest"): t; case _: Globals.die("","overloads.ml"); };
				return {rates:acc.concat(el.map(function(e) return rateArg(t,e))),rest:true};
			}
			if(el.length>0 && args.length>0) {acc.unshift(rateArg(args[0].type,el[0])); return mkRate(acc,el.slice(1),args.slice(1));}
			if(el.length==0) return {rates:acc,rest:false};
			return Globals.die("","overloads.ml");
		}
		var best:Null<{rates:Array<ConversionRate>,rest:Bool,list:Array<FieldCallCandidateData<A>>}>=null;
		for(f in compatible) {
			var args=switch follow(f.fcType) {case TFun(s): s.args; case _: Globals.die("","overloads.ml");};
			try {
				var r=mkRate([],f.fcArgs,args);
				if(best==null || isBest(r.rates,best.rates)) best={rates:r.rates,rest:r.rest,list:[f]};
				else if(isBest(best.rates,r.rates)) {}
				else if(r.rest && !best.rest) {}
				else if(!r.rest && best.rest) best={rates:r.rates,rest:r.rest,list:[f]};
				else best.list.unshift(f);
			} catch(_:Not_found) {}
		}
		if(best==null) return []; best.list.reverse(); return best.list;
	}
}
