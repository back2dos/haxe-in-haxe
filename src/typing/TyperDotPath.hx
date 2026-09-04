package typing;

import core.TType;
import core.Globals.Pos;
import core.Error;
import core.WithType;
import context.Typecore;
import typing.TyperBase.*;
import typing.Calls.*;
import typing.Fields.*;

// haxe/src/typing/typerDotPath.ml — mechanical draft; not compile-validated.
typedef DotPathResolution = {var access:Access; var rest:Array<DotPathPart>;}

class TyperDotPath {
	public static function mkDotPathPart(s:String, p:Pos):DotPathPart {
		return {name:s, letterCase:isLowerIdent(s, p) ? PLowercase : PUppercase, pos:p};
	}
	public static function sDotPath(parts:Array<DotPathPart>):String return parts.map(function(p) return p.name).join(".");
	public static function resolveModuleField(ctx:Dynamic, m:ModuleDef, path:Array<DotPathPart>, p:Pos, mode:AccessMode, withType:WithType):DotPathResolution {
		if (path.length == 0 || m.mStatics == null) throw "Not_found";
		var first = path[0], c = m.mStatics;
		var f = c.clStatics.get(first.name);
		if (f == null) throw "Not_found";
		var e = typeModuleType(ctx, TClassDecl(c), first.pos);
		return {access:fieldAccess(ctx, mode, f, FHStatic(c), e, first.pos), rest:path.slice(1)};
	}
	public static function resolveModuleType(ctx:Dynamic, m:ModuleDef, name:String, p:Pos):Access {
		return mkModuleTypeAccess(ctx, Typeload.findTypeInModule(m, name), p);
	}
	public static function resolveInModule(ctx:Dynamic, m:ModuleDef, path:Array<DotPathPart>, p:Pos, mode:AccessMode, withType:WithType):DotPathResolution {
		try return resolveModuleField(ctx, m, path, p, mode, withType) catch (error:Dynamic) {if (error != "Not_found") throw error;}
		if (path.length > 0 && path[0].letterCase == PUppercase) {
			try return {access:resolveModuleType(ctx, m, path[0].name, path[0].pos), rest:path.slice(1)}
			catch (error:Dynamic) {if (error != "Not_found") throw error;}
		}
		return {access:resolveModuleType(ctx, m, m.mPath.name, p), rest:path};
	}
	public static function resolveQualified(ctx:Dynamic, pack:Array<String>, name:String, nextPath:Array<DotPathPart>, p:Pos, mode:AccessMode, withType:WithType):DotPathResolution {
		try {
			var m = Typeload.loadModule(ctx, {pack:pack, name:name}, p);
			return resolveInModule(ctx, m, nextPath, p, mode, withType);
		} catch (error:Error) {
			switch error.error.errMessage {
				case ModuleNotFound(path) if (path.name == name && path.pack.length == pack.length && path.pack.join(".") == pack.join(".")):
					var t = Typeload.findTypeInCurrentModuleContext(ctx, pack, name);
					return {access:mkModuleTypeAccess(ctx, t, p), rest:nextPath};
				case _: throw error;
			}
		}
	}
	public static function resolveUnqualified(ctx:Dynamic, name:String, nextPath:Array<DotPathPart>, p:Pos, mode:AccessMode, withType:WithType):DotPathResolution {
		try {
			var t = Typeload.findTypeInCurrentModuleContext(ctx, [], name);
			if (nextPath.length > 0) {
				var first = nextPath[0];
				var e = typeModuleType(ctx, t, p);
				var access = typeField(TypeFieldConfig.create(true), ctx, e, first.name, first.pos, mode, withType);
				return {access:access, rest:nextPath.slice(1)};
			}
			return {access:mkModuleTypeAccess(ctx, t, p), rest:nextPath};
		} catch (error:Dynamic) {
			if (error != "Not_found") throw error;
			return Typeload.findInUnqualifiedModules(ctx, name, p, function(m, resume) return resolveInModule(ctx, m, nextPath, p, mode, withType), true);
		}
	}
	public static function resolveDotPath(ctx:Dynamic, pathParts:Array<DotPathPart>, mode:AccessMode, withType:WithType):Access {
		var packAcc:Array<DotPathPart> = [];
		for (i in 0...pathParts.length) {
			var part = pathParts[i];
			if (part.letterCase == PLowercase) {packAcc.unshift(part); continue;}
			var path = pathParts.slice(i + 1);
			var useMode = path.length <= 1 ? mode : MGet;
			var useType = path.length <= 1 ? withType : WithType.value;
			var resolved = if (packAcc.length > 0) {
				var pack = packAcc.map(function(part) return part.name); pack.reverse();
				resolveQualified(ctx, pack, part.name, path, part.pos, useMode, useType);
			} else resolveUnqualified(ctx, part.name, path, part.pos, useMode, useType);
			return fieldChain(ctx, resolved.rest, resolved.access);
		}
		throw "Not_found";
	}
}
