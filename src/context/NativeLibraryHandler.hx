package context;

import compiler.ParsedArg.NativeLibArg;
import context.Common.CommonContext;

// port: only the HXB library branch is implemented: SWF and JVM libraries (SwfLoader,
// JavaModern) belong to target milestones outside HXB and are rejected explicitly.
class NativeLibraryHandler {
	public static function addNativeLib(com:CommonContext, lib:NativeLibArg):Void->Void {
		var file = lib.libFile;
		var isExtern = lib.libExtern;
		return switch lib.libKind {
			case SwfLib:
				throw new core.ds.ArgumentError("SWF library input (" + file + ") is not supported by haxe-in-haxe");
			case JavaLib:
				throw new core.ds.ArgumentError("JVM library input (" + file + ") is not supported by haxe-in-haxe");
			case HxbLib:
				var hxbLib = compiler.hxb.HxbLib.createHxbLib(com, file);
				com.hxbLibs.unshift(hxbLib);
				function() {
					hxbLib.load();
				}
		}
	}
}
