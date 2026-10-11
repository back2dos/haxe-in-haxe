package typing;

import core.WithType as WithTypeTools;
import core.WithType.WithTypeValue;
import core.TType;
import core.Globals.Pos;
import core.Error;
import core.WithType;
import context.Typecore;
import context.Typecore.Typer;
import core.ds.NotFound;
import typing.TyperBase.*;
import typing.TyperBase.AccessKind;
import core.Error.TypingError;
import typing.Calls.*;
import typing.Fields.*;
import typing.Fields.TypeFieldConfig;

@:structInit class DotPathResolution {
	public var access:AccessKind;
	public var rest:Array<DotPathPart>;

	public inline function new(access:AccessKind, rest:Array<DotPathPart>) {
		this.access = access;
		this.rest = rest;
	}

	public inline function clone():DotPathResolution return new DotPathResolution(access, rest);
}

class TyperDotPath {
	public static function mkDotPathPart(s:String, p:Pos):DotPathPart {
		return {name: s, caseKind: isLowerIdent(s, p) ? PLowercase : PUppercase, pos: p};
	}

	public static function sDotPath(parts:Array<DotPathPart>):String return parts.map(function(p) return p.name).join(".");

	/** resolve given path against module fields or raise Not_found */
	public static function resolveModuleField(ctx:Typer, m:ModuleDef, path:Array<DotPathPart>, p:Pos, mode:AccessMode,
			withType:WithTypeValue):DotPathResolution {
		if (path.length == 0 || m.mStatics == null) throw NotFound.raise();
		var first = path[0], c = m.mStatics;
		var f = c.clStatics.get(first.name); // raises Not_found
		if (f == null) throw NotFound.raise();
		var e = typeModuleType(ctx, TClassDecl(c), first.pos);
		return {access: fieldAccess(ctx, mode, f, FHStatic(c), e, first.pos), rest: path.slice(1)};
	}

	public static function resolveModuleType(ctx:Typer, m:ModuleDef, name:String, p:Pos):AccessKind {
		return mkModuleTypeAccess(ctx, Typeload.findTypeInModule(m, name), p); // raises Not_found
	}

	public static function resolveInModule(ctx:Typer, m:ModuleDef, path:Array<DotPathPart>, p:Pos, mode:AccessMode,
			withType:WithTypeValue):DotPathResolution {
		// first, try to find module-level static access
		try return resolveModuleField(ctx, m, path, p, mode, withType)
		catch (_:NotFound) {}
		// if there was no module fields, resolve
		if (path.length > 0 && path[0].caseKind == PUppercase) {
			try return {access: resolveModuleType(ctx, m, path[0].name, path[0].pos), rest: path.slice(1)} catch (_:NotFound) {}
		}
		return {access: resolveModuleType(ctx, m, m.mPath.name, p), rest: path};
	}

	/** resolve given qualified module pack+name (and possibly next path part) or raise Not_found */
	public static function resolveQualified(ctx:Typer, pack:Array<String>, name:String, nextPath:Array<DotPathPart>, p:Pos,
			mode:AccessMode, withType:WithTypeValue):DotPathResolution {
		try {
			var m = Typeload.loadModule(ctx, {pack: pack, name: name}, p);
			return resolveInModule(ctx, m, nextPath, p, mode, withType);
		} catch (error:TypingError) {
			switch error.error.errMessage {
				case ModuleNotFound(path)
					if (path.name == name && path.pack.length == pack.length && path.pack.join(".") == pack.join(".")):
					// might be an instance of https://github.com/HaxeFoundation/haxe/issues/9150
					// so let's also check (pack,name) of a TYPE in the current module context ¯\_(ツ)_/¯
					var t = Typeload.findTypeInCurrentModuleContext(ctx, pack, name); // raises Not_found
					return {access: mkModuleTypeAccess(ctx, t, p), rest: nextPath};
				case _:
					throw error;
			}
		}
	}

	/** resolve the given unqualified name (and possibly next path part) or raise Not_found */
	public static function resolveUnqualified(ctx:Typer, name:String, nextPath:Array<DotPathPart>, p:Pos, mode:AccessMode,
			withType:WithTypeValue):DotPathResolution {
		try {
			// if there's a type with this name in current module context - try resolving against it
			var t = Typeload.findTypeInCurrentModuleContext(ctx, [], name); // raises Not_found
			/*
				if there's further field access, it might be a this-package module access rather than static field access,
				so we try resolving a field first and fall back to find_in_unqualified_modules
			*/
			if (nextPath.length > 0) {
				var first = nextPath[0];
				var e = typeModuleType(ctx, t, p);
				var access = typeField(TypeFieldConfig.create(true), ctx, e, first.name, first.pos, mode, withType);
				return {access: access, rest: nextPath.slice(1)};
			}
			return {access: mkModuleTypeAccess(ctx, t, p), rest: nextPath};
		} catch (_:NotFound) {
			// otherwise run the unqualified module resolution mechanism and look into the modules
			return Typeload.findInUnqualifiedModules(ctx, name, p, m -> resolveInModule(ctx, m, nextPath, p, mode, withType)); // raise Not_found
		}
	}

	/** given a list of dot path parts, resolve it into access getter or raise Not_found */
	public static function resolveDotPath(ctx:Typer, pathParts:Array<DotPathPart>, mode:AccessMode, withType:WithTypeValue):AccessKind {
		var packAcc:Array<DotPathPart> = [];
		for (i in 0...pathParts.length) {
			var part = pathParts[i];
			if (part.caseKind == PLowercase) {
				// part starts with lowercase - it's a package part, add it the accumulator and proceed
				packAcc.unshift(part);
				continue;
			}
			var path = pathParts.slice(i + 1);
			// If this is the last part we want to use the actual mode.
			var useMode = path.length <= 1 ? mode : MGet;
			var useType = path.length <= 1 ? withType : WithTypeTools.value;
			// part starts with uppercase - it's a module name - try resolving
			var resolved = if (packAcc.length > 0) {
				var pack = packAcc.map(function(part) return part.name);
				pack.reverse();
				resolveQualified(ctx, pack, part.name, path, part.pos, useMode, useType);
			} else resolveUnqualified(ctx, part.name, path, part.pos, useMode, useType);
			// if we get here (that is, Not_found is not raised) - we have something to resolve against
			return fieldChain(ctx, resolved.rest, resolved.access, mode, withType);
		}
		// if we get to here, it means that there was no uppercase part, so it's not a qualified dot-path
		throw NotFound.raise();
	}
}
