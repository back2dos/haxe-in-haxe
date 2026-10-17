package hxmc;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import sys.FileSystem;
import sys.io.File;
import core.Globals.GlobalTypePath;
import core.TType;
import compiler.hxb.HxbData;
import compiler.server.ServerCache;
import context.Common;
import core.Message.CompilerMessageKind;
import core.Message.WarningMode;
import hxmc.ModuleStore;

// The compilation server's module cache made durable (docs/plans/compiler.md, "Cached
// modules"): a build writes the typed modules it ends with, as the server
// keeps them in its HXB mode (each module's HXB chunks, its dependencies,
// kind, file and check policy), into a store in the user's cache directory
// (ModuleStore.hx); the next build puts them back in the server's cache
// before typing, and the server's checks decide, module by module and only
// for the modules the build loads, which are still good; the HXB is read
// and decoded on demand.
//
// Defines: a module is kept with the defines it read (its file's conditions,
// its macros' Context.defined and getDefines) and those the compiler read
// in the build that typed it (Define.readHook: the typer's and filters'
// options, the target's); a build restores the variant whose reads have its
// values, so a define only some modules read leaves the others (the std)
// good, in a store shared by every signature. The macros' context, when it
// does not exist yet, gets the defines it will have (predicted as
// MacroContext does it, checked when it is created).
//
// Validity (ServerCache.checkModuleHook, check below): the module's file
// (a content hash where the date or size differ: a fresh checkout changes
// every date; a date within RACY seconds of the parse is not trusted), the
// file its path resolves to now (a module shadowed by a new file earlier in
// the class path is typed again), its defines, and its dependencies by hash:
// each dependency's interface (ModuleInterface: its declarations without
// the bodies its users cannot see, and its own dependencies' interfaces,
// per strongly connected component) as it was when the module was typed, or
// its whole content (its source and everything it depends on) for a macro's
// module and modules typed with macros. A dependency typed again whose
// interface did not change leaves its dependents good (early cutoff:
// ServerCache.dependencyDirtyHook; it is typed from its source where the
// server expects it cached, loadDirtyModuleHook).
//
// A build from the cache writes the same output as one without it
// (hxmc/test/ModuleCacheCheck.hx), which takes two things the server's HXB
// cache does not keep: the modifiers of unbound monomorphs (Null<Unknown>:
// CheckingHxbWriter, given back to the reader's monomorphs through
// ServerCache.readerCreatedHook) and what the sort of the types walks of a
// restored module, whose expressions are the filtered ones (Skeletons,
// through Finalization.sortExprHook).
//
// On by default; HXMC_MODULE_CACHE=0 or -D hxmc.no-module-cache turns it
// off (HXMC_MODULE_CACHE=0 also when -D hxmc.module-cache is given).
// Through `haxe` (HaxeMain) and the tool alike, for every target. Not used
// (the build types everything from source): display requests, the
// compilation server and its clients (already in memory), builds of several
// parts (--next, --each), init macros (--macro: their effects are not in the
// key yet), deprecated defines, HXB libraries or output, native libraries,
// WASI. A build in which a macro registers a callback (Context.onGenerate,
// onAfterTyping, onAfterGenerate) or defines something while typing writes
// nothing: a module restored later would not do it again. HXMC_STATS=1
// prints what the cache did, HXMC_MODULE_CACHE_LOG=1 each module checked
// and each one not kept.
//
// A build rewrites its key's index when it typed modules or restored other
// variants: its modules first, then the variants it did not use, at most
// MAX_VARIANTS per module. Module and variable ids continue from the
// store's (the server keeps the ids of the modules and variables it
// restores). The tool directories, the indexes and the blobs no index names
// are trimmed by last use and size (CacheDir.trim).
class ModuleCache {
	static inline var ID_LIMIT = 1 << 30;
	static inline var MAX_VARIANTS = 4;
	static final noMonos = {
		var o = new BytesOutput();
		o.writeInt32(0);
		o.getBytes();
	}

	static var state:Null<ModuleCacheState> = null;
	static var hookCalls = 0;
	static var parseHookInstalled = false;
	static var start = haxe.Timer.stamp();
	static final mutex = new sys.thread.Mutex();
	static var mainThread:Null<sys.thread.Thread> = null;
	// the defines read before the cache opened, per defines context
	static var early:Array<{ctx:core.Define.DefineContext, keys:Map<String, Bool>}> = [];
	// each context's typer (to type a module from its source)
	static var typers:Array<{com:CommonContext, g:context.Typecore.TyperGlobals}> = [];

	public static function current():Null<ModuleCacheState>
		return state;

	public static function install() {
		compiler.Compiler.beforeTypingHook = hook;
		if (Sys.systemName() == "Wasi") return;
		mainThread = sys.thread.Thread.current();
		core.Define.readHook = onRead;
		Common.externalDefinesHook = onExternal;
		typing.TyperEntry.createdHook = onTyper;
		ServerCache.dependencyDirtyHook = onDependencyDirty;
		ServerCache.loadDirtyModuleHook = loadDirty;
		typing.TypeloadModule.typeFromSourceHook = onTypeFromSource;
		core.TUnification.maybeUsedHook = onMaybeUsed;
		// (a lazy typing continues the typing of the module that made it)
		Common.lazyHook = function(f:Void->T):Void->T {
			var s = state;
			if (s == null || s.typingStack.length == 0) return f;
			var maker = s.typingStack[s.typingStack.length - 1];
			return function() {
				if (state != s) return f();
				s.typingStack.push(maker);
				var r = try f() catch (x:Dynamic) {
					s.typingStack.pop();
					throw x;
				}
				s.typingStack.pop();
				return r;
			};
		};
		// (a delayed task continues the typing of the module that delayed it)
		context.Typecore.delayHook = function(f:Void->Void):Void->Void {
			var s = state;
			if (s == null || s.typingStack.length == 0) return f;
			var maker = s.typingStack[s.typingStack.length - 1];
			return function() {
				var s2 = state;
				if (s2 != s) {
					f();
					return;
				}
				s.typingStack.push(maker);
				try f() catch (x:Dynamic) {
					s.typingStack.pop();
					throw x;
				}
				s.typingStack.pop();
			};
		};
		wrapTypeExpr();
	}

	// Typecore.typeExprRef, wrapped to know the module whose code is being
	// typed (the maker of the structural marks); again after each typer's
	// creation, which sets the reference anew (Typer.initialize)
	static var typeExprWrapper:Null<Dynamic> = null;

	static function wrapTypeExpr() {
		if (typeExprWrapper != null && Reflect.compareMethods(context.Typecore.typeExprRef, typeExprWrapper)) return;
		var typeExpr = context.Typecore.typeExprRef;
		var w = function(ctx:context.Typecore.Typer, e:core.Ast.Expr, withType:core.WithType.WithTypeValue, ?mode:context.Typecore.AccessMode):TExpr {
			var s = state;
			if (s == null) return typeExpr(ctx, e, withType, mode);
			s.typingStack.push(ctx.m.curmod);
			var r = try typeExpr(ctx, e, withType, mode) catch (x:Dynamic) {
				s.typingStack.pop();
				throw x;
			}
			s.typingStack.pop();
			return r;
		}
		typeExprWrapper = w;
		context.Typecore.typeExprRef = w;
	}

