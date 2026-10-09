package compiler;

import core.Globals;
import core.Globals.GlobalTypePath;
import core.Json.JsonValue;
import core.ClassPaths.ResolvedFile;
import core.ds.OcamlHash;
import core.ds.OcamlHashtbl;
import core.ds.PriorityQueue;
import core.ds.PriorityQueue.PriorityQueues;
import syntax.Parser.ParserDisplayInformation;
import core.Ast;
import core.TType;

// haxe/src/compiler/compilationCache.ml
// Hash tables whose iteration order is observable in display results use
// OcamlHashtbl with OCaml's polymorphic hash, so they iterate like upstream.
@:structInit class CachedFile {
	public var cFilePath:ResolvedFile;
	public var cTime:Float;
	public var cPackage:Array<String>;
	public var cDecls:Array<TypeDecl>;
	public var cModuleName:Null<String>;
	public var cPdi:ParserDisplayInformation;
	public inline function new(cFilePath:ResolvedFile, cTime:Float, cPackage:Array<String>, cDecls:Array<TypeDecl>, cModuleName:Null<String>, cPdi:ParserDisplayInformation) { this.cFilePath = cFilePath; this.cTime = cTime; this.cPackage = cPackage; this.cDecls = cDecls; this.cModuleName = cModuleName; this.cPdi = cPdi; }
}

@:structInit class CachedDirectory {
	public var cPath:String;
	public var cMtime:Float;
	public inline function new(cPath:String, cMtime:Float) { this.cPath = cPath; this.cMtime = cMtime; }
}

@:structInit class CachedNativeLib {
	public var cNlMtime:Float;
	public var cNlFiles:OcamlHashtbl<GlobalTypePath, Package>;
	public inline function new(cNlMtime:Float, cNlFiles:OcamlHashtbl<GlobalTypePath, Package>) { this.cNlMtime = cNlMtime; this.cNlFiles = cNlFiles; }
}

/** `HxbData.module_cache` **/
@:structInit class ModuleCache {
	public var mcPath:GlobalTypePath;
	public var mcId:Int;
	public var mcChunks:Array<{kind:compiler.hxb.HxbData.ChunkKind, data:haxe.io.Bytes}>;
	public var mcExtra:ModuleDefExtra;
	public inline function new(mcPath:GlobalTypePath, mcId:Int, mcChunks:Array<{kind:compiler.hxb.HxbData.ChunkKind, data:haxe.io.Bytes}>, mcExtra:ModuleDefExtra) { this.mcPath = mcPath; this.mcId = mcId; this.mcChunks = mcChunks; this.mcExtra = mcExtra; }
}

class CompilationCache {
	public static function getModuleNameOfCfile(file:String, cfile:CachedFile):String {
		if (cfile.cModuleName == null) {
			var name = core.Path.moduleNameOfFile(file);
			cfile.cModuleName = name;
			return name;
		}
		return cfile.cModuleName;
	}

	public static function createDirectory(path:String, mtime:Float):CachedDirectory return {cPath: path, cMtime: mtime};

	public static function stringTable<V>():OcamlHashtbl<String, V> return new OcamlHashtbl(OcamlHash.hashString, (a, b) -> a == b, 0);

	public static function pathTable<V>():OcamlHashtbl<GlobalTypePath, V> return new OcamlHashtbl(OcamlHash.hashPath, (a, b) -> a.name == b.name && a.pack.join(".") == b.pack.join(".") && a.pack.length == b.pack.length, 0);

	public static function pathEq(a:GlobalTypePath, b:GlobalTypePath):Bool return a.name == b.name && a.pack.length == b.pack.length && a.pack.join(".") == b.pack.join(".");
}

