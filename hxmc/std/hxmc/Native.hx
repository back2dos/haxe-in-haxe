package hxmc;

// Reflection for the std implementations (Type and Reflect are Haxe code
// over these, also haxe.Int64.isInt64 and the maps' hashes): the dynamic
// access of the runtime, hxmc.rt.Dyn, under its API name.
#if (hxmc.wasm_gc)
typedef Native = hxmc.rt.gc.GcNative;
#else
typedef Native = hxmc.rt.Dyn;
#end
