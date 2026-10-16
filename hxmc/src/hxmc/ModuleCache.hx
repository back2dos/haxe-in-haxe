package hxmc;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import sys.FileSystem;
import sys.io.File;
import core.Globals.GlobalTypePath;
import core.TType;
import compiler.hxb.HxbData;
import context.Common;
import core.Message.CompilerMessageKind;
import core.Message.WarningMode;
import core.Json.JsonValue;

// The compilation server's module cache made durable (hxmc/PLANS.md, "Cached
// modules"): a build writes the typed modules it ends with, as the server
// keeps them in its HXB mode (each module's HXB chunks, its dependencies,
// kind, file and check policy), into a store in the user's cache directory;
// the next build with the same key puts them back in the server's cache
// before typing, and the server's own checks decide, module by module and
// only for the modules the build loads, which are still good (the module's
// file, its dependencies: a dirty one makes its dependents dirty); the HXB is
// decoded on demand. What a cache from an earlier process needs beyond those
// checks is ServerCache.checkModuleHook's (check below): the file's content
// (a content hash where the date or size differ: a fresh checkout changes
// every date; a date within RACY seconds of the parse is not trusted), the
// file the module's path resolves to now (a module shadowed by a new file
// earlier in the class path is typed again), and dependencies the store does
// not have. A build from the cache writes the same output as one without it
// (hxmc/test/ModuleCacheCheck.hx), which takes two things the server's HXB
// cache does not keep: the modifiers of unbound monomorphs (Null<Unknown>:
// CheckingHxbWriter, given back to the reader's monomorphs through
// ServerCache.readerCreatedHook) and what the sort of the types walks of a
// restored module, whose expressions are the filtered ones (Skeletons,
// through Finalization.sortExprHook).
//
// Opt-in: HXMC_MODULE_CACHE=1 or -D hxmc.module-cache; HXMC_MODULE_CACHE=0
// or -D hxmc.no-module-cache turns it off (also when the define is given).
// Through `haxe` (HaxeMain) and the tool alike, for every target. Not used
// (the build types as usual, TypesCache included): display requests, the
// compilation server and its clients (already in memory), builds of several
// parts (--next, --each), init macros (--macro: their effects are not in the
// key yet), HXB libraries or output, native libraries, WASI. A build in
// which a macro registers a callback (Context.onGenerate, onAfterTyping,
// onAfterGenerate) while typing writes nothing: a module restored later
// would not register it again. HXMC_STATS=1 prints what the cache did,
// HXMC_MODULE_CACHE_LOG=1 each module checked and each one not kept.
//
// Store: <cache>/modules/<tool>/<key>-<signature>.pack, one pack per server
// context (the program's and its macros', each with its signature: the
// defines), <key> the working directory, the class paths and the std; a
// pack is an index (the files with their date, size and content hash; per
// module its path, id, ModuleDefExtra, HXB chunks, monomorph modifiers and
// skeletons) written whole beside and renamed into place. A build rewrites
// the packs it changed: its modules, and the modules of the old pack it did
// not load, except those that depend on a module it typed again or found
// dirty. Module and variable ids continue from the store's (the server keeps
// the ids of the modules and variables it restores). The tool directories
// are trimmed with the types cache's rules (TypesCache.trim).
class ModuleCache {
	public static inline var MAGIC = "hxmc-modules 4";
	static final noMonos = {
		var o = new BytesOutput();
		o.writeInt32(0);
		o.getBytes();
	}

	static var previousHook:Null<(CommonContext, compiler.ParsedArg.ArgContext) -> Void>;
	static var state:Null<ModuleCacheState> = null;
	static var hookCalls = 0;
	static var parseHookInstalled = false;
	static var start = haxe.Timer.stamp();

	public static function current():Null<ModuleCacheState>
		return state;

	public static function install() {
		previousHook = compiler.Compiler.beforeTypingHook;
		compiler.Compiler.beforeTypingHook = hook;
	}

	static function wanted(com:CommonContext):Bool {
		var env = Sys.getEnv("HXMC_MODULE_CACHE");
		if (env == "0" || TypesCache.define(com, "hxmc.no-module-cache") != null) return false;
		return env == "1" || TypesCache.define(com, "hxmc.module-cache") != null;
	}

	// why a build that wants the cache cannot use it (null: it can)
	static function unusable(com:CommonContext, actx:compiler.ParsedArg.ArgContext):Null<String> {
		if (hookCalls > 1 || com.partScope.hasNext) return "several compilations";
		if (com.sctx.isServer || Driver.resident) return "compilation server";
		if (actx.displayArg != null || com.display.dmsKind != DMNone) return "display request";
		if (actx.configMacros.length > 0) return "init macros";
		if (actx.hxbLibs.length > 0 || actx.nativeLibs.length > 0) return "libraries";
		if (actx.hxbOut != null) return "HXB output";
		if (Sys.systemName() == "Wasi") return "WASI";
		return null;
	}

	static function hook(com:CommonContext, actx:compiler.ParsedArg.ArgContext) {
		hookCalls++;
		state = null;
		compiler.server.ServerCache.checkModuleHook = null;
		typing.Finalization.sortExprHook = null;
		var why = wanted(com) ? unusable(com, actx) : "off";
		var s = why == null ? open(com) : null;
		if (s == null) {
			if (why == null) why = "no cache directory";
			if (why != "off" && Sys.getEnv("HXMC_STATS") == "1") Sys.println('hxmc: module cache not used ($why)');
			if (previousHook != null) previousHook(com, actx);
			return;
		}
		state = s;
		s.com = com;
		compiler.server.ServerCache.checkModuleHook = check;
		typing.Finalization.sortExprHook = Skeletons.sortExpr;
		// (what the sort of the types walks, of every class typed: before the
		// filters change it)
		com.callbacks.addAfterTyping(_ -> Skeletons.computeAll(com));
		if (!parseHookInstalled) {
			parseHookInstalled = true;
			// (the modifiers of a restored module's monomorphs, once the
			// server has read it)
			compiler.server.ServerCache.readerCreatedHook = function(com, path, reader) {
				var s = state;
				if (s == null) return;
				var p = s.packs.get(context.CommonCache.getCacheSign(com));
				var e = p == null ? null : p.modules.get(key(path));
				if (e != null && e.monos.length > 4) s.readers.push({com: com, reader: reader, monos: e.monos});
			}
			var typeModule = typing.TypeloadCacheHook.typeModuleHook;
			typing.TypeloadCacheHook.typeModuleHook = function(com, delay, path, p) {
				var r = typeModule(com, delay, path, p);
				var s = state;
				if (s != null) s.restoreMonos();
				return r;
			}
			var inner = typing.TypeloadParse.parseHook;
			typing.TypeloadParse.parseHook = function(com, rfile, p) {
				var s = state;
				if (s != null) s.note(core.Path.getFullPath(rfile.file));
				return inner(com, rfile, p);
			}
		}
		// (before the compiler's own: registrations from now until typing is
		// done are the macros')
		com.callbacks.addAfterSave(() -> capture(com));
		com.callbacks = new WatchedCallbacks(com.callbacks, com, what -> if (s.volatileReason == null) s.volatileReason = what);
	}

