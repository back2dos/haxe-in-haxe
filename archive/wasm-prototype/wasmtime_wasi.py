#!/usr/bin/env python3
# EXPERIMENTAL: runs a standalone (WASI) linear-memory build of backend/ C
# output in Wasmtime: Cranelift-compiled, optionally from a precompiled file.
#   wasmtime_wasi.py prog.wasm [--aot cache.cwasm]
import os, sys, time, wasmtime
path = sys.argv[1]
aot = sys.argv[sys.argv.index("--aot") + 1] if "--aot" in sys.argv else None
cfg = wasmtime.Config()
cfg.wasm_exceptions = True
cfg.wasm_reference_types = True
cfg.wasm_function_references = True
cfg.wasm_gc = True  # exnref needs the GC type system
cfg.cranelift_opt_level = "speed"
eng = wasmtime.Engine(cfg)
t0 = time.perf_counter()
if aot:
    if not os.path.exists(aot) or os.path.getsize(aot) == 0:
        open(aot, "wb").write(wasmtime.Module.from_file(eng, path).serialize())
    mod = wasmtime.Module.deserialize_file(eng, aot)
else:
    mod = wasmtime.Module.from_file(eng, path)
t1 = time.perf_counter()
linker = wasmtime.Linker(eng)
linker.define_wasi()
linker.define_func("env", "emscripten_notify_memory_growth", wasmtime.FuncType([wasmtime.ValType.i32()], []), lambda i: None)
store = wasmtime.Store(eng)
wasi = wasmtime.WasiConfig()
wasi.inherit_stdout()
wasi.inherit_stderr()
store.set_wasi(wasi)
inst = linker.instantiate(store, mod)
try:
    inst.exports(store)["_start"](store)
except wasmtime.ExitTrap as e:
    if e.code != 0: raise
t2 = time.perf_counter()
print(f"compile/load {1000*(t1-t0):.1f} ms, run {1000*(t2-t1):.1f} ms", file=sys.stderr)
