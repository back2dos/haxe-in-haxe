package compiler.server;

import core.Globals.Pos;
import core.Ast.Package;
import core.ClassPaths.ResolvedFile;
import core.Define;
import core.display.DisplayPosition;
import syntax.Parser.ParseResult;
import context.Common;
import context.CommonCache;
import compiler.CompilationCache;

// haxe/src/compiler/server/serverCache.ml: parse_file and the parse hook of
// enable_cache_mode. The batch compiler also runs in cache mode (haxe.ml calls
// Server.setup_server_context), so display requests see the parsed-file cache.
// The module cache (type_module, check_module, ...) belongs to the server milestone.
class ServerCache {
	public static function parseFile(sctx:Dynamic, com:CommonContext, rfile:ResolvedFile, p:Pos):ParseResult<Package> {
		var cc = CommonCache.getCache(com);
		var file = rfile.file;
		var ffile = core.Path.getFullPath(rfile.file);
		var fkey = com.partScope.fileKeys.get(file);
		var isDisplayFile = DisplayPosition.displayPosition.isInFile(com.partScope.fileKeys.get(ffile));
		var currentStdin:Null<String> = sctx.currentStdin;
		if (isDisplayFile && currentStdin != null && (com.fileContents.length > 0 || Common.defined(com, Define.DisplayStdin))) {
			return typing.SourceParser.parseFileFromString(com, file, p, currentStdin);
		}
		var ftime = Common.fileTime(ffile);
		var stop = core.Timer.startTimer(com.timerCtx, ["server", "parser cache"]);
		try {
			var data:ParseResult<Package> = try {
				var cfile = cc.findFile(fkey);
				if (cfile.cTime != ftime) throw core.ds.NotFound.raise();
				ParseSuccess(({pack: cfile.cPackage, declarations: cfile.cDecls} : Package), cfile.cPdi);
			} catch (_:core.ds.NotFound) {
				var parseResult = typing.SourceParser.parseFile(com, rfile, p);
				switch parseResult {
					case ParseError(_, _, _):
						// "not cached, has parse error"
					case ParseSuccess(data, pdi):
						if (isDisplayFile) {
							if (pdi.pdErrors.length > 0) {
								// "not cached, is display file with parse errors"
							} else if (com.display.dmsPerFile) {
								cc.cacheFile(fkey, rfile, ftime, data, pdi);
								// "cached, is intact display file"
							} else {
								// "not cached, is display file"
							}
						} else {
							// We assume that when not in display mode it's okay to cache stuff that has #if display
							// checks. The reasoning is that non-display mode has more information than display mode.
							var cache = com.display.dmsFullTyping || !(com.partScope.parserState.specialIdentifierFiles : core.ds.ThreadSafeHashtbl<String, String>).exists(fkey);
							if (cache) cc.cacheFile(fkey, {file: ffile, classPath: rfile.classPath}, ftime, data, pdi);
						}
				}
				// ServerMessage.parsed (server logging) is part of the server milestone.
				parseResult;
			};
			stop();
			return data;
		} catch (e:Dynamic) {
			stop();
			throw e;
		}
	}

	/** The parse hook installed by `enable_cache_mode`. **/
	public static function enableCacheMode(sctx:Dynamic):Void {
		typing.SourceParser.parseHook = function(com, rfile, p) return parseFile(sctx, com, rfile, p);
	}
}
