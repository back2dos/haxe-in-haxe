# backend/ (EXPERIMENTAL)

This is a prototype code generator: one typed IR feeding a WasmGC emitter
and a C emitter. It is an explicit scope expansion and not part of the
port's conformance work. The design, measurements and recommendation are in
[bench/WASM-BACKEND.md](../bench/WASM-BACKEND.md).

- `src/backend/Main.hx`: runs the port's compiler (cross platform). Through
  `compiler.Compiler.generateHook`, it receives the filtered program (what an
  HXB archive holds) and writes `<out>.wat` and `<out>.c`.
- `src/backend/Lower.hx`: typed AST → IR (`Ir.hx`), for the subset listed
  in the design note.
- `src/backend/EmitWat.hx`: IR → WasmGC text (prototype; a real emitter
  would write binary wasm, see the design note §2.6).
- `src/backend/EmitC.hx`: IR → C. Its `Roots` analysis decides which
  references need shadow-stack slots.
- `rt/`: the C runtime (generational copying GC, exceptions, arrays) and
  `run.js`, the Node runner for WasmGC modules.
- `bench/`: the benchmark programs. `tools/`: the baseline builders and the
  Wasmtime/WAMR runners.

```sh
sh backend/build.sh                                   # Bench -> bin/backend/Bench/{prog_c,prog_linear.js,prog.wasm}
HXFLAGS="-D retain" VARIANT=-retain sh backend/build.sh
sh backend/build.sh backend/bench/exc Exc
sh backend/tools/baselines.sh                         # HL/C native, HL/C->wasm, JS for comparison
bin/backend/Bench/prog_c
node backend/rt/run.js bin/backend/Bench/prog.wasm
python3 backend/tools/besttime.py 5 bin/backend/Bench/prog_c
```

`build.sh` needs Node, gcc and Binaryen (`BINARYEN`, default
`/root/emsdk/upstream/bin`). `baselines.sh` also needs Emscripten, the
runtime objects from `bench/build-wasm.sh` and a haxe with the hl2c fix
(`HAXE_HLC`).
