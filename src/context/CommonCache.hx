package context;

import context.Common;
import compiler.CompilationCache;
import core.Define;
import core.TType;

// haxe/src/context/commonCache.ml
// lib_build_task and handle_native_lib belong to native-library input (SWF/JVM),
// which is a later milestone: Compiler.Setup.initNativeLibs rejects native libraries.
class CommonCache {
	// context

	public static function getCache(com:CommonContext):ContextCache {
		if (com.cache == null) {
			var sign = Define.getSignature(com.defines);
			return (com.cs : Cache).getContext(sign);
		}
		return com.cache;
	}

	public static function getCacheSign(com:CommonContext):String {
		if (com.cache == null) return Define.getSignature(com.defines);
		return (com.cache : ContextCache).getSign();
	}

	public static function cacheContext(cs:Cache, com:CommonContext):Void {
		var cc = getCache(com);
		var sign = Define.getSignature(com.defines);
		var parallels:Array<{cc:ContextCache, m:ModuleDef, f:Void->Array<{kind:compiler.hxb.HxbData.ChunkKind, data:haxe.io.Bytes}>}> = [];
		function cacheModule(m:ModuleDef):Void {
			if (Define.defined(com.defines, Define.DisableHxbCache)) {
				// If we have a signature mismatch, look-up cache for module. Physical equality check is fine as a heuristic.
				var cc = m.mExtra.mSign == sign ? cc : cs.getContext(m.mExtra.mSign);
				cc.cacheModuleInMemory(m.mPath, m);
			} else {
				var anonIdentification = new typing.TanonIdentification<Dynamic>();
				function warn(w:Dynamic, s:String, p:core.Globals.Pos):Void com.warning(w, com.warningOptions, s, p);
				var config:Dynamic = if (com.hxbWriterConfig == null) new compiler.hxb.HxbWriterConfig.WriterTargetConfig() else (com.isMacroContext ? com.hxbWriterConfig.macroConfig : com.hxbWriterConfig.targetConfig);
				// If we have a signature mismatch, look-up cache for module. Physical equality check is fine as a heuristic.
				var cc = m.mExtra.mSign == sign ? cc : cs.getContext(m.mExtra.mSign);
				var f = cc.cacheHxbModule(config, warn, anonIdentification, m);
				if (f != null) parallels.push({cc: cc, m: m, f: f});
			}
		}
		for (m in com.modules) cacheModule(m);
		var a = [for (x in parallels) {cc: x.cc, m: x.m, chunks: x.f()}];
		for (x in a) x.cc.addBinaryCache(x.m, x.chunks);
		var macroCom = com.getMacros();
		if (macroCom != null) {
			cc.addChild(getCacheSign(macroCom));
			cacheContext(cs, macroCom);
		}
		if (Define.defined(com.defines, Define.HxbStats)) throw new core.ds.Failure("HXB reader statistics require HXB input, which is not supported by haxe-in-haxe");
	}

	public static function maybeAddContextSign(cs:Cache, com:CommonContext, desc:String):Void {
		var sign = Define.getSignature(com.defines);
		cs.addInfo(sign, desc, com.platform, com.classPaths, com.defines);
	}

	public static function lockSignature(com:CommonContext, name:String):Void {
		var cs:Cache = com.cs;
		maybeAddContextSign(cs, com, name);
		com.cache = getCache(com);
	}

	public static function maybeCacheContext(com:CommonContext):Void {
		if (com.display.dmsFullTyping && com.display.dmsPopulateCache) {
			core.Timer.time(com.timerCtx, ["server", "cache context"], function(com) {cacheContext(com.cs, com); return null;}, com);
			// ServerMessage.cached_modules: server logging, part of the server milestone.
		}
	}
}
