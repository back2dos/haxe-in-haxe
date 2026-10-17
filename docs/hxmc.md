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
of each module before the filters, which HXB does not keep. Macros are
trusted as the server trusts them: a macro whose result changes without
its inputs changing (the date, randomness, a file not registered with
`Context.registerModuleDependency`) keeps its earlier result until its
module changes. Plans: [plans/compiler.md](plans/compiler.md)

## Targets

Targets: Linux (static ELF with musl's members; with `-D hxmc.libc=glibc`, an
executable dynamically linked against the system's glibc: PT_INTERP, DT_NEEDED,
imports with the symbol versions of glibc 2.17 bound at load time, a
generated `_start` calling `__libc_start_main`; runtime objects of their own,
`<target>-glibc`, the runtime's Haxe code the same), Windows (PE over the UCRT,
imports written from the import libraries), macOS (Mach-O against
libSystem, ad-hoc signed), each on x86-64 and ARM64, Android (a shared
library of position-independent code against Bionic, in an APK hxmc writes:
Android, below), and wasm32-wasi (the
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

## Android

`-D hxmc.target=android-arm64` (phones) or `android-x86_64` (emulators):
Android 10 (API 29) and later, the first with ELF thread-locals in Bionic.
The output is the program's shared library (`lib<name>.so`), or with an
output ending in `.apk` an APK holding it as `lib/<abi>/libmain.so`, which
the framework's `NativeActivity` loads (no Java, no `classes.dex`, no SDK or
NDK at build time):

```sh
haxe -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/examples -main Cube \
  --custom-target hxmc=bin/cube.apk -D hxmc.target=android-arm64 -D hxmc.android-package=org.example.cube
adb install -r bin/cube.apk
adb shell am start -n org.example.cube/android.app.NativeActivity
adb logcat -s hxmc        # what the app prints (stdout and stderr)
```

| Option | |
| --- | --- |
| `-D hxmc.android-package=<id>` | the application id (default `org.hxmc.<the output's name>`) |
| `-D hxmc.android-label=<text>` | the launcher's label (the output's name) |
| `-D hxmc.android-version=<n>`, `-D hxmc.android-version-name=<text>` | `versionCode` (1), `versionName` (1.0) |
| `-D hxmc.android-min-sdk=<n>`, `-D hxmc.android-target-sdk=<n>` | 29 (the floor: ELF TLS), 35 |
| `-D hxmc.android-key=<file>`, `HXMC_ANDROID_KEY` | the debug key's file (default `<cache>/android/debug-key`, made on first use) |
| `-D hxmc.exports=<names>` | what the library exports besides `ANativeActivity_onCreate` |