	static function stats():Bool
		return Sys.getEnv("HXMC_STATS") == "1";

	static function ms(t:Float):Int
		return Std.int((haxe.Timer.stamp() - t) * 1000);

	// the store for this build: its packs read and put in the server's cache
	static function open(com:CommonContext):Null<ModuleCacheState> {
		var root = TypesCache.cacheRoot();
		if (root == null) return null;
		var t0 = haxe.Timer.stamp();
		var modules = root + "modules/";
		var dir = modules + TypesCache.toolStamp() + "/";
		var used = dir + "used";
		if (!FileSystem.exists(used) || TypesCache.now() - TypesCache.mtime(used) > TypesCache.USED_REFRESH)
			if (!TypesCache.touch(used)) return null;
		TypesCache.trim(modules, dir);
		var key = Fingerprint.hash(["hxmc-modules", Sys.getCwd(), Sys.getEnv("HAXE_STD_PATH"), com.classPaths.asStringList().join("\n")].join("\x00"));
		var s = new ModuleCacheState(dir, dir + key + "-");
		var prefix = key + "-";
		var names = try FileSystem.readDirectory(dir) catch (_:Dynamic) [];
		names.sort(Reflect.compare);
		for (n in names)
			if (StringTools.startsWith(n, prefix) && StringTools.endsWith(n, ".pack")) {
				var p = try ModulePack.read(dir + n) catch (e:Dynamic) {
					if (stats()) Sys.println('hxmc: module cache: $n unreadable ($e)');
					null;
				}
				if (p != null && dir + prefix + p.sign + ".pack" == dir + n) s.packs.set(p.sign, p);
			}
		// ids continue from the store's (restored modules and variables keep theirs)
		var midHigh = 0, varHigh = 0;
		for (p in s.packs) {
			if (p.moduleHigh > midHigh) midHigh = p.moduleHigh;
			if (p.varHigh > varHigh) varHigh = p.varHigh;
		}
		@:privateAccess {
			if (core.TFunctions.moduleUid.load() < midHigh) core.TFunctions.moduleUid.store(midHigh);
			if (core.TFunctions.varUid.load() < varHigh) core.TFunctions.varUid.store(varHigh);
		}
		var n = 0;
		for (p in s.packs) {
			var cc = com.cs.getContext(p.sign);
			var hxb = cc.getHxb();
			for (e in p.modules) {
				var x = ModulePack.readExtra(e.extra);
				if (x.mKind == MImport) {
					// (an import.hx: no types, kept as a module in memory, as the server does)
					cc.cacheModuleInMemory(e.path, ({mId: e.id, mPath: e.path, mTypes: [], mStatics: null, mExtra: x} : ModuleDef));
				} else {
					var mc:compiler.hxb.HxbData.ModuleCache = {
						mcPath: e.path,
						mcId: e.id,
						mcChunks: e.chunks,
						mcExtra: x
					};
					hxb.replace(e.path, mc);
				}
				n++;
			}
		}
		s.loaded = n;
		if (stats()) Sys.println('hxmc: module cache: $n modules in ${Lambda.count(s.packs)} packs read (${ms(t0)} ms)');
		return s;
	}

	public static function key(p:GlobalTypePath):String
		return p.pack.join("/") + "|" + p.name;

	// the com whose context has this signature (the build's or its macros')
	public static function comFor(com:CommonContext, sign:String):Null<CommonContext> {
		if (context.CommonCache.getCacheSign(com) == sign) return com;
		var m = com.getMacros();
		if (m != null && context.CommonCache.getCacheSign(m) == sign) return m;
		return null;
	}

	// whether the module's path resolves to its file in this com
	static function resolvesTo(com:CommonContext, path:GlobalTypePath, fileKey:String):Bool {
		var r = try typing.TypeloadParse.resolveModuleFile(com, path, {value: path.pack.copy()}, core.Globals.nullPos) catch (_:Dynamic) null;
		return r != null && com.partScope.fileKeys.get(core.Path.getFullPath(r.file)) == fileKey;
	}

	static function fileHash(s:ModuleCacheState, file:String):Null<String> {
		var h = s.hashes.get(file);
		if (h == null) {
			h = try haxe.crypto.Md5.make(File.getBytes(file)).toHex() catch (_:Dynamic) null;
			if (h != null) s.hashes.set(file, h);
		}
		return h;
	}

	static function size(file:String):Float
		return try FileSystem.stat(file).size catch (_:Dynamic) -1;

	// ServerCache.checkModuleHook: a module from the store, before the
	// server's checks
	static function check(com:CommonContext, mPath:GlobalTypePath, mExtra:ModuleDefExtra):Null<ModuleSkipReason> {
		var s = state;
		if (s == null) return null;
		var p = s.packs.get(mExtra.mSign);
		if (p == null) return null;
		var e = p.modules.get(key(mPath));
		if (e == null) return null;
		var t0 = haxe.Timer.stamp();
		var r = verify(com, s, p, e, mPath, mExtra);
		s.checked++;
		if (r != null) s.dirty.set(mExtra.mSign + "\x00" + key(mPath), true);
		if (s.log) Sys.println("hxmc: module cache: " + core.Globals.sTypePath(mPath) + (r == null ? " good" : " dirty: " + core.TPrinting.Printer.sModuleSkipReason(r)));
		s.checkTime += haxe.Timer.stamp() - t0;
		return r;
	}

