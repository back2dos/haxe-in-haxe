package context.display;

import core.Json.JsonValue;
import compiler.CompilationCache;
import context.Memory;

// haxe/src/context/display/displayMemory.ml
// Every request reports object sizes (Objsize); see context/Memory.hx.
class DisplayMemory {
	public static function getMemoryJson(cs:Cache, mreq:MemoryRequest):JsonValue {
		Memory.memSize(cs);
		return JNull;
	}
}
