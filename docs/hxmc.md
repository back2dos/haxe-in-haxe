# hxmc internals

## Pipeline

hxmc turns a typed Haxe program into a native executable with its own code
generator and linker: no C compiler, assembler or system linker at build time.

```
typed AST --(ir.Lower)--> hxmc IR --(Prep: ir.Facts)--> --(MirBuild)--> Mir (SSA) --(Inline, Sroa, Opt)-->
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
| `Mir.hx`, `MirBuild.hx`, `Opt.hx`, `Inline.hx`, `Sroa.hx` | the SSA IR, its construction, inlining, scalar replacement of frame slots (struct values), value numbering, store forwarding, LICM, dead code |
| `Lir.hx`, `Regalloc.hx`, `x64/`, `a64/` | instruction selection, linear-scan allocation, encoders (checked against llvm-mc: `EncCheck`), emission |
| `Obj.hx`, `ElfWriter.hx`, `*Reader.hx`, `Link*.hx`, `MkRt.hx`, `DataGen.hx` | objects, the linkers (static ELF, `LinkDyn.hx` dynamic ELF against glibc; PE with imports written directly; Mach-O with an ad-hoc signature), the runtime-object builder, the program's data |
| `wasm/` | wasm32-wasi: structured code from Mir, the linker, exception handling with `exnref` (or the legacy instructions) |
| `Target.hx`, `Abi.hx`, `CAbi.hx` | per-target facts; how each C ABI passes structs by value |
| `MkStd.hx` | hxmc's std merged with the Eval originals (the macro context shares the program's class paths) |
| `macro/` | native macros, a prototype (`haxe` built with `-D hxmc.jit`, Linux x86-64; `-D hxmc.macros=native\|verify`): macro classes compiled by hxmc and linked into the running compiler, behind the macro engine seam `haxe/src/macros/MacroEngine.hx` ([PLANS.md](../hxmc/PLANS.md), "Native macros") |

Conventions: references live across a GC point are shadow-stack slots
(cold sites spill only on the slow path); `try` is `rt_handler` with the C
library's `_setjmp`; calls follow the target's C ABI; a `@:hxmc.struct`
value is the address of its memory (a frame slot, an object's inline
field, memory behind a `Ptr`), copied on assignment, its result written
where a hidden last argument says ([hxmc/LOWLEVEL.md](../hxmc/LOWLEVEL.md),
"Struct values"); thread-locals use
local-exec TLS on Linux, `_tls_index` on Windows, the TLV template on macOS;
program-wide numbers (type indices, field ids, offsets) are absolute symbols
resolved by the linker, so a module's code does not change when the numbering
does.

Frame pointers: arm64 code always keeps the x29/x30 frame record (Apple's
ABI requires it). On x86-64, `-D hxmc.frame-pointers` (implied by `-debug`;
`HXMC_FRAME_POINTERS=1` for builds whose command line is fixed, such as the
tool's and the port's: `HXMC_FRAME_POINTERS=1 HXMC_SYMBOLS=1 make port`)
starts every function with `push rbp; mov rbp, rsp` and keeps rbp out of
register allocation, so `perf record -g` (frame-pointer mode) and debuggers
walk the stack; the chain runs through the runtime's Haxe code and stops in
the C library. It costs 0.8% more code and no time measurable in the noise
of the self-compile, the tool's build of the port or the benchmarks; the
default stays off. `Mem.frame()` returns the caller's record (null without
records); the corpus case `FrameChain` walks it. No unwind tables
(`.eh_frame`, `.pdata`) are written: `perf --call-graph dwarf` and
debuggers' CFI-based unwinding need them (PLANS.md).

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
"The runtime without C of our own"). The nursery's size adapts (unless
`RT_MINOR_KB` fixes it; Gc.hx): it starts at 4 MB, doubles after a minor
collection that promoted more than a 16th of what was allocated since the
previous one and halves after 8 that promoted less than a 64th, between a
floor of 4 MB per thread that allocated in the last cycles and a ceiling of
16 MB plus 8 MB per other such thread, at most 32 MB. Programs whose
objects die young keep a nursery that stays in the caches; the port typing
or compiling macro-heavy code grows it to 16 MB, which keeps medium-lived
objects out of the old space (6-17% faster, up to 31% less peak memory);
parallel phases get a larger one, so their threads stop for fewer
collections. `RT_STATS=1` prints the resizes and what was promoted. The
modules of hxmc's own package
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

## Module cache

The compilation server's HXB module cache, made durable
(`hxmc/src/hxmc/ModuleCache.hx`; opt-in: `HXMC_MODULE_CACHE=1` or
`-D hxmc.module-cache`, `HXMC_MODULE_CACHE=0` or `-D hxmc.no-module-cache`
off; through `haxe` and the tool, for every target): a successful build
writes its typed modules (HXB chunks, dependencies, file and check policy)
into a store in the user cache directory (`modules/<tool>/`, beside
`types/`, with the same trim), one pack per server context (the program's,
its macros'), keyed by the defines (the server's signature), the class
paths, the working directory and the std. The next build puts them in the
server's cache, and the server's checks decide which are good, lazily, for
the modules the build loads; beyond them, a module's file is compared by
content hash where its date or size changed, its path must still resolve
to it (shadowing), and the dependencies must be in the store. Not used for
display requests, the server itself, several compilations, init macros,
HXB libraries or output; a macro registering `onGenerate`, `onAfterTyping`
or `onAfterGenerate` while typing makes the build write nothing. The
output is the same as without the cache (`make test-module-cache`): the
cache also keeps the modifiers of unbound monomorphs and what the sort of
the types walks of each module before the filters, which HXB does not keep.
When it is on, the types cache is not used. Plans: [hxmc/PLANS.md](../hxmc/PLANS.md),
"Cached modules".

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
`HXMC_DUMP=<function>`, `HXMC_MAP=<file>` (Windows), `HXMC_FRAME_POINTERS`,
`RT_MINOR_KB` (a fixed nursery), `RT_TLAB_KB`, `RT_OLD_MB`, `RT_STATS`, `RT_VERIFY`.

## WebAssembly

WebAssembly is the seventh target, described with the others under Targets above; the playground and the npm fallback run the port as a wasm32-wasi module. The browser runner for programs (`packages/os/browser.mjs`) and the `imports.mjs` convention are in [hxmc/PLANS.md](../hxmc/PLANS.md), "Graphics".

## Origin

hxmc began as the second back end of hxc, the C target this repository had
until 2026-10-14; its IR, runtime and std came from there, and its corpus's
golden files are hxc's outputs. Plans: [hxmc/PLANS.md](../hxmc/PLANS.md); the low-level
API and C interop design: [hxmc/LOWLEVEL.md](../hxmc/LOWLEVEL.md).