	// TUnification.maybeUsedHook: a class field marked as maybe used through
	// a structure (CfMaybeUsed, which DCE reads), and its accessors, by the
	// module being typed
	static function onMaybeUsed(cl:Null<TClass>, f1:TClassField, f2:Null<TClassField>) {
		var s = state;
		if (s == null) return;
		var maker = s.typingStack.length > 0 ? s.typingStack[s.typingStack.length - 1] : null;
		mutex.acquire();
		s.liveMarks.push({maker: maker, cf: f1});
		if (cl != null && f2 != null)
			switch f2.cfKind {
				case Var(v):
					var names = [];
					switch v.vRead {
						case AccCall | AccPrivateCall: names.push("get_" + f1.cfName);
						case _:
					}
					switch v.vWrite {
						case AccCall | AccPrivateCall: names.push("set_" + f1.cfName);
						case _:
					}
					for (n in names) {
						var f = try core.TFunctions.rawClassField(cf -> cf.cfType, cl, [for (_ in cl.clParams) core.TFunctions.tDynamic], n).field catch (_:Dynamic) null;
						if (f != null) s.liveMarks.push({maker: maker, cf: f});
					}
				case _:
			}
		mutex.release();
	}

	// the build's structural marks made exact (before DCE reads them): a
	// restored module's fields lose the marks its HXB kept (its users' typing
	// in an earlier build) and get those of this build's users: the ones
	// typed now marked them again, the restored ones replay theirs
	static function fixMarks(s:ModuleCacheState, coms:Array<CommonContext>) {
		var refs = new haxe.ds.ObjectMap<TClassField, String>();
		var byRef = new Map<String, TClassField>();
		var restored = [];
		for (role in 0...coms.length)
			for (m in coms[role].modules) {
				var r = s.restored(m) != null;
				if (r) restored.push(m);
				for (t in m.mTypes)
					switch t {
						case TClassDecl(c):
							var base = role + "|" + key(m.mPath) + "|" + c.clPath.name + "|";
							inline function add(cf:TClassField, k:String) {
								if (cf == null) return;
								refs.set(cf, base + k + cf.cfName);
								byRef.set(base + k + cf.cfName, cf);
								if (r) core.TFunctions.removeClassFieldFlag(cf, CfMaybeUsed);
							}
							add(c.clConstructor, "c|");
							for (cf in c.clOrderedFields)
								add(cf, "f|");
							for (cf in c.clOrderedStatics)
								add(cf, "s|");
						case _:
					}
			}
		var unattributed = 0;
		for (lm in s.liveMarks) {
			core.TFunctions.addClassFieldFlag(lm.cf, CfMaybeUsed);
			var ref = refs.get(lm.cf);
			if (ref == null) continue;
			var maker:Null<ModuleDef> = lm.maker == null ? null : Std.isOfType(lm.maker, core.TType.ModuleDef) ? lm.maker : {
				var x:{com:CommonContext, path:GlobalTypePath} = lm.maker;
				x.com.moduleLut.findOpt(x.path);
			};
			if (maker == null) {
				if (s.log) Sys.println("hxmc: module cache: a structural mark on " + ref + " outside the typing of a module");
				unattributed++;
				continue;
			}
			var l = s.madeMarks.get(maker);
			if (l == null) s.madeMarks.set(maker, l = []);
			if (l.indexOf(ref) < 0) l.push(ref);
		}
		for (m in restored)
			for (ref in s.restored(m).marks) {
				var cf = byRef.get(ref);
				if (cf != null) core.TFunctions.addClassFieldFlag(cf, CfMaybeUsed);
			}
		for (l in s.madeMarks)
			l.sort(Reflect.compare);
		s.unattributedMarks = unattributed;
		if (unattributed > 0 && s.log) Sys.println("hxmc: module cache: " + unattributed + " structural marks made outside the typing of a module");
	}

	// TypeloadModule.typeFromSourceHook: while a module of the store is typed
	// from its source, the restored modules of its cycle it loads are typed
	// from theirs too (decoded then, they would refer to its types before they
	// are ready); the others of its cycle stay restored
	static function onTypeFromSource(com:CommonContext, path:GlobalTypePath, start:Bool) {
		var s = state;
		if (s == null) return;
		if (!start) {
			s.creating.pop();
			s.typingStack.pop();
			return;
		}
		// (a module being typed from its source: its ModuleDef found later)
		s.typingStack.push({com: com, path: path});
		var v = s.variantOf(context.CommonCache.getCacheSign(com), path);
		s.creating.push(v == null ? -1 : s.sccOf(v));
	}

	static function wanted(com:CommonContext):Bool {
		var env = Sys.getEnv("HXMC_MODULE_CACHE");
		return env != "0" && CacheDir.define(com, "hxmc.no-module-cache") == null;
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
		for (k in com.defines.values.keys())
			if (core.Define.deprecationLut.exists(k)) return "deprecated define " + k;
		return null;
	}

