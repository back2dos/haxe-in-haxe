package context;

import compiler.ParsedArg.NativeLibArg;
import context.Common.CommonContext;

// port: SWF libraries (SwfLoader) belong to a target milestone outside HXB and are
// rejected explicitly.
class NativeLibraryHandler {
	public static function addNativeLib(com:CommonContext, lib:NativeLibArg):Void->Void {
		var file = lib.libFile;
		var isExtern = lib.libExtern;
		return switch lib.libKind {
			case SwfLib:
				throw new core.ds.ArgumentError("SWF library input (" + file + ") is not supported by haxe-in-haxe");
			case JavaLib:
				function add(file:String):Void->Void {
					var std = file == "lib/hxjava-std.jar";
					return codegen.JavaModern.addJavaLib(com, file, std, isExtern);
				}
				if (try sys.FileSystem.isDirectory(file) catch (_:Dynamic) false) {
					var dir = file;
					function() for (file in sys.FileSystem.readDirectory(dir)) {
						if (StringTools.endsWith(file, ".jar")) add(dir + "/" + file)();
					}
				} else
					add(file);
			case HxbLib:
				var hxbLib = compiler.hxb.HxbLib.createHxbLib(com, file);
				com.hxbLibs.unshift(hxbLib);
				function() {
					hxbLib.load();
				}
		}
	}
}
