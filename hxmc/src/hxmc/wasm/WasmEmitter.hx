package hxmc.wasm;

// The emitter interface for WebAssembly: functions go through WasmGen
// (Driver), so this one only answers that allocation stubs are compiled
// functions.
class WasmEmitter implements hxmc.Target.Emitter {
	public function new() {}

	public function func(f:hxmc.Lir.LFunc, usedRegs:Array<Bool>, global:Bool):Obj.Symbol
		throw "hxmc: wasm: no machine code";

	public function useSection(name:Null<String>) {}

	public function allocStub(name:String, lo:Int, tySym:Null<String>, tyVal:Int, bytes:Int):Bool
		return false;
}