	static function verify(com:CommonContext, s:ModuleCacheState, p:ModulePack, e:StoredModule, mPath:GlobalTypePath, mExtra:ModuleDefExtra):Null<ModuleSkipReason> {
		var file = core.Path.UniqueKey.lazyPath(mExtra.mFile);
		switch mExtra.mKind {
			case MCode | MMacro:
				// (a module of the macros' context checked from the program's
				// before that context exists: its class paths are not known
				// yet, only its file is checked)
				var rcom = comFor(com, mExtra.mSign);
				if (rcom != null && !resolvesTo(rcom, mPath, core.Path.UniqueKey.lazyKey(mExtra.mFile))) return Shadowed(file);
			case MFake | MImport:
			case MExtern:
				return LibraryChanged;
		}
		var time = Common.fileTime(file);
		if (time == 0 && !FileSystem.exists(file)) {
			// (a @:generic instance: a type path for a file, checked by its dependencies)
			if (!(mExtra.mKind == MFake && e.mtime == 0)) return FileChanged(file);
		} else {
			var f = p.files.get(file);
			if (f == null) return FileChanged(file);
			if (!(f.mtime == time && f.size == size(file)) && fileHash(s, file) != f.hash) return FileChanged(file);
			mExtra.mTime = time;
		}
		// (dependencies the store did not keep: the server could not find them)
		for (d in mExtra.mDeps) {
			var found = try {
				com.cs.getContext(d.mdSign).findModuleExtra(d.mdPath);
				true;
			} catch (_:core.ds.NotFound) false;
			if (!found) return DependencyDirty(d.mdPath, LibraryChanged);
		}
		return null;
	}

	// after the state is saved (before DCE and generation change the typed
	// program): the modules of the build as the server would cache them
	static function capture(com:CommonContext) {
		var s = state;
		if (s == null || s.volatileReason != null) return;
		if (Common.hasErrorToReport(com)) {
			s.volatileReason = "errors";
			return;
		}
		var t0 = haxe.Timer.stamp();
		var coms = [com];
		var mcom = com.getMacros();
		if (mcom != null) coms.push(mcom);
		var jobs:Array<{out:CapturedModule, f:Void->CachedChunks}> = [];
		for (c in coms) {
			var config:compiler.hxb.HxbWriterConfig.WriterTargetConfig = switch c.hxbWriterConfig {
				case null: new compiler.hxb.HxbWriterConfig.WriterTargetConfig();
				case config: c.isMacroContext ? config.macroConfig : config.targetConfig;
			}
			function warn(w:core.Message.WarningCode, msg:String, p:core.Globals.Pos):Void c.warning(w, c.warningOptions, msg, p);
			for (m in c.modules) {
				var x = m.mExtra;
				s.seen.set(x.mSign + "\x00" + key(m.mPath), true);
				inline function skip(why:String)
					if (s.log) Sys.println("hxmc: module cache: " + core.Globals.sTypePath(m.mPath) + " not kept (" + why + ")");
				if (x.mKind == MExtern) {
					skip("kind");
					continue;
				}
				var file = core.Path.UniqueKey.lazyPath(x.mFile);
				var time = Common.fileTime(file);
				var rec:Null<StoredFile> = null;
				if (time == 0 && !FileSystem.exists(file)) {
					if (!(x.mKind == MFake && x.mTime == 0)) {
						skip("no file");
						continue;
					}
				} else {
					// (a file changed while the build ran, or a module from another file)
					if (time != x.mTime) {
						skip("file changed");
						continue;
					}
					if ((x.mKind == MCode || x.mKind == MMacro) && !resolvesTo(c, m.mPath, core.Path.UniqueKey.lazyKey(x.mFile))) {
						skip("path resolves elsewhere");
						continue;
					}
					// (the content as parsed, else as the store has it, else now)
					rec = s.parsed.get(file);
					if (rec == null) {
						var p = s.packs.get(x.mSign);
						var old = p == null ? null : p.files.get(file);
						if (old != null && old.mtime == time && old.size == size(file)) rec = old else rec = s.record(file);
					}
					if (rec == null) {
						skip("unreadable");
						continue;
					}
				}
				var out:CapturedModule = {
					sign: x.mSign,
					path: m.mPath,
					id: m.mId,
					file: rec == null ? null : file,
					rec: rec,
					extra: ModulePack.writeExtra(x),
					chunks: null,
					monos: null,
					skeletons: null,
					fresh: true
				};
				s.captured.push(out);
				// restored and not processed again: the stored chunks
				var p = s.packs.get(x.mSign);
				var e = p == null ? null : p.modules.get(key(m.mPath));
				out.skeletons = e != null && e.id == m.mId ? e.skeletons : Skeletons.encode(s, x.mSign, m.mPath);
				if (e != null && e.id == m.mId && x.mProcessed == e.processed) {
					out.chunks = e.chunks;
					out.monos = e.monos;
					out.fresh = false;
					continue;
				}
				if (x.mKind == MImport) {
					out.chunks = [];
					out.monos = noMonos;
					continue;
				}
				if (s.log && e != null) Sys.println("hxmc: module cache: " + core.Globals.sTypePath(m.mPath) + " encoded again (id " + m.mId + "/" + e.id + ", processed " + x.mProcessed + ")");
				// (as ContextCache.cacheHxbModule, with a writer that keeps what
				// HXB does not)
				jobs.push({
					out: out,
					f: function() {
						var w = new CheckingHxbWriter(config, warn, new typing.TanonIdentification<Dynamic>());
						w.writeModule(m);
						out.monos = w.monoModifiers();
						return (w.getChunks() : CachedChunks);
					}
				});
			}
		}
		var none:{out:CapturedModule, chunks:CachedChunks} = {out: null, chunks: []};
		var done = context.Parallel.runWithPool(com.sctx.pool, function(pool) {
			return context.Parallel.ParallelArray.map(pool, function(j:{out:CapturedModule, f:Void->CachedChunks}) return {out: j.out, chunks: j.f()}, jobs, none);
		});
		for (d in done)
			d.out.chunks = d.chunks;
		s.written = jobs.length;
		s.captureTime = haxe.Timer.stamp() - t0;
	}