class ContextCache {
	final files:OcamlHashtbl<String, CachedFile> = CompilationCache.stringTable();
	final modules:OcamlHashtbl<GlobalTypePath, ModuleDef> = CompilationCache.pathTable();
	final binaryCache:OcamlHashtbl<GlobalTypePath, ModuleCache> = CompilationCache.pathTable();
	final tmpBinaryCache:OcamlHashtbl<GlobalTypePath, ModuleCache> = CompilationCache.pathTable();
	final getHxbModuleMutex = new sys.thread.Mutex();
	final removedFiles:OcamlHashtbl<String, ResolvedFile> = CompilationCache.stringTable();
	var json:JsonValue = JNull;
	var initialized = false;
	var lastAccessTime = Sys.time();
	final children:OcamlHashtbl<String, Bool> = CompilationCache.stringTable();
	final index:Int;
	final sign:String;

	public function new(index:Int, sign:String) {
		this.index = index;
		this.sign = sign;
	}

	// files

	public function findFile(key:String):CachedFile return files.find(key);

	public function cacheFile(key:String, path:ResolvedFile, time:Float, data:Package, pdi:ParserDisplayInformation):Void {
		files.replace(key, {cFilePath: path, cTime: time, cPackage: data.pack, cDecls: data.declarations, cModuleName: null, cPdi: pdi});
	}

	public function removeFile(key:String):Void {
		var f = files.findOpt(key);
		if (f != null) {
			files.remove(key);
			removedFiles.replace(key, f.cFilePath);
		}
	}

	/** Like remove_file, but doesn't keep track of the file **/
	public function removeFileForReal(key:String):Void files.remove(key);

	// modules

	public function findModule(path:GlobalTypePath):ModuleDef return modules.find(path);

	public function findModuleOpt(path:GlobalTypePath):Null<ModuleDef> return modules.findOpt(path);

	public function getHxbModule(path:GlobalTypePath):ModuleCache {
		getHxbModuleMutex.acquire();
		try {
			var mc = tmpBinaryCache.findOpt(path);
			if (mc == null) {
				var mc0 = binaryCache.find(path);
				var mExtra = mc0.mcExtra.clone();
				mc = {mcPath: mc0.mcPath, mcId: mc0.mcId, mcChunks: mc0.mcChunks, mcExtra: mExtra};
				tmpBinaryCache.add(path, mc);
			}
			getHxbModuleMutex.release();
			return mc;
		} catch (e:haxe.Exception) {
			getHxbModuleMutex.release();
			throw e;
		}
	}

	public function findModuleExtra(path:GlobalTypePath):ModuleDefExtra {
		var m = modules.findOpt(path);
		return m != null ? m.mExtra : getHxbModule(path).mcExtra;
	}

	public function addBinaryCache(m:ModuleDef, chunks:Array<{kind:compiler.hxb.HxbData.ChunkKind, data:haxe.io.Bytes}>):Void {
		var extra = m.mExtra.clone();
		extra.mCacheState = MSGood;
		extra.mDisplayDeps = null;
		binaryCache.replace(m.mPath, {
			mcPath: m.mPath,
			mcId: m.mId,
			mcChunks: chunks,
			mcExtra: extra
		});
	}

	public function cacheHxbModule(config:Dynamic, warn:(warning:Dynamic, msg:String, p:core.Globals.Pos) -> Void, anonIdentification:Dynamic, m:ModuleDef):Null<Void->Array<{kind:compiler.hxb.HxbData.ChunkKind, data:haxe.io.Bytes}>> {
		return switch m.mExtra.mKind {
			case MImport:
				modules.add(m.mPath, m);
				null;
			case _:
				function() {
					var writer = new compiler.hxb.HxbWriter(config.generateDocumentation, warn, anonIdentification);
					writer.writeModule(m);
					return writer.getChunks();
				}
		};
	}

	public function cacheModuleInMemory(path:GlobalTypePath, m:ModuleDef):Void modules.replace(path, m);

	public function clearTempCache():Void tmpBinaryCache.clear();

	public function clearCache():Void {
		modules.clear();
		clearTempCache();
	}

