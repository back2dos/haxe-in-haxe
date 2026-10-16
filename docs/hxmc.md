# hxmc internals

## Pipeline

hxmc turns a typed Haxe program into a native executable with its own code
generator and linker: no C compiler, assembler or system linker at build time.

```
typed AST --(ir.Lower)--> hxmc IR --(Prep: ir.Facts)--> --(MirBuild)--> Mir (SSA) --(Opt)-->
    --(x64|a64 Isel)--> LIR --(Regalloc, Emit)--> Obj (per module, cached) | --(wasm/WasmGen)--> wasm
    --(DataGen: tables, strings)--> Obj --(Link: ELF | LinkPE | LinkMachO | LinkWasm)--> executable
```

| File (`hxmc/src/hxmc/`) | |
| --- | --- |
| `Main.hx`, `Options.hx`, `Driver.hx` | the tool: runs the port's compiler with a generate hook, compiles every module (in parallel, cached) and links; `--server` keeps the compilation server resident |
| `HaxeMain.hx` | `haxe` with hxmc built in (the npm package): `--custom-target hxmc=<out>` |
| `ir/Ir.hx`, `Lower.hx`, `FnLower.hx` | the IR (structured statements in A-normal form, explicit GC points) and the lowering of the filtered typed AST |
| `ir/Facts.hx`, `Prep.hx` | the program-wide facts: names, layouts, type indices, field ids, no-GC functions, cold sites, GC points, as symbols |
| `UpToDate.hx`, `Fingerprint.hx`, `LowerCache.hx` | rebuilds: the whole build skipped when nothing changed, each module's object reused when its fingerprint is unchanged, lowered bodies reused by the server |
| `Mir.hx`, `MirBuild.hx`, `Opt.hx`, `Inline.hx` | the SSA IR, its construction, inlining, value numbering, store forwarding, LICM, dead code |
| `Lir.hx`, `Regalloc.hx`, `x64/`, `a64/` | instruction selection, linear-scan allocation, encoders (checked against llvm-mc: `EncCheck`), emission |
| `Obj.hx`, `ElfWriter.hx`, `*Reader.hx`, `Link*.hx`, `MkRt.hx`, `DataGen.hx` | objects, the linkers (static ELF, `LinkDyn.hx` dynamic ELF against glibc; PE with imports written directly; Mach-O with an ad-hoc signature), the runtime-object builder, the program's data |
| `wasm/` | wasm32-wasi: structured code from Mir, the linker, exception handling with `exnref` (or the legacy instructions) |
| `Target.hx`, `Abi.hx` | per-target facts |
| `MkStd.hx` | hxmc's std merged with the Eval originals (the macro context shares the program's class paths) |

Conventions: references live across a GC point are shadow-stack slots
(cold sites spill only on the slow path); `try` is `rt_handler` with the C
library's `_setjmp`; calls follow the target's C ABI; thread-locals use
local-exec TLS on Linux, `_tls_index` on Windows, the TLV template on macOS;
program-wide numbers (type indices, field ids, offsets) are absolute symbols
resolved by the linker, so a module's code does not change when the numbering
does.

## Runtime in Haxe

Runtime in Haxe: most of the runtime is Haxe compiled with the program
(`hxmc/std/hxmc/rt`: strings, Dynamic access, reflection, arrays, bytes,
dates, inflate, the POSIX and Windows system layers, and Math: musl's libm
ported, `LibM.hx`, with the same results on every target), written with a
small internal API (`hxmc.unsafe`: `Ptr`, `Mem` loads, stores, allocation
and symbols, `Atomic`; `@:hxmc.c` and `@:hxmc.rt` externs of C functions,
`@:hxmc.noGc` functions, `@:hxmc.export`/`@:hxmc.host` implementations of
runtime functions, `@:hxmc.callback` functions C calls,
`@:hxmc.threadLocal` statics). The collector, threads and the stop-the-world
handshake, startup and `rt_throw` are Haxe too (`Gc.hx`, `Threads.hx`,
`Start.hx`; the heap census with `-D hxmc.census`): no C of hxmc's own is
linked, only the C library, mbedtls and libuv ([hxmc/LOWLEVEL.md](../hxmc/LOWLEVEL.md),
"The runtime without C of our own"). The modules of hxmc's own package
of the std (the runtime, `hxmc.unsafe`, the natives) are typed once per
tool and configuration and cached as an HXB archive (`hxmc/src/hxmc/TypesCache.hx`;
`HXMC_TYPES_CACHE=0` turns it off): a build loads them instead of typing
them, and its executable is the same (`make fixpoint` checks it). The cache
is the user's (`$XDG_CACHE_HOME/hxmc` or `~/.cache/hxmc`, macOS
`~/Library/Caches/hxmc`, Windows `%LOCALAPPDATA%\hxmc\cache`; `HXMC_CACHE`
overrides; one that cannot be written is not used), shared by every build
of the tool, each in its own `types/<tool>/`; once a day a build removes
those unused for 14 days, and the least recently used beyond 1 GB
(`hxmc/test/CacheCheck.hx` checks it). A change of the runtime's
interface or of the IR's conventions needs a tool that knows it: build once
against the previous runtime first, or bootstrap again.

## Targets

Targets: Linux (static ELF with musl's members; with `-D hxmc.libc=glibc`, an
executable dynamically linked against the system's glibc: PT_INTERP, DT_NEEDED,
imports with the symbol versions of glibc 2.17 bound at load time, a
generated `_start` calling `__libc_start_main`; runtime objects of their own,
`<target>-glibc`, the runtime's Haxe code the same), Windows (PE over the UCRT,
imports written from the import libraries), macOS (Mach-O against
libSystem, ad-hoc signed), each on x86-64 and ARM64, and wasm32-wasi (the
whole runtime in Haxe; exception handling with `exnref`, or with
`-D hxmc.wasm-eh=legacy` the legacy `try`/`catch_all`/`rethrow`, which node 22
runs without flags and wasmtime not at all; run with
`node hxmc/bootstrap/wasi.mjs m.wasm` or `wasmtime run -W exceptions=y --dir . m.wasm`;
no threads, sockets or processes). mbedtls 2.28 and libuv 1.48
(`hxmc/deps/deps.sh`) become `ssl.o` and `uv.o`, linked only into programs that
use `sys.ssl` or `eval.luv`. Environment for development: `HXMC_OPT=0`,
`HXMC_INLINE=<flat>,<loop>,<runtime>`, `HXMC_SYMBOLS=1`, `HXMC_SIZE_STATS=1`,
`HXMC_DUMP=<function>`, `HXMC_MAP=<file>` (Windows), `RT_MINOR_KB`,
`RT_OLD_MB`, `RT_STATS`, `RT_VERIFY`.

## WebAssembly

WebAssembly is the seventh target, described with the others under Targets above; the playground and the npm fallback run the port as a wasm32-wasi module. The browser runner for programs (`packages/os/browser.mjs`) and the `imports.mjs` convention are in [hxmc/PLANS.md](../hxmc/PLANS.md), "Graphics".

## Origin

hxmc began as the second back end of hxc, the C target this repository had
until 2026-10-14; its IR, runtime and std came from there, and its corpus's
golden files are hxc's outputs. Plans: [hxmc/PLANS.md](../hxmc/PLANS.md); the low-level
API and C interop design: [hxmc/LOWLEVEL.md](../hxmc/LOWLEVEL.md).
