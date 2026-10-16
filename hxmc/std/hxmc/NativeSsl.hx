package hxmc;

// mbedtls behind the Eval natives of mbedtls.* and sys.ssl.*
// (src/macros/eval/EvalSsl.hx), mirroring the OCaml bindings
// haxe/libs/mbedtls/mbedtls.ml: hxmc.rt.Ssl, or hxmc.rt.wasm.NoSsl on
// WebAssembly (every call throws). Contexts are opaque runtime handles. An
// alias, so that the implementation is typed only for the programs that use
// this API.
typedef NativeSsl = #if (hxmc.target == "wasm32-wasi") hxmc.rt.wasm.NoSsl #else hxmc.rt.Ssl #end;
