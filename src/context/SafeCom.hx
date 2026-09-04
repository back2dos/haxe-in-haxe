package context;
import core.Globals;
import core.TType;
import core.Message;
import context.PlatformConfig;
import context.DumpConfig;
import typing.Type;
import typing.Error;
import filters.FilterContext;
import sys.thread.Mutex;
// Draft mechanical translation of haxe/src/context/safeCom.ml; unvalidated.
typedef SavedWarning = {
	var wModule:ModuleDef;
	var wWarning:Dynamic;
	var wOptions:Array<Array<Dynamic>>;
	var wMsg:String;
	var wPos:core.Globals.Pos;
}
typedef SafeContext = {
	var basic:BasicTypes;
	var platform:core.Globals.Platform;
	var defines:core.Define.DefineContext;
	var platformConfig:PlatformConfig;
	var debug:Bool;
	var isMacroContext:Bool;
	var foptimize:Bool;
	var doinline:Bool;
	var dumpConfig:DumpConfiguration;
	var exceptions:{value:Array<Dynamic>};
	var exceptionsMutex:Mutex;
	var warnings:{value:Array<SavedWarning>};
	var warningsMutex:Mutex;
	var errors:{value:Array<Dynamic>};
	var errorsMutex:Mutex;
	var timerCtx:Dynamic;
	var findModule:core.Globals.GlobalTypePath->ModuleDef;
	var findModuleByType:core.Globals.GlobalTypePath->ModuleDef;
	var curclass:TClass;
	var curfield:TClassField;
}
class SafeCom {
	public static function ofCom(com:Dynamic):SafeContext return {
		basic:com.basic, platform:com.platform, defines:com.defines, platformConfig:com.config,
		debug:com.debug, isMacroContext:com.isMacroContext, foptimize:com.foptimize,
		doinline:com.doinline, dumpConfig:com.partScope.dumpConfig,
		exceptions:{value:[]}, exceptionsMutex:new Mutex(), warnings:{value:[]}, warningsMutex:new Mutex(),
		errors:{value:[]}, errorsMutex:new Mutex(), timerCtx:com.timerCtx,
		findModule:com.moduleLut.find, findModuleByType:com.moduleLut.findByType,
		curclass:Type.nullClass, curfield:Type.nullField
	};
	public static function ofTyper(ctx:Dynamic):SafeContext {
		var out = ofCom(ctx.com);
		out.curclass = ctx.c.curclass;
		out.curfield = ctx.f.curfield;
		return out;
	}
	public static function finalize(scom:SafeContext, com:Dynamic):Void {
		var warnings = scom.warnings.value;
		var errors = scom.errors.value;
		var exns = scom.exceptions.value;
		scom.warnings.value = [];
		scom.errors.value = [];
		scom.exceptions.value = [];
		for (warning in warnings) Common.moduleWarning(com,warning.wModule,warning.wWarning,warning.wOptions,warning.wMsg,warning.wPos);
		for (err in errors) Common.displayErrorExt(com,err);
		if (exns.length > 0) throw exns[0];
	}
	public static function runWithScom<T>(com:Dynamic, scom:SafeContext, f:Void->T):T {
		var result:T;
		try result = f() catch (exn:Dynamic) { finalize(scom,com); throw exn; }
		finalize(scom,com);
		return result;
	}
	static function protect<T>(mutex:Mutex, f:Void->T):T {
		mutex.acquire();
		var result:T;
		try result = f() catch (exn:Dynamic) { mutex.release(); throw exn; }
		mutex.release();
		return result;
	}
	public static function addError(scom:SafeContext, err:Dynamic):Void {
		protect(scom.errorsMutex,function() { scom.errors.value.unshift(err); return null; });
	}
	public static function addExn(scom:SafeContext, exn:Dynamic):Void {
		if (Std.isOfType(exn, typing.Error.CompilerError)) addError(scom,exn.error);
		else protect(scom.exceptionsMutex,function() { scom.exceptions.value.unshift(exn); return null; });
	}
	public static function addWarning(scom:SafeContext, w:Dynamic, msg:String, p:core.Globals.Pos):Void {
		var options = Warning.fromMeta(scom.curfield.cfMeta).concat(Warning.fromMeta(scom.curclass.clMeta));
		switch Warning.getMode(w,options) {
			case WMEnable:
				protect(scom.warningsMutex,function() {
					scom.warnings.value.unshift({wModule:scom.curclass.clModule,wWarning:w,wOptions:options,wMsg:msg,wPos:p});
					return null;
				});
			case WMDisable:
		}
	}
	public static function runExpressionFiltersSafe(scom:SafeContext, detailTimes:Bool, filters:Array<{name:String, run:SafeContext->TExpr->TExpr}>, t:ModuleType, ignoreProcessedStatus:Bool = false):Void {
		function run(local:SafeContext, identifier:Null<String>, e:TExpr):TExpr {
			try {
				var next = e;
				for (filter in filters) {
					try next = FilterContext.withTimer(local.timerCtx,detailTimes,filter.name,identifier,function() return filter.run(local,next));
					catch (failure:core.StringError.Failure) Error.raiseTypingError(failure.message,next.epos);
				}
				return next;
			} catch (exc:Dynamic) { addExn(local,exc); return e; }
		}
		switch t {
			case TClassDecl(c) if (FilterContext.isRemovableClass(c)):
			case TClassDecl(c):
				var local:SafeContext = Reflect.copy(scom);
				local.curclass = c;
				function processField(cf:TClassField):Void {
					if (ignoreProcessedStatus || !Type.hasClassFieldFlag(cf,CfPostProcessed)) {
						var fieldContext:SafeContext = Reflect.copy(local);
						fieldContext.curfield = cf;
						if (cf.cfExpr != null && !FilterContext.isRemovableField(fieldContext.isMacroContext,cf))
							cf.cfExpr = run(fieldContext,Globals.sTypePath(c.clPath)+"."+cf.cfName,cf.cfExpr);
					}
					for (overload in cf.cfOverloads) processField(overload);
				}
				for (cf in c.clOrderedFields) processField(cf);
				for (cf in c.clOrderedStatics) processField(cf);
				if (c.clConstructor != null) processField(c.clConstructor);
				var init = typing.TClass.getClInit(c);
				if (init != null) typing.TClass.setClInit(c,run(local,Globals.sTypePath(c.clPath)+".__init__",init));
			case TEnumDecl(_), TTypeDecl(_), TAbstractDecl(_):
		}
	}
	public static function adaptScomToMt(scom:SafeContext, mt:ModuleType):SafeContext return switch mt {
		case TClassDecl(c): var out:SafeContext = Reflect.copy(scom); out.curclass = c; out;
		case _: scom;
	};
	public static function runTypeFiltersSafe(scom:SafeContext, filters:Array<SafeContext->ModuleType->Void>, types:Array<ModuleType>):Void {
		for (t in types) {
			var local = adaptScomToMt(scom,t);
			for (f in filters) f(local,t);
		}
	}
	public static function needsInline(scom:SafeContext, c:TClass, cf:TClassField):Bool return switch cf.cfKind {
		case Method(MethInline): scom.doinline || Typecore.isForcedInline(c,cf);
		case _: false;
	};
}