	/** Clears all module caches and user-file parse cache entries, preserving only stdlib/lib file parse cache. **/
	public function clearModules():Void {
		modules.clear();
		binaryCache.clear();
		clearTempCache();
		removedFiles.clear();
		var remove = [];
		files.iter(function(k, cfile) switch cfile.cFilePath.classPath.scope {
			case User: remove.push(k);
			case Std | StdTarget | Lib:
		});
		// Hashtbl.filter_map_inplace keeps the order of the remaining bindings
		for (k in remove) files.remove(k);
	}

	// initialization

	public function isInitialized():Bool return initialized;

	public function setInitialized(value:Bool):Void initialized = value;

	public function getSign():String return sign;

	public function getIndex():Int return index;

	public function getFiles():OcamlHashtbl<String, CachedFile> return files;

	public function getModules():OcamlHashtbl<GlobalTypePath, ModuleDef> return modules;

	public function getHxb():OcamlHashtbl<GlobalTypePath, ModuleCache> return binaryCache;

	// TODO handle hxb cache there too
	public function getRemovedFiles():OcamlHashtbl<String, ResolvedFile> return removedFiles;

	public function getJson():JsonValue return json;

	public function setJson(j:JsonValue):Void json = j;

	/** Pointers for memory inspection. **/
	public function getPointers():Array<Dynamic> return [files, modules, binaryCache];

	// access tracking

	public function updateAccessTime():Void lastAccessTime = Sys.time();

	public function getLastAccessTime():Float return lastAccessTime;

	// child contexts

	public function addChild(childSign:String):Void children.replace(childSign, true);

	public function getChildren():OcamlHashtbl<String, Bool> return children;
}

abstract class ServerTask {
	final id:Array<String>;
	final priority:Int;

	public function new(id:Array<String>, priority:Int) {
		this.id = id;
		this.priority = priority;
	}

	abstract function execute():Void;

	public function run():Void execute();

	public function getPriority():Int return priority;

	public function getId():Array<String> return id;
}

class ArbitraryTask extends ServerTask {
	final f:Void->Void;

	public function new(id:Array<String>, priority:Int, f:Void->Void) {
		super(id, priority);
		this.f = f;
	}

	function execute():Void f();
}

class Cache {
	final contexts:OcamlHashtbl<String, ContextCache> = CompilationCache.stringTable();
	var contextList:Array<ContextCache> = [];
	final haxelib:core.ds.Hashtbl<{libs:Array<String>, extra:Null<String>}, Array<String>> = new core.ds.Hashtbl(0);
	final directories:OcamlHashtbl<String, Array<CachedDirectory>> = CompilationCache.stringTable();
	final nativeLibs:OcamlHashtbl<String, CachedNativeLib> = CompilationCache.stringTable();
	var tasks:PriorityQueue<ServerTask> = Empty;

	public function new() {}

	public function clear():Void {
		contexts.clear();
		contextList = [];
		haxelib.clear();
		directories.clear();
		nativeLibs.clear();
		tasks = Empty;
	}

	/** Like clear, but preserves the file parse cache and directory cache within each context. **/
	public function softClear():Void {
		contexts.iter((_, cc) -> cc.clearModules());
		contextList = [];
		haxelib.clear();
		nativeLibs.clear();
		tasks = Empty;
	}

	// contexts

	public function clearTempCache():Void contexts.iter((_, ctx) -> ctx.clearTempCache());

	public function getContext(sign:String):ContextCache {
		var cache = contexts.findOpt(sign);
		if (cache != null) {
			cache.updateAccessTime();
			if (contextList.indexOf(cache) < 0) contextList.unshift(cache);
			return cache;
		}
		var cache = new ContextCache(contexts.length(), sign);
		cache.updateAccessTime();
		contextList.unshift(cache);
		contexts.add(sign, cache);
		return cache;
	}

