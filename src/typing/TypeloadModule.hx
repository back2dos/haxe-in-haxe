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
	var basicTypes:Map<String, T> = new Map();
	var basicModule:ModuleDef;
	var nextModuleId = 0;
	var nextVarId = 0;

	public function new(classPaths:ClassPaths, defines:DefineContext) {
		this.classPaths = classPaths;
		this.defines = defines;
		basicModule = {
			mId: -1, mPath: {pack: [], name: "StdTypes"}, mTypes: [], mStatics: null,
			mExtra: {mFile: "<built-in>", mSign: "", mDisplay: {mInlineCalls: [], mTypeHints: [], mImportPositions: new Map()}, mCheckPolicy: [], mTime: 0,
				mCacheState: MSUnknown, mAdded: 0, mChecked: 0, mProcessed: 0, mDeps: new IntMap(), mDisplayDeps: null, mKind: MFake, mCacheBoundObjects: [], mFeatures: new Map()}
		};
		for (name in ["Void", "Int", "Float", "Bool", "String"]) basicTypes.set(name, makeBasicType(name));
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

	/** First step of typerEntry.load_std_types. Basic-type rebinding follows once
		type parameters and abstract typing are available. */
	public function loadStdTypes():ModuleDef return loadModule({pack: [], name: "StdTypes"});

	/** Modules in the order they were allocated, matching the batch load graph. */
	public function loadedModules():Array<ModuleDef> {
		var result = [for (module in modules) module];
		result.sort(function(a, b) return a.mId - b.mId);
		return result;
	}

	function makeModule(path:GlobalTypePath, file:String):ModuleDef {
		return {
			mId: nextModuleId++, mPath: path, mTypes: [], mStatics: null,
			mExtra: {mFile: file, mSign: Define.getSignature(defines), mDisplay: {mInlineCalls: [], mTypeHints: [], mImportPositions: new Map()}, mCheckPolicy: [], mTime: 0,
				mCacheState: MSUnknown, mAdded: 0, mChecked: 0, mProcessed: 0, mDeps: new IntMap(), mDisplayDeps: null, mKind: MCode, mCacheBoundObjects: [], mFeatures: new Map()}
		};
	}

	function createModuleTypes(module:ModuleDef, declarations:Array<TypeDecl>):Void {
		// Like typeload's first pass, allocate every declaration before looking at
		// fields. This makes references to later declarations in the same module
		// available while field signatures are built.
		for (declaration in declarations) switch declaration.definition {
			case EClass(value): module.mTypes.push(TClassDecl(makeClass(module, value, declaration.pos)));
			case EEnum(value): module.mTypes.push(TEnumDecl(makeEnum(module, value, declaration.pos)));
			case ETypedef(value): module.mTypes.push(TTypeDecl(makeDef(module, value, declaration.pos)));
			case EAbstract(value): module.mTypes.push(TAbstractDecl(makeAbstract(module, value, declaration.pos)));
			case EImport(_) | EUsing(_) | EStatic(_):
		}
		for (declaration in declarations) switch declaration.definition {
			case EClass(value): populateClassFields(module, findClass(module, value.name.name), value.data);
			case EEnum(value): populateEnumConstructors(module, findEnum(module, value.name.name), value.data);
			case ETypedef(_) | EAbstract(_) | EImport(_) | EUsing(_) | EStatic(_):
		}
	}

	function populateClassFields(module:ModuleDef, cls:TClass, fields:Array<ClassField>):Void {
		for (field in fields) {
			var isStatic = hasAccess(field, AStatic);
			var type = fieldType(module, cls, field);
			var typed:TClassField = {
				cfName: field.cffName.name, cfType: type, cfPos: field.cffPos, cfNamePos: field.cffName.pos,
				cfDoc: field.cffDoc, cfMeta: field.cffMeta, cfKind: fieldKind(field), cfParams: [],
				cfExpr: null, cfExprUnoptimized: null, cfOverloads: [], cfFlags: fieldFlags(field, isStatic)
			};
			if (field.cffName.name == "new" && !isStatic) cls.clConstructor = typed;
			else if (isStatic) {
				cls.clStatics.set(typed.cfName, typed);
				cls.clOrderedStatics.push(typed);
			} else {
				cls.clFields.set(typed.cfName, typed);
				cls.clOrderedFields.push(typed);
			}
		}
		// Signatures have to be installed before bodies are typed: a method body
		// may call a method declared later in the same class.
		for (field in fields) {
			var typed = hasAccess(field, AStatic) ? cls.clStatics.get(field.cffName.name) : (field.cffName.name == "new" ? cls.clConstructor : cls.clFields.get(field.cffName.name));
			switch field.cffKind {
				case FVar(_, value) | FProp(_, _, _, value): if (value != null) typed.cfExpr = typeExpr(module, cls, value, new StringMap());
				case FFun(func): if (func.fExpr != null) typed.cfExpr = typeFunction(module, cls, func, switch typed.cfType { case TFun(signature): signature; case _: {args: [], ret: TDynamic(null)}; });
			}
		}
	}

	// Small batch-only subset of typer.ml. It deliberately preserves an unknown
	// type as Dynamic until BasicTypes and Typecore are available.
	function typeFunction(module:ModuleDef, cls:TClass, func:Func, signature:TSignature):TExpr {
		var locals = new StringMap<TVar>();
		var args = [];
		for (index in 0...func.fArgs.length) {
			var arg = func.fArgs[index];
			var variable = makeVar(arg.name.name, signature.args[index].type, TVOArgument, arg.name.pos, arg.meta);
			locals.set(variable.vName, variable);
			args.push({variable: variable, defaultValue: arg.expr == null ? null : typeExpr(module, cls, arg.expr, locals)});
		}
		var body = typeExpr(module, cls, func.fExpr, locals);
		return typed(TFunction({tfArgs:args, tfType:signature.ret, tfExpr:body}), TFun(signature), func.fExpr.pos);
	}

	function typeExpr(module:ModuleDef, cls:TClass, source:Expr, locals:StringMap<TVar>):TExpr {
		var fallback = TDynamic(null);
		return switch source.expr {
			case EConst(value): switch value {
				case Int(v, _): typed(TConst(TInt(Std.parseInt(v))), basic("Int"), source.pos);
				case Float(v, _): typed(TConst(TFloat(v)), basic("Float"), source.pos);
				case String(v, _): typed(TConst(TString(v)), basic("String"), source.pos);
				case Ident("true"): typed(TConst(TBool(true)), basic("Bool"), source.pos);
				case Ident("false"): typed(TConst(TBool(false)), basic("Bool"), source.pos);
				case Ident("null"): typed(TConst(TNull), fallback, source.pos);
				case Ident(name): typeIdent(module, cls, name, locals, source.pos);
				case Regexp(_, _): typed(TIdent(Ast.sConstant(value)), fallback, source.pos);
			};
			case EParenthesis(expr): var value = typeExpr(module, cls, expr, locals); typed(TParenthesis(value), value.etype, source.pos);
			case EBinop(op, left, right): var l = typeExpr(module, cls, left, locals); var r = typeExpr(module, cls, right, locals); typed(TBinop(op, l, r), op == OpAssign ? l.etype : fallback, source.pos);
			case EVars(vars): typeVars(module, cls, vars, locals, source.pos);
			case EBlock(exprs): var values = [for (expr in exprs) typeExpr(module, cls, expr, locals)]; typed(TBlock(values), values.length == 0 ? fallback : values[values.length - 1].etype, source.pos);
			case ECall(expr, args): var callee = typeExpr(module, cls, expr, locals); var values = [for (arg in args) typeExpr(module, cls, arg, locals)]; var result = switch callee.etype { case TFun(sig): sig.ret; case _: fallback; }; typed(TCall(callee, values), result, source.pos);
			case EField(expr, name, _): typeField(typeExpr(module, cls, expr, locals), name, source.pos);
			case ENew(path, args): typeNew(module, path.path, args, cls, locals, source.pos);
			case EFunction(_, func): var signature:TSignature = {args:[for (arg in func.fArgs) {name:arg.name.name, optional:arg.optional, type:arg.type == null ? fallback : resolveTypeHint(module, arg.type)}], ret:func.fType == null ? fallback : resolveTypeHint(module, func.fType)}; typeFunction(module, cls, func, signature);
			case EReturn(expr): typed(TReturn(expr == null ? null : typeExpr(module, cls, expr, locals)), fallback, source.pos);
			case EThrow(expr): typed(TThrow(typeExpr(module, cls, expr, locals)), fallback, source.pos);
			case EIf(condition, thenExpr, elseExpr): var thenValue = typeExpr(module, cls, thenExpr, locals); typed(TIf(typeExpr(module, cls, condition, locals), thenValue, elseExpr == null ? null : typeExpr(module, cls, elseExpr, locals)), thenValue.etype, source.pos);
			case EWhile(condition, body, flag): typed(TWhile(typeExpr(module, cls, condition, locals), typeExpr(module, cls, body, locals), flag), fallback, source.pos);
			case _: typed(TIdent("<untyped>"), fallback, source.pos);
		};
	}

	function typeVars(module:ModuleDef, cls:TClass, vars:Array<EVar>, locals:StringMap<TVar>, pos:Pos):TExpr {
		var result:Array<TExpr> = [];
		for (value in vars) {
			var type = value.evType == null ? TDynamic(null) : resolveTypeHint(module, value.evType);
			var variable = makeVar(value.evName.name, type, TVOLocalVariable, value.evName.pos, value.evMeta);
			locals.set(variable.vName, variable);
			result.push(typed(TVar(variable, value.evExpr == null ? null : typeExpr(module, cls, value.evExpr, locals)), type, value.evName.pos));
		}
		return result.length == 1 ? result[0] : typed(TBlock(result), TDynamic(null), pos);
	}

	function typeIdent(module:ModuleDef, cls:TClass, name:String, locals:StringMap<TVar>, pos:Pos):TExpr {
		var local = locals.get(name);
		if (local != null) return typed(TLocal(local), local.vType, pos);
		var field = cls.clFields.get(name);
		if (field == null) field = cls.clStatics.get(name);
		if (field != null) return typed(TField(typed(TConst(TThis), cls.clType, pos), FInstance(cls, [], field)), field.cfType, pos);
		var moduleType = findModuleType(module, name);
		if (moduleType == null && name.length > 0 && name.charAt(0) == name.charAt(0).toUpperCase()) {
			try moduleType = findModuleType(loadModule({pack: module.mPath.pack, name: name}), name) catch (_:Dynamic) {}
		}
		if (moduleType != null) return typed(TTypeExpr(moduleType), TDynamic(null), pos);
		return typed(TIdent(name), TDynamic(null), pos);
	}

	function typeField(object:TExpr, name:String, pos:Pos):TExpr {
		switch object.eexpr {
			case TTypeExpr(TClassDecl(cls)):
				var field = cls.clStatics.get(name);
				if (field != null) return typed(TField(object, FStatic(cls, field)), field.cfType, pos);
			case _:
		}
		switch object.etype {
			case TInst(cls, params):
				var field = cls.clFields.get(name);
				if (field != null) return typed(TField(object, FInstance(cls, params, field)), field.cfType, pos);
			case _:
		}
		return typed(TField(object, FDynamic(name)), TDynamic(null), pos);
	}

	function typeNew(module:ModuleDef, path:TypePath, args:Array<Expr>, cls:TClass, locals:StringMap<TVar>, pos:Pos):TExpr {
		var type = resolvePath(module, path);
		var values = [for (arg in args) typeExpr(module, cls, arg, locals)];
		return switch type {
			case TInst(target, params): typed(TNew(target, params, values), type, pos);
			case _: typed(TIdent("<new>"), TDynamic(null), pos);
		};
	}

	function makeVar(name:String, type:T, origin:TVarOrigin, pos:Pos, meta:Metadata):TVar return {vId:nextVarId++, vName:name, vType:type, vKind:VUser(origin), vExtra:null, vMeta:meta, vFlags:0, vPos:pos};
	static function typed(expr:TExprDef, type:T, pos:Pos):TExpr return {eexpr:expr, etype:type, epos:pos};

	function populateEnumConstructors(module:ModuleDef, en:TEnum, constructors:Array<EnumConstructor>):Void {
		for (index in 0...constructors.length) {
			var constructor = constructors[index];
			var args = [for (arg in constructor.ecArgs) {name: arg.name, optional: arg.optional, type: resolveTypeHint(module, arg.type)}];
			var typed:TEnumField = {
				efName: constructor.ecName.name, efType: args.length == 0 ? en.eType : TFun({args: args, ret: en.eType}),
				efPos: constructor.ecPos, efNamePos: constructor.ecName.pos, efDoc: constructor.ecDoc,
				efIndex: index, efParams: [], efMeta: constructor.ecMeta
			};
			en.eConstrs.set(typed.efName, typed);
			en.eNames.push(typed.efName);
		}
	}

	function fieldType(module:ModuleDef, cls:TClass, field:ClassField):T return switch field.cffKind {
		case FVar(type, _): type == null ? TDynamic(null) : resolveTypeHint(module, type);
		case FProp(_, _, type, _): type == null ? TDynamic(null) : resolveTypeHint(module, type);
		case FFun(func): TFun({args: [for (arg in func.fArgs) {name: arg.name.name, optional: arg.optional, type: arg.type == null ? TDynamic(null) : resolveTypeHint(module, arg.type)}], ret: func.fType == null ? TDynamic(null) : resolveTypeHint(module, func.fType)});
	}

	function fieldKind(field:ClassField):FieldKind return switch field.cffKind {
		case FVar(_, _): Var({vRead: AccNormal, vWrite: AccNormal});
		case FProp(get, set, _, _): Var({vRead: accessKind(get.name), vWrite: accessKind(set.name)});
		case FFun(_): Method(hasAccess(field, ADynamic) ? MethDynamic : hasAccess(field, AInline) ? MethInline : hasAccess(field, AMacro) ? MethMacro : MethNormal);
	}

	function resolveTypeHint(module:ModuleDef, hint:TypeHint):T return switch hint.type {
		case CTPath(path): resolvePath(module, path.path);
		case CTFunction(args, ret): TFun({args: [for (index in 0...args.length) {name: "arg" + index, optional: false, type: resolveTypeHint(module, args[index])}], ret: resolveTypeHint(module, ret)});
		case CTParent(type) | CTOptional(type) | CTNamed(_, type): resolveTypeHint(module, type);
		// Structural, intersection and extension types need Typecore's anonymous
		// field builder. Keep an explicitly dynamic placeholder until that pass.
		case CTAnonymous(_) | CTExtend(_, _) | CTIntersection(_): TDynamic(null);
	}

	function resolvePath(current:ModuleDef, path:TypePath):T {
		if (path.tpackage.length == 0 && path.tsub == null && basicTypes.exists(path.tname)) return basic(path.tname);
		if (path.tpackage.length == 0 && path.tname == "Dynamic") return TDynamic(null);
		var target = current;
		if (path.tpackage.length != 0) target = loadModule({pack: path.tpackage, name: path.tname});
		else if (findModuleType(current, path.tname) == null) {
			// Until typed type-parameter classes are constructed, an unqualified
			// parameter such as Array<T>'s T is indistinguishable from a local type
			// path here. Preserve batch loading by treating an absent local module as
			// the existing dynamic placeholder rather than failing module bootstrap.
			try target = loadModule({pack: current.mPath.pack, name: path.tname}) catch (_:Dynamic) return TDynamic(null);
		}
		var name = path.tpackage.length == 0 ? path.tname : (path.tsub == null ? path.tname : path.tsub);
		if (path.tpackage.length == 0 && path.tsub != null) name = path.tsub;
		var type = findModuleType(target, name);
		if (type == null) return TDynamic(null); // built-ins await BasicTypes/Typecore.
		var params = [for (param in path.tparams) switch param { case TPType(type): resolveTypeHint(current, type); case TPExpr(_): TDynamic(null); }];
		return switch type {
			case TClassDecl(cls): TInst(cls, params);
			case TEnumDecl(en): TEnum(en, params);
			case TTypeDecl(def): TType(def, params);
			case TAbstractDecl(abs): TAbstract(abs, params);
		};
	}

	function basic(name:String):T return basicTypes.get(name);
	function makeBasicType(name:String):T {
		var abs:TAbstract = {aPath:{pack:[], name:name}, aModule:basicModule, aPos:{pfile:"<built-in>",pmin:0,pmax:0}, aNamePos:{pfile:"<built-in>",pmin:0,pmax:0}, aPrivate:false, aDoc:null, aMeta:[], aParams:[], aUsing:[], aRestore:function(){}, aOps:[], aUnops:[], aImpl:null, aThis:TDynamic(null), aFrom:[], aFromField:[], aTo:[], aToField:[], aArray:[], aRead:null, aWrite:null, aCall:null, aConstructor:null, aExtern:true, aEnum:false};
		abs.aThis = TAbstract(abs, []);
		return abs.aThis;
	}

	function findClass(module:ModuleDef, name:String):TClass return switch findModuleType(module, name) { case TClassDecl(cls): cls; case _: throw 'Class ' + name + ' was not allocated'; };
	function findEnum(module:ModuleDef, name:String):TEnum return switch findModuleType(module, name) { case TEnumDecl(en): en; case _: throw 'Enum ' + name + ' was not allocated'; };
	function findModuleType(module:ModuleDef, name:String):Null<ModuleType> {
		for (type in module.mTypes) if (switch type { case TClassDecl(cls): cls.clPath.name == name; case TEnumDecl(en): en.ePath.name == name; case TTypeDecl(def): def.tPath.name == name; case TAbstractDecl(abs): abs.aPath.name == name; }) return type;
		return null;
	}

	static function accessKind(name:String):VarAccess return switch name { case "never": AccNever; case "null": AccNo; case "default": AccNormal; case _: AccCall; };
	static function fieldFlags(field:ClassField, isStatic:Bool):Int {
		var flags = flag(CfPublic);
		if (hasAccess(field, APrivate)) flags = 0;
		if (isStatic) flags |= flag(CfStatic);
		if (hasAccess(field, AExtern)) flags |= flag(CfExtern);
		if (hasAccess(field, AFinal)) flags |= flag(CfFinal);
		if (hasAccess(field, AOverride)) flags |= flag(CfOverride);
		if (hasAccess(field, AAbstract)) flags |= flag(CfAbstract);
		if (hasAccess(field, AOverload)) flags |= flag(CfOverload);
		return flags;
	}
	static function flag(value:FlagTClassField):Int return 1 << core.TType.TType.flagTClassFieldNames.indexOf(Std.string(value));
	static function hasAccess(field:ClassField, access:Access):Bool {
		for (value in field.cffAccess) if (value.access == access) return true;
		return false;
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