	// the end of a build (code: its exit code): the packs it changed written
	public static function finish(code:Int) {
		var s = state;
		state = null;
		compiler.server.ServerCache.checkModuleHook = null;
		typing.Finalization.sortExprHook = null;
		if (s == null) return;
		var t0 = haxe.Timer.stamp();
		var wrote = 0;
		if (code == 0 && s.volatileReason == null && s.captured.length > 0) {
			// the stored modules this build did not end with: kept unless
			// found dirty, or depending (in any pack) on a module the build
			// typed again or did not keep
			var changed = new Map<String, Bool>();
			for (k in s.dirty.keys()) changed.set(k, true);
			var kept = new Map<String, Bool>();
			for (c in s.captured)
				if (c.fresh) changed.set(c.sign + "\x00" + key(c.path), true) else kept.set(c.sign + "\x00" + key(c.path), true);
			for (k in s.seen.keys())
				if (!kept.exists(k)) changed.set(k, true);
			var old:Array<{k:String, sign:String, e:StoredModule}> = [];
			for (p in s.packs)
				for (mk => e in p.modules) {
					var k = p.sign + "\x00" + mk;
					if (!s.seen.exists(k) && !changed.exists(k)) old.push({k: k, sign: p.sign, e: e});
				}
			var more = true;
			while (more) {
				more = false;
				for (o in old)
					if (!changed.exists(o.k))
						for (d in o.e.deps)
							if (changed.exists(d)) {
								changed.set(o.k, true);
								more = true;
								break;
							}
			}
			// per signature: the build's modules, then the old ones kept
			var bySign = new Map<String, Array<CapturedModule>>();
			var dirtySigns = new Map<String, Bool>();
			for (c in s.captured) {
				var l = bySign.get(c.sign);
				if (l == null) bySign.set(c.sign, l = []);
				l.push(c);
				if (c.fresh) dirtySigns.set(c.sign, true);
			}
			// (and the packs that lose modules)
			for (p in s.packs) {
				if (!bySign.exists(p.sign)) bySign.set(p.sign, []);
				for (mk in p.modules.keys()) {
					var k = p.sign + "\x00" + mk;
					if (s.seen.exists(k) ? !kept.exists(k) : changed.exists(k)) dirtySigns.set(p.sign, true);
				}
			}
			var midHigh = @:privateAccess core.TFunctions.moduleUid.load();
			var varHigh = @:privateAccess core.TFunctions.varUid.load();
			for (sign => list in bySign) {
				if (!dirtySigns.exists(sign)) continue;
				var keep = [for (o in old) if (o.sign == sign && !changed.exists(o.k)) o.e];
				var path = s.base + sign + ".pack";
				var tmp = path + "." + TypesCache.nonce() + ".tmp";
				var ok = try {
					File.saveBytes(tmp, ModulePack.write(sign, midHigh, varHigh, list, keep, s.packs.get(sign)));
					TypesCache.replace(tmp, path);
				} catch (e:Dynamic) {
					try FileSystem.deleteFile(tmp) catch (_:Dynamic) {}
					false;
				}
				if (ok) wrote++;
			}
		}
		if (stats())
			Sys.println('hxmc: module cache: ${s.checked} checked (${Std.int(s.checkTime * 1000)} ms), ${s.written} modules encoded (${Std.int(s.captureTime * 1000)} ms), '
				+ '$wrote packs written (${ms(t0)} ms)' + (s.volatileReason != null ? ' (not written: ${s.volatileReason})' : ''));
	}
}

@:structInit class StoredFile {
	public var mtime:Float;
	public var size:Float;
	public var hash:String;
}

@:structInit class StoredModule {
	public var path:GlobalTypePath;
	public var id:Int;
	public var mtime:Float;
	// mProcessed as restored (-1: processed in an earlier compilation)
	public var processed:Int;
	// the module's ModuleDefExtra as written (ModulePack.writeExtra)
	public var extra:Bytes;
	public var chunks:CachedChunks;
	// CheckingHxbWriter.monoModifiers
	public var monos:Bytes;
	// Skeletons.encode (decoded on demand)
	public var skeletons:Bytes;
	public var skeletonMap:Null<Map<String, Bytes>> = null;
	// the dependencies' keys (signature, path)
	public var deps:Array<String>;
}

@:structInit class CapturedModule {
	public var sign:String;
	public var path:GlobalTypePath;
	public var id:Int;
	public var file:Null<String>;
	public var rec:Null<StoredFile>;
	public var extra:Bytes;
	public var chunks:Null<CachedChunks>;
	// CheckingHxbWriter.monoModifiers
	public var monos:Null<Bytes>;
	// Skeletons.encode
	public var skeletons:Null<Bytes>;
	// typed (or processed) by this build
	public var fresh:Bool;
}

class ModuleCacheState {
	public var dir:String;
	public var base:String;
	public var packs = new Map<String, ModulePack>();
	public var hashes = new Map<String, String>();
	public var dirty = new Map<String, Bool>();
	public var seen = new Map<String, Bool>();
	public var captured:Array<CapturedModule> = [];
	public var com:Null<CommonContext> = null;
	// per module (signature and path), what the sort of the types walks of
	// its classes' fields, as typed in this build (Skeletons)
	public var skeletons = new Map<String, Map<String, Bytes>>();
	public var walked = new Map<String, Bool>();
	// the readers of restored modules whose monomorphs have modifiers
	public var readers:Array<{com:CommonContext, reader:compiler.hxb.HxbReader, monos:Bytes}> = [];
	public var volatileReason:Null<String> = null;
	// HXMC_MODULE_CACHE_LOG=1: each module checked, each not kept, each encoded again
	public var log = Sys.getEnv("HXMC_MODULE_CACHE_LOG") == "1";
	public var loaded = 0;
	public var checked = 0;
	public var written = 0;
	public var checkTime = 0.0;
	public var captureTime = 0.0;

