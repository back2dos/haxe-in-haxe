package hxmc;

import hxmc.Lir;
import hxmc.Mir;

// A target architecture's code generator: instruction selection (which
// also tells the register allocator about its instructions) and emission.
interface Selector extends Regalloc.RegTarget {
	function select(mf:MFunc, layout:Array<MBlock>):LFunc;
}

interface Emitter {
	function func(f:LFunc, usedRegs:Map<Int, Bool>, global:Bool):Obj.Symbol;
}

class Target {
	public static function selector(abi:Abi):Selector
		return abi.arm ? new hxmc.a64.Isel(abi.os == "macos") : new hxmc.x64.Isel();

	public static function emitter(abi:Abi, obj:Obj):Emitter
		return abi.arm ? new hxmc.a64.Emit(obj) : new hxmc.x64.Emit(obj);
}
