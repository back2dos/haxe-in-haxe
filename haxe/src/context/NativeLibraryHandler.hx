/*
	The Haxe Compiler
	Copyright (C) 2005-2019  Haxe Foundation

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

package context;

import compiler.ParsedArg.NativeLibArg;
import context.Common.CommonContext;

class NativeLibraryHandler {
	public static function addNativeLib(com:CommonContext, lib:NativeLibArg):Void->Void {
		var file = lib.libFile;
		var isExtern = lib.libExtern;
		return switch lib.libKind {
			case SwfLib:
				codegen.SwfLoader.add_swf_lib(com, file, isExtern);
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