	// the files parsed, as the parser read them (their date, size and
	// content hash)
	public var parsed = new Map<String, StoredFile>();

	public function note(file:String)
		if (!parsed.exists(file)) {
			var r = record(file);
			if (r != null) parsed.set(file, r);
		}

	// a file's date, size and content hash; a date within RACY seconds of
	// now is not kept (a later change within the date's resolution would
	// not show): the next build compares the content
	public function record(file:String):Null<StoredFile> {
		var st = try FileSystem.stat(file) catch (_:Dynamic) return null;
		var b = try File.getBytes(file) catch (_:Dynamic) return null;
		var mtime = st.mtime.getTime() / 1000.0;
		return {mtime: TypesCache.now() - mtime < RACY ? -1 : mtime, size: b.length, hash: haxe.crypto.Md5.make(b).toHex()};
	}

	static inline var RACY = 3.0;

	// the modifiers back on the monomorphs of the modules read since
	public function restoreMonos() {
		var l = readers;
		readers = [];
		for (r in l)
			CheckingHxbWriter.restore(r.com, r.reader, r.monos);
	}

	public function new(dir:String, base:String) {
		this.dir = dir;
		this.base = base;
	}
}

// a pack: one server context's modules
class ModulePack {
	public var sign:String;
	public var moduleHigh:Int;
	public var varHigh:Int;
	public var files = new Map<String, StoredFile>();
	public var modules = new Map<String, StoredModule>();

	function new() {}

	// (the constructors in declaration order, written by index; the
	// compiler compares them with ==)
	static final chunkKinds:Array<ChunkKind> = [
		STR, DOC, MDF, MTF, IMP, CLR, ENR, ABR, TDR, OFR, OFD, OBD, CLD, END, ABD, TDD, EOT, EFR, CFR, CFD, EFD, AFD, EOF, EXD, EOM
	];
	static final moduleKinds:Array<ModuleKind> = [MCode, MMacro, MFake, MExtern, MImport];
	static final policies:Array<ModuleCheckPolicy> = [NoFileSystemCheck, CheckFileModificationTime, CheckFileContentModification];
	static final diagnosticsKinds:Array<core.Message.MessageKind> = [
		DKUnusedImport, DKUnresolvedIdentifier, DKCompilerMessage, DKReplacableCode, DKParserError, DKDeprecationWarning, DKInactiveBlock, DKMissingFields
	];
	static final origins:Array<ModuleDepOrigin> = [MDepFromTyping, MDepFromImport, MDepFromMacro, MDepFromMacroInclude, MDepFromMacroDefine];

	public static function str(o:BytesOutput, s:String) {
		var b = Bytes.ofString(s);
		o.writeInt32(b.length);
		o.write(b);
	}

	public static function rstr(i:BytesInput):String {
		var n = i.readInt32();
		return i.readString(n);
	}

	public static function path(o:BytesOutput, p:GlobalTypePath) {
		o.writeInt32(p.pack.length);
		for (s in p.pack)
			str(o, s);
		str(o, p.name);
	}

	public static function rpath(i:BytesInput):GlobalTypePath {
		var pack = [for (_ in 0...i.readInt32()) rstr(i)];
		return {pack: pack, name: rstr(i)};
	}

	static function json(o:BytesOutput, j:JsonValue)
		switch j {
			case JString(v):
				o.writeByte(0);
				str(o, v);
			case JFloat(v):
				o.writeByte(1);
				o.writeDouble(v);
			case JInt(v):
				o.writeByte(2);
				o.writeInt32(v);
			case JObject(fields):
				o.writeByte(3);
				o.writeInt32(fields.length);
				for (f in fields) {
					str(o, f.name);
					json(o, f.value);
				}
			case JArray(values):
				o.writeByte(4);
				o.writeInt32(values.length);
				for (v in values)
					json(o, v);
			case JBool(v):
				o.writeByte(v ? 6 : 5);
			case JNull:
				o.writeByte(7);
		}

	static function rjson(i:BytesInput):JsonValue
		return switch i.readByte() {
			case 0: JString(rstr(i));
			case 1: JFloat(i.readDouble());
			case 2: JInt(i.readInt32());
			case 3: JObject([
					for (_ in 0...i.readInt32()) {
						var name = rstr(i);
						({name: name, value: rjson(i)} : core.Json.JsonField);
					}
				]);
			case 4: JArray([for (_ in 0...i.readInt32()) rjson(i)]);
			case 5: JBool(false);
			case 6: JBool(true);
			case _: JNull;
		}

	static function depKey(sign:String, p:GlobalTypePath):String
		return sign + "\x00" + p.pack.join("/") + "|" + p.name;

	// a module's ModuleDefExtra (what the server's binary cache keeps of it;
	// mProcessed only as processed or not)
	public static function writeExtra(x:ModuleDefExtra):Bytes {
		var o = new BytesOutput();
		str(o, core.Path.UniqueKey.lazyPath(x.mFile));
		str(o, x.mSign);
		o.writeDouble(x.mTime);
		o.writeByte(x.mKind.getIndex());
		o.writeByte(x.mProcessed != 0 ? 1 : 0);
		o.writeByte(x.mCheckPolicy.length);
		for (p in x.mCheckPolicy)
			o.writeByte(p.getIndex());
		var ids = [for (k in x.mDeps.keys()) k];
		ids.sort((a, b) -> a - b);
		o.writeInt32(ids.length);
		for (id in ids) {
			var d = x.mDeps.get(id);
			o.writeInt32(id);
			str(o, d.mdSign);
			o.writeByte(d.mdKind.getIndex());
			path(o, d.mdPath);
			o.writeByte(d.mdOrigin.getIndex());
		}
		var objs = x.mCacheBoundObjects;
		o.writeInt32(objs.length);
		for (c in objs)
			switch c {
				case Resource(name, data):
					o.writeByte(0);
					str(o, name);
					o.writeInt32(data.length);
					o.write(data);
				case IncludeFile(file, contents):
					o.writeByte(1);
					str(o, file);
					str(o, contents);
				case Message(cm):
					o.writeByte(2);
					str(o, cm.cmMessage);
					str(o, cm.cmPos.pfile);
					o.writeInt32(cm.cmPos.pmin);
					o.writeInt32(cm.cmPos.pmax);
					o.writeInt32(cm.cmDepth);
					o.writeByte(cm.cmFromMacro ? 1 : 0);
					switch cm.cmMessageKind {
						case MKError:
							o.writeByte(0);
						case MKInfo:
							o.writeByte(2);
						case MKWarning(w, options):
							o.writeByte(1);
							str(o, w);
							o.writeInt32(options.length);
							for (l in options) {
								o.writeInt32(l.length);
								for (wo in l) {
									str(o, wo.woWarning);
									o.writeByte(wo.woMode.getIndex());
								}
							}
					}
					o.writeByte(cm.cmDiagnosticsKind.getIndex());
					json(o, cm.cmJson);
			}
		var fs = [for (k in x.mFeatures.keys()) k];
		fs.sort(Reflect.compare);
		o.writeInt32(fs.length);
		for (f in fs) {
			str(o, f);
			o.writeByte(x.mFeatures.get(f) ? 1 : 0);
		}
		return o.getBytes();
	}

