#!/usr/bin/env python3
# EXPERIMENTAL: runs a backend/ WasmGC module in Wasmtime (pip wasmtime), with
# Cranelift JIT or an ahead-of-time precompiled artifact.
#   wasmtime_run.py prog.wasm [--aot cache.cwasm] [--collector drc|null]
import sys, time, wasmtime
path = sys.argv[1]
aot = sys.argv[sys.argv.index("--aot") + 1] if "--aot" in sys.argv else None
cfg = wasmtime.Config()
cfg.wasm_gc = True
cfg.wasm_function_references = True
cfg.wasm_exceptions = True
cfg.wasm_reference_types = True
if "--collector" in sys.argv:
    cfg.collector = sys.argv[sys.argv.index("--collector") + 1]
eng = wasmtime.Engine(cfg)
t0 = time.perf_counter()
if aot:
    import os
    if not os.path.exists(aot) or os.path.getsize(aot) == 0:
        open(aot, "wb").write(wasmtime.Module.from_file(eng, path).serialize())
    mod = wasmtime.Module.deserialize_file(eng, aot)
else:
    mod = wasmtime.Module.from_file(eng, path)
t1 = time.perf_counter()
store = wasmtime.Store(eng)
out = []
pr = wasmtime.Func(store, wasmtime.FuncType([wasmtime.ValType.i32()], []), lambda v: out.append(str(v)))
inst = wasmtime.Instance(store, mod, [pr])
inst.exports(store)["main"](store)
t2 = time.perf_counter()
print("\n".join(out))
print(f"compile/load {1000*(t1-t0):.1f} ms, run {1000*(t2-t1):.1f} ms", file=sys.stderr)
