package compiler.hxb;

import core.Globals.GlobalTypePath;
import core.TType;
import compiler.hxb.HxbData.TypingMode;

// Port of haxe/src/compiler/hxb/hxbReaderApi.ml. The virtual class becomes an
// interface.
interface HxbReaderApi {
	function makeModule(path:GlobalTypePath, file:String):ModuleDef;
	function addModule(m:ModuleDef):Void;
	function resolveType(pack:Array<String>, mname:String, tname:String, mode:TypingMode):ModuleType;
	function resolveModule(path:GlobalTypePath, mode:TypingMode):ModuleDef;
	function basicTypes():BasicTypes;
	function getVarId(i:Int):Int;
	function readExpressionEagerly(cf:TClassField):Bool;
	function makeLazyType(t:T, f:Void->T):T;
}

class HxbReaderApiNull implements HxbReaderApi {
	public function new() {}

	public function makeModule(_:GlobalTypePath, _:String):ModuleDef throw "assert false";

	public function addModule(_:ModuleDef):Void throw "assert false";

	public function resolveType(_:Array<String>, _:String, _:String, _:TypingMode):ModuleType throw "assert false";

	public function resolveModule(_:GlobalTypePath, _:TypingMode):ModuleDef throw "assert false";

	public function basicTypes():BasicTypes throw "assert false";

	public function getVarId(_:Int):Int throw "assert false";

	public function readExpressionEagerly(_:TClassField):Bool throw "assert false";

	public function makeLazyType(_:T, _:Void->T):T throw "assert false";
}