	public static function readExtra(b:Bytes):ModuleDefExtra {
		var i = new BytesInput(b);
		var file = rstr(i);
		var sign = rstr(i);
		var time = i.readDouble();
		var kind = moduleKinds[i.readByte()];
		// (processed in an earlier compilation: below every compilation step)
		var processed = i.readByte() == 1 ? -1 : 0;
		var policy = [for (_ in 0...i.readByte()) policies[i.readByte()]];
		var x = core.TFunctions.moduleExtra(file, sign, time, kind, 0, policy);
		x.mProcessed = processed;
		for (_ in 0...i.readInt32()) {
			var id = i.readInt32();
			var dsign = rstr(i);
			var dkind = moduleKinds[i.readByte()];
			var dpath = rpath(i);
			var origin = origins[i.readByte()];
			x.mDeps.set(id, ({mdSign: dsign, mdKind: dkind, mdPath: dpath, mdOrigin: origin} : ModuleDep));
		}
		for (_ in 0...i.readInt32())
			switch i.readByte() {
				case 0:
					var name = rstr(i);
					var data = i.read(i.readInt32());
					x.mCacheBoundObjects.push(Resource(name, data));
				case 1:
					var f = rstr(i);
					x.mCacheBoundObjects.push(IncludeFile(f, rstr(i)));
				case _:
					var msg = rstr(i);
					var pfile = rstr(i);
					var pmin = i.readInt32();
					var pmax = i.readInt32();
					var depth = i.readInt32();
					var fromMacro = i.readByte() == 1;
					var kind = switch i.readByte() {
						case 0: MKError;
						case 2: MKInfo;
						case _:
							var w:core.Message.WarningCode = rstr(i);
							var options = [
								for (_ in 0...i.readInt32()) [
									for (_ in 0...i.readInt32()) {
										var ww:core.Message.WarningCode = rstr(i);
										({woWarning: ww, woMode: i.readByte() == 0 ? WMEnable : WMDisable} : core.Message.WarningOption);
									}
								]
							];
							MKWarning(w, options);
					}
					var dk = diagnosticsKinds[i.readByte()];
					x.mCacheBoundObjects.push(Message(({
						cmMessage: msg,
						cmPos: {pfile: pfile, pmin: pmin, pmax: pmax},
						cmDepth: depth,
						cmFromMacro: fromMacro,
						cmMessageKind: kind,
						cmDiagnosticsKind: dk,
						cmJson: rjson(i)
					} : core.Message.CompilerMessage)));
			}
		for (_ in 0...i.readInt32()) {
			var f = rstr(i);
			x.mFeatures.set(f, i.readByte() == 1);
		}
		return x;
	}

	static function extraDeps(b:Bytes):{mtime:Float, processed:Int, deps:Array<String>} {
		var x = readExtra(b);
		return {mtime: x.mTime, processed: x.mProcessed, deps: [for (d in x.mDeps) depKey(d.mdSign, d.mdPath)]};
	}

	public static function write(sign:String, midHigh:Int, varHigh:Int, list:Array<CapturedModule>, keep:Array<StoredModule>, old:Null<ModulePack>):Bytes {
		var o = new BytesOutput();
		str(o, ModuleCache.MAGIC);
		str(o, sign);
		o.writeInt32(midHigh);
		o.writeInt32(varHigh);
		var files = new Map<String, StoredFile>();
		for (c in list)
			if (c.file != null) files.set(c.file, c.rec);
		if (old != null)
			for (e in keep) {
				var f = readExtra(e.extra);
				var file = core.Path.UniqueKey.lazyPath(f.mFile);
				if (!files.exists(file) && old.files.exists(file)) files.set(file, old.files.get(file));
			}
		var names = [for (k in files.keys()) k];
		names.sort(Reflect.compare);
		o.writeInt32(names.length);
		for (n in names) {
			var f = files.get(n);
			str(o, n);
			o.writeDouble(f.mtime);
			o.writeDouble(f.size);
			str(o, f.hash);
		}
		o.writeInt32(list.length + keep.length);
		function module(p:GlobalTypePath, id:Int, extra:Bytes, chunks:CachedChunks, monos:Bytes, skeletons:Bytes) {
			path(o, p);
			o.writeInt32(id);
			o.writeInt32(extra.length);
			o.write(extra);
			o.writeInt32(chunks.length);
			for (c in chunks) {
				o.writeByte(c.kind.getIndex());
				o.writeInt32(c.data.length);
				o.write(c.data);
			}
			o.writeInt32(monos.length);
			o.write(monos);
			o.writeInt32(skeletons.length);
			o.write(skeletons);
		}
		for (c in list)
			module(c.path, c.id, c.extra, c.chunks, c.monos, c.skeletons);
		for (e in keep)
			module(e.path, e.id, e.extra, e.chunks, e.monos, e.skeletons);
		return o.getBytes();
	}