	public function addInfo(sign:String, desc:String, platform:Platform, classPaths:core.ClassPaths, defines:core.Define.DefineContext):Int {
		var cc = getContext(sign);
		inline function kv(n:String, v:JsonValue):core.Json.JsonField return {name: n, value: v};
		var jo:JsonValue = JObject([
			kv("index", JInt(cc.getIndex())),
			kv("desc", JString(desc)),
			kv("platform", JString(Globals.platformName(platform))),
			kv("classPaths", JArray(classPaths.asStringList().map(s -> JString(s)))),
			kv("signature", JString(sign)),
			kv("defines", JArray(core.ds.PMap.foldi(function(k:String, v:String, acc:Array<JsonValue>) {
				acc.unshift(JObject([kv("key", JString(k)), kv("value", JString(v))]));
				return acc;
			}, defines.values, [])))
		]);
		cc.setJson(jo);
		return cc.getIndex();
	}

	public function getContexts():Array<ContextCache> return contextList;

	// files

	public function removeFiles(file:String):Void contexts.iter((_, cc) -> cc.removeFile(file));

	public function getContextFiles(signs:Array<String>):Array<{key:String, file:CachedFile}> {
		return contexts.fold(function(sign, cc, acc:Array<{key:String, file:CachedFile}>) {
			if (signs.contains(sign)) return cc.getFiles().fold(function(file, cfile, acc:Array<{key:String, file:CachedFile}>) {
				acc.unshift({key: file, file: cfile});
				return acc;
			}, acc);
			return acc;
		}, []);
	}

	public function getFiles():Array<{sign:String, key:String, file:CachedFile}> {
		return contexts.fold(function(sign, cc, acc:Array<{sign:String, key:String, file:CachedFile}>) {
			return cc.getFiles().fold(function(file, cfile, acc:Array<{sign:String, key:String, file:CachedFile}>) {
				acc.unshift({sign: sign, key: file, file: cfile});
				return acc;
			}, acc);
		}, []);
	}

	// modules

	public function iterModules(f:ModuleDef->Void):Void contexts.iter((_, cc) -> cc.getModules().iter((_, m) -> f(m)));

	public function getModules():Array<ModuleDef> {
		return contexts.fold(function(_, cc, acc:Array<ModuleDef>) {
			return cc.getModules().fold(function(_, m, acc:Array<ModuleDef>) {
				acc.unshift(m);
				return acc;
			}, acc);
		}, []);
	}

	public function taintModule(mPath:GlobalTypePath, reason:ModuleTaintingReason):Void {
		contexts.iter(function(_, cc) {
			cc.getModules().iter(function(_, m) {
				if (CompilationCache.pathEq(m.mPath, mPath)) m.mExtra.mCacheState = MSBad(Tainted(reason));
			});
			cc.getHxb().iter(function(_, mc) {
				if (CompilationCache.pathEq(mc.mcPath, mPath)) mc.mcExtra.mCacheState = switch [reason, mc.mcExtra.mCacheState] {
					case [CheckDisplayFile, state = MSBad(_)]: state;
					case _: MSBad(Tainted(reason));
				};
			});
		});
	}

	public function taintModules(fileKey:String, reason:ModuleTaintingReason):Void {
		contexts.iter(function(_, cc) {
			cc.getModules().iter(function(_, m) {
				if (core.Path.UniqueKey.lazyKey(m.mExtra.mFile) == fileKey) m.mExtra.mCacheState = MSBad(Tainted(reason));
			});
			cc.getHxb().iter(function(_, mc) {
				if (core.Path.UniqueKey.lazyKey(mc.mcExtra.mFile) == fileKey) mc.mcExtra.mCacheState = switch [reason, mc.mcExtra.mCacheState] {
					case [CheckDisplayFile, state = MSBad(_)]: state;
					case _: MSBad(Tainted(reason));
				};
			});
		});
	}

	// haxelibs

	public function findHaxelib(key:{libs:Array<String>, extra:Null<String>}):Array<String> return haxelib.find(key);

	public function cacheHaxelib(key:{libs:Array<String>, extra:Null<String>}, value:Array<String>):Void haxelib.replace(key, value);

	// directories

	public function findDirectories(key:String):Array<CachedDirectory> return directories.find(key);

	public function addDirectories(key:String, value:Array<CachedDirectory>):Void directories.replace(key, value);