	static function hook(com:CommonContext, actx:compiler.ParsedArg.ArgContext) {
		hookCalls++;
		state = null;
		ServerCache.checkModuleHook = null;
		typing.Finalization.sortExprHook = null;
		var why = wanted(com) ? unusable(com, actx) : "off";
		var s = why == null ? open(com) : null;
		early = [];
		if (s == null) {
			if (why == null) why = "no cache directory";
			if (why != "off" && stats()) Sys.println('hxmc: module cache not used ($why)');
			return;
		}
		state = s;
		ServerCache.checkModuleHook = check;
		typing.Finalization.sortExprHook = Skeletons.sortExpr;
		// (what the sort of the types walks, of every class typed: before the
		// filters change it)
		com.callbacks.addAfterTyping(_ -> Skeletons.computeAll(com));
		if (!parseHookInstalled) {
			parseHookInstalled = true;
			// (the blob of a restored module and the modifiers of its
			// monomorphs, once the server has read it)
			ServerCache.readerCreatedHook = function(com, path, reader) {
				var s = state;
				if (s == null) return;
				var v = s.variantOf(context.CommonCache.getCacheSign(com), path);
				if (v == null || !s.load(v)) return;
				if (v.monos.length > 4) s.readers.push({com: com, reader: reader, monos: v.monos});
			}
			var typeModule = typing.TypeloadCacheHook.typeModuleHook;
			typing.TypeloadCacheHook.typeModuleHook = function(com, delay, path, p) {
				var s = state;
				if (s != null && s.creating.length > 0) s.cycleGuard(com, path);
				var r = typeModule(com, delay, path, p);
				var s = state;
				if (s != null) s.restoreMonos();
				return r;
			}
			var inner = typing.TypeloadParse.parseHook;
			typing.TypeloadParse.parseHook = function(com, rfile, p) {
				var s = state;
				if (s == null) return inner(com, rfile, p);
				var file = core.Path.getFullPath(rfile.file);
				s.note(file);
				var pk = (com.isMacroContext ? 1 : 0) + "\x00" + file;
				var main = sys.thread.Thread.current() == mainThread;
				var prev = s.parsing;
				if (main) s.parsing = pk;
				var r = try inner(com, rfile, p) catch (e:Dynamic) {
					if (main) s.parsing = prev;
					throw e;
				}
				if (main) s.parsing = prev;
				// (its interface hashed when needed: the build's in parallel when it
				// writes the store)
				if (!s.decls.exists(pk)) {
					mutex.acquire();
					s.decls.set(pk, switch r {
						case ParseSuccess(data, _): data.declarations;
						case _: null;
					});
					mutex.release();
				}
				return r;
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

	// Define.readHook: a define read (by the compiler, or by a macro through
	// Common.externalDefinesHook first)
	static function onRead(ctx:core.Define.DefineContext, key:String) {
		var s = state;
		if (s == null) {
			if (hookCalls > 0) return;
			mutex.acquire();
			var e = null;
			for (x in early)
				if (x.ctx == ctx) e = x;
			if (e == null) early.push(e = {ctx: ctx, keys: new Map()});
			e.keys.set(key, true);
			mutex.release();
			return;
		}
		s.read(ctx, key);
	}

	// Common.externalDefinesHook: a macro reads (a null key: all) or writes a define
	static function onExternal(com:CommonContext, name:Null<String>, write:Bool) {
		var s = state;
		if (s == null) return;
		if (write) {
			if (!s.captured && s.volatileReason == null) s.volatileReason = "a macro defines " + name;
			return;
		}
		var m = try macros.eval.EvalContext.getCtx().curapi.currentModule() catch (_:Dynamic) null;
		if (m == null) return;
		var role = s.roleOfSign(m.mExtra.mSign);
		if (role < 0) return;
		var role0 = com == s.com ? 0 : 1;
		mutex.acquire();
		var rk = role + "|" + key(m.mPath);
		var l = s.moduleReads.get(rk);
		if (l == null) s.moduleReads.set(rk, l = new Map());
		l.set(role0 + "\x00" + (name == null ? "*" : name), true);
		s.skipKey = name;
		mutex.release();
	}

	// TyperEntry.createdHook (before the typer loads anything): the
	// program's typer, then the macros' context's modules (the context its
	// macros run in, or the one it will create, with the defines the program
	// has now)
	static function onTyper(ctx:context.Typecore.Typer) {
		typers.push({com: ctx.com, g: ctx.g});
		wrapTypeExpr();
		var s = state;
		if (s == null) return;
		if (ctx.com == s.com && s.macroPending) {
			s.macroPending = false;
			var macros = ctx.g.macros;
			if (macros != null) {
				s.signs[1] = context.CommonCache.getCacheSign(macros.typer.com);
				s.defs[1] = macros.typer.com.defines.values;
			} else {
				var p = try predictMacroDefines(s.com) catch (_:Dynamic) null;
				if (p != null) {
					s.signs[1] = p.sign;
					s.defs[1] = p.values;
				}
			}
			var t0 = haxe.Timer.stamp();
			s.loaded = s.register(0);
			if (s.signs[1] != null) s.loaded += s.register(1);
			if (stats())
				Sys.println('hxmc: module cache: ${s.loaded} modules of ${s.index.variants.length} variants read (${Std.int((s.openTime + haxe.Timer.stamp() - t0) * 1000)} ms)');
			return;
		}
		if (ctx.com.isMacroContext && ctx.com == s.com.getMacros() && !s.macroPending) {
			var sign = context.CommonCache.getCacheSign(ctx.com);
			if (sign != s.signs[1]) {
				if (s.volatileReason == null) s.volatileReason = "the macros' context has other defines than predicted";
				if (stats()) Sys.println("hxmc: module cache: the macros' context's signature " + sign + " is not the predicted " + s.signs[1]);
				if (s.log) {
					var a = ctx.com.defines.values, p = s.defs[1];
					for (k in a.keys())
						if (p == null || p.get(k) != a.get(k)) Sys.println("hxmc: module cache:   " + k + "=" + a.get(k) + " predicted " + (p == null ? null : p.get(k)));
					if (p != null)
						for (k in p.keys())
							if (!a.exists(k)) Sys.println("hxmc: module cache:   " + k + " predicted " + p.get(k) + ", absent");
				}
			}
		}
	}

	static function typerOf(com:CommonContext):Null<context.Typecore.TyperGlobals> {
		var i = typers.length;
		while (i-- > 0)
			if (typers[i].com == com) return typers[i].g;
		return null;
	}

	// ServerCache.loadDirtyModuleHook: a module typed again under one restored
	static function loadDirty(com:CommonContext, path:GlobalTypePath, p:core.Globals.Pos):Null<ModuleDef> {
		var s = state;
		if (s == null) return null;
		var g = typerOf(com);
		if (g == null) return null;
		s.typedUnder++;
		if (s.log) Sys.println("hxmc: module cache: " + core.Globals.sTypePath(path) + " typed again under a restored module");
		return typing.TypeloadModule.loadModulePrime(com, g, path, p);
	}

	// ServerCache.dependencyDirtyHook: a module checked good by its
	// dependencies' hashes stays good
	static function onDependencyDirty(com:CommonContext, mPath:GlobalTypePath, mExtra:ModuleDefExtra, dep:ModuleDep, reason:ModuleSkipReason):Bool {
		var s = state;
		if (s == null) return false;
		var role = s.roleOfSign(mExtra.mSign);
		return role >= 0 && s.approved.exists(role + "|" + key(mPath));
	}

	// the macros' context's defines, as MacroContext.createMacroContext
	// makes them
	static function predictMacroDefines(com:CommonContext):{sign:String, values:haxe.ds.StringMap<String>} {
		var c = Common.clone(com, true);
		var d = Common.adaptDefinesToMacroContext(c.defines);
		c.defines.values = d.values;
		c.defines.definesSignature = null;
		c.platform = core.Globals.Platform.Eval;
		Common.initPlatform(c);
		return {sign: core.Define.getSignature(c.defines), values: c.defines.values};
	}

	// the store for this build: its index read, the variants that match put
	// in the server's cache
	static function open(com:CommonContext):Null<ModuleCacheState> {
		var root = CacheDir.root();
		if (root == null) return null;
		var t0 = haxe.Timer.stamp();
		var modules = root + "modules/";
		var dir = modules + CacheDir.toolStamp() + "/";
		var used = dir + "used";
		if (!FileSystem.exists(used) || CacheDir.now() - CacheDir.mtime(used) > CacheDir.USED_REFRESH)
			if (!CacheDir.touch(used)) return null;
		CacheDir.trim(modules, dir, d -> {
			ModuleStore.sweep(d);
			ObjectStore.sweep(d);
		});
		var key = Fingerprint.hash(["hxmc-modules", Sys.getCwd(), Sys.getEnv("HAXE_STD_PATH"), com.classPaths.asStringList().join("\n")].join("\x00"));
		var s = new ModuleCacheState(dir, dir + key + ".idx", com);
		s.signs[0] = context.CommonCache.getCacheSign(com);
		s.defs[0] = com.defines.values;
		var mcom = com.getMacros();
		// the defines read so far
		for (e in early) {
			var role = e.ctx == com.defines ? 0 : mcom != null && e.ctx == mcom.defines ? 1 : -1;
			if (role >= 0)
				for (k in e.keys.keys())
					s.global.set(role + "\x00" + k, true);
		}
		var ix = try ModuleStore.readIndex(s.indexPath) catch (e:Dynamic) {
			if (stats()) Sys.println('hxmc: module cache: ${s.indexPath} unreadable ($e)');
			null;
		}
		if (ix != null) {
			// (ids only grow from build to build: far from the 32-bit limit the
			// store starts again from nothing)
			if (ix.moduleHigh > ID_LIMIT || ix.varHigh > ID_LIMIT) ix = null;
		}
		if (ix == null) ix = new StoreIndex();
		s.index = ix;
		if (ix.variants.length > 0) CacheDir.used(s.indexPath);
		@:privateAccess {
			if (core.TFunctions.moduleUid.load() < ix.moduleHigh) core.TFunctions.moduleUid.store(ix.moduleHigh);
			if (core.TFunctions.varUid.load() < ix.varHigh) core.TFunctions.varUid.store(ix.varHigh);
		}
		s.openTime = haxe.Timer.stamp() - t0;
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

	// the file a module's path resolves to in this com (null: none)
	public static function resolve(com:CommonContext, path:GlobalTypePath):Null<core.ClassPaths.ResolvedFile>
		return try typing.TypeloadParse.resolveModuleFile(com, path, {value: path.pack.copy()}, core.Globals.nullPos) catch (_:Dynamic) null;

	// whether the module's path resolves to its file in this com
	static function resolvesTo(com:CommonContext, path:GlobalTypePath, fileKey:String):Bool {
		var r = resolve(com, path);
		return r != null && com.partScope.fileKeys.get(core.Path.getFullPath(r.file)) == fileKey;
	}

	public static function size(file:String):Float
		return try FileSystem.stat(file).size catch (_:Dynamic) -1;

	// ServerCache.checkModuleHook: a module from the store, before the
	// server's checks
	static function check(com:CommonContext, mPath:GlobalTypePath, mExtra:ModuleDefExtra):Null<ModuleSkipReason> {
		var s = state;
		if (s == null) return null;
		var role = s.roleOfSign(mExtra.mSign);
		if (role < 0) return null;
		var v = s.chosen[role].get(key(mPath));
		if (v == null) return null;
		var t0 = haxe.Timer.stamp();
		var r = verify(com, s, v, mPath, mExtra);
		s.checked++;
		if (r == null) s.approved.set(v.roleKey(), true);
		if (s.log) Sys.println("hxmc: module cache: " + core.Globals.sTypePath(mPath) + (r == null ? " good" : " dirty: " + core.TPrinting.Printer.sModuleSkipReason(r)));
		s.checkTime += haxe.Timer.stamp() - t0;
		return r;
	}

	static function verify(com:CommonContext, s:ModuleCacheState, v:Variant, mPath:GlobalTypePath, mExtra:ModuleDefExtra):Null<ModuleSkipReason> {
		var file = core.Path.UniqueKey.lazyPath(mExtra.mFile);
		if (!v.matched) return FileChanged(file + " (defines)");
		// (a build macro's module: typed again every build, so that the macro
		// runs, also for what it keeps for other modules' macros)
		if (v.macroBuilt) return FileChanged(file + " (built by a macro)");
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
			if (!(mExtra.mKind == MFake && v.mtime == 0)) return FileChanged(file);
		} else {
			var f = v.fileRec;
			if (f == null) return FileChanged(file);
			if (!(f.mtime == time && f.size == size(file)) && s.fileHash(file) != f.hash) return FileChanged(file);
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
		// the dependencies as they were when it was typed: their interface,
		// or their whole content
		for (d in v.deps)
			if (s.depHash(d) != d.expect) return DependencyDirty(d.path, FileChanged(d.eligible ? "(interface)" : "(content)"));
		if (mExtra.mKind != MImport && !s.load(v)) return LibraryChanged;
		return null;
	}

	// after the state is saved (before DCE and generation change the typed
	// program): the modules of the build as the server would cache them
	static function capture(com:CommonContext) {
		var s = state;
		if (s == null) return;
		s.captured = true;
		{
			var mcom = com.getMacros();
			fixMarks(s, mcom != null && context.CommonCache.getCacheSign(mcom) == s.signs[1] ? [com, mcom] : [com]);
		}
		// (a mark the store could not give back to its maker)
		if (s.unattributedMarks > 0 && s.volatileReason == null) s.volatileReason = s.unattributedMarks + " structural marks made outside the typing of a module";
		if (s.volatileReason != null) return;
		if (Common.hasErrorToReport(com)) {
			s.volatileReason = "errors";
			return;
		}
		var t0 = haxe.Timer.stamp();
		// (and the macros' context's, when it is the one predicted: not a
		// context only an init macro used)
		var mcom = com.getMacros();
		var coms = [com];
		if (mcom != null && context.CommonCache.getCacheSign(mcom) == s.signs[1]) coms.push(mcom);
		// the defines the compiler read in this build, with their values
		var buildReads:Array<Read> = [];
		for (k in s.global.keys()) {
			var i = k.indexOf("\x00");
			var role = Std.parseInt(k.substr(0, i));
			var name = k.substr(i + 1);
			buildReads.push({role: role, name: name, value: s.value(role, name)});
		}
		buildReads.sort((a, b) -> Reflect.compare(a.role + a.name, b.role + b.name));
		var jobs:Array<{v:Variant, f:Void->{chunks:CachedChunks, monos:Bytes}}> = [];
		var all:Array<Variant> = [];
		var byKey = [new Map<String, Variant>(), new Map<String, Variant>()];
		for (role in 0...coms.length) {
			var c = coms[role];
			var config:compiler.hxb.HxbWriterConfig.WriterTargetConfig = switch c.hxbWriterConfig {
				case null: new compiler.hxb.HxbWriterConfig.WriterTargetConfig();
				case config: c.isMacroContext ? config.macroConfig : config.targetConfig;
			}
			function warn(w:core.Message.WarningCode, msg:String, p:core.Globals.Pos):Void c.warning(w, c.warningOptions, msg, p);
			var optimize = c.defines.values.exists(core.Define.AnalyzerOptimize);
			for (m in c.modules) {
				var x = m.mExtra;
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
					rec = s.parsed.get(core.Path.getFullPath(file));
					var old = s.restored(m);
					if (rec == null && old != null && old.fileRec != null && old.fileRec.mtime == time && old.fileRec.size == size(file))
						rec = old.fileRec;
					if (rec == null) rec = s.record(file);
					if (rec == null) {
						skip("unreadable");
						continue;
					}
				}
				var v = new Variant();
				v.role = role;
				v.path = m.mPath;
				v.key = key(m.mPath);
				v.id = m.mId;
				v.extra = ModuleStore.writeExtra(x);
				v.signs = s.signs.copy();
				v.kind = x.mKind;
				v.processed = x.mProcessed != 0 ? -1 : 0;
				v.mtime = x.mTime;
				v.file = file;
				v.fileRec = rec;
				v.matched = true;
				v.deps = [];
				var macroDefines = false;
				var ok = true;
				for (d in x.mDeps) {
					var r = s.signs.indexOf(d.mdSign);
					if (r < 0) {
						ok = false;
						break;
					}
					switch d.mdOrigin {
						case MDepFromMacroInclude | MDepFromMacroDefine: macroDefines = true;
						case _:
					}
					// (in the same context its interface stands for it, also for a
					// macro that looked at it; across contexts, a macro's module, its
					// whole content: its code runs)
					var eligible = r == role;
					v.deps.push({role: r, path: d.mdPath, key: key(d.mdPath), eligible: eligible, expect: ""});
				}
				if (!ok) {
					skip("a dependency of another context");
					continue;
				}
				v.deps.sort((a, b) -> Reflect.compare(a.role + "|" + a.key, b.role + "|" + b.key));
				var old = s.restored(m);
				if (old != null) {
					v.reads = old.reads;
					v.buildReads = old.buildReads;
					v.iface = old.iface;
				} else {
					var pk = role + "\x00" + core.Path.getFullPath(file);
					var reads:Array<Read> = [];
					var names = s.fileReads.get(pk);
					if (names != null)
						for (n in names.keys())
							reads.push({role: role, name: n, value: s.value(role, n)});
					var mr = s.moduleReads.get(role + "|" + v.key);
					if (mr != null)
						for (k in mr.keys()) {
							var i = k.indexOf("\x00");
							var r = Std.parseInt(k.substr(0, i));
							var n = k.substr(i + 1);
							reads.push({role: r, name: n, value: s.value(r, n)});
						}
					reads.sort((a, b) -> Reflect.compare(a.role + a.name, b.role + b.name));
					v.reads = reads;
					v.buildReads = buildReads;
					var ifaceMode = (x.mKind == MCode || x.mKind == MMacro) && StringTools.endsWith(file, ".hx") && !macroDefines && mr == null
						&& !optimize && !macroBuilt(m);
					v.iface = null;
					v.ifacePk = ifaceMode ? pk : null;
					if (s.log && v.ifacePk == null && (x.mKind == MCode || x.mKind == MMacro))
						Sys.println("hxmc: module cache: " + core.Globals.sTypePath(m.mPath) + " kept whole (" + (!ifaceMode ? (macroDefines ? "macro-defined" : mr != null ? "macro reads" : optimize ? "analyzer-optimize" : macroBuilt(m) ? "built by a macro" : "file") : "no interface") + ")");
				}
				// (the structural marks its typing made: Marks)
				var made = s.madeMarks.get(m);
				v.marks = old != null ? old.marks : made == null ? [] : made;
				v.macroBuilt = (x.mKind == MCode || x.mKind == MMacro) && macroBuilt(m);
				all.push(v);
				byKey[role].set(v.key, v);
				// restored and not processed again: the stored blob
				if (old != null && x.mProcessed == old.processed) {
					v.blob = old.blob;
					v.blobSize = old.blobSize;
					continue;
				}
				v.fresh = true;
				v.prev = old;
				var skeletons = old != null && old.skeletons != null ? old.skeletons : Skeletons.encode(s, x.mSign, m.mPath);
				if (x.mKind == MImport) {
					v.blobBytes = ModuleStore.encodeBlob([], noMonos, skeletons);
					continue;
				}
				if (s.log && old != null) Sys.println("hxmc: module cache: " + core.Globals.sTypePath(m.mPath) + " encoded again (processed " + x.mProcessed + ")");
				// (as ContextCache.cacheHxbModule, with a writer that keeps what
				// HXB does not)
				v.skeletons = skeletons;
				jobs.push({
					v: v,
					f: function() {
						var w = new CheckingHxbWriter(config, warn, new typing.TanonIdentification<Dynamic>());
						w.writeModule(m);
						return {chunks: (w.getChunks() : CachedChunks), monos: w.monoModifiers()};
					}
				});
			}
		}
		// the fresh modules' interfaces (v.iface held their file's key), hashed in parallel
		var t1 = haxe.Timer.stamp();
		var pks = [];
		for (v in all)
			if (v.ifacePk != null && !s.ifaces.exists(v.ifacePk) && pks.indexOf(v.ifacePk) < 0) pks.push(v.ifacePk);
		var hashed = context.Parallel.runWithPool(com.sctx.pool, function(pool) {
			return context.Parallel.ParallelArray.map(pool, function(pk:String) {
				var d = s.decls.get(pk);
				return d == null ? null : try ModuleInterface.hash(d) catch (_:Dynamic) null;
			}, pks, null);
		});
		for (i in 0...pks.length)
			s.ifaces.set(pks[i], hashed[i]);
		s.ifaceTime += haxe.Timer.stamp() - t1;
		for (v in all)
			if (v.ifacePk != null) v.iface = s.ifaces.get(v.ifacePk);
		var none:{v:Variant, r:{chunks:CachedChunks, monos:Bytes}} = {v: null, r: null};
		var done = context.Parallel.runWithPool(com.sctx.pool, function(pool) {
			return context.Parallel.ParallelArray.map(pool, function(j:{v:Variant, f:Void->{chunks:CachedChunks, monos:Bytes}}) return {v: j.v, r: j.f()}, jobs,
				none);
		});
		for (d in done) {
			d.v.blobBytes = ModuleStore.encodeBlob(d.r.chunks, d.r.monos, d.v.skeletons);
			// (a restored module processed again, the same as stored: its blob)
			var o = d.v.prev;
			if (o != null && o.loaded && d.v.blobBytes.length == o.blobSize
				&& ModuleStore.encodeBlob(o.chunks, o.monos, o.skeletons).compare(d.v.blobBytes) == 0) {
				d.v.blob = o.blob;
				d.v.blobSize = o.blobSize;
				d.v.blobBytes = null;
				d.v.fresh = false;
				s.written--;
			}
		}
		// (each new blob named uniquely: this build's nonce and a counter)
		var nonce = CacheDir.nonce(), count = 0;
		for (v in all)
			if (v.blobBytes != null) {
				v.blob = nonce + "-" + (count++);
				v.blobSize = v.blobBytes.length;
			}
		// (the modules of the store this build did not load, as they are)
		for (role in 0...2)
			for (k => v in s.chosen[role])
				if (!byKey[role].exists(k)) byKey[role].set(k, v);
		// the modules whose dependencies are all kept, with the hashes of
		// their dependencies
		var dropped = true;
		while (dropped) {
			dropped = false;
			for (v in all) {
				if (byKey[v.role].get(v.key) != v) continue;
				for (d in v.deps)
					if (!byKey[d.role].exists(d.key)) {
						byKey[v.role].remove(v.key);
						dropped = true;
						if (s.log) Sys.println("hxmc: module cache: " + core.Globals.sTypePath(v.path) + " not kept (a dependency is not: " + d.role + " " + d.key + ")");
						break;
					}
			}
		}
		var kept = [for (v in all) if (byKey[v.role].get(v.key) == v) v];
		var closure = new Closure(s, (role, k) -> byKey[role].get(k), "!");
		for (v in kept)
			for (d in v.deps) {
				var w = byKey[d.role].get(d.key);
				d.expect = d.eligible ? closure.di(w) : closure.df(w);
			}
		s.kept = kept;
		s.written += jobs.length;
		s.captureTime = haxe.Timer.stamp() - t0;
	}

	// whether a build macro made a type of the module (@:build, @:genericBuild,
	// or @:autoBuild on a class it extends or implements): its fields may
	// depend on its whole source (the macro reads the bodies)
	static function macroBuilt(m:ModuleDef):Bool {
		inline function has(meta:core.Ast.Metadata, l:Array<core.MetaList.StrictMeta>):Bool {
			var r = false;
			for (x in l)
				if (core.Meta.has(x, meta)) r = true;
			return r;
		}
		function inherited(c:Null<TClass>, depth:Int):Bool {
			if (c == null || depth > 64) return false;
			if (core.Meta.has(AutoBuild, c.clMeta)) return true;
			if (c.clSuper != null && inherited(c.clSuper.cls, depth + 1)) return true;
			for (i in c.clImplements)
				if (inherited(i.cls, depth + 1)) return true;
			return false;
		}
		for (t in m.mTypes)
			switch t {
				case TClassDecl(c):
					if (has(c.clMeta, [Build, AutoBuild, GenericBuild]) || inherited(c, 0)) return true;
				case TEnumDecl(e):
					if (has(e.eMeta, [Build])) return true;
				case TAbstractDecl(a):
					if (has(a.aMeta, [Build, GenericBuild])) return true;
				case TTypeDecl(_):
			}
		return false;
	}

	// the end of a build (code: its exit code): the index written when it changed
	public static function finish(code:Int) {
		var s = state;
		state = null;
		ServerCache.checkModuleHook = null;
		typing.Finalization.sortExprHook = null;
		if (s == null) return;
		var t0 = haxe.Timer.stamp();
		var blobs = 0;
		var wrote = false;
		if (code == 0 && s.volatileReason == null && s.kept != null && s.kept.length > 0) {
			// the build's modules, then the other variants (not those it
			// superseded: the same module with the same reads), at most
			// MAX_VARIANTS per module
			var list = s.kept.copy();
			var count = new Map<String, Int>();
			var same = new Map<String, Bool>();
			for (v in list) {
				count.set(v.roleKey(), 1);
				same.set(v.roleKey() + "\x00" + ModuleStore.readsKey(v.reads.concat(v.buildReads)), true);
			}
			for (v in s.index.variants) {
				var k = v.roleKey();
				if (same.exists(k + "\x00" + ModuleStore.readsKey(v.reads.concat(v.buildReads)))) continue;
				var n = count.exists(k) ? count.get(k) : 0;
				if (n >= MAX_VARIANTS) continue;
				count.set(k, n + 1);
				list.push(v);
			}
			var changed = list.length != s.index.variants.length;
			if (!changed)
				for (i in 0...list.length)
					if (list[i].fresh || list[i].roleKey() != s.index.variants[i].roleKey() || list[i].blob != s.index.variants[i].blob) {
						changed = true;
						break;
					}
			if (changed) {
				var ok = true;
				for (v in list)
					if (v.blobBytes != null) {
						if (!ModuleStore.saveBlob(s.dir, v.blob, v.blobBytes)) ok = false;
						blobs++;
					}
				var ix = new StoreIndex();
				ix.moduleHigh = @:privateAccess core.TFunctions.moduleUid.load();
				ix.varHigh = @:privateAccess core.TFunctions.varUid.load();
				ix.variants = list;
				var tmp = s.indexPath + "." + CacheDir.nonce() + ".tmp";
				if (ok)
					wrote = try {
						File.saveBytes(tmp, ModuleStore.writeIndex(ix));
						CacheDir.replace(tmp, s.indexPath);
					} catch (e:Dynamic) {
						try FileSystem.deleteFile(tmp) catch (_:Dynamic) {}
						false;
					}
			}
		}
		if (stats())
			Sys.println('hxmc: module cache: ${s.checked} checked (${Std.int(s.checkTime * 1000)} ms), ${s.written} modules encoded (${Std.int(s.captureTime * 1000)} ms), '
				+ '${s.typedUnder} typed again under restored ones, ${s.cycleTyped} with their cycle, interfaces ${Std.int(s.ifaceTime * 1000)} ms, $blobs blobs, index ${wrote ? "written" : "unchanged"} (${ms(t0)} ms)'
				+ (s.volatileReason != null ? ' (not written: ${s.volatileReason})' : ''));
	}
}

// the hashes of modules' interfaces (di) and whole contents (df), with
// their dependencies', per strongly connected component (Tarjan's): over
// the variants a build restores (their files and defines now), or over the
// modules a build ends with (when it writes them)
class Closure {
	final s:ModuleCacheState;
	final node:(Int, String) -> Null<Variant>;
	final memo = new Map<String, {di:String, df:String, clean:Bool, scc:Int}>();
	var sccs = 0;
	final index = new Map<String, Int>();
	final low = new Map<String, Int>();
	final onStack = new Map<String, Bool>();
	final stack:Array<Variant> = [];
	var counter = 0;

	// what stands for a module the store does not have (never the same in
	// a check as when the hashes were written)
	final missing:String;

	public function new(s:ModuleCacheState, node:(Int, String) -> Null<Variant>, missing:String) {
		this.s = s;
		this.node = node;
		this.missing = missing;
	}

	public function di(v:Null<Variant>):String
		return v == null ? missing : get(v).di;

	public function df(v:Null<Variant>):String
		return v == null ? missing : get(v).df;

	// whether every module of its strongly connected component has the file
	// and defines it was typed with (a module typed again in a cycle with
	// restored ones would be referenced by them while it is typed: a cycle
	// is restored whole or typed again whole)
	public function clean(v:Variant):Bool
		return get(v).clean;

	// its strongly connected component's number
	public function scc(v:Variant):Int
		return get(v).scc;

	function get(v:Variant):{di:String, df:String, clean:Bool, scc:Int} {
		var h = memo.get(v.roleKey());
		if (h == null) {
			connect(v);
			h = memo.get(v.roleKey());
		}
		return h;
	}

	function connect(v:Variant) {
		var k = v.roleKey();
		index.set(k, counter);
		low.set(k, counter);
		counter++;
		stack.push(v);
		onStack.set(k, true);
		for (d in v.deps) {
			var w = node(d.role, d.key);
			if (w == null) continue;
			var wk = w.roleKey();
			if (memo.exists(wk)) continue;
			if (!index.exists(wk)) {
				connect(w);
				if (low.get(wk) < low.get(k)) low.set(k, low.get(wk));
			} else if (onStack.exists(wk)) {
				if (index.get(wk) < low.get(k)) low.set(k, index.get(wk));
			}
		}
		if (low.get(k) != index.get(k)) return;
		var members = [];
		while (true) {
			var w = stack.pop();
			onStack.remove(w.roleKey());
			members.push(w);
			if (w == v) break;
		}
		members.sort((a, b) -> Reflect.compare(a.roleKey(), b.roleKey()));
		var inside = new Map<String, Bool>();
		for (m in members)
			inside.set(m.roleKey(), true);
		var f = new StringBuf(), i = new StringBuf();
		var ineligibleInside = false;
		var clean = true;
		for (m in members) {
			if (clean && !s.ownClean(m)) clean = false;
			f.add(m.roleKey());
			f.add("\n");
			f.add(s.sFull(m));
			i.add(m.roleKey());
			i.add("\n");
			i.add(s.sIface(m));
			for (d in m.deps) {
				var w = node(d.role, d.key);
				if (w == null) {
					f.add("\n" + missing);
					i.add("\n" + missing);
				} else if (inside.exists(w.roleKey())) {
					f.add("\n~" + w.roleKey());
					i.add("\n~" + w.roleKey());
					if (!d.eligible) ineligibleInside = true;
				} else {
					var h = memo.get(w.roleKey());
					f.add("\n" + h.df);
					i.add("\n" + (d.eligible ? h.di : h.df));
				}
			}
			f.add("\n;");
			i.add("\n;");
		}
		var dfh = haxe.crypto.Md5.encode("F" + f.toString());
		var dih = ineligibleInside ? dfh : haxe.crypto.Md5.encode("I" + i.toString());
		// (and each member's dependencies as they were when it was typed: a
		// member typed again for its dependencies makes the cycle typed again)
		if (clean)
			for (m in members) {
				for (d in m.deps) {
					var w = node(d.role, d.key);
					var actual = w == null ? missing : inside.exists(w.roleKey()) ? (d.eligible ? dih : dfh) : {
						var h = memo.get(w.roleKey());
						d.eligible ? h.di : h.df;
					};
					if (actual != d.expect) {
						clean = false;
						break;
					}
				}
				if (!clean) break;
			}
		var n = sccs++;
		for (m in members)
			memo.set(m.roleKey(), {di: dih, df: dfh, clean: clean, scc: n});
	}
}

class ModuleCacheState {
	public var dir:String;
	public var indexPath:String;
	public var com:CommonContext;
	public var index:StoreIndex;
	// per role (0: the program's context, 1: the macros'), its signature and
	// defines (the macros': predicted while that context does not exist)
	public var signs:Array<Null<String>> = [null, null];
	public var defs:Array<Null<haxe.ds.StringMap<String>>> = [null, null];
	// per role, the variant restored for each module (ModuleCache.key)
	public var chosen = [new Map<String, Variant>(), new Map<String, Variant>()];
	public var approved = new Map<String, Bool>();
	public var hashes = new Map<String, String>();
	public var closure:Null<Closure> = null;
	// the defines read: by the compiler (role and name), while parsing a file
	// (role and file: names), by a module's macros (role|key: role and name)
	public var global = new Map<String, Bool>();
	public var fileReads = new Map<String, Map<String, Bool>>();
	public var moduleReads = new Map<String, Map<String, Bool>>();
	// the file being parsed (role and file), and the read a macro makes
	// through Common.externalDefinesHook (not the compiler's)
	public var parsing:Null<String> = null;
	public var skipKey:Null<String> = null;
	// per role and file, its interface as parsed (ModuleInterface; null: none)
	public var ifaces = new Map<String, Null<String>>();
	// per role and file, its declarations as parsed (null: a parse error)
	public var decls = new Map<String, Null<Array<core.Ast.TypeDecl>>>();

	// a file's interface as parsed in this build (null: not parsed, or none)
	public function iface(pk:String):Null<String> {
		if (ifaces.exists(pk)) return ifaces.get(pk);
		var d = decls.get(pk);
		var t0 = haxe.Timer.stamp();
		var h = d == null ? null : try ModuleInterface.hash(d) catch (_:Dynamic) null;
		ifaceTime += haxe.Timer.stamp() - t0;
		ifaces.set(pk, h);
		return h;
	}
	// per module (signature and path), what the sort of the types walks of
	// its classes' fields, as typed in this build (Skeletons)
	public var skeletons = new Map<String, Map<String, Bytes>>();
	public var walked = new Map<String, Bool>();
	// the readers of restored modules whose monomorphs have modifiers
	public var readers:Array<{com:CommonContext, reader:compiler.hxb.HxbReader, monos:Bytes}> = [];
	public var volatileReason:Null<String> = null;
	public var captured = false;
	public var kept:Null<Array<Variant>> = null;
	// HXMC_MODULE_CACHE_LOG=1: each module checked, each not kept, each encoded again
	public var log = Sys.getEnv("HXMC_MODULE_CACHE_LOG") == "1";
	public var loaded = 0;
	public var checked = 0;
	public var written = 0;
	public var typedUnder = 0;
	public var checkTime = 0.0;
	public var ifaceTime = 0.0;
	public var captureTime = 0.0;

	// the files parsed, as the parser read them (their date, size and
	// content hash)
	public var parsed = new Map<String, StoredFile>();

	public function new(dir:String, indexPath:String, com:CommonContext) {
		this.dir = dir;
		this.indexPath = indexPath;
		this.com = com;
	}

	public var macroPending = true;
	// the modules whose code is being typed (Typecore.typeExprRef), the
	// structural marks made (by the module being typed, null outside), per
	// module the marks it made (Marks)
	public var typingStack:Array<Dynamic> = [];
	public var liveMarks:Array<{maker:Null<Dynamic>, cf:TClassField}> = [];
	public var madeMarks = new haxe.ds.ObjectMap<ModuleDef, Array<String>>();
	public var unattributedMarks = 0;
	// the cycles (Closure.scc) of the modules being typed from their source
	public var creating:Array<Int> = [];
	public var cycleTyped = 0;

	public function sccOf(v:Variant):Int {
		if (closure == null) closure = new Closure(this, (role, k) -> chosen[role].get(k), "?");
		return closure.scc(v);
	}

	// a restored module about to be loaded while a module of its cycle is
	// typed from its source: typed from its source too
	public function cycleGuard(com:CommonContext, path:GlobalTypePath) {
		var v = variantOf(context.CommonCache.getCacheSign(com), path);
		if (v == null || v.mc == null) return;
		// (the server's copy for this compilation)
		var mc = try context.CommonCache.getCache(com).getHxbModule(path) catch (_:Dynamic) null;
		if (mc == null) return;
		switch mc.mcExtra.mCacheState {
			case MSBad(_): return;
			case _:
		}
		if (creating.indexOf(sccOf(v)) < 0) return;
		mc.mcExtra.mCacheState = MSBad(FileChanged(v.file + " (typed with a module of its cycle)"));
		cycleTyped++;
		if (log) Sys.println("hxmc: module cache: " + core.Globals.sTypePath(path) + " typed again with a module of its cycle");
	}
	public var openTime = 0.0;

	// the variants of a role that match the build's defines put in the
	// server's cache: per module, the newest whose reads match (of those,
	// one whose file has the content it has now: a file edited back), else
	// the newest (checked dirty); the number of modules
	public function register(role:Int):Int {
		var first = new Map<String, Variant>();
		var more = new Map<String, Array<Variant>>();
		var c = chosen[role];
		for (v in index.variants) {
			if (v.role != role) continue;
			if (!first.exists(v.key)) first.set(v.key, v);
			if (!matches(v)) continue;
			v.matched = true;
			if (!c.exists(v.key)) c.set(v.key, v) else {
				var l = more.get(v.key);
				if (l == null) more.set(v.key, l = []);
				l.push(v);
			}
		}
		for (k => l in more) {
			var v = c.get(k);
			if (v.file == null || v.fileRec == null) continue;
			var time = Common.fileTime(v.file);
			if (v.fileRec.mtime == time && v.fileRec.size == ModuleCache.size(v.file)) continue;
			var h = fileHash(v.file);
			if (h == null || h == v.fileRec.hash) continue;
			for (w in l)
				if (w.fileRec != null && w.fileRec.hash == h) {
					c.set(k, w);
					break;
				}
		}
		for (k => v in first)
			if (!c.exists(k)) c.set(k, v);
		var cc = com.cs.getContext(signs[role]);
		var hxb = cc.getHxb();
		var n = 0;
		for (v in c) {
			var x = ModuleStore.readExtra(v.extra);
			x.mSign = signs[role];
			for (d in x.mDeps) {
				var r = v.signs.indexOf(d.mdSign);
				if (r >= 0 && signs[r] != null) d.mdSign = signs[r];
			}
			v.x = x;
			if (x.mKind == MImport) {
				// (an import.hx: no types, kept as a module in memory, as the server does)
				cc.cacheModuleInMemory(v.path, ({mId: v.id, mPath: v.path, mTypes: [], mStatics: null, mExtra: x} : ModuleDef));
			} else {
				var mc:compiler.hxb.HxbData.ModuleCache = {
					mcPath: v.path,
					mcId: v.id,
					mcChunks: [],
					mcExtra: x
				};
				v.mc = mc;
				hxb.replace(v.path, mc);
			}
			n++;
		}
		return n;
	}

	public function roleOfSign(sign:String):Int
		return sign == signs[0] ? 0 : sign != null && sign == signs[1] ? 1 : -1;

	public function comOf(role:Int):Null<CommonContext> {
		if (role == 0) return com;
		var m = com.getMacros();
		return m != null && context.CommonCache.getCacheSign(m) == signs[1] ? m : null;
	}

	// the variant restored for a module of the context with this signature
	public function variantOf(sign:String, path:GlobalTypePath):Null<Variant> {
		var role = roleOfSign(sign);
		return role < 0 ? null : chosen[role].get(ModuleCache.key(path));
	}

	// the variant a module of the build was restored from (null: typed)
	public function restored(m:ModuleDef):Null<Variant> {
		var v = variantOf(m.mExtra.mSign, m.mPath);
		return v != null && v.id == m.mId && (v.mc != null || v.kind == MImport) ? v : null;
	}

	// a define read in a defines context (Define.readHook)
	public function read(ctx:core.Define.DefineContext, key:String) {
		var role = ctx == com.defines ? 0 : -1;
		if (role < 0) {
			var m = com.getMacros();
			if (m != null && ctx == m.defines) role = 1 else return;
		}
		@:privateAccess ModuleCache.mutex.acquire();
		if (skipKey != null && skipKey == key) {
			skipKey = null;
		} else if (parsing != null && sys.thread.Thread.current() == @:privateAccess ModuleCache.mainThread) {
			var l = fileReads.get(parsing);
			if (l == null) fileReads.set(parsing, l = new Map());
			l.set(key, true);
		} else
			global.set(role + "\x00" + key, true);
		@:privateAccess ModuleCache.mutex.release();
	}

	// a role's defines now (the macros': their context's once it exists)
	function defsNow(role:Int):Null<haxe.ds.StringMap<String>> {
		if (role == 0) return com.defines.values;
		var m = com.getMacros();
		if (m != null && m.defines.values != defs[1]) {
			if (context.CommonCache.getCacheSign(m) == signs[1]) defs[1] = m.defines.values;
		}
		return defs[1];
	}

	// a define's value in a role now (null: not defined); "*": all of them
	public function value(role:Int, name:String):Null<String> {
		var d = defsNow(role);
		if (d == null) return "?";
		if (name == "*") {
			var ks = [for (k in d.keys()) k];
			ks.sort(Reflect.compare);
			return haxe.crypto.Md5.encode([for (k in ks) k + "=" + d.get(k)].join("\n"));
		}
		return d.get(name);
	}

	final buildMatch = new haxe.ds.ObjectMap<Array<Read>, Bool>();
	final buildValues = new haxe.ds.ObjectMap<Array<Read>, String>();

	function readsMatch(l:Array<Read>):Bool {
		for (r in l)
			if (value(r.role, r.name) != r.value) return false;
		return true;
	}

	public function matches(v:Variant):Bool {
		if (!readsMatch(v.reads)) return false;
		var m = buildMatch.get(v.buildReads);
		if (m == null) buildMatch.set(v.buildReads, m = readsMatch(v.buildReads));
		return m;
	}

	function readsValues(l:Array<Read>):String {
		var b = new StringBuf();
		for (r in l) {
			b.add(r.role);
			b.add(r.name);
			b.add("=");
			var x = value(r.role, r.name);
			b.add(x == null ? "!" : x);
			b.add("\n");
		}
		return b.toString();
	}

	// (the values of a build's reads, hashed once)
	function buildValuesOf(l:Array<Read>):String {
		var h = buildValues.get(l);
		if (h == null) buildValues.set(l, h = haxe.crypto.Md5.encode(readsValues(l)));
		return h;
	}

	public function fileHash(file:String):Null<String> {
		var h = hashes.get(file);
		if (h == null) {
			h = try haxe.crypto.Md5.make(File.getBytes(file)).toHex() catch (_:Dynamic) null;
			if (h != null) hashes.set(file, h);
		}
		return h;
	}

	// what stands for something not known now (never equal to anything)
	var unknowns = 0;

	function unknown():String
		return "?" + (unknowns++);

	// the content hash of a variant's file now ("-": none, "?": missing)
	function curFileHash(v:Variant):String {
		var file = v.file;
		if (file == null || file == "") return "-";
		var time = Common.fileTime(file);
		if (time == 0 && !FileSystem.exists(file)) return v.kind == MFake && v.mtime == 0 ? "-" : unknown();
		var f = v.fileRec;
		if (f != null && f.mtime == time && f.size == ModuleCache.size(file)) return f.hash;
		var h = fileHash(file);
		return h == null ? unknown() : h;
	}

	// a variant's interface now (its file parsed again where it changed or
	// its defines differ)
	function curIface(v:Variant):String {
		if (v.fileRec != null && v.matched && curFileHash(v) == v.fileRec.hash) return v.iface;
		var c = comOf(v.role);
		if (c == null) return unknown();
		var r = ModuleCache.resolve(c, v.path);
		if (r == null || core.Path.getFullPath(r.file) != core.Path.getFullPath(v.file)) return unknown();
		var pk = v.role + "\x00" + core.Path.getFullPath(v.file);
		if (!decls.exists(pk)) try typing.TypeloadParse.parseHook(c, r, core.Globals.nullPos) catch (_:Dynamic) {}
		var h = iface(pk);
		return h == null ? unknown() : h;
	}

	// what stands for a variant's whole content (with the defines the build
	// that typed it read: a macro's module runs its code), and for its
	// interface (its file's declarations as parsed now, or its content and
	// its own defines for a module typed with macros: not the build's, which
	// would make the same interface typed in two builds two)
	public function sFull(v:Variant):String
		return haxe.crypto.Md5.encode("full\n" + curFileHash(v) + "\n" + readsValues(v.reads) + buildValuesOf(v.buildReads));

	public function sIface(v:Variant):String {
		if (v.iface == null) return haxe.crypto.Md5.encode("own\n" + curFileHash(v) + "\n" + readsValues(v.reads));
		return haxe.crypto.Md5.encode("iface\n" + curIface(v));
	}

	// whether a variant can be restored as it is: its defines and its file's content
	public function ownClean(v:Variant):Bool
		return v.matched && (v.fileRec == null ? curFileHash(v) == "-" : curFileHash(v) == v.fileRec.hash);

	public function sccClean(v:Variant):Bool {
		if (closure == null) closure = new Closure(this, (role, k) -> chosen[role].get(k), "?");
		return closure.clean(v);
	}

	// a dependency's hash now (its interface or its content)
	public function depHash(d:StoredDep):String {
		if (closure == null) closure = new Closure(this, (role, k) -> chosen[role].get(k), "?");
		var w = chosen[d.role].get(d.key);
		return d.eligible ? closure.di(w) : closure.df(w);
	}

	// a variant's blob read, its chunks given to the server's copy
	public function load(v:Variant):Bool {
		if (v.loaded) return true;
		if (!ModuleStore.loadBlob(dir, v)) return false;
		if (v.mc != null && v.mc.mcChunks.length == 0)
			for (c in v.chunks)
				v.mc.mcChunks.push(c);
		return true;
	}

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
		return {mtime: CacheDir.now() - mtime < RACY ? -1 : mtime, size: b.length, hash: haxe.crypto.Md5.make(b).toHex()};
	}

	static inline var RACY = 3.0;

	// the modifiers back on the monomorphs of the modules read since
	public function restoreMonos() {
		var l = readers;
		readers = [];
		for (r in l)
			CheckingHxbWriter.restore(r.com, r.reader, r.monos);
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

	static function restoredEntry(s:ModuleCacheState, m:ModuleDef):Null<ModuleStore.Variant>
		return s.restored(m);

	static function typeRef(o:BytesOutput, m:ModuleDef, name:String) {
		ModuleStore.path(o, m.mPath);
		ModuleStore.str(o, name);
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
					ModuleStore.str(o, cf.cfName);
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
		if (entry.skeletonMap == null) {
			if (entry.skeletons == null) return e;
			entry.skeletonMap = decode(entry.skeletons);
		}
		var b = entry.skeletonMap.get(c.clPath.name + "\x00" + (cf == null ? "" : cf == c.clConstructor ? "new" : cf.cfName));
		var r = b == null || com == null ? null : play(com, b);
		if (r == null) {
			if (s.log) Sys.println("hxmc: module cache: no walk kept for " + core.Globals.sTypePath(c.clPath) + "." + (cf == null ? "__init__" : cf.cfName));
			return e;
		}
		return r;
	}

	static function findType(com:CommonContext, i:BytesInput):Null<ModuleType> {
		var mp = ModuleStore.rpath(i);
		var name = ModuleStore.rstr(i);
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
					var f = ModuleStore.rstr(i);
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
			ModuleStore.str(o, k);
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
			var k = ModuleStore.rstr(i);
			m.set(k, i.read(i.readInt32()));
		}
		return m;
	}
}