	public static function read(file:String):Null<ModulePack> {
		var b = File.getBytes(file);
		var i = new BytesInput(b);
		if (rstr(i) != ModuleCache.MAGIC) return null;
		var p = new ModulePack();
		p.sign = rstr(i);
		p.moduleHigh = i.readInt32();
		p.varHigh = i.readInt32();
		for (_ in 0...i.readInt32()) {
			var n = rstr(i);
			var mtime = i.readDouble();
			var size = i.readDouble();
			p.files.set(n, {mtime: mtime, size: size, hash: rstr(i)});
		}
		for (_ in 0...i.readInt32()) {
			var mp = rpath(i);
			var id = i.readInt32();
			var extra = i.read(i.readInt32());
			var chunks:CachedChunks = [];
			for (_ in 0...i.readInt32()) {
				var kind = chunkKinds[i.readByte()];
				chunks.push({kind: kind, data: i.read(i.readInt32())});
			}
			var monos = i.read(i.readInt32());
			var skeletons = i.read(i.readInt32());
			var x = extraDeps(extra);
			p.modules.set(mp.pack.join("/") + "|" + mp.name, {
				path: mp,
				id: id,
				mtime: x.mtime,
				processed: x.processed,
				extra: extra,
				chunks: chunks,
				monos: monos,
				skeletons: skeletons,
				deps: x.deps
			});
		}
		return p;
	}
}

// the compiler's callbacks, telling when a macro registers one before
// typing is done (while a module is typed: a module restored later would not
// register it)
class WatchedCallbacks extends CompilerCallbacks {
	final com:CommonContext;
	final onEarly:String->Void;

	public function new(old:CompilerCallbacks, com:CommonContext, onEarly:String->Void) {
		super();
		this.com = com;
		this.onEarly = onEarly;
		@:privateAccess {
			beforeTyperCreate = old.beforeTyperCreate;
			afterInitMacros = old.afterInitMacros;
			afterTyping = old.afterTyping;
			beforeSave = old.beforeSave;
			afterSave = old.afterSave;
			afterFilters = old.afterFilters;
			afterGeneration = old.afterGeneration;
			nullSafetyReport = old.nullSafetyReport;
		}
	}

	function early(what:String)
		if (com.stage.getIndex() < CTypingDone.getIndex() && fromMacroApi()) onEarly(what);

	static var apiNames:Null<Array<Int>> = null;

	// whether Eval is running haxe.macro.Context's onGenerate, onAfterTyping
	// or onAfterGenerate (the compiler registers callbacks of its own while
	// typing, also in a macro: a forced inline call's check)
	static function fromMacroApi():Bool {
		var env = try macros.eval.EvalContext.getEval(null).env catch (_:Dynamic) null;
		if (env == null) return false;
		if (apiNames == null) {
			var h = macros.eval.EvalHash.hash;
			apiNames = [h("haxe.macro.Context"), h("onGenerate"), h("onAfterTyping"), h("onAfterGenerate")];
		}
		while (env != null) {
			switch env.envInfo.kind {
				case EKMethod(t, f) if (t == apiNames[0] && (f == apiNames[1] || f == apiNames[2] || f == apiNames[3])):
					return true;
				case _:
			}
			env = env.envParent;
		}
		return false;
	}

	override public function addAfterTyping(f:Array<ModuleType>->Void) {
		early("onAfterTyping");
		super.addAfterTyping(f);
	}

	override public function addBeforeSave(f:Void->Void) {
		early("onGenerate");
		super.addBeforeSave(f);
	}

	override public function addAfterSave(f:Void->Void) {
		early("onGenerate");
		super.addAfterSave(f);
	}

	override public function addAfterFilters(f:Void->Void) {
		early("afterFilters");
		super.addAfterFilters(f);
	}

	override public function addAfterGeneration(f:Void->Void) {
		early("onAfterGenerate");
		super.addAfterGeneration(f);
	}

	override public function addNullSafetyReport(f:NullSafetyReportCallback) {
		early("nullSafetyReport");
		super.addNullSafetyReport(f);
	}
}

// the server's HXB writer, keeping what HXB does not of the module's unbound
// monomorphs: their modifiers (a Null<Unknown> read back would be a plain
// monomorph, and the program after it could differ). Per monomorph with
// modifiers: its index in the module's table, then the modifiers (0
// MNullable, 1 MOpenStructure, 2 MDynamic).
class CheckingHxbWriter extends compiler.hxb.HxbWriter {
	public function monoModifiers():Bytes {
		var o = new BytesOutput();
		var items = @:privateAccess tmonos.toList();
		var n = 0;
		for (it in items)
			if (it.key.tmModifiers.length > 0) n++;
		o.writeInt32(n);
		for (i in 0...items.length) {
			var mods = items[i].key.tmModifiers;
			if (mods.length == 0) continue;
			o.writeInt32(i);
			o.writeByte(mods.length);
			for (m in mods)
				o.writeByte(switch m {
					case MNullable(_): 0;
					case MOpenStructure: 1;
					case MDynamic: 2;
				});
		}
		return o.getBytes();
	}

	// the modifiers back on the monomorphs a reader made (after it read the module)
	public static function restore(com:CommonContext, reader:compiler.hxb.HxbReader, b:Bytes) {
		var i = new BytesInput(b);
		var monos:Array<T> = @:privateAccess reader.tmonos;
		for (_ in 0...i.readInt32()) {
			var index = i.readInt32();
			var mods = [
				for (_ in 0...i.readByte()) switch i.readByte() {
					case 0: MNullable(com.basic.tnull);
					case 1: MOpenStructure;
					case _: MDynamic;
				}
			];
			switch index < monos.length ? monos[index] : null {
				case TMono(r):
					r.tmModifiers = mods;
				case _:
			}
		}
	}
}

// What the sort of the types (Finalization.sortTypes) walks of a class's
// fields, kept per module: a module restored from the store has its
// expressions as the filters left them, and the sort must walk what it saw
// when the module was typed (the order of the types, and so the program's
// type numbering, follows it). Per expression (a class's init, a static
// field, the constructor), the walk's events in order: a type expression
// (0, its kind, module and name), a construction (1, the class), a static
// field (2, the class and field). Played back as a block of those
// expressions, the walk does the same.
class Skeletons {
	static function moduleKey(sign:String, p:GlobalTypePath):String
		return sign + "\x00" + ModuleCache.key(p);

