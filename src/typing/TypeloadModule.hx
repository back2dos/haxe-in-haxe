package typing;

import core.Ast;
import core.Ast.TypeDecl;
import core.ClassPaths;
import core.ClassPaths.ResolvedFile;
import core.Define;
import core.Define.DefineContext;
import core.Globals;
import core.Globals.GlobalTypePath;
import core.Globals.Pos;
import core.TType;
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import typing.TypeloadParse.ParseError;

// Initial, batch-only structure port of haxe/src/typing/typeloadModule.ml.
// It deliberately stops after atomically allocating module/type shells: field
// typing, imports, dependencies, caching and display require Typecore/Common.
class TypeloadModule {
	var classPaths:ClassPaths;
	var defines:DefineContext;
	var modules:Map<String, ModuleDef> = new Map();
	var nextModuleId = 0;

	public function new(classPaths:ClassPaths, defines:DefineContext) {
		this.classPaths = classPaths;
		this.defines = defines;
	}

	public function resolveModuleFile(path:GlobalTypePath):ResolvedFile {
		return classPaths.findFile(path.pack.concat([path.name]).join("/") + ".hx");
	}

	public function loadModule(path:GlobalTypePath):ModuleDef {
		var key = moduleKey(path);
		if (modules.exists(key)) return modules.get(key);
		var parsed = TypeloadParse.parseFile(defines, resolveModuleFile(path));
		if (!samePath(path.pack, parsed.data.pack)) throw new ParseError('Module package does not match file path ' + Globals.sTypePath(path), {pfile: parsed.file, pmin: 0, pmax: 0});
		var module = makeModule(path, parsed.file);
		modules.set(key, module); // upstream installs the module before creating types.
		createModuleTypes(module, parsed.data.declarations);
		return module;
	}

	public function findModule(path:GlobalTypePath):Null<ModuleDef> return modules.get(moduleKey(path));

	function makeModule(path:GlobalTypePath, file:String):ModuleDef {
		return {
			mId: nextModuleId++, mPath: path, mTypes: [], mStatics: null,
			mExtra: {mFile: file, mSign: Define.getSignature(defines), mDisplay: {mInlineCalls: [], mTypeHints: [], mImportPositions: new Map()}, mCheckPolicy: [], mTime: 0,
				mCacheState: MSUnknown, mAdded: 0, mChecked: 0, mProcessed: 0, mDeps: new IntMap(), mDisplayDeps: null, mKind: MCode, mCacheBoundObjects: [], mFeatures: new Map()}
		};
	}

	function createModuleTypes(module:ModuleDef, declarations:Array<TypeDecl>):Void {
		for (declaration in declarations) switch declaration.definition {
			case EClass(value): module.mTypes.push(TClassDecl(makeClass(module, value, declaration.pos)));
			case EEnum(value): module.mTypes.push(TEnumDecl(makeEnum(module, value, declaration.pos)));
			case ETypedef(value): module.mTypes.push(TTypeDecl(makeDef(module, value, declaration.pos)));
			case EAbstract(value): module.mTypes.push(TAbstractDecl(makeAbstract(module, value, declaration.pos)));
			case EImport(_) | EUsing(_) | EStatic(_):
		}
	}

	function makeClass(module:ModuleDef, value:ClassDefinition, pos:Pos):TClass {
		var path = typePath(module, value.name.name, has(value.flags, HPrivate));
		var cls:TClass = null;
		cls = {clPath:path, clModule:module, clPos:pos, clNamePos:value.name.pos, clPrivate:has(value.flags,HPrivate), clDoc:value.doc, clMeta:value.meta, clParams:[], clUsing:[], clRestore:function(){}, clType:TDynamic(null), clKind:KNormal, clFlags:0, clSuper:null, clImplements:[], clFields:new StringMap(), clStatics:new StringMap(), clOrderedStatics:[], clOrderedFields:[], clDynamic:null, clArrayAccess:null, clConstructor:null, clInit:null, clBuild:function() return Built, clDescendants:[]};
		cls.clType = TInst(cls, []);
		return cls;
	}

	function makeEnum(module:ModuleDef, value:EnumDefinition, pos:Pos):TEnum {
		var en:TEnum = {ePath:typePath(module,value.name.name,has(value.flags,EPrivate)), eModule:module, ePos:pos, eNamePos:value.name.pos, ePrivate:has(value.flags,EPrivate), eDoc:value.doc, eMeta:value.meta, eParams:[], eUsing:[], eRestore:function(){}, eType:TDynamic(null), eFlags:0, eConstrs:new StringMap(), eNames:[]};
		en.eType = TEnum(en, []); return en;
	}

	function makeDef(module:ModuleDef, value:TypedefDefinition, pos:Pos):TDef {
		var def:TDef = {tPath:typePath(module,value.name.name,has(value.flags,TDPrivate)), tModule:module, tPos:pos, tNamePos:value.name.pos, tPrivate:has(value.flags,TDPrivate), tDoc:value.doc, tMeta:value.meta, tParams:[], tUsing:[], tRestore:function(){}, tType:TDynamic(null)};
		def.tType = TType(def, []); return def;
	}

	function makeAbstract(module:ModuleDef, value:AbstractDefinition, pos:Pos):TAbstract {
		var abs:TAbstract = {aPath:typePath(module,value.name.name,has(value.flags,AbPrivate)), aModule:module, aPos:pos, aNamePos:value.name.pos, aPrivate:has(value.flags,AbPrivate), aDoc:value.doc, aMeta:value.meta, aParams:[], aUsing:[], aRestore:function(){}, aOps:[], aUnops:[], aImpl:null, aThis:TDynamic(null), aFrom:[], aFromField:[], aTo:[], aToField:[], aArray:[], aRead:null, aWrite:null, aCall:null, aConstructor:null, aExtern:has(value.flags,AbExtern), aEnum:has(value.flags,AbEnum)};
		abs.aThis = TAbstract(abs, []); return abs;
	}

	function typePath(module:ModuleDef, name:String, privateType:Bool):GlobalTypePath return {pack: privateType ? module.mPath.pack.concat(["_" + module.mPath.name]) : module.mPath.pack, name:name};
	static function samePath(a:Array<String>, b:Array<String>):Bool return a.join(".") == b.join(".");
	static function moduleKey(path:GlobalTypePath):String return Globals.sTypePath(path);
	static function has<T>(values:Array<T>, value:T):Bool return values.indexOf(value) != -1;
}
