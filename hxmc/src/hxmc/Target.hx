package hxmc;

import hxmc.Lir;
import hxmc.Mir;

// A target architecture's code generator: instruction selection (which
// also tells the register allocator about its instructions) and emission.
interface Selector extends Regalloc.RegTarget {
	function select(mf:MFunc, layout:Array<MBlock>):LFunc;
}

interface Emitter {
	function func(f:LFunc, usedRegs:Array<Bool>, global:Bool):Obj.Symbol;
	// where the next functions go: their own section (`name`, Link's dead
	// code removal may drop it), or the object's .text (null)
	function useSection(name:Null<String>):Void;
	// a stub that records its caller for the stack maps (frame pointer and
	// return address in rt_last_fp/rt_last_pc), sets the first integer
	// arguments to constants (a value, or a symbol's), and jumps to
	// `target`: false when the target cannot write one (StackMaps)
	function recordingStub(name:String, target:String, consts:Array<{v:Int, sym:Null<String>}>):Bool;
}

class Target {
	public static function selector(abi:Abi):Selector
		return abi.arm ? new hxmc.a64.Isel(abi) : new hxmc.x64.Isel(abi);

	public static function emitter(abi:Abi, obj:Obj):Emitter
		return abi.arm ? new hxmc.a64.Emit(obj, abi.os == "windows", abi.os == "macos") : new hxmc.x64.Emit(obj, abi.os == "windows", abi.os == "macos");
}
