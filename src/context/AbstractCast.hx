package context;
import core.Globals;
import core.Globals.Pos;
import core.Ast;
import core.TType;
import core.Meta;
import typing.Type;
import typing.Abstract;
import typing.Monomorph;
import typing.Error;
import typing.CallUnification;
import core.ds.NotFound;
import context.SafeCom.SafeContext;
// Draft mechanical translation of haxe/src/context/abstractCast.ml; unvalidated.
// Macro dispatch retains the upstream hook; its runtime remains a later milestone.
class AbstractCast {
	static final castStack:Array<TClassField> = [];
	public static function makeStaticCall(ctx:Dynamic, c:TClass, cf:TClassField, a:TAbstract, pl:TParams, args:Array<TExpr>, t:T, p:Pos):TExpr {
		switch cf.cfKind {
			case Method(MethMacro):
				if (args.length != 1) throw "abstractCast: invalid macro cast argument count";
				var pushed = Typecore.pushThis(ctx,args[0]);
				ctx.e.withTypeStack.unshift(typing.WithType.withType(t));
				var e = switch ctx.g.doMacro(ctx,MExpr,c.clPath,cf.cfName,[pushed.expr],p) {
					case MSuccess(expr): Typecore.typeExpr(ctx,expr,typing.WithType.withType(t));
					case _: Typecore.typeExpr(ctx,{expr:EConst(Ident("null")),pos:p},typing.WithType.value);
				};
				ctx.e.withTypeStack.shift();
				try e = castOrUnifyRaise(ctx,t,e,p) catch (err:typing.Error.CompilerError) {
					switch err.error.errMessage { case Unify(_): throw new NotFound(); case _: throw err; }
				}
				pushed.restore();
				return e;
			case _: return CallUnification.makeStaticCallBetter(ctx,c,cf,pl,args,t,p);
		}
	}
	public static function doCheckCast(ctx:Dynamic, uctx:Dynamic, tleft:T, eright:TExpr, p:Pos):TExpr {
		function recurse(cf:TClassField, f:Void->TExpr):TExpr {
			switch cf.cfKind {
				case Method(MethMacro):
					if (castStack.length > 0 && castStack[0] == cf)
						try Type.unifyCustom(uctx,eright.etype,tleft) catch (err:typing.Type.UnifyError) Error.raiseErrorMsg(Unify(err.errors),eright.epos);
				case _:
			}
			if (cf == ctx.f.curfield || castStack.indexOf(cf) != -1) Error.raiseTypingError("Recursive implicit cast",p);
			castStack.unshift(cf);
			var result:TExpr;
			try result = f() catch (err:Dynamic) { castStack.shift(); throw err; }
			castStack.shift();
			return result;
		}
		function make(found:Dynamic):TExpr {
			var a:TAbstract = found.abs;
			var tl:TParams = found.params;
			var cf:TClassField = found.field.field;
			if (Meta.has(Meta.MultiType,cf.cfMeta)) return Type.mkCast(eright,tleft,p);
			if (a.aImpl == null) throw "abstractCast: missing implementation";
			return recurse(cf,function() {
				var ret = makeStaticCall(ctx,a.aImpl,cf,a,tl,[eright],tleft,p);
				return {eexpr:TMeta({meta:Meta.ImplicitCast,exprs:[],pos:ret.epos},ret),etype:ret.etype,epos:ret.epos};
			});
		}
		if (Type.typeIseqCustom(uctx,tleft,eright.etype)) return eright;
		function loop(stack:Array<{left:T,right:T}>, left:T, right:T):TExpr {
			for (pair in stack) if (Type.fastEq(left,pair.left) && Type.fastEq(right,pair.right)) throw new NotFound();
			var next = [{left:left,right:right}].concat(stack);
			return switch [Type.follow(left),Type.follow(right)] {
				case [TAbstract(a1,tl1),TAbstract(a2,tl2)]: make(Abstract.findToFrom(uctx,eright.etype,left,a2,tl2,a1,tl1));
				case [TAbstract(a,tl),_]:
					try make({abs:a,params:tl,field:Abstract.findFrom(uctx,eright.etype,a,tl)}) catch (_:NotFound) {
						var found:Null<TExpr> = null;
						for (tc in a.aFrom) if (!Type.typeIseqCustom(uctx,tc,left)) {
							found = loop(next,Type.applyParams(a.aParams,tl,tc),right);
							break;
						}
						if (found == null) throw new NotFound();
						found;
					}
				case [_,TAbstract(a,tl)]:
					try make({abs:a,params:tl,field:Abstract.findTo(uctx,left,a,tl)}) catch (_:NotFound) {
						var found:Null<TExpr> = null;
						for (tc in a.aTo) if (!Type.typeIseqCustom(uctx,tc,right)) {
							found = loop(next,left,Type.applyParams(a.aParams,tl,tc));
							break;
						}
						if (found == null) throw new NotFound();
						found;
					}
				case [TInst(c,tl),TFun(_)] if (Type.hasClassFlag(c,CFunctionalInterface)):
					var cf = typing.TClass.getSingularInterfaceField(c.clOrderedFields);
					if (cf == null) throw new NotFound();
					function map(t:T):T return Type.applyParams(c.clParams,tl,t);
					var monos = Monomorph.spawnConstrainedMonos(map,cf.cfParams);
					Typecore.unifyRaiseCustom(Type.nativeUnificationContext,eright.etype,map(Type.applyParams(cf.cfParams,monos,cf.cfType)),p);
					if (Type.hasMono(right)) Error.raiseTypingError("Cannot use this function as a functional interface because it has unknown types: " + Type.sType(Type.printContext(),right),p);
					Type.mkCast(eright,left,p);
				case _: throw new NotFound();
			};
		}
		return loop([],tleft,eright.etype);
	}
	public static function castOrUnifyRaise(ctx:Dynamic, tleft:T, eright:TExpr, p:Pos, ?uctx:Dynamic):TExpr {
		if (uctx == null) uctx = Type.defaultUnificationContext();
		try return doCheckCast(ctx,uctx,tleft,eright,p) catch (_:NotFound) {
			Typecore.unifyRaiseCustom(uctx,eright.etype,tleft,p);
			return eright;
		}
	}
	public static function castOrUnify(ctx:Dynamic, tleft:T, eright:TExpr, p:Pos):TExpr {
		try return castOrUnifyRaise(ctx,tleft,eright,p) catch (err:typing.Error.CompilerError) {
			switch err.error.errMessage {
				case Unify(_): Typecore.raiseOrDisplayError(ctx,err.error); return eright;
				case _: throw err;
			}
		}
	}
	public static function prepareArrayAccessField(ctx:Dynamic, a:TAbstract, pl:TParams, cf:TClassField, p:Pos):Dynamic {
		var monos = [for (_ in cf.cfParams) Typecore.spawnMonomorph(ctx,p)];
		function map(t:T):T return Type.applyParams(a.aParams,pl,Type.applyParams(cf.cfParams,monos,t));
		function checkConstraints():Void {
			for (i in 0...monos.length) {
				var m = monos[i];
				for (tc in Type.getConstraints(cf.cfParams[i])) switch Type.follow(m) {
					case TMono(_): throw new typing.Type.UnifyError([]);
					case _: Type.unify(m,map(tc));
				}
			}
		}
		function getTa():T {
			var ta = Type.applyParams(a.aParams,pl,a.aThis);
			return Type.hasClassFieldFlag(cf,CfImpl) ? ta : TAbstract(a,pl);
		}
		return {map:map,checkConstraints:checkConstraints,getTa:getTa};
	}
	public static function findArrayReadAccessRaise(ctx:Dynamic, a:TAbstract, pl:TParams, e1:TExpr, p:Pos):Dynamic {
		for (cf in a.aArray) {
			var prepared = prepareArrayAccessField(ctx,a,pl,cf,p);
			var tf = Type.follow(prepared.map(cf.cfType));
			switch tf {
				case TFun(sig) if (sig.args.length >= 2 && Type.isEmptyOrPosInfos(sig.args.slice(2))):
					try {
						Type.unify(sig.args[0].type,prepared.getTa());
						var e1 = castOrUnifyRaise(ctx,sig.args[1].type,e1,p);
						prepared.checkConstraints();
						return {field:cf,type:tf,ret:sig.ret,index:e1};
					} catch (_:typing.Type.UnifyError) {} catch (err:typing.Error.CompilerError) {
						switch err.error.errMessage { case Unify(_): case _: throw err; }
					}
				case _:
			}
		}
		throw new NotFound();
	}
	public static function findArrayWriteAccessRaise(ctx:Dynamic, a:TAbstract, pl:TParams, e1:TExpr, e2:TExpr, p:Pos):Dynamic {
		for (cf in a.aArray) {
			var prepared = prepareArrayAccessField(ctx,a,pl,cf,p);
			var tf = Type.follow(prepared.map(cf.cfType));
			switch tf {
				case TFun(sig) if (sig.args.length >= 3 && Type.isEmptyOrPosInfos(sig.args.slice(3))):
					try {
						Type.unify(sig.args[0].type,prepared.getTa());
						var e1 = castOrUnifyRaise(ctx,sig.args[1].type,e1,p);
						var e2 = castOrUnifyRaise(ctx,sig.args[2].type,e2,p);
						prepared.checkConstraints();
						return {field:cf,type:tf,ret:sig.ret,index:e1,value:e2};
					} catch (_:typing.Type.UnifyError) {} catch (err:typing.Error.CompilerError) {
						switch err.error.errMessage { case Unify(_): case _: throw err; }
					}
				case _:
			}
		}
		throw new NotFound();
	}
	public static function findArrayReadAccess(ctx:Dynamic, a:TAbstract, tl:TParams, e1:TExpr, p:Pos):Dynamic {
		try return findArrayReadAccessRaise(ctx,a,tl,e1,p) catch (_:NotFound) {
			return Error.raiseTypingError("No @:arrayAccess function for " + Type.sType(Type.printContext(),TAbstract(a,tl)) + " accepts argument of " + Type.sType(Type.printContext(),e1.etype),p);
		}
	}
	public static function findArrayWriteAccess(ctx:Dynamic, a:TAbstract, tl:TParams, e1:TExpr, e2:TExpr, p:Pos):Dynamic {
		try return findArrayWriteAccessRaise(ctx,a,tl,e1,e2,p) catch (_:NotFound) {
			return Error.raiseTypingError("No @:arrayAccess function for " + Type.sType(Type.printContext(),TAbstract(a,tl)) + " accepts arguments of " + Type.sType(Type.printContext(),e1.etype) + " and " + Type.sType(Type.printContext(),e2.etype),p);
		}
	}
	public static function findToField(uctx:Dynamic, b:T, ab:TAbstract, tl:TParams):Dynamic {
		var a = TAbstract(ab,tl);
		function check(t:T,cf:TClassField):Dynamic return switch Type.follow(cf.cfType) {
			case TFun(sig) if (sig.args.length > 0):
				var ta = sig.args[0].type;
				function outerMap(t:T):T return Type.applyParams(ab.aParams,tl,t);
				var monos = Monomorph.spawnConstrainedMonos(outerMap,cf.cfParams);
				function map(t:T):T return outerMap(Type.applyParams(cf.cfParams,monos,t));
				var uctx = Type.getAbstractContext(uctx,a,b,ab);
				var unifyFunc = Type.getAbstractUnifyFunc(uctx,EqStrict);
				var athis = map(ab.aThis);
				if (Meta.has(Meta.MultiType,ab.aMeta) && Type.hasMono(athis)) throw new typing.Type.UnifyError([]);
				var equalityContext = Reflect.copy(uctx);
				equalityContext.equalityKind = EqStrict;
				Type.withVariance(uctx,function(t1,t2) return Type.typeEqCustom(equalityContext,t1,t2),athis,map(ta));
				unifyFunc(map(t),b);
				{type:t,field:cf,monos:monos};
			case _: throw "abstractCast: invalid to-field type";
		};
		for (entry in ab.aToField) try return check(entry.type,entry.field) catch (_:typing.Type.UnifyError) {}
		throw new NotFound();
	}
	public static function findMultitypeSpecializationFull(platform:core.Globals.Platform,a:TAbstract,pl:TParams,p:Pos):Dynamic {
		var uctx = Type.defaultUnificationContext();
		var m = Type.mkMono();
		var params = Abstract.findMultitypeParams(a,pl);
		var tl:TParams = params.params;
		var found:Dynamic;
		try {
			found = findToField(uctx,m,a,tl);
			for (t in (cast params.definitiveTypes:TParams)) if (Type.hasMono(t)) {
				var at = Type.applyParams(a.aParams,pl,a.aThis);
				Error.raiseTypingError("Type parameters of multi type abstracts must be known (for " + Type.sType(Type.printContext(),at) + ")",p);
			}
		} catch (_:NotFound) {
			var at = Type.applyParams(a.aParams,pl,a.aThis);
			var st = Type.sType(Type.printContext(),at);
			if (Type.hasMono(at)) Error.raiseTypingError("Type parameters of multi type abstracts must be known (for " + st + ")",p);
			else Error.raiseTypingError("Abstract " + Globals.sTypePath(a.aPath) + " has no @:to function that accepts " + st,p);
		}
		return {field:found.field,fieldMonos:found.monos,type:Type.follow(m),params:tl};
	}
	public static function findMultitypeSpecialization(platform:core.Globals.Platform,a:TAbstract,pl:TParams,p:Pos):Dynamic {
		var found = findMultitypeSpecializationFull(platform,a,pl,p);
		return {field:found.field,type:found.type};
	}
	public static function handleAbstractCasts(scom:SafeContext,e:TExpr):TExpr {
		function loop(e:TExpr):TExpr return switch e.eexpr {
			case TNew(c,pl,el) if (switch c.clKind { case KAbstractImpl(_): true; case _: false; }):
				var a = switch c.clKind { case KAbstractImpl(a): a; case _: throw "abstractCast: invalid implementation"; };
				if (!Meta.has(Meta.MultiType,a.aMeta)) {
					switch Abstract.getUnderlyingType(a,pl) {
						case TInst(c,tl): {eexpr:TNew(c,tl,el),etype:TInst(c,tl),epos:e.epos};
						case _: Error.raiseTypingError("Cannot construct " + Type.sType(Type.printContext(),TAbstract(a,pl)),e.epos);
					}
				} else {
					var found = findMultitypeSpecializationFull(scom.platform,a,pl,e.epos);
					var cf:TClassField = found.field;
					var m:T = found.type;
					var eThis = typing.Texpr.Builder.makeStaticThis(c,e.epos);
					var ef = Type.mk(TField(eThis,FStatic(c,cf)),Type.applyParams(cf.cfParams,found.fieldMonos,cf.cfType),e.epos);
					var call = filters.ExceptionFunctions.makeCall(scom,ef,[Type.mk(TConst(TNull),TAbstract(a,found.params),e.epos)].concat(el),m,e.epos);
					{eexpr:call.eexpr,etype:m,epos:call.epos};
				}
			case TCall({eexpr:TField(_,FStatic(c,cf))},[e1]) if (c.clPath.pack.length == 0 && c.clPath.name == "Std" && cf.cfName == "string" && (switch Type.follow(e1.etype) { case TAbstract(a,_) if (a.aImpl != null): true; case _: false; })):
				switch Type.follow(e1.etype) {
					case TAbstract(a,tl) if (a.aImpl != null):
						var c = a.aImpl;
						var cf = c.clStatics.get("toString");
						if (cf == null) e;
						else {
							function call():TExpr return filters.ExceptionFunctions.makeStaticCall(scom,c,cf,[e1],scom.basic.tstring,e.epos);
							if (!Type.isNullable(e1.etype)) call();
							else {
								var p = e.epos;
								var chkNull = Type.mk(TBinop(OpEq,e1,Type.mk(TConst(TNull),e1.etype,p)),scom.basic.tbool,p);
								Type.mk(TIf(chkNull,Type.mk(TConst(TString("null")),scom.basic.tstring,p),call()),scom.basic.tstring,p);
							}
						}
					case _: throw "abstractCast: invalid abstract string call";
				}
			case TCall(e1,el):
				try {
					function findAbstract(e:TExpr,t:T):Dynamic {
						switch Type.follow(t) {
							case TAbstract(a,pl) if (Meta.has(Meta.MultiType,a.aMeta)): return {abs:a,params:pl,expr:e};
							case _:
						}
						return switch e.eexpr {
							case TCast(e1,null): findAbstract(e1,e1.etype);
							case TLocal(v) if (v.vExtra != null && v.vExtra.vExpr != null):
								var original = v.vExtra.vExpr;
								switch Type.follow(original.etype) {
									case TAbstract(a,pl) if (Meta.has(Meta.MultiType,a.aMeta)): {abs:a,params:pl,expr:Type.mk(TCast(e,null),original.etype,e.epos)};
									case _: throw new NotFound();
								}
							case _: throw new NotFound();
						};
					}
					function findField(e1:TExpr):TExpr return switch e1.eexpr {
						case TCast(e2,null): {eexpr:TCast(findField(e2),null),etype:e1.etype,epos:e1.epos};
						case TField(e2,fa):
							var found = findAbstract(e2,e2.etype);
							var a:TAbstract = found.abs;
							var pl:TParams = found.params;
							var e2 = loop(found.expr);
							var m = Abstract.getUnderlyingType(a,pl);
							var fname = Type.fieldName(fa);
							var el = el.map(loop);
							try {
								var fa = Type.quickField(m,fname);
								function getFunType(t:T):{type:T,signature:TSignature} return switch Type.follow(t) {
									case TFun(sig): {type:TFun(sig),signature:sig};
									case _: throw new NotFound();
								};
								var funType = switch fa {
									case FStatic(_,cf): getFunType(cf.cfType);
									case FInstance(c,tl,cf): getFunType(Type.applyParams(c.clParams,tl,cf.cfType));
									case FAnon(cf): getFunType(cf.cfType);
									case _: throw new NotFound();
								};
								function maybeCast(e:TExpr,t:T,p:Pos):TExpr return Type.typeIseq(e.etype,t) ? e : Type.mk(TCast(e,null),t,p);
								var ef = Type.mk(TField({eexpr:e2.eexpr,etype:m,epos:e2.epos},fa),funType.type,e2.epos);
								if (Type.hasMeta(Meta.MultiType,a.aMeta)) switch Type.follow(e1.etype) {
									case TFun(original):
										var args = funType.signature.args;
										var casted:Array<TExpr> = [];
										for (i in 0...el.length) {
											if (i >= args.length) { casted.push(el[i]); continue; }
											var t = args[i].type;
											if (i < original.args.length) switch Type.follow(t) {
												case TMono(_): switch Type.follow(original.args[i].type) { case TDynamic(_): t = original.args[i].type; case _: }
												case _:
											}
											casted.push(maybeCast(el[i],t,el[i].epos));
										}
										el = casted;
									case _:
								}
								var ecall = filters.ExceptionFunctions.makeCall(scom,ef,el,funType.signature.ret,e.epos);
								maybeCast(ecall,e.etype,e.epos);
							} catch (_:NotFound) {
								switch Type.follow(m) {
									case TAbstract(a,pl) if (a.aImpl != null):
										var c = a.aImpl;
										var cf = c.clStatics.get(fname);
										if (cf == null) throw new NotFound();
										filters.ExceptionFunctions.makeStaticCall(scom,c,cf,[e2].concat(el),e.etype,e.epos);
									case _: throw new NotFound();
								}
							}
						case _: throw new NotFound();
					};
					findField(e1);
				} catch (_:NotFound) Type.mapExpr(loop,e);
			case _: Type.mapExpr(loop,e);
		};
		return loop(e);
	}
	static final installCastOrUnifyRaise = install();
	static function install():Bool { Typecore.castOrUnifyRaiseRef = castOrUnifyRaise; return true; }
}