The shared library (`LinkDyn.hx`, shared with `-D hxmc.shared` in the glibc
mode, `hxmc/test/SharedCheck.hx`): ET_DYN at address 0; the code was
pc-relative already (program-wide numbers are absolute symbols, not
addresses), so an address in data becomes an `R_*_RELATIVE` relocation (the
read-only data holding one moves to the writable segment), an import a GOT
slot bound at load time (`BIND_NOW`; calls through a stub), a library's
variable its slot too (the address computation that names it, adrp+add or
lea, made a load of the slot; the runtime takes `environ`'s address once,
`Start.hx`, since a load cannot be rewritten so); thread-locals as on macOS:
generated code calls `hxmc_tls_base` once per function, a stub the linker
writes that returns the module's TLS block for the thread (TLSDESC on arm64,
the general dynamic model's `__tls_get_addr` on x86-64, where Bionic has no
TLSDESC; initial-exec is refused for a dlopen'ed library); 16 KB segments
(Android 15's pages); `DT_HASH`, `DT_SONAME`, the exports (`Abi.exports`:
`ANativeActivity_onCreate`) in `.dynsym`, every other symbol hidden; section
headers (Bionic's linker reads `.dynamic` and `.dynstr` through them).

Bionic: the runtime's C library calls are imports of `libc.so`, `libm.so`
and `libdl.so` with Bionic's symbol versions (`LIBC`, `LIBC_N`, ... `LIBC_Q`):
the runtime objects `android-arm64` and `android-x86_64` hold the table of
everything those libraries export to API 29 apps, made by `mkrt.sh` from
Bionic's version scripts (their arch and `introduced=` tags), and
compiler-rt's helpers; `deps.sh` fetches Bionic's headers at a pinned AOSP
commit, against which mbedtls and libuv are compiled (`sys.ssl` and
`eval.luv` link; not exercised on a device yet) and `Layouts.hx` reads the layouts (Bionic's pthread types,
`_SC_PAGESIZE` 39). The runtime's differences: `__errno`, `__cxa_atexit` with
the library's `__dso_handle` (Bionic's `atexit` is crtbegin's), `environ`'s
address (`Mem.target()` 9 and 10: `Mem.target() >= 9` is Android, `Mem.os()`
is Linux's). Other libraries (`libandroid.so`, `liblog.so`, `libEGL.so`) are
imported unversioned; `@:hxmc.lib("libEGL.so.1")` names `libEGL.so` there.

The app (`packages/os`, `hxmc.os.android`): the export
`ANativeActivity_onCreate` (no-GC Haxe, `Activity.hx`, what the NDK's
`android_native_app_glue` does in C) sets the activity's callbacks, sends
stdout and stderr to logcat (tag `hxmc`) and starts the program's thread,
where the runtime starts (the generated `main`) with an `ALooper` watching
a pipe of the callbacks' commands; the callbacks run on the UI thread, which
the runtime does not know, and wait for the ones whose state the program
must take (a window created or going, an input queue, pause, destroy).
`AndroidWindow` is the activity's window behind `Window`, `App.run` polls
the looper (input queue: touches as the left button, their drags also as
`Scroll`, keys as X11 KeySyms), draws only with a window and not paused,
and sleeps in the looper otherwise; a window taken by the system is
`Surface.lost` (gfx lets go of its EGL surface first) and a `Suspend`
event, a new one `Resume`. `packages/gfx`'s GL back end is EGL's default
display on the `ANativeWindow`, GLES 3.0 from `libGLESv3.so`.

The APK (`hxmc/src/hxmc/android/Apk.hx`): `AndroidManifest.xml` in binary
XML (`Axml.hx`: `hasCode="false"`, `NativeActivity` with
`android.app.lib_name`, `extractNativeLibs="false"`, the configuration
changes the activity keeps, a framework theme; no `resources.arsc`), the
library stored and aligned to 16 KB (the rest to 4 bytes: what `zipalign -P
16` does), then the APK Signature Scheme v2 block, ECDSA P-256 with SHA-256
in plain Haxe (`P256.hx`, RFC 6979's deterministic nonces, so an APK signs
the same way each time; the self-signed certificate `Der.hx` writes) with a
debug key kept in the user's cache directory, so reinstalls keep their
signature. The cube's APK: 296 KB (arm64; its library 279 KB), 280 KB
(x86-64); a hello world's library 108 KB and 92 KB. Checks:
`hxmc/test/ApkCheck.hx` (`make android-check`: the zip, the manifest read
back, the library's ELF, the signature's digest and signature; `zipalign`,
`aapt`, `apksigner` where installed), `make shared-check`, and
`packages/gfx/test/android.sh` on a device or emulator (`make
android-device-check`; CI: an x86-64 emulator). Not yet: one ABI per APK,
release signing (a keystore), icons and resources, the clipboard, text
input and anything else of Java's (JNI: [plans/targets.md](plans/targets.md#android)).

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

## Origin

hxmc began as the second back end of hxc, the C target this repository had
until 2026-10-14; its IR, runtime and std came from there, and its corpus's
golden files are hxc's outputs. Plans: [ROADMAP.md](../ROADMAP.md) and
[plans/](plans/README.md); the low-level API and C interop design: [plans/lowlevel.md](plans/lowlevel.md).
