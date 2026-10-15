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

package core;

// port: from haxe/src/core/type.ml.
// port: OCaml's include facade is represented by the original TType, TFunctions,
// TPrinting, TUnification, Texpr and TOther modules and their imports at use sites.
import core.TType;
import core.TFunctions;
import core.TPrinting;
import core.TUnification;
import core.Texpr;
import core.TOther;

class Type {
	public static function initialize():Void {
		TFunctions.monomorphBindRef = TUnification.Monomorph.bind;
		TFunctions.monomorphCreateRef = TUnification.Monomorph.create;
	}

	static function __init__():Void initialize();
}