	public function removeDirectory(key:String, value:String):Void {
		var current = directories.findOpt(key);
		if (current != null) directories.replace(key, current.filter(dir -> dir.cPath != value));
	}

	public function hasDirectory(key:String, value:String):Bool {
		var current = directories.findOpt(key);
		return current != null && core.ds.ArrayTools.exists(current, dir -> dir.cPath == value);
	}

	public function addDirectory(key:String, value:CachedDirectory):Void {
		var current = directories.findOpt(key);
		if (current != null) addDirectories(key, [value].concat(current)) else addDirectories(key, [value]);
	}

	public function clearDirectories(key:String):Void directories.remove(key);

	// native lib

	public function addNativeLib(key:String, files:OcamlHashtbl<GlobalTypePath, Package>, timestamp:Float):Void nativeLibs.replace(key, {cNlFiles: files, cNlMtime: timestamp});

	public function getNativeLib(key:String):Null<CachedNativeLib> return nativeLibs.findOpt(key);

	// tasks

	public function addTask(task:ServerTask):Void tasks = PriorityQueues.insert(tasks, task.getPriority(), task);

	public function hasTask():Bool return !PriorityQueues.isEmpty(tasks);

	public function getTask():ServerTask {
		var r = PriorityQueues.extract(tasks);
		tasks = r.queue;
		return r.element;
	}

	public function runTasks(recursive:Bool, f:ServerTask->Bool):Void {
		function loop(acc:PriorityQueue<ServerTask>):PriorityQueue<ServerTask> {
			var current = tasks;
			tasks = Empty;
			function f_(r:{ranTask:Bool, acc:PriorityQueue<ServerTask>}, prio:Int, task:ServerTask):{ranTask:Bool, acc:PriorityQueue<ServerTask>} {
				if (f(task)) {
					task.run();
					return {ranTask: true, acc: r.acc};
				}
				return {ranTask: r.ranTask, acc: PriorityQueues.insert(r.acc, prio, task)};
			}
			var r = PriorityQueues.fold(current, f_, {ranTask: false, acc: acc});
			if (recursive && r.ranTask) return loop(r.acc);
			return r.acc;
		}
		tasks = PriorityQueues.merge(tasks, loop(Empty));
	}

	// context lifecycle

	/**
		Remove context caches that haven't been accessed for [maxAgeSeconds] seconds.
		A stale context is only removed if no live (non-stale) context transitively
		reaches it via `children` edges.
	**/
	public function removeStaleContexts(maxAgeSeconds:Int):Int {
		var now = Sys.time();
		var threshold = now - maxAgeSeconds;
		function isStale(cc:ContextCache):Bool return cc.getLastAccessTime() < threshold;
		var anyStale = contexts.fold((_, cc, acc) -> acc || isStale(cc), false);
		if (!anyStale) return 0;
		var kept = CompilationCache.stringTable();
		var worklist:Array<ContextCache> = [];
		contexts.iter(function(sign, cc) {
			if (!isStale(cc)) {
				kept.replace(sign, true);
				worklist.unshift(cc);
			}
		});
		while (worklist.length > 0) {
			var cc = worklist.shift();
			cc.getChildren().iter(function(targetSign, _) {
				if (!kept.mem(targetSign)) {
					kept.replace(targetSign, true);
					var targetCc = contexts.findOpt(targetSign);
					if (targetCc != null) worklist.unshift(targetCc);
				}
			});
		}
		var toRemove = contexts.fold(function(sign, cc, acc:Array<String>) {
			if (isStale(cc) && !kept.mem(sign)) acc.unshift(sign);
			return acc;
		}, []);
		for (sign in toRemove) contexts.remove(sign);
		if (toRemove.length > 0) contextList = contextList.filter(cc -> !toRemove.contains(cc.getSign()));
		return toRemove.length;
	}

	/** Pointers for memory inspection. **/
	public function getPointers():Array<Dynamic> return [contexts, haxelib, directories, nativeLibs];
}
