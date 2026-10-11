package context.display;

import core.Json.JsonValue;
import compiler.CompilationCache;
import context.Memory;

// port: every request reports object sizes (Objsize), which Memory.memSize does not support,
// so the request bodies are not translated.
class DisplayMemory {
	public static function getMemoryJson(cs:Cache, mreq:MemoryRequest):JsonValue {
		Memory.memSize(cs);
		return JNull;
	}
}