	static function restoredEntry(s:ModuleCacheState, m:ModuleDef):Null<StoredModule> {
		var p = s.packs.get(m.mExtra.mSign);
		var e = p == null ? null : p.modules.get(ModuleCache.key(m.mPath));
		return e != null && e.id == m.mId ? e : null;
	}

	static function typeRef(o:BytesOutput, m:ModuleDef, name:String) {
		ModulePack.path(o, m.mPath);
		ModulePack.str(o, name);
	}

	static function record(e:TExpr):Bytes {
		var o = new BytesOutput();
		function rec(e:TExpr)
			switch e.eexpr {
				case TTypeExpr(t):
					o.writeByte(0);
					o.writeByte(switch t {
						case TClassDecl(_): 0;
						case TEnumDecl(_): 1;
						case TAbstractDecl(_): 2;
						case TTypeDecl(_): 3;
					});
					var i = core.TFunctions.tInfos(t);
					typeRef(o, i.mtModule, i.mtPath.name);
				case TNew(c, _, _):
					core.Texpr.iter(rec, e);
					o.writeByte(1);
					typeRef(o, c.clModule, c.clPath.name);
				case TField(e1, FStatic(c, cf)):
					rec(e1);
					o.writeByte(2);
					typeRef(o, c.clModule, c.clPath.name);
					ModulePack.str(o, cf.cfName);
				case _:
					core.Texpr.iter(rec, e);
			}
		rec(e);
		return o.getBytes();
	}

	static function computeClass(s:ModuleCacheState, c:TClass) {
		var mk = moduleKey(c.clModule.mExtra.mSign, c.clModule.mPath);
		var ck = mk + "\x00" + c.clPath.name;
		if (s.walked.exists(ck)) return;
		s.walked.set(ck, true);
		var map = s.skeletons.get(mk);
		if (map == null) s.skeletons.set(mk, map = new Map());
		var init = core.TOther.TClassTools.getClInit(c);
		if (init != null) map.set(c.clPath.name + "\x00", record(init));
		for (cf in c.clStatics)
			if (cf.cfExpr != null) map.set(c.clPath.name + "\x00" + cf.cfName, record(cf.cfExpr));
		if (c.clConstructor != null && c.clConstructor.cfExpr != null) map.set(c.clPath.name + "\x00new", record(c.clConstructor.cfExpr));
	}

	// the classes of the modules this build typed (not restored)
	public static function computeAll(com:CommonContext) {
		var s = ModuleCache.current();
		if (s == null) return;
		var key = "com:" + context.CommonCache.getCacheSign(com);
		if (s.walked.exists(key)) return;
		s.walked.set(key, true);
		com.moduleLut.iter(function(_, m) {
			if (restoredEntry(s, m) != null) return;
			for (t in m.mTypes)
				switch t {
					case TClassDecl(c): computeClass(s, c);
					case _:
				}
		});
	}

	// Finalization.sortExprHook
	public static function sortExpr(c:TClass, cf:Null<TClassField>, e:TExpr):TExpr {
		var s = ModuleCache.current();
		if (s == null) return e;
		var com = ModuleCache.comFor(s.com, c.clModule.mExtra.mSign);
		if (com != null) computeAll(com);
		var entry = restoredEntry(s, c.clModule);
		if (entry == null) return e;
		if (entry.skeletonMap == null) entry.skeletonMap = decode(entry.skeletons);
		var b = entry.skeletonMap.get(c.clPath.name + "\x00" + (cf == null ? "" : cf == c.clConstructor ? "new" : cf.cfName));
		var r = b == null || com == null ? null : play(com, b);
		if (r == null) {
			if (s.log) Sys.println("hxmc: module cache: no walk kept for " + core.Globals.sTypePath(c.clPath) + "." + (cf == null ? "__init__" : cf.cfName));
			return e;
		}
		return r;
	}

	static function findType(com:CommonContext, i:BytesInput):Null<ModuleType> {
		var mp = ModulePack.rpath(i);
		var name = ModulePack.rstr(i);
		var m = com.moduleLut.findOpt(mp);
		if (m == null) return null;
		for (t in m.mTypes)
			if (core.TFunctions.tInfos(t).mtPath.name == name) return t;
		return null;
	}

	static function play(com:CommonContext, b:Bytes):Null<TExpr> {
		var i = new BytesInput(b);
		var nodes:Array<TExpr> = [];
		var p = core.Globals.nullPos;
		var t = core.TFunctions.tDynamic;
		inline function mk(d:TExprDef):TExpr
			return core.TFunctions.mk(d, t, p);
		while (i.position < b.length)
			switch i.readByte() {
				case 0:
					i.readByte();
					var mt = findType(com, i);
					if (mt == null) return null;
					nodes.push(mk(TTypeExpr(mt)));
				case 1:
					switch findType(com, i) {
						case TClassDecl(c): nodes.push(mk(TNew(c, [], [])));
						case _: return null;
					}
				case _:
					var mt = findType(com, i);
					var f = ModulePack.rstr(i);
					switch mt {
						case TClassDecl(c) if (c.clStatics.exists(f)):
							nodes.push(mk(TField(mk(TConst(TNull)), FStatic(c, c.clStatics.get(f)))));
						case _:
							return null;
					}
			}
		return mk(TBlock(nodes));
	}

	public static function encode(s:ModuleCacheState, sign:String, p:GlobalTypePath):Bytes {
		var map = s.skeletons.get(moduleKey(sign, p));
		var o = new BytesOutput();
		var keys = map == null ? [] : [for (k in map.keys()) k];
		keys.sort(Reflect.compare);
		o.writeInt32(keys.length);
		for (k in keys) {
			ModulePack.str(o, k);
			var b = map.get(k);
			o.writeInt32(b.length);
			o.write(b);
		}
		return o.getBytes();
	}

	static function decode(b:Bytes):Map<String, Bytes> {
		var i = new BytesInput(b);
		var m = new Map<String, Bytes>();
		for (_ in 0...i.readInt32()) {
			var k = ModulePack.rstr(i);
			m.set(k, i.read(i.readInt32()));
		}
		return m;
	}
}
