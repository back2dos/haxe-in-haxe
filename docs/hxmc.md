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
| `Unwind.hx`, `Dwarf.hx` | unwind tables from the emitters' frame records (`.eh_frame`, `.pdata`/`.xdata`, `__eh_frame`), `-debug`'s DWARF lines (Debugging, below) |
| `Obj.hx`, `ElfWriter.hx`, `*Reader.hx`, `Link*.hx`, `MkRt.hx`, `DataGen.hx` | objects, the linkers (static ELF, `LinkDyn.hx` dynamic ELF against glibc; PE with imports written directly; Mach-O with an ad-hoc signature), the runtime-object builder, the program's data |
| `wasm/` | wasm32-wasi: structured code from Mir, the linker, exception handling with `exnref` (or the legacy instructions) |
| `Target.hx`, `Abi.hx`, `CAbi.hx` | per-target facts; how each C ABI passes structs by value |
| `MkStd.hx` | hxmc's std merged with the Eval originals (the macro context shares the program's class paths; a custom target gets no `_std` directory in the reference compiler) |
| `macro/` | native macros, a prototype (`haxe` built with `-D hxmc.jit`, Linux x86-64; `-D hxmc.macros=native\|verify`): macro classes compiled by hxmc and linked into the running compiler, behind the macro engine seam `haxe/src/macros/MacroEngine.hx` ([plans/compiler.md](plans/compiler.md), "Native macros") |

Conventions: references live across a GC point are shadow-stack slots
(cold sites spill only on the slow path); `try` is `rt_handler` with the C
library's `_setjmp`; calls follow the target's C ABI; a `@:hxmc.struct`
value is the address of its memory (a frame slot, an object's inline
field, memory behind a `Ptr`), copied on assignment (also through Haxe's
inliner and analyzer: hooks set by `ir/CInterop.install`), its result written
where a hidden last argument says ([plans/lowlevel.md](plans/lowlevel.md),
"Struct values"); thread-locals use
local-exec TLS on Linux, `_tls_index` on Windows, the TLV template on macOS;
program-wide numbers (type indices, field ids, offsets) are absolute symbols
resolved by the linker, so a module's code does not change when the numbering
does.

## Debugging

