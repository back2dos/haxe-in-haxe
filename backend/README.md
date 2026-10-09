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
  would write binary wasm, see the design note §2.7).
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

## Limits of the C build of the port

The hxc runtime is single-threaded (one shadow stack, a stop-the-world
copying GC without thread support), and the port's C build uses the
single-threaded `sys.thread` stand-ins of `bench/js-shims`. So the
compilation server (`--wait`, which runs requests on a worker thread) does not
work in it yet; `--connect` as a client does. `sys.net.Socket`/`Host` are real
(`backend/std-hxc/sys/net`, over `rt_net.c`).

## The hxc haxelib package

`backend/haxelib/` packages the C target as a library for the user's own Haxe
(`haxe -lib hxc -main Main --custom-target hxc=bin/main`); usage is in
[haxelib/README.md](haxelib/README.md). The user's Haxe types the program;
the init macro (`hxc/Boot.hx`) makes it write the program as HXB and, after
generation, runs the bundled `bin/hxc.com` on the archive (`--hxb-lib`) and
then the C compiler. `hxc.com` is the port with the C backend, compiled by
itself to C and with cosmocc to one portable APE binary.

```sh
sh backend/haxelib/build.sh          # bin/haxelib/hxc.zip (cosmocc on PATH; about 5 min)
haxelib install bin/haxelib/hxc.zip
haxe -lib hxc -cp src -main Main --custom-target hxc=out/main
```

The archive must come from the Haxe build `hxc.com` was made from (the
pinned `haxe/`; recorded in the package's `hxc.json`). The tool runs with the
user's std path as `HAXE_STD_PATH`: DCE reruns on the loaded modules and
treats classes outside the std path as user code (kept whole).

Checked: a Map/sort/exception program and a macro/Reflect/Json program with
cc (gcc), tcc and `-D hxc.static`; `--no-output`, `-D hxc.c-only`, type
errors and `haxelib run hxc`. The backend tool itself built through the
package (`haxe -lib hxc ... -main backend.Main`) gives byte-identical C to
the source build (9 s: typing by the reference compiler, then `hxc.com`).
