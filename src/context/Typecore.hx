package context;
import core.Message.WarningCode;
import core.Globals;
import core.Globals.Pos;
import core.Globals.GlobalTypePath;
import core.Ast;
import core.TType;
import core.Meta;
import core.ds.PersistentMap;
import core.ds.NotFound;
import context.TyperPass;
import context.Resolution;
import core.TFunctions as TypeOps;
import core.TUnification;
import core.TUnification.Monomorph;
import core.MetaList.StrictMeta;
import core.Meta as MetadataTools;
import core.Texpr;
import core.Warning;
import core.WarningList;
import Type as StdType;
import core.Error.Error;
import core.Error.ErrorMsg;

// Draft mechanical translation of haxe/src/context/typecore.ml; unvalidated.
// Macro and display callbacks retain their shape; their runtimes are not implemented here.
typedef TypePatch = { var tpType:Null<ComplexType>; var tpRemove:Bool; var tpMeta:Metadata; }
enum CurrentFun { FunMember; FunStatic; FunConstructor; FunMemberAbstract; FunMemberClassLocal; FunMemberAbstractLocal; }
enum MacroMode { MExpr; MBuild; MMacroType; MDisplay; }
enum AccessMode { MGet; MSet(rhs:Null<Expr>); MCall(args:Array<Expr>); }
typedef TyperModule = {
	var curmod:ModuleDef;
	var importResolution:ResolutionList;
	var ownResolution:Null<ResolutionList>;
	var enumWithType:Null<ModuleType>;
	var moduleUsing:Array<{cls:TClass,pos:Pos}>;
	var importStatements:Array<Import>;
	var isDisplayFile:Bool;
}
typedef TyperClass = { var curclass:TClass; var tthis:T; var getBuildInfos:Void->Null<{type:ModuleType,params:TParams,fields:Array<ClassField>}>; }
enum BuildKind { BuildNormal; BuildGeneric(cls:TClass); BuildGenericBuild; BuildMacroType; }
typedef BuildInfo = {
	var buildKind:BuildKind;
	var buildPath:GlobalTypePath;
	var buildParams:TypeParams;
	var buildExtern:Bool;
	var buildApply:TParams->T;
}
enum MacroResult { MSuccess(expr:Expr); MError; MMacroInMacro; }
typedef TyperPassTasks = { var tasks:Array<Void->Void>; var tasksLate:Array<Void->Void>; }
enum FunctionMode { FunFunction; FunCoroutine; FunNotFunction; }
typedef CallArgContext = { var cacInOverload:Bool; var cacBodyCapture:{value:Array<core.Message.CompilerMessage>}; }
typedef TyperGlobals = {
	var delayed:Array<TyperPassTasks>;
	var delayedMinIndex:Int;
	var debugDelayed:Array<Dynamic>;
	var retainMeta:Bool;
	var coreApi:Null<Typer>;
	var macros:Null<{finalize:Void->Void,typer:Typer}>;
	var moduleCheckPolicies:Array<{pack:Array<String>,policies:Array<ModuleCheckPolicy>,recursive:Bool}>;
	var globalUsing:Array<{cls:TClass,pos:Pos}>;
	var complete:Bool;
	var typeHints:Array<{display:ModuleDefDisplay,pos:Pos,type:T}>;
	var loadOnlyCachedModules:Bool;
	var returnPartialType:Bool;
	var buildCount:Int;
	var tDynamicDef:T;
	var delayedDisplay:Null<Dynamic>;
	var callArgContext:Null<CallArgContext>;
	var rootTyper:Typer;
	var continuationApi:Null<Dynamic>;
	var doMacro:Typer->MacroMode->GlobalTypePath->String->Array<Expr>->Pos->MacroResult;
	var doLoadMacro:Typer->Bool->GlobalTypePath->String->Pos->Dynamic;
	var doLoadModule:(ctx:Typer,path:GlobalTypePath,p:Pos,?origin:ModuleDepOrigin)->ModuleDef;
	var doLoadTypeDef:Typer->Pos->TypePath->ModuleType;
	var getBuildInfo:Typer->ModuleType->Pos->BuildInfo;
	var doFormatString:Typer->String->Pos->Expr;
	var doLoadCoreClass:Typer->TClass->TClass;
}
typedef TyperExpr = {
	var curfun:CurrentFun;
	var functionMode:FunctionMode;
	var ret:T;
	var opened:Array<TAnon>;
	var monomorphs:Array<{mono:TMono,pos:Pos}>;
	var inLoop:Bool;
	var bypassAccessor:Int;
	var withTypeStack:Array<Dynamic>;
	var callArgumentStack:Array<Array<Expr>>;
	var macroDepth:Int;
}
typedef TyperField = {
	var curfield:TClassField;
	var locals:PersistentMap<String,TVar>;
	var vthis:Null<TVar>;
	var isUntyped:Bool;
	var meta:Metadata;
	var inDisplay:Bool;
	var inCallArgs:Bool;
}
typedef Typer = {
	var com:Dynamic;
	var t:BasicTypes;
	var g:TyperGlobals;
	var m:TyperModule;
	var c:TyperClass;
	var f:TyperField;
	var e:TyperExpr;
	var pass:TyperPass;
	var typeParams:TypeParams;
	var allowInline:Bool;
	var allowTransform:Bool;
	var memoryMarker:Array<Float>;
}
enum FieldHost { FHStatic(cls:TClass); FHInstance(cls:TClass,params:TParams); FHAbstract(abs:TAbstract,params:TParams,cls:TClass); FHAnon; }
typedef FieldAccess = {
	var faOn:TExpr;
	var faField:TClassField;
	var faHost:FieldHost;
	var faInline:Bool;
	var faPos:Pos;
	var faFieldPos:Null<Pos>;
}
typedef StaticExtensionAccess = { var seThis:TExpr; var seAccess:FieldAccess; }
enum DotPathPartCase { PUppercase; PLowercase; }
typedef DotPathPart = { var name:String; var caseKind:DotPathPartCase; var pos:Pos; }
class ForbidPackage extends haxe.Exception {
	public final forbidden:{name:String,path:GlobalTypePath,pos:Pos};
	public final positions:Array<Pos>;
	public final reason:String;
	public function new(forbidden,positions,reason) { super(reason); this.forbidden=forbidden; this.positions=positions; this.reason=reason; }
}
class WithTypeError extends haxe.Exception {
	public final error:Dynamic;
	public function new(error:Dynamic) { super("WithTypeError"); this.error = error; }
}
class TyperManager {
	public static function create(ctx:Typer,m:TyperModule,c:TyperClass,f:TyperField,e:TyperExpr,pass:TyperPass,params:TypeParams):Typer {
		if (Typecore.passIndex(pass) < Typecore.passIndex(ctx.pass)) throw "Bad context clone from " + Globals.sTypePath(ctx.m.curmod.mPath) + "(" + Typecore.passName(ctx.pass) + ") to " + Globals.sTypePath(m.curmod.mPath) + "(" + Typecore.passName(pass) + ")";
		return {com:ctx.com,g:ctx.g,t:ctx.com.basic,m:m,c:c,f:f,e:e,pass:pass,
			allowInline:ctx.allowInline,allowTransform:ctx.allowTransform,typeParams:params,memoryMarker:Typecore.memoryMarker};
	}
	public static function createCtxC(c:TClass):TyperClass return {
		curclass:c,
		tthis:switch c.clKind {
			case KAbstractImpl(a): switch a.aThis { case TMono(r) if (r.tmType == null): TAbstract(a,core.TFunctions.extractParamTypes(c.clParams)); case t: t; }
			case _: TInst(c,core.TFunctions.extractParamTypes(c.clParams));
		},
		getBuildInfos:function() return null
	};
	public static function createCtxF(cf:TClassField):TyperField return {
		locals:PersistentMap.empty(),curfield:cf,vthis:null,isUntyped:false,meta:[],inDisplay:false,inCallArgs:false
	};
	public static function createCtxE(curfun:CurrentFun,functionMode:FunctionMode):TyperExpr return {
		curfun:curfun,functionMode:functionMode,ret:core.TFunctions.tDynamic,opened:[],monomorphs:[],inLoop:false,
		bypassAccessor:0,withTypeStack:[],callArgumentStack:[],macroDepth:0
	};
	public static function cloneForModule(ctx:Typer,m:TyperModule):Typer {
		var out = create(ctx,m,ctx.c,ctx.f,ctx.e,PBuildModule,[]);
		out.allowTransform = true; out.allowInline = true; return out;
	}
	public static function cloneForClass(ctx:Typer,cls:TClass):Typer {
		var c = createCtxC(cls);
		var params = switch cls.clKind { case KAbstractImpl(a): a.aParams; case _: cls.clParams; };
		return create(ctx,ctx.m,c,ctx.f,ctx.e,PBuildClass,params);
	}
	public static function cloneForEnum(ctx:Typer,en:TEnum):Typer return create(ctx,ctx.m,createCtxC(core.TFunctions.nullClass),ctx.f,ctx.e,PBuildClass,en.eParams);
	public static function cloneForTypedef(ctx:Typer,td:TDef):Typer return create(ctx,ctx.m,createCtxC(core.TFunctions.nullClass),ctx.f,ctx.e,PBuildClass,td.tParams);
	public static function cloneForAbstract(ctx:Typer,a:TAbstract):Typer return create(ctx,ctx.m,createCtxC(core.TFunctions.nullClass),ctx.f,ctx.e,PBuildClass,a.aParams);
	public static function cloneForField(ctx:Typer,cf:TClassField,params:TypeParams):Typer return create(ctx,ctx.m,ctx.c,createCtxF(cf),ctx.e,PBuildClass,params);
	public static function cloneForEnumField(ctx:Typer,params:TypeParams):Typer return create(ctx,ctx.m,ctx.c,createCtxF(core.TFunctions.nullField),ctx.e,PBuildClass,params);
	public static function cloneForExpr(ctx:Typer,curfun:CurrentFun,inFunction:FunctionMode):Typer {
		var e = createCtxE(curfun,inFunction);
		switch curfun {
			case FunMember,FunMemberAbstract,FunStatic,FunConstructor:
				e.monomorphs = ctx.e.monomorphs; ctx.e.monomorphs = [];
			case FunMemberAbstractLocal,FunMemberClassLocal:
		}
		return create(ctx,ctx.m,ctx.c,ctx.f,e,PTypeField,ctx.typeParams);
	}
	public static function cloneForTypeParams(ctx:Typer,params:TypeParams):Typer return create(ctx,ctx.m,ctx.c,ctx.f,ctx.e,ctx.pass,params);
	public static function cloneForTypeParameterExpression(ctx:Typer):Typer return create(ctx,ctx.m,ctx.c,createCtxF(ctx.f.curfield),createCtxE(ctx.e.curfun,FunNotFunction),PTypeField,ctx.typeParams);
	public static function isCoroutineContext(ctx:Typer):Bool return ctx.e.functionMode == FunCoroutine;
	public static function isFunctionContext(ctx:Typer):Bool return switch ctx.e.functionMode { case FunFunction,FunCoroutine: true; case FunNotFunction: false; };
}
class Typecore {
	public static final memoryMarker:Array<Float> = [Sys.time()];
	public static var makeCallRef:(ctx:Dynamic,e:TExpr,el:Array<TExpr>,t:T,p:Pos,?forceInline:Bool)->TExpr = function(ctx,e,el,t,p,?forceInline) throw "makeCallRef is not initialized";
	public static var typeExprRef:(ctx:Dynamic,e:core.Ast.Expr,withType:Dynamic,?mode:Dynamic)->TExpr = function(ctx,e,withType,?mode) throw "typeExprRef is not initialized";
	public static var typeBlockRef:Dynamic = function(ctx,el,withType,p) throw "typeBlockRef is not initialized";
	public static var unifyMinRef:Dynamic = function(ctx,el) throw "unifyMinRef is not initialized";
	public static var unifyMinForTypeSourceRef:Dynamic = function(ctx,el,src) throw "unifyMinForTypeSourceRef is not initialized";
	public static var analyzerRunOnExprRef:Dynamic = function(com,name,e) throw "analyzerRunOnExprRef is not initialized";
	public static var castOrUnifyRaiseRef:(ctx:Dynamic,t:T,e:TExpr,p:Pos,?uctx:Dynamic)->TExpr = function(ctx,t,e,p,?uctx) throw "castOrUnifyRaiseRef is not initialized";
	public static var typeGenericFunctionRef:Dynamic = function(ctx,access,candidate,withType,p) throw "typeGenericFunctionRef is not initialized";
	public static var createContextRef:Dynamic = function(com,macros) throw "createContextRef is not initialized";
	public static function passIndex(p:TyperPass):Int return StdType.enumIndex(p);
	public static function passName(p:TyperPass):String return switch p {
		case PBuildModule: "build-module";
		case PBuildClass: "build-class";
		case PConnectField: "connect-field";
		case PTypeField: "type-field";
		case PCheckConstraint: "check-constraint";
		case PForce: "force";
		case PFinal: "final";
	};
	public static function makeBuildInfo(kind:BuildKind,path:GlobalTypePath,params:TypeParams,isExtern:Bool,apply:TParams->T):BuildInfo return {buildKind:kind,buildPath:path,buildParams:params,buildExtern:isExtern,buildApply:apply};
	public static function warning(ctx:Typer,w:Dynamic,msg:String,p:Pos,depth:Int=0):Void {
		var options = Warning.fromMeta(ctx.f.curfield.cfMeta).concat(Warning.fromMeta(ctx.c.curclass.clMeta));
		switch Warning.getMode(w,options) { case WMEnable: Common.moduleWarning(ctx.com,ctx.m.curmod,w,options,msg,p); case WMDisable: }
	}
	public static function makeCall(ctx:Typer,e:TExpr,el:Array<TExpr>,t:T,p:Pos):TExpr return makeCallRef(ctx,e,el,t,p);
	public static function typeExpr(ctx:Typer,e:Expr,withType:Dynamic,?mode:AccessMode):TExpr return typeExprRef(ctx,e,withType,mode == null ? MGet : mode);
	public static function unifyMin(ctx:Typer,el:Array<TExpr>):T return unifyMinRef(ctx,el);
	public static function unifyMinForTypeSource(ctx:Typer,el:Array<TExpr>,src:Dynamic):T return unifyMinForTypeSourceRef(ctx,el,src);
	public static function spawnMonomorphRaw(ctx:Typer,p:Pos):TMono {
		var mono = Monomorph.create(); ctx.e.monomorphs = [{mono:mono,pos:p}].concat(ctx.e.monomorphs); return mono;
	}
	public static function spawnMonomorph(ctx:Typer,p:Pos):T return TMono(spawnMonomorphRaw(ctx,p));
	public static function monomorphTransaction(ctx:Typer):Void->Void {
		var current = ctx.e.monomorphs;
		var known:Array<{mono:TMono,constraints:Array<TMonoConstraint>}> = [];
		for (entry in current) if (entry.mono.tmType == null) known.unshift({mono:entry.mono,constraints:entry.mono.tmDownConstraints});
		return function() {
			for (entry in known) {
				if (entry.mono.tmType != null) entry.mono.tmType = null;
				if (entry.constraints != entry.mono.tmDownConstraints) entry.mono.tmDownConstraints = entry.constraints;
			}
			ctx.e.monomorphs = current;
		};
	}
	public static function makeStaticFieldAccess(c:TClass,cf:TClassField,t:T,p:Pos):TExpr return core.TFunctions.mk(TField(core.Texpr.Builder.makeStaticThis(c,p),FStatic(c,cf)),t,p);
	public static function enterCallArgs(ctx:Typer,inOverload:Bool):Void->Void {
		var oldInCallArgs = ctx.f.inCallArgs;
		var oldContext = ctx.g.callArgContext;
		ctx.f.inCallArgs = true;
		ctx.g.callArgContext = {cacInOverload:inOverload,cacBodyCapture:{value:[]}};
		return function() { ctx.f.inCallArgs = oldInCallArgs; ctx.g.callArgContext = oldContext; };
	}
	public static function inOverloadCallArgs(ctx:Typer):Bool return ctx.g.callArgContext != null && ctx.g.callArgContext.cacInOverload;
	public static function resetCallArgBodyCapture(ctx:Typer):{value:Array<core.Message.CompilerMessage>} {
		var buf = {value:[]}; if (ctx.g.callArgContext != null) ctx.g.callArgContext.cacBodyCapture = buf; return buf;
	}
	public static function callArgBodyCapture(ctx:Typer):Null<{value:Array<core.Message.CompilerMessage>}> return ctx.g.callArgContext == null ? null : ctx.g.callArgContext.cacBodyCapture;
	public static function raiseWithTypeError(msg:String,p:Pos):Dynamic throw new WithTypeError(Error.makeError(Custom(msg),p));
	public static function raiseOrDisplay(ctx:Typer,l:Dynamic,p:Pos):Void {
		if (ctx.f.isUntyped) return;
		if (ctx.f.inCallArgs) throw new WithTypeError(Error.makeError(Unify(l),p));
		Common.displayErrorExt(ctx.com,Error.makeError(Unify(l),p));
	}
	public static function raiseOrDisplayError(ctx:Typer,err:Dynamic):Void {
		if (ctx.f.isUntyped) return;
		if (ctx.f.inCallArgs) throw new WithTypeError(err);
		Common.displayErrorExt(ctx.com,err);
	}
	public static function raiseOrDisplayMessage(ctx:Typer,msg:String,p:Pos):Void {
		if (ctx.f.inCallArgs) raiseWithTypeError(msg,p); else Common.displayError(ctx.com,msg,p);
	}
	public static function unify(ctx:Typer,t1:T,t2:T,p:Pos):Void {
		try TUnification.unify(t1,t2) catch (err:core.TUnification.Unify_error) raiseOrDisplay(ctx,err.errors,p);
	}
	public static function unifyRaiseCustom(uctx:Dynamic,t1:T,t2:T,p:Pos):Void {
		try TUnification.unifyCustom(uctx,t1,t2) catch (err:core.TUnification.Unify_error) Error.raiseErrorMsg(Unify(err.errors),p);
	}
	public static function unifyRaise(a:T,b:T,p:Pos):Void unifyRaiseCustom(TUnification.defaultUnificationContext(),a,b,p);
	public static function saveLocals(ctx:Typer):Void->Void { var locals = ctx.f.locals; return function() ctx.f.locals = locals; }
	public static function addLocal(ctx:Typer,k:TVarKind,n:String,t:T,p:Pos):TVar {
		var v = core.TFunctions.allocVar(k,n,t,p);
		if (n != "_") switch k {
			case VUser(_):
				try {
					var previous = ctx.f.locals.find(n);
					var inStd = false;
					for (path in (cast ctx.com.classPaths.getStdPaths():Array<core.ClassPath.IClassPath>)) if (StringTools.startsWith(p.pfile,path.path)) { inStd = true; break; }
					if (!inStd) {
						warning(ctx,WVarShadow,"This variable shadows a previously declared variable",p);
						warning(ctx,WVarShadow,core.Error.complMsg("Previous variable was here"),previous.vPos,1);
					}
				} catch (_:NotFound) {}
			case _:
		}
		ctx.f.locals = ctx.f.locals.add(n,v);
		return v;
	}
	public static function addLocalWithOrigin(ctx:Typer,origin:TVarOrigin,n:String,t:T,p:Pos):TVar { core.Naming.checkLocalVariableName(ctx.com,n,origin,p); return addLocal(ctx,VUser(origin),n,t,p); }
	public static function genLocal(ctx:Typer,t:T,p:Pos):TVar return addLocal(ctx,VGenerated,Globals.genLocalPrefix,t,p);
	public static function isGenLocal(v:TVar):Bool return switch v.vKind { case VGenerated: true; case _: false; };
	public static function delay(g:TyperGlobals,p:TyperPass,f:Void->Void):Void {
		var index = passIndex(p); var tasks = g.delayed[index]; tasks.tasks.unshift(f); if (index < g.delayedMinIndex) g.delayedMinIndex = index;
	}
	public static function delayLate(g:TyperGlobals,p:TyperPass,f:Void->Void):Void {
		var index = passIndex(p); var tasks = g.delayed[index]; tasks.tasksLate.unshift(f); if (index < g.delayedMinIndex) g.delayedMinIndex = index;
	}
	public static function delayIfMono(g:TyperGlobals,p:TyperPass,t:T,f:Void->Void):Void switch core.TFunctions.follow(t) { case TMono(_): delay(g,p,f); case _: f(); }
	public static function flushPass(g:TyperGlobals,p:TyperPass,where:Dynamic):Void {
		var index = g.delayedMinIndex;
		while (index <= passIndex(p)) {
			var tasks = g.delayed[index];
			if (tasks.tasks.length != 0) {
				var f = tasks.tasks.shift(); f(); flushPass(g,p,where); return;
			} else if (tasks.tasksLate.length != 0) {
				tasks.tasks = tasks.tasksLate.copy(); tasks.tasks.reverse(); tasks.tasksLate = []; flushPass(g,p,where); return;
			} else { index++; g.delayedMinIndex = index; }
		}
	}
	public static function makePass<T>(ctx:Typer,f:T):T return f;
	public static function enterFieldTypingPass(g:TyperGlobals,info:Dynamic):Void flushPass(g,PConnectField,info);
	public static function makeLazy(ctx:TyperGlobals,tProc:T,f:Void->T,where:Dynamic):TLazy {
		var r = Common.makeUnforcedLazy(tProc,f,where);
		delay(ctx,PForce,function() { core.TFunctions.lazyType(r); }); return r;
	}
	public static function isForcedInline(c:Null<TClass>,cf:TClassField):Bool {
		if (c != null) { switch c.clKind { case KAbstractImpl(_): return true; case _: } if (core.TFunctions.hasClassFlag(c,CExtern)) return true; }
		return core.TFunctions.hasClassFieldFlag(cf,CfExtern);
	}
	public static function needsInline(ctx:Typer,c:Null<TClass>,cf:TClassField):Bool return switch cf.cfKind { case Method(MethInline): ctx.allowInline && (ctx.com.doinline || isForcedInline(c,cf)); case _: false; };
	public static function canAccess(ctx:Typer,c:TClass,cf:TClassField,stat:Bool,checkProp:Bool=false,isSetter:Bool=false):Bool {
		var isPrivateProp = checkProp && switch cf.cfKind {
			case Var({vRead:AccPrivateCall}) if (!isSetter): true;
			case Var({vWrite:AccPrivateCall}) if (isSetter): true;
			case _: false;
		};
		if (!isPrivateProp && core.TFunctions.hasClassFieldFlag(cf,CfPublic)) return true;
		if (c == ctx.c.curclass) return true;
		if (ctx.m.curmod.mStatics != null && c == ctx.m.curmod.mStatics) return true;
		function makePath(c:TClass,f:TClassField):Array<String> return switch c.clKind {
			case KAbstractImpl(a): a.aPath.pack.concat([a.aPath.name,f.cfName]);
			case KGenericInstance(c,_): makePath(c,f);
			case _ if (c.clPrivate): c.clPath.pack.slice(0,-1).concat([c.clPath.name,f.cfName]);
			case _: c.clPath.pack.concat([c.clPath.name,f.cfName]);
		};
		function exprPath(acc:Array<String>,e:Expr):Array<String> return switch e.expr {
			case EField(e,f,_): exprPath([f].concat(acc),e);
			case EConst(Ident(n)): [n].concat(acc);
			case _: [];
		};
		function chkPath(sub:Array<String>,full:Array<String>,isCurrentPath:Bool):Bool {
			for (i in 0...sub.length) {
				if (i >= full.length || sub[i] != full[i]) return false;
				if (!isCurrentPath && i == sub.length-1 && !core.StringHelper.startsUppercaseIdentifier(sub[i])) return false;
			}
			return true;
		}
		function has(meta:Dynamic,c:TClass,f:TClassField,entry:{path:Array<String>,isCurrent:Bool}):Bool {
			function loop(metadata:Metadata):Bool {
				for (m in metadata) if (m.meta == meta) for (e in m.exprs) switch e.expr {
					case EConst(Ident("std")): if (entry.path.length == 2) return true;
					case _: var p = exprPath([],e); if (p.length != 0 && chkPath(p,entry.path,entry.isCurrent)) return true;
				}
				return false;
			}
			return loop(c.clMeta) || loop(f.cfMeta);
		}
		var modulePath = ctx.c.curclass.clModule.mPath;
		var curPaths:Array<{path:Array<String>,isCurrent:Bool}> = [{path:modulePath.pack.concat([modulePath.name]),isCurrent:false}];
		function collect(c:TClass,isCurrentPath:Bool):Void {
			curPaths.unshift({path:makePath(c,ctx.f.curfield),isCurrent:isCurrentPath});
			if (c.clSuper != null) collect(c.clSuper.cls,false);
			for (implemented in c.clImplements) collect(implemented.cls,false);
		}
		collect(ctx.c.curclass,true);
		var isConstr = cf.cfName == "new";
		function loop(c:TClass):Bool {
			try {
				if (has(StrictMeta.Access,ctx.c.curclass,ctx.f.curfield,{path:makePath(c,cf),isCurrent:true})) return true;
				function allowed(f:TClassField):Bool {
					if (core.TFunctions.extendsClass(ctx.c.curclass,c)) return true;
					for (p in curPaths) if (has(StrictMeta.Allow,c,f,p)) return true;
					return false;
				}
				var found = false;
				if (isConstr) {
					var constructor = c.clConstructor;
					if (constructor != null) {
						if (allowed(constructor)) found = true;
						else if (constructor.cfExpr != null) throw NotFound.raise();
					}
				} else {
					var field = (stat ? c.clStatics : c.clFields).get(cf.cfName);
					if (field != null) found = allowed(field);
				}
				return found || (c.clSuper != null && loop(c.clSuper.cls));
			} catch (_:NotFound) return false;
		}
		if (loop(c)) return true;
		switch c.clKind {
			case KTypeParameter(ttp):
				for (t in core.TFunctions.getConstraints(ttp)) switch core.TFunctions.follow(t) { case TInst(c,_): if (loop(c)) return true; case _: }
			case _:
		}
		return MetadataTools.has(StrictMeta.PrivateAccess,ctx.f.meta);
	}
	public static function checkFieldAccess(ctx:Typer,c:TClass,f:TClassField,stat:Bool,p:Pos):Void {
		if (!ctx.f.isUntyped && !canAccess(ctx,c,f,stat)) Common.displayError(ctx.com,"Cannot access private field " + f.cfName,p);
	}
	public static function prepareUsingField(cf:TClassField):TClassField return switch core.TFunctions.follow(cf.cfType) {
		case TFun(sig) if (sig.args.length > 0):
			var tf = sig.args[0].type;
			var overloads:Array<TClassField> = [];
			for (cfo in cf.cfOverloads) switch cfo.cfType {
				case TFun(overloadSig) if (overloadSig.args.length > 0):
					var tfo = core.TFunctions.applyParams(cfo.cfParams,core.TFunctions.extractParamTypes(cfo.cfParams),overloadSig.args[0].type);
					if (TUnification.typeIseq(tf,tfo)) {
						var copy:TClassField = Reflect.copy(cfo);
						copy.cfType = TFun({args:overloadSig.args.slice(1),ret:overloadSig.ret});
						overloads.unshift(copy);
					}
				case _:
			}
			var out:TClassField = Reflect.copy(cf);
			out.cfOverloads = overloads;
			out.cfType = TFun({args:sig.args.slice(1),ret:sig.ret});
			out;
		case _: cf;
	};
	public static function mergeCoreDoc(ctx:Typer,mt:ModuleType):Void {
		var c:Null<TClass> = switch mt { case TClassDecl(c): c; case TAbstractDecl(a): a.aImpl; case _: null; };
		if (c == null || !MetadataTools.has(StrictMeta.CoreApi,c.clMeta)) return;
		var core = ctx.g.doLoadCoreClass(ctx,c);
		if (c.clDoc == null) c.clDoc = core.clDoc;
		function maybeMerge(map:TypeMap<TClassField>,cf:TClassField):Void {
			if (cf.cfDoc == null) { var other = map.get(cf.cfName); if (other != null) cf.cfDoc = other.cfDoc; }
		}
		for (cf in c.clOrderedFields) maybeMerge(core.clFields,cf);
		for (cf in c.clOrderedStatics) maybeMerge(core.clStatics,cf);
		if (c.clConstructor != null && c.clConstructor.cfDoc == null && core.clConstructor != null) c.clConstructor.cfDoc = core.clConstructor.cfDoc;
	}
	public static function safeMonoClose(ctx:Typer,m:TMono,p:Pos):Void {
		try Monomorph.close(m) catch (err:core.TUnification.Unify_error) raiseOrDisplay(ctx,err.errors,p);
	}
	public static function relativePath(ctx:Typer,file:String):String return ctx.com.classPaths.relativePath(file);
	public static function mkInfosT(ctx:Typer,p:Pos,params:Array<{key:{name:String,pos:Pos,quote:QuoteStatus},expr:TExpr}>,t:T):TExpr {
		var file = ctx.com.isMacroContext ? p.pfile : Common.defined(ctx.com,core.Define.AbsolutePath) ? core.Path.getFullPath(p.pfile) : relativePath(ctx,p.pfile);
		var line = syntax.Lexer.getErrorLine(p);
		var className = Globals.sTypePath(ctx.c.curclass.clPath);
		var fields = [
			{key:{name:"fileName",pos:Globals.nullPos,quote:NoQuotes},expr:core.Texpr.Builder.makeString(ctx.com.basic,file,p)},
			{key:{name:"lineNumber",pos:Globals.nullPos,quote:NoQuotes},expr:core.Texpr.Builder.makeInt(ctx.com.basic,line,p)},
			{key:{name:"className",pos:Globals.nullPos,quote:NoQuotes},expr:core.Texpr.Builder.makeString(ctx.com.basic,className,p)}
		];
		if (ctx.f.curfield.cfName != "") fields.push({key:{name:"methodName",pos:Globals.nullPos,quote:NoQuotes},expr:core.Texpr.Builder.makeString(ctx.com.basic,ctx.f.curfield.cfName,p)});
		return core.TFunctions.mk(TObjectDecl(fields.concat(params)),t,p);
	}
	public static function mkInfos(ctx:Typer,p:Pos,params:Array<ObjectField>):Expr {
		var file = ctx.com.isMacroContext ? p.pfile : Common.defined(ctx.com,core.Define.AbsolutePath) ? core.Path.getFullPath(p.pfile) : relativePath(ctx,p.pfile);
		var fields:Array<ObjectField> = [
			{key:{name:"fileName",pos:Globals.nullPos,quote:NoQuotes},expr:{expr:EConst(String(file,SDoubleQuotes)),pos:p}},
			{key:{name:"lineNumber",pos:Globals.nullPos,quote:NoQuotes},expr:{expr:EConst(Int(Std.string(syntax.Lexer.getErrorLine(p)),null)),pos:p}},
			{key:{name:"className",pos:Globals.nullPos,quote:NoQuotes},expr:{expr:EConst(String(Globals.sTypePath(ctx.c.curclass.clPath),SDoubleQuotes)),pos:p}}
		];
		if (ctx.f.curfield.cfName != "") fields.push({key:{name:"methodName",pos:Globals.nullPos,quote:NoQuotes},expr:{expr:EConst(String(ctx.f.curfield.cfName,SDoubleQuotes)),pos:p}});
		return {expr:EObjectDecl(fields.concat(params)),pos:p};
	}
	public static function isPosInfos(t:T):Bool return switch t {
		case TMono(r): r.tmType != null && isPosInfos(r.tmType);
		case TLazy(f): isPosInfos(core.TFunctions.lazyType(f));
		case TType(td,[]) if (td.tPath.pack.length == 1 && td.tPath.pack[0] == "haxe" && td.tPath.name == "PosInfos"): true;
		case TType(td,tl): isPosInfos(core.TFunctions.applyTypedef(td,tl));
		case TAbstract(a,[inner]) if (a.aPath.pack.length == 0 && a.aPath.name == "Null"): isPosInfos(inner);
		case _: false;
	};
	public static function isEmptyOrPosInfos(args:Array<{name:String,optional:Bool,type:T}>):Bool return args.length == 0 || (args.length == 1 && args[0].optional && isPosInfos(args[0].type));
	static var storedTypedExprUid = 0;
	public static function getNextStoredTypedExprId():Int return ++storedTypedExprUid;
	public static function makeStoredIdExpr(id:Int,p:Pos):Expr return {expr:EConst(Int(Std.string(id),null)),pos:p};
	public static function storeTypedExpr(com:Dynamic,te:TExpr,p:Pos):{id:Int,expr:Expr} {
		var id = getNextStoredTypedExprId(); com.partScope.storedTypedExprs.add(id,te);
		return {id:id,expr:{expr:EMeta({meta:StrictMeta.StoredTypedExpr,exprs:[],pos:Globals.nullPos},makeStoredIdExpr(id,p)),pos:p}};
	}
	public static function pushThis(ctx:Typer,e:TExpr):{expr:Expr,restore:Void->Void} return switch e.eexpr {
		case TConst(ct = TInt(_)),TConst(ct = TFloat(_)),TConst(ct = TString(_)),TConst(ct = TBool(_)):
			{expr:{expr:EConst(core.TFunctions.tconstToConst(ct)),pos:e.epos},restore:function() {}};
		case _:
			var stored = storeTypedExpr(ctx.com,e,e.epos);
			{expr:stored.expr,restore:function() ctx.com.partScope.storedTypedExprs.remove(stored.id)};
	};
	public static function createDeprecationContext(ctx:Typer):Dynamic {
		var out = context.display.DeprecationCheck.createContext(ctx.com);
		out.classMeta = ctx.c.curclass.clMeta; out.fieldMeta = ctx.f.curfield.cfMeta; out.curmod = ctx.m.curmod; return out;
	}
	public static function getOverloads(com:Dynamic,c:TClass,i:String):Dynamic {
		var key = {path:c.clPath,name:i};
		try return com.overloadCache.find(key) catch (_:NotFound) {
			var overloads = codegen.Overloads.collectOverloads(function(t) return t,c,i);
			com.overloadCache.add(key,overloads); return overloads;
		}
	}
}