Frame pointers: every function keeps a frame record (x86-64: `push rbp;
mov rbp, rsp`, rbp kept out of register allocation; arm64: the x29/x30 pair,
which Apple's ABI requires), so `perf record -g` (frame-pointer mode),
debuggers and `Mem.frame()` (the caller's record; the corpus case
`FrameChain` walks it) walk the stack; the chain runs through the
runtime's Haxe code and stops in the C library. On x86-64 they are the
default since 2026-10-17 (0.9% more code, no time measurable in the noise of
the self-compile, the tool's build of the port or the benchmarks); `-D
hxmc.no-frame-pointers` (or `HXMC_FRAME_POINTERS=0`, for builds whose
command line is fixed) leaves them out.

Unwind tables, always written (`hxmc/src/hxmc/Unwind.hx`): the emitters
(`x64/Emit.hx`, `a64/Emit.hx`) record what each prologue and epilogue does
to the frame (pushes, the frame pointer's setting, the allocation, saved
registers, and back), with the offsets where each instruction ends
(`Obj.FuncRec`, kept in the cached objects), and each linker writes them in
its format: ELF `.eh_frame` with its search table `.eh_frame_hdr`
(`PT_GNU_EH_FRAME`; with the entries of the runtime object's live C code),
Mach-O `__eh_frame` (no `__unwind_info`: the system's unwinder and lldb read
the DWARF), Windows `.pdata` with `.xdata` (x86-64 `UNWIND_INFO`, the
epilogues recognized by the unwinder; arm64 unwind codes with an epilogue
scope per epilogue; identical ones shared; sorted with the runtime
object's). A function's frame is the same at every instruction of its body:
outgoing stack arguments are part of the frame (no adjustment around calls),
nothing allocates on the stack dynamically, and `hxmc_call_on_stack`, the
stack switch of the main thread, runs on its frame pointer, which unwinders
follow back to the old stack. On arm64 the callee-saved registers are stored
right above the outgoing arguments, where Windows' unwind codes reach them
(at most 504 bytes above sp; beyond that the outgoing arguments are
allocated after the stores). DWARF unwinding (gdb and lldb backtraces
without heuristics, `perf --call-graph dwarf`, C++-style unwinders such as
glibc's `backtrace()`) and Windows' (`RtlVirtualUnwind`, debuggers, crash
dumps, SEH walking through generated frames) need them. They cost, for the
tool itself (24,400 functions): ELF 1.0 MB (5.7% of 17.5 MB; 6.0% on arm64),
Mach-O 0.98 MB (5.1%), Windows 12 (x86-64) or 8 (arm64) bytes per function
in `.pdata` (1.2%) and the shared `.xdata`.

Source lines (`-debug`, or `-D hxmc.lines` alone): positions flow from the
typed AST to the emitted code: the lowering puts a `SPos` statement (file,
line) before each statement's code (`FnLower.stmt`), `MirBuild` gives the
instructions it builds the current one (`MIns.pos`, `SrcPos`; the inliner
copies them, so inlined code has its own file and lines), instruction
selection passes it to the target instructions (`LIns.pos`), and the
emitters record a row where it changes (`FuncRec.lines`, mapped through
branch relaxation). The linkers write DWARF 4 (`hxmc/src/hxmc/Dwarf.hx`):
`.debug_line`, `.debug_info` with a compilation unit per module and a
subprogram per function named by its Haxe name (`pack.Class.field`), and
`.debug_aranges`/`.debug_ranges`; in ELF files, in Mach-O files' `__DWARF`
segment, and in PE files as MinGW's toolchain writes them (with a COFF
symbol table: gdb, lldb and llvm-symbolizer read them; no PDB, so not the
Visual Studio debugger or WinDbg: [plans/codegen.md](plans/codegen.md)). Every pass steps over the
positions, so the code is the same with and without them (DebugCheck
compares the code of both builds); they add 2.7 MB (15.6%) to the tool.
`-debug` also writes the symbol table (`-D hxmc.symbols` or
`HXMC_SYMBOLS=1` alone).

Checks: the corpus case `UnwindTables` compares the system's own unwinders
with the frame-pointer chain from a recursion, a closure the runtime's sort
calls back and after a caught exception (glibc's `backtrace()` in the glibc
mode, `RtlCaptureStackBackTrace` on Windows and under Wine, libunwind's
`_Unwind_Backtrace` on macOS); `hxmc/test/DebugCheck.hx` (in `make check`
and CI's test jobs) builds `hxmc/test/debug/Lines.hx` with `-debug` and runs
gdb in batch mode (lldb without gdb; lldb on macOS): a breakpoint at a Haxe
line, then a backtrace that must name the Haxe functions with the lines of
their calls, as in

```
Breakpoint 1, Lines.inner () at hxmc/test/debug/Lines.hx:10
10			seen.push(depth); // break here
#0  Lines.inner () at hxmc/test/debug/Lines.hx:10
#1  0x0000000000408550 in Lines.inner () at hxmc/test/debug/Lines.hx:9
#2  0x0000000000408550 in Lines.inner () at hxmc/test/debug/Lines.hx:9
#3  0x000000000040859c in F_Lines_inner__sclos ()
#4  0x0000000000408467 in Lines.outer () at hxmc/test/debug/Lines.hx:20
#5  0x0000000000408295 in Lines.main () at hxmc/test/debug/Lines.hx:29
#6  0x0000000000408141 in hx_main_body ()
#7  0x0000000000408241 in hxmc_call_on_stack ()
#8  0x000000000040df06 in hxmc.rt.Start.runMain () at .../hxmc/rt/Start.hx:92
#9  0x000000000040817a in main ()
```

and checks every target's tables with readelf, llvm-readobj and
llvm-dwarfdump.

## Runtime in Haxe

Runtime in Haxe: most of the runtime is Haxe compiled with the program
(`hxmc/std/hxmc/rt`: strings, Dynamic access, reflection, arrays, bytes,
dates, inflate, the POSIX and Windows system layers, and Math: musl's libm
ported, `LibM.hx`, with the same results on every target), written with a
small internal API (`hxmc.unsafe`: `Ptr`, `Mem` loads, stores, allocation
and symbols, `Atomic`; `@:hxmc.c` and `@:hxmc.rt` externs of C functions,
`@:hxmc.noGc` functions, `@:hxmc.export`/`@:hxmc.host` implementations of
runtime functions, `@:hxmc.callback` functions C calls,
`@:hxmc.threadLocal` statics; the compiler rejects an address from `Mem.addr`
live across a GC point outside `@:hxmc.noGc` code, `Facts.checkRawAddresses`). The collector, threads and the stop-the-world
handshake, startup and `rt_throw` are Haxe too (`Gc.hx`, `Threads.hx`,
`Start.hx`; the heap census with `-D hxmc.census`): no C of hxmc's own is
linked, only the C library, mbedtls and libuv ([plans/lowlevel.md](plans/lowlevel.md),
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
collections. `RT_STATS=1` prints the resizes and what was promoted. A change of the runtime's
interface or of the IR's conventions needs a tool that knows it: build once
against the previous runtime first, or bootstrap again.

## Module cache

The compilation server's HXB module cache, made durable
(`hxmc/src/hxmc/ModuleCache.hx`, `ModuleStore.hx`; on by default,
`HXMC_MODULE_CACHE=0` or `-D hxmc.no-module-cache` off; through `haxe` and
the tool, for every target): a successful build writes its typed modules
(HXB chunks, dependencies, file and check policy) into a store in the user
cache directory (`$XDG_CACHE_HOME/hxmc` or `~/.cache/hxmc`, macOS
`~/Library/Caches/hxmc`, Windows `%LOCALAPPDATA%\hxmc\cache`; `HXMC_CACHE`
overrides; one that cannot be written is not used), in `modules/<tool>/`
for each build of the tool: an index per working directory, class paths
and std (`<key>.idx`), the modules' HXB in blobs (one pack per build that
writes some, `b/<name>.pk`, written beside the rest of the build), read only
for the modules a build restores, and the compiled objects (`o/`, `ObjectStore.hx`:
named by the hash of their lowered IR, shared by every output; per output
the list of objects its last build used and its up-to-date record; the
objects stay next to the output, in `<out>.hxmc/`, only where the cache
directory cannot be written); once a day a build removes the tool
directories, indexes and object lists unused for 14 days, the least
recently used beyond 1 GB, and the packs and objects nothing names (`CacheDir.hx`, checked by
`hxmc/test/CacheCheck.hx`). An index keeps variants of each module, each
with the defines it read (its file's conditions, its macros'
`Context.defined`, and those the compiler read in the build that typed
it): a build restores the variant whose reads have its values, so a define
only some modules read leaves the others (the std) good. The server's
checks decide which modules are good, lazily, for the modules the build
loads; beyond them, a module's file is compared by content hash where its
date or size changed, its path must still resolve to it (shadowing), and
each dependency must have the hash it had when the module was typed: the
hash of its interface (`ModuleInterface.hx`: its declarations without the
bodies of functions whose type is written out; positions only for the
expressions kept, which inlining copies), or of its whole content across
contexts (a macro's code runs). A module typed again whose interface did
not change leaves its dependents restored (early cutoff: a body edited in
a central module of the port types that module again, not its
dependents); an edit undone restores the earlier variant. Modules built by
macros are restored too; the state macros keep between calls is tracked:
the static variables of macro classes (not the std's) the macros run in a
module's typing use are kept with it (a registry an `@:autoBuild` fills
for another macro, a counter naming generated types). Such a module is
restored while no macro of the build uses that state; a macro that uses
it after such a module was restored makes the build run again, those
modules typed (`HXMC_MODULE_CACHE_RETYPE`), and an edited one has the
others that keep state there typed from the start. A callback a macro
registers while a module is typed (`onGenerate`, `onAfterTyping`,
`onAfterGenerate`) makes that module typed every build. Not used for
display requests, the server itself, several compilations, init macros,
deprecated defines, HXB libraries or output, WASI; such a callback
registered outside the typing of a module, or a macro defining something,
makes the build write nothing. The output is the same as
without the cache (`make test-module-cache`; `make fixpoint`: the tool
building itself with the cache cold, warm and off): the cache also keeps
the modifiers of unbound monomorphs and what the sort of the types walks
of each module before the filters, which HXB does not keep. What a macro's
result depends on beyond the sources is learned from the macro std's
natives (`EvalStdLib.volatileHook`, `fileHook`, `envHook`), for the module
being typed when the macro runs (the one the static-variable tracking
names). A call whose result changes from run to run (`Date.now`,
`Sys.time`, `Sys.cpuTime`, `Timer.stamp`, `Math.random`, `Std.random`,
sockets, `sys.net.Host`, `sys.Http`, `sys.ssl`, `Sys.command`,
`sys.io.Process`, `Sys.getChar`, eval.luv's network, processes, signals,
time, random, file system and system information) makes the module
typed every build, its macros run again; its dependents stay restored
through its interface as parsed, unless the call was where they copy the
result (an inline or macro field, a field whose type is not written out,
a build macro): then its interface counts as new every build. A file a
macro reads (`File.getContent`, `getBytes`, `read`; `FileSystem.exists`,
`isDirectory`, `stat`, `readDirectory`, `fullPath`) is a read of the module
kept with what the macro saw (the content's hash, the listing, whether it
exists, the status, the full path), as an environment variable it reads
(`Sys.getEnv`, `Sys.environment`, eval.luv's `Env`) is with its value: the
module is restored while they are the same (a file touched but not changed
leaves it), its interface is its whole content (they may change it), and a
variant per value is kept (`registerModuleDependency` keeps working, the
file then both a dependency and a read; a macro reading its module's own
file adds nothing). `@:hxmc.noCache` on a type, or
`-D hxmc.no-cache=<package, module or library directory,...>` (read without
entering the key), makes a module typed every build, its dependents with
it; `HXMC_MODULE_CACHE_LOG=1` says why a module was typed (`Clock typed
every build (macro called Date.now at src/Macros.hx:4)`, `Data dirty: ...
(data.txt, read by a macro)`), `HXMC_STATS=1` counts the modules typed from
source and those typed every build. A module whose types share a path
(an abstract whose implementation class `@:native` renamed to it, processed
in the macros' context: eval's `mbedtls.SslAuthmode`) is not kept: HXB names
a type by its module and name. Plans: [plans/compiler.md](plans/compiler.md)

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
`HXMC_DUMP=<function>`, `HXMC_MAP=<file>` (Windows), `HXMC_FRAME_POINTERS=0`,
`RT_MINOR_KB` (a fixed nursery), `RT_TLAB_KB`, `RT_OLD_MB`, `RT_STATS`, `RT_VERIFY`.

## WebAssembly

WebAssembly is the seventh target, described with the others under Targets above; the playground and the npm fallback run the port as a wasm32-wasi module.

Programs in the browser: a package whose externs are imports of a module
(`@:hxmc.lib("hxmc_gfx")`) ships an `imports.mjs`, whose default export maps
a host to import objects, possibly asynchronously (gfx requests the WebGPU
adapter and device before `main`); `packages/os/browser.mjs` merges them,
gives WASI preview 1 without a file system and runs `_start`. JavaScript
objects live in its handle table, Haxe sees integers. The runtime stays
intact after `_start` returns, and JavaScript calls a `@:hxmc.callback` by
its index in the exported `__indirect_function_table` (corpus case
`WasmCallback`): `@hxmc/os`'s canvas window runs its loop from
`requestAnimationFrame` that way, paused while the canvas is out of view.

### WasmGC (-D hxmc.wasm-gc, an experiment)

With `-D hxmc.wasm-gc` (and `-D hxmc.target=wasm32-wasi`) the IR after Lower
becomes a WasmGC module instead (`hxmc/src/hxmc/wasmgc/`): objects live in the
engine's collector, with no linear memory, shadow stack or barriers. What main and the
initializers reach is emitted (`GcGen.Reach`); every reference is an `eqref`,
cast to its concrete type where it is used; all types are in one recursion
group, so the class hierarchy is wasm's subtyping (`instanceof` is
`ref.test`); virtual and interface calls go through a funcref table indexed by
class and selector; closures are structs whose first field is a typed
function reference (`call_ref`); exceptions are the legacy try/catch
instructions. The runtime is `hxmc/std/hxmc/rt/gc`: Haxe over intrinsics
(`hxmc.rt.gc.W`, expanded by `FuncGen.host`), its `@:hxmc.wasmgc` classes the
only ones whose `@:hxmc.host` functions are bound; Math's transcendental
functions, float formatting and parsing are the host's (`hxmc/bootstrap/wasmgc.mjs`, which
runs a module under node). A runtime function not covered yet fails the
build with its name. `make wasmgc-check` compares `hxmc/test/wasmgc`'s programs
with their native output; `make wasmgc-bench` adds the linear-memory build:
times, peak RSS, sizes.

## Origin

hxmc began as the second back end of hxc, the C target this repository had
until 2026-10-14; its IR, runtime and std came from there, and its corpus's
golden files are hxc's outputs. Plans: [ROADMAP.md](../ROADMAP.md) and
[plans/](plans/README.md); the low-level API and C interop design: [plans/lowlevel.md](plans/lowlevel.md).
