package hxmc;

// libuv behind the Eval natives of eval.luv.* (src/macros/eval/EvalLuv.hx),
// standing for the OCaml luv library: hxmc.rt.Uv, or hxmc.rt.wasm.NoUv on
// WebAssembly (available() is false, the rest throws). Loops, handles,
// requests, directories and synchronization objects are integer ids;
// callbacks only run inside `loopRun`, through its dispatcher:
// dispatcher(id, event, int, value), events as in hxmc.rt.Uv (EV_*). Socket
// addresses are Bytes of `sockaddrSize()` bytes (sockaddr_storage). An
// alias, so that the implementation is typed only for the programs that use
// this API.
typedef NativeUv = #if (hxmc.target == "wasm32-wasi") hxmc.rt.wasm.NoUv #else hxmc.rt.Uv #end;
