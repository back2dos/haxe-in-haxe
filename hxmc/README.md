# hxmc: Haxe to machine code

hxmc is a custom target that turns a typed Haxe program (the HXB archive
your Haxe writes, or source through the port's front end) into a native
executable with its own code generator and linker: no C compiler,
assembler or system linker at build time. It is self-contained in this
directory: its IR and lowering (`src/hxmc/ir`), its runtime (`rt/`,
compiled ahead of time per target into one relocatable object,
`tools/mkrt.sh`), its std (`std/`, target `--custom-target hxmc`) and its
build, which hxmc does itself (`Makefile`; the first tool comes from the
reference compiler, see "Bootstrap"). It started as a code generator for
hxc's IR and was separated from hxc (see "Origin"); nothing here uses
`hxc/`.

Status: development. Every function of the port and of the test corpus
compiles natively for the six desktop targets: x86-64 and arm64 Linux
(static ELF, own linker, musl), x86-64 and arm64 Windows (PE, imports
written directly) and x86-64 and arm64 macOS (Mach-O against libSystem,
ad-hoc signed); the port built by hxmc compiles itself to byte-identical
HXB (see "Targets" for how each is checked), and hxmc builds itself.
WebAssembly (`wasm32-wasi`) is a seventh target, with its whole runtime in
Haxe; the port compiles itself there too (see "WebAssembly").
Run time is near clang -O2 on hxc's C, executables are about 10% larger
than clang -O2's dynamic ones (static, runtime included). Deeper
incremental rebuilds, the haxelib, APE builds and C interop are deferred
(see "Status").

## Design

```
HXB --(port: --hxb-lib)--> typed AST --(ir.Lower)--> hxmc IR --(Prep: ir.Facts)
    --(MirBuild)--> Mir (SSA) --(Opt)--> --(x64|a64/Isel)--> LIR --(Regalloc)--> --(Emit, Asm)--> Obj (per module, cached)
    --(DataGen: tables, strings)--> Obj
    --(Link: ELF | LinkPE: PE | LinkMachO: Mach-O, with the runtime object)--> executable
```

| File | |
| --- | --- |
| `src/hxmc/Main.hx`, `Options.hx`, `Driver.hx` | the tool: runs the port's compiler with a generate hook, then compiles every module (in parallel, cached) and links; `--server` keeps the port's compilation server resident (objects kept in memory) |
| `src/hxmc/ir/Ir.hx`, `Lower.hx`, `FnLower.hx` | the IR (structured statements in A-normal form, explicit GC points) and the lowering of the filtered typed AST to it: Int/Bool/Float/Int64 unboxed, generics erased, values converted where declared and use-site types differ |
| `src/hxmc/ir/Facts.hx` | the program-wide preparation: function and literal names, object layouts, type indices, field ids, the absolute symbols of program-wide numbers, no-GC functions, cold sites (`SCold`), GC points |
| `src/hxmc/LowerCache.hx` | resident builds: lowered function bodies reused while the server keeps their fields, through the `Lower.lowerBody` hook (calls into the lowering replayed, objects rebound) |
| `src/hxmc/UpToDate.hx`, `Fingerprint.hx` | rebuilds: the whole build is skipped when archive (its ZIP directory), arguments and tool are unchanged; otherwise each module's object is reused when its fingerprint (its IR plus what its code reads of the rest of the program) is unchanged |
| `src/hxmc/Prep.hx` | the facts (`ir.Facts`) the code, the data and the runtime agree on, as symbols |
| `src/hxmc/Mir.hx`, `MirBuild.hx` | the machine-independent SSA IR and its construction from hxmc's IR (Braun et al. on the structured statements); expands the runtime's inline helpers (allocation, write barrier, array access, inline caches); tags loads and stores with a memory class |
| `src/hxmc/Opt.hx`, `Inline.hx` | machine-independent optimizations: inlining of small functions, global value numbering over the dominator tree (loads by memory class and version), store forwarding, loop-invariant code motion, branches decided by dominating branches, dead code |
| `src/hxmc/Lir.hx`, `Regalloc.hx` | target instructions over virtual registers; linear-scan allocation with lifetime holes, spill weights by loop depth, fixed ranges for physical registers, caller-saved registers kept across slow-path calls (saved around them) |
| `src/hxmc/x64/`, `src/hxmc/a64/` | x86-64 and AArch64: instruction selection (System V, Win64, AAPCS64), encoders (checked against llvm-mc), emission (frames, jump tables, constant pools) |
| `src/hxmc/Obj.hx`, `ElfWriter.hx`, `ElfReader.hx`, `CoffReader.hx`, `MachOReader.hx` | relocatable objects in memory, ELF output, ELF/COFF/Mach-O input |
| `src/hxmc/DataGen.hx` | the program's data: type tables, dispatch rows, strings, globals, and the absolute symbols of program-wide numbers |
| `src/hxmc/Link.hx`, `LinkPE.hx`, `LinkMachO.hx`, `A64Reloc.hx`, `MkRt.hx` | the linkers (static ELF; PE with import tables written directly, TLS directory, .pdata, base relocations on arm64; Mach-O with dyld's rebase/bind opcodes, stubs, TLV descriptors and an ad-hoc code signature) and the runtime-object builder (COFF member selection, COMDAT, imports; Mach-O objects merged) |
| `src/hxmc/Target.hx`, `Abi.hx` | per-target facts and the code-generator factory |
| `rt/` | the runtime's C part (GC, exceptions, threads, system, sockets, the std natives not yet in Haxe; `rt.h`), the slow paths of generated code (`rthxmc.c`) and word-at-a-time `memcmp`/`bcmp` for musl (`rtlibc.c`) |
| `std/` | the target's std: overrides of upstream modules, the runtime's Haxe part (`hxmc.rt`, `hxmc.Native*`; see "Runtime in Haxe"), its intrinsics (`hxmc.unsafe`) and the externs of its C part, merged into `bin/hxmc/std` by `tools/mkstd.py` |
| `Makefile`, `tools/bootstrap/` | the build of the tool (by itself) and its bootstrap |
| `test/` | the corpus: programs (`cases/`), frozen fuzzer programs (`fuzz-1000.tar.gz`), golden outputs (`expected/`), encoder tests (`encoder/`) |

Conventions (inherited from hxc, whose C used the same runtime):

- GC roots: reference locals live across a GC point are shadow-stack
  slots (`fr[k]`, `Roots`: a frame pushed by the prologue, popped on
  return; locals that never live at the same time share a slot); cold
  sites (`SCold`) store the live references on the shadow stack only on
  the slow path (in spare slots of the function's frame when it has one).
  The C part of the runtime keeps its references there too (`RT_ROOT`).
  Stack maps were tried and reverted (see "Stack maps: tried and
  reverted").
- Exceptions: `try` is the runtime's `rt_handler` with the C library's
  `_setjmp` (jmp_buf layout per target); in functions with a `try` a
  scalar assigned in a try body and referenced outside it lives in memory,
  so a handler sees its latest value after the second return of setjmp.
- Calls follow the C ABI of the target; generated functions use it too.
- Thread-local runtime state (`rt_sp`, `rt_young_ptr`, ...) is reached with
  the local-exec TLS model on Linux, `_tls_index` + section offsets on
  Windows (gs:[0x58] on x86-64, x18 + 0x58 on arm64), and on macOS at its
  offset in the image's TLV template from the thread's copy of it
  (`hxmc_tls_base` in the runtime, through a descriptor of offset 0 the
  linker defines); the base is computed once per function.
- Symbols are the C names everywhere (generated functions `F_<name>`,
  the runtime's externs `hxmc_<Class>_<name>`); Mach-O's leading underscore is
  dropped when the runtime's objects are read and added back for libSystem.
- Program-wide numbers (type indices, field ids, signatures, global
  offsets, type spans) are absolute symbols (`TY_`, `FID_`, `SIG_`,
  `GIOFF_`, `TYSPAN_`) defined by DataGen and resolved by the linker, so a
  module's code does not change when the numbering does (and it can be
  cached).

### Hooks for later targets and uses

Kept open on purpose (where):

- Position-independent output and shared libraries (Android `lib*.so`,
  iOS): `Abi.reloc` (`Static`/`Pic`) and `Abi.output`
  (`Executable`/`SharedLibrary`), `-D hxmc.pic`, `-D hxmc.shared`; the code
  generators already address code and data pc-relatively (`lea rip+x`,
  `adrp/add`) and program-wide numbers are absolute symbols, not
  addresses, so only the linker depends on the model. The Mach-O and
  arm64 PE executables are already position-independent (rebases or base
  relocations of absolute pointers, imports through slots); the ELF linker
  refuses PIC output explicitly until it writes GOT/PLT, dynamic
  relocations and `DT_NEEDED`, and no linker writes shared libraries yet.
- TLS model: `Abi.tls` (`LocalExec`, `WinTlsIndex`, `MachoTlv` implemented;
  `InitialExec`, `Desc` (TLSDESC) not yet); instruction selection fails
  explicitly on a model it does not implement.
- Segment alignment: `Abi.segAlign` (4K x86-64, 64K arm64 Linux, 16K Apple
  arm64), `-D hxmc.seg-align=16384` (Android 15+).
- Platform variants: `Abi.libc` (musl, glibc, bionic, ucrt, libsystem) and
  `Abi.platform` (macos, ios, ios-simulator: the Mach-O build version).
- Mir and `Opt` know nothing about x86-64 or arm64 (memory classes, value
  numbering); target facts go through `Abi`/`Target`. A wasm target would
  be a separate structured code generator from hxmc's IR (which keeps the
  structured control flow) or Mir, with linear memory and the shadow stack.
- Native macros / hot reload: a module compiles to an in-memory `Obj`
  (code, data, relocations) independent of file writing and linking, which
  a loader could relocate against live addresses; program-wide numbers stay
  symbolic so a runtime could register new types and dispatch entries and
  resolve them at load time; link-time dead-code elimination and table
  compaction belong in the linker, not in code generation.

## Runtime in Haxe

Most of the runtime is Haxe compiled by hxmc itself (`std/hxmc/rt`, and
the std's own classes over it), Go-style: runtime operations become ordinary functions of
the program, inlined into user code where they are small and dropped when
unused, in one language. What needs the machine directly is written with a
small internal API (`std/hxmc/unsafe`, not a user API):

- `Ptr`: a raw address (an `hxmc.I64` the collector neither traces nor
  moves). `Mem.addr(o)`/`Mem.obj(p)` convert a reference and the address
  of its payload; an address taken from a heap object is valid only until
  the next GC point.
- `Mem`: loads and stores of every width at `p + off` (and indexed, `p +
  off + i * size`), `setRefBarrier` (a store through the write barrier),
  `alloc`/`allocRaw` (an object of a run-time size, type index and kind),
  `sym` (the address of a symbol of the program or runtime), `tlsGet`/
  `tlsSet` (the runtime's thread-locals), `abi` (Abi's layout constants),
  `os`/`arm`/`target` (the target, constants: FnLower lowers only the
  branch an `if` or `?:` on a comparison of one with a constant takes, so
  the other target's functions are never reached; written
  `if (Mem.os() == 2)`, never `a && b`), `stack` (a frame area), `ult`,
  `callRef1`/`callRef2` (calls through code pointers). MirBuild expands them
  inline; none but the allocations and calls is a GC point.
- `Atomic`: sequentially consistent loads, stores, add, exchange and
  compare-exchange of 32 and 64 bits and a fence (x86-64: `mov`, `xchg`,
  `lock xadd`, `lock cmpxchg`, `mfence`; arm64: `ldar`, `stlr`,
  `ldaxr`/`stlxr` loops, `dmb ish`: ARMv8.0, no LSE), expanded by
  instruction selection.
- C interop: `@:hxmc.c` extern classes are C functions called by symbol
  with the target's C ABI (`LibC`: scalars and pointers; Int is a C int,
  I64 and Ptr 64-bit, Float a double; never GC points); `@:hxmc.rt` ones
  are the runtime's C functions, which may collect. `@:hxmc.varargs(k)`
  marks a variadic C function with k fixed parameters (x86-64 System V
  sets `al`; Apple arm64 passes the rest on the stack). `Posix`, `Win32`
  and `Winsock` declare the system's functions the runtime calls;
  `hxmc/tools/mkrt.sh` names them so the runtime object provides them
  (musl's members on Linux, import records on Windows; libSystem binds
  at load time on macOS).
- `@:hxmc.noGc` on a function: it must not reach a GC point (it may keep
  raw addresses across its calls); Facts checks it and names the culprit.
  Raw addresses of heap objects belong in such functions only: inline
  code of the std that takes one (`Mem.addr`) is expanded into the
  program, whose lowering may compute the address before an allocation
  among the same expression's operands, which moves the object (the
  haxe.atomic cells call no-GC helpers).
- `@:hxmc.export("sym")` / `@:hxmc.host("sym")` on a static function of an
  `hxmc` package class: it implements runtime function `sym` for the
  natives the code generator knows by name (String, StringBuf, Std,
  Array, haxe.io.Bytes, Date, Math.random, the Dynamic operations: core
  types with runtime layouts). Generated code's calls of `sym` (FnLower's
  `ECallHost`) become direct calls of it (Lower.bindHosts: not GC points
  when it is `@:hxmc.noGc`, inlinable); an exported one is also called by
  the C part by that symbol, so it is always compiled. Each runtime function gets its own section, which the
  ELF linker drops when nothing reaches it, and is inlined only in loops
  (HXMC_INLINE's third value).
- The other runtime areas are plain typed Haxe the std calls directly
  (no extern, no binding, dropped by Haxe's dead-code elimination when
  unused): `hxmc.NativeSys` and `hxmc.NativeNet` choose the POSIX or the
  Windows implementation (`hxmc.rt.PosixSys`/`WinSys`,
  `PosixNet`/`WinNet`) by `Mem.os()`, `hxmc.Native` (reflection) calls
  `hxmc.rt.Dyn`, `hxmc.NativeZip` is the implementation, haxe.atomic's
  cells are written over `Atomic`. `hxmc.NativeGc`, `NativeSsl`,
  `NativeThread` and `NativeUv` remain externs of C functions (bound to
  Haxe implementations on WebAssembly, see "WebAssembly").

The modules with bound natives load with every program through
`std/Std.hx` (`import hxmc.rt.Runtime`; those classes are `@:keep`). A
change that needs new intrinsics and uses them at once needs a tool that
knows them: bootstrap (or build once against the previous std and runtime
object first). `tools/mkstd.py` still merges each override of an upstream
module with the original for Eval (`#if eval`): a custom target gets no
`_std` directory of its own in the reference compiler, and the macro
context shares the program's class paths.

| Haxe (`std/hxmc/rt`) | from | what stays in C, and why |
| --- | --- | --- |
| `Str.hx`: strings, UTF-8, comparison, hashing, concatenation, Int formatting, String/StringBuf/Std natives | `rt_str.c` | `hx_format_float` (in `rt_dyn.c`): shortest round-trip doubles through printf/strtod (WebAssembly's `wasm/FloatText.hx` writes and reads the same text in Haxe; the native targets keep the C library's) |
| `Dyn.hx`, `Types.hx`: structural and Dynamic access, inline-cache lookups, Dynamic operators, type tests, Std.string, reflection (`hxmc.Native`) | `rt_dyn.c` | the field-name table (interning under a lock, names outside the heap) and the per-thread inline-cache entries (until threads move) |
| `Arr.hx`, `Bytes.hx`, `Date.hx`, `hxmc/NativeZip.hx`: Array, haxe.io.Bytes, Date and Math.random natives, inflate and CRC-32 | `rt_std.c` | nothing |
| `PosixSys.hx`, `PosixNet.hx`: Sys, FileSystem, File, Process, sockets and host resolution over POSIX | `rt_sys.c`, `rt_net.c` | nothing (blocking waits go through the scheduler's `rt_wait_fd`/`rt_blocking_enter`) |
| `haxe/atomic/AtomicInt.hx`, `AtomicObject.hx`: the haxe.atomic cells over `Atomic` | `rt_thread.c` | the rest of `rt_thread.c`: see below |
| `WinSys.hx`, `WinNet.hx`: the same over the UCRT, kernel32 and Winsock (wide strings are Haxe's UTF-16 units) | `rt_sys_win.c`, `rt_net_win.c` | `rt_win.c`: the Winsock error mapping and WSAStartup, shared with TLS and the scheduler |

Still C (5.6k lines with the libc glue, from 11.7k; OS threads only, the
Emscripten, Cosmopolitan, tcc and green-thread variants inherited from hxc
are gone): the collector and allocator (`rt.c`), the libuv binding for eval.luv (`rt_uv.c`), TLS over
the platform's library (`rt_ssl.c`), the field names, inline-cache tables
and `hx_format_float` (`rt_dyn.c`), the heap census of a debug build
(`rt_census.c`: `HXMC_RT_CENSUS=1 hxmc/tools/mkrt.sh`, then `RT_CENSUS=1`),
and threads (`rt_thread.c`): thread start and exit,
the stop-the-world handshake with the collector (safepoints, safe regions,
root scanning of every thread), park/unpark, the main stack switch
(assembly shims, Windows fibers), and the mutex, condition and semaphore
natives. Those are pthread and SRW-lock objects (sizes and layouts differ
per C library), finalized by the collector, and the code is the
collector's other half; moving it means moving `rt.c` with it. The
collector itself stays C (stage 5b, judged not worthwhile): it
runs while no Haxe code may (the world is stopped, objects are being
moved), so it would need no-GC Haxe over raw memory with calls through
code pointers, its copying and scanning loops would at best match clang
-O2's, and it would have to move with the stop-the-world handshake of
`rt_thread.c`; nothing in speed or size would improve (allocation's fast
path is already inline code, and the roots are found through the shadow
stack either way).

Collapsing the extern and bound-implementation pairs into typed areas
(after stage 5a) left the generated code's instructions unchanged and
took 8 to 12 KB off every executable (port 19623 -> 19615 KB), 75 KB off
a small program's HXB (alloc 753 -> 677 KB) and up to 5% off builds
(port 6.29 -> 5.98 s, best of 5).

## Building

Run from the repository root (GNU make; zig and ld.lld build the runtime
objects; the reference compiler `haxe/haxe`, `make reference`):

```sh
make -f hxmc/Makefile             # bin/hxmc/hxmc: the tool, built by the previous tool from source (about 10 s)
make -f hxmc/Makefile fixpoint    # the tool rebuilt by itself twice: byte-identical
make -f hxmc/Makefile rt          # bin/hxmc/rt/<target>/rt.o for the six targets (the host's is built with the tool)
make -f hxmc/Makefile test        # the corpus against its golden files (RUN_ARGS="--target linux-arm64" ...)
make -f hxmc/Makefile portcheck   # the port built by hxmc self-compiles to the reference's HXB
python3 hxmc/tools/run.py --target windows-x86_64   # the corpus under wine64 (linux-arm64: qemu-aarch64-static)
python3 hxmc/tools/run.py --target macos-arm64 --stage <dir>   # cross: build only (any target)
python3 hxmc/tools/check.py <dir>  # on the target's machine: run the staged programs, compare outputs
python3 hxmc/tools/enctest.py --arch x64|a64   # encoders against llvm-mc
sh hxmc/tools/hxmc.sh <case>      # rerun hxmc on a corpus case (HXMC_DUMP=<function> prints its Mir)
python3 hxmc/bench/measure.py     # run time, size and build time of the benchmark cases
python3 hxmc/bench/rebuild.py     # cold / no-change / one-module-edit build times (--server: through the resident tool)
SMALL=1 sh hxmc/tools/portcheck.sh  # the port check, also with a 256 KB nursery
```

- The tool is the port (`src/`) with hxmc (`hxmc/src`) as its generate
  hook, typed against hxmc's std (`-D hih_no_generators`: without the
  port's other target generators). `make -f hxmc/Makefile` rebuilds it with
  the previous tool from source (`bin/hxmc/hxmc.new`, then moved over the
  running binary); a change to code generation reaches the tool's own code
  on the next rebuild, which `fixpoint` checks.
- Programs: `bin/hxmc/hxmc <out> <haxe arguments> -cp bin/hxmc/std
  --custom-target hxmc` (from source) or `bin/hxmc/hxmc <out> --hxb-lib
  <archive> -main <Main> --custom-target hxmc` (an archive written with
  `-cp bin/hxmc/std --custom-target hxmc=<dir> --hxb <archive>`), with
  `-D hxmc.target=<target>` to cross-build. The tool finds the runtime
  object next to itself (`bin/hxmc/rt/<target>/rt.o`; `HXMC_RT_OBJ`
  overrides).
- `HXMC_OPT=0` turns off Mir optimizations (`HXMC_LICM=0` only LICM,
  `HXMC_INLINE=<flat>,<loop>,<runtime flat>` the inlining limits;
  `HXMC_FALIGN`/`HXMC_FSHIFT` vary function alignment and padding to see
  how much a timing depends on code layout); `HXMC_SYMBOLS=1` (or
  `-debug`) writes a symbol table (profilers: `valgrind --tool=callgrind`);
  `HXMC_SIZE_STATS=1` prints the bytes of code by instruction kind, memory
  class, hot and cold blocks; `HXMC_LOWER_CHECK=1` (server) compares the
  executable built from cached bodies with one from a fresh lowering.
- Windows: `HXMC_MAP=<file>` writes the address of every symbol (PE files
  get no symbol table); a crash prints its exception and image offset
  (`rthxmc.c`, installed by a TLS callback; `HXMC_TRACE=1` also says the
  image started); `HXMC_PE_DIAG=<variant,...>` writes loader-bisecting
  variants (`lowbase`, `fixed`, `nopdata`, `bssdata`, `notls`, `ret42`).

### Bootstrap

The first tool comes from the reference compiler; nothing else is needed
but node (and hxnodejs) for one run:

```sh
make -f hxmc/Makefile bootstrap   # about 2 minutes
```

1. The reference compiler writes the tool as JavaScript
   (`bin/hxmc/boot/hxmc.js`: the port runs on node, with the
   single-threaded `sys.thread` and `sys.net` stand-ins of
   `tools/bootstrap/js`) and the tool's HXB archive
   (`bin/hxmc/boot/hxmc.hxb.zip`, typed against hxmc's std).
2. node runs the JavaScript tool on that archive (one thread, about a
   minute): `bin/hxmc/boot/hxmc1`, the first native tool.
3. `hxmc1` builds `bin/hxmc/hxmc` from source; from then on the tool
   rebuilds itself. (`hxmc1` itself differs from what native tools build,
   e.g. through JavaScript's integer arithmetic and map order in
   heuristics; the tool it builds is the fixpoint: `make -f hxmc/Makefile
   fixpoint` rebuilds it twice and compares.)

A previously built tool works as well (copy it to `bin/hxmc/hxmc`), as
long as it compiles the current sources correctly; after a change of the
runtime's interface or of the IR's conventions, bootstrap again. CI
(below) bootstraps on every run.

### Tests and their oracle

The corpus is the programs of `test/cases` (`<Name>.hx` with class
`<Name>`: small programs written for hxmc, and Bench, Exc and Regress,
copied from hxc's test programs) and 60 fuzzer programs (seed 1000 of
`bin/fuzz/fuzz --emit -n 60`, `test/fuzz-1000.tar.gz`, extracted to
`bin/hxmc-fuzz`). Each case's HXB is written once by the reference
compiler and cached; its output (`exit <code>` and stdout, run with a 64 KB
nursery so that a missing or stale root shows) must equal its golden file,
`test/expected/<case>.txt`. A corpus run takes 6 s.

The golden files are frozen: they are the outputs of the same programs
compiled by hxc (C by tcc) when hxmc was separated from it, the oracle
until then, which every target matched. The reference compiler's
`--interp` is not an oracle here: target-dependent behavior differs
(`Std.string` of a Bool in Dynamic context, array printing, ...; 39 of the
67 programs). A new case gets its golden file with `run.py --bless <case>`
(written from hxmc's output: check it by hand before committing); a
program whose output should change has its golden file edited, with the
reason in the commit. The fuzzer programs are frozen as sources, not
regenerated, so a change of the fuzzer does not change the corpus.

`RT_VERIFY=1` (every target; CI runs the corpus with it) fills the free
nursery with a byte pattern at startup and after every collection: an
allocation that is not initialized reads the pattern from its first use
instead of zeros before the first collection and the bytes of dead
objects after it, and a reference a collection did not see (a missing
root) reads it instead of the moved object's old copy. Its heap checks
(WebAssembly) cannot see the first kind: `Bytes.alloc` once returned
uninitialized bytes, which the crypto library's Sha512 reads as its zero
padding, so HaxeBenchmarks' sha512 gave wrong digests once the nursery had
been reused (correct with a nursery too large to collect); `Int64Gc`
covers it.

The port check: the port built by hxmc compiles its own source to HXB,
compared member by member with the reference's (also with
`RT_MINOR_KB=256`).

## Targets

Every target is cross-built on Linux: the tool, the runtime object of the
target (`hxmc/tools/mkrt.sh <target>`: `rt/` by zig cc, `-DHXMC_NO_SSL
-DHXMC_NO_UV`) and the programs; no C compiler, assembler, linker or SDK is
involved when a program is built.

| target | output | runtime object | thread-locals | checked |
| --- | --- | --- | --- | --- |
| linux-x86_64 | static ELF (Link) | musl, partially linked (ld.lld -r) | local-exec | corpus and port here and on CI |
| linux-arm64 | static ELF, 64K segments | musl | local-exec | corpus and port under qemu and on CI |
| windows-x86_64 | PE32+ at 0x400000 (LinkPE) | UCRT/MinGW-w64 COFF members (MkRt) | gs:[0x58][_tls_index] | corpus and port under wine and on CI |
| windows-arm64 | PE32+ at 0x140000000, base relocations | as x86-64, arm64 COFF | x18+0x58, [_tls_index] | CI (windows-11-arm) |
| macos-x86_64 | Mach-O, PIE (LinkMachO) | Mach-O objects merged (MkRt.macho), libSystem bound | TLV template | CI (macos-15-intel) |
| macos-arm64 | Mach-O, PIE, 16K pages, ad-hoc signed | as x86-64, arm64 | TLV template | CI (macos-15) |
| wasm32-wasi | WebAssembly module, WASI preview 1 (LinkWasm) | none: the runtime is Haxe | globals (one thread) | corpus under node 22 and wasmtime here and on CI |

- Windows: imports are written from the import libraries' members (DLL and
  name, `.hxmc.imports`), code imports through thunks; the C library's
  constructors (`.ctors`, winpthreads') run from `__CTOR_LIST__`, the TLS
  directory is MinGW's `_tls_used`. arm64 images must be relocatable and
  load only above 4 GB (a lower preferred base is refused with "not a valid
  Win32 application"), and the loader needs the import address table
  8-byte aligned (else STATUS_INSTRUCTION_MISALIGNMENT). setjmp/longjmp are
  MinGW's non-unwinding ones (`_setjmp(buf, NULL)`, `__mingw_setjmp`), so
  generated code needs no unwind information (none is written: .pdata
  covers the runtime only). Frames of a page or more probe each page.
- macOS: classic dyld information (rebase and bind opcodes; chained fixups
  are not needed for the minimum versions written, 11.0 arm64 / 10.15
  x86-64), non-lazy binding of everything libSystem provides (the runtime's
  undefined symbols and the C functions generated code calls; Mach-O names
  are the C names with `_`), an export trie with `__mh_execute_header`,
  LC_MAIN at the generated `main`, LC_UUID (a digest of the file),
  `MH_HAS_TLV_DESCRIPTORS` (dyld sets up `__thread_vars` only with it), and
  an ad-hoc, linker-signed code signature (CodeDirectory of SHA-256 hashes
  of 4K pages, the executable segment flagged as the main binary), which
  arm64 requires. Apple arm64 packs stack arguments by size (Isel). The
  runtime object is not garbage-collected by section (Mach-O objects have
  one `__text`; the whole runtime is linked).

### WebAssembly

`-D hxmc.target=wasm32-wasi` writes one WebAssembly module (32-bit memory,
WASI preview 1 imports, exception handling), built from Haxe alone: no C
compiler, no C runtime, no object reader or third-party linker. The program
must be typed for the target too (the HXB written with the same define:
`std/hxmc/rt/Runtime.hx` types the WebAssembly runtime only then, so native
programs' HXB is unchanged). Run it with
`wasmtime run -W exceptions=y --dir . m.wasm` or
`node --experimental-wasm-exnref --no-turbo-fast-api-calls tools/wasi.mjs m.wasm`
(node 22: exnref is behind a flag, and its WASI `fd_write` as a fast API
call can start a V8 collection that crashes with a large module memory).

- Code (`src/hxmc/wasm/WasmGen.hx`): from Mir after Opt and inlining, in
  place of instruction selection and register allocation. Control flow is
  structured over the dominator tree as in Ramsey's "Beyond Relooper"
  (merge nodes get a `block`, loop headers a `loop`, every branch a `br` to
  an enclosing label); SSA values become locals, colored in dominator order
  (not in functions with try blocks), and a value used once in its own block
  is folded onto the value stack (pure values always, loads when nothing is
  written in between); phi copies are parallel copies through the value
  stack on each edge. Pointers stay i64 in Mir and are wrapped to i32 at
  each memory access. Frame slots (`Mem.stack`, spills of references) live
  in a stack in linear memory (1 MB, `HXMC_WASM_STACK_KB`). `try` uses
  exception handling: setjmp returns 0, the try body (the dominator subtree
  of its first block) is wrapped in `try_table (catch_all)`, whose pad
  checks that the runtime's current handler is this one and otherwise
  rethrows; `rt_throw` throws the one tag.
- Relocations: function and type indices, globals and data addresses are
  written as padded LEBs (`Obj` kinds RWasmFunc, RWasmType, RWasmGlobal,
  RWasmAddr, RWasmAddr32) and re-encoded minimally at link time.
- Link (`src/hxmc/wasm/LinkWasm.hx`): what `_start` reaches, data from
  4 KB, then the runtime's cells and the frame stack, then `__heap_base`;
  a table of the functions whose address is taken (index 0 is null); each
  thread-local variable a global; memcpy/memmove/memset as `memory.copy`/
  `memory.fill`, the f64 rounding functions, fmin/fmax/copysign, memory.size
  and memory.grow written by the linker. `-debug` or `HXMC_SYMBOLS=1` adds
  a name section (stack traces in wasmtime). No object cache: modules are
  linked from the objects of the run.
- Runtime (`std/hxmc/rt/wasm`, classes marked `@:hxmc.wasm`, bound only
  for this target; the rest of the runtime in Haxe is shared): `Heap`
  (regions over `memory.grow`, malloc/free/realloc with power-of-two size
  classes), `Gc` (rt.c's collector single-threaded: the same object layout,
  write barrier, remembered set, nursery growth and copying old space,
  shadow-stack roots; `@:hxmc.collects` marks its entry points so that
  callers keep no frame slot in a register across them; `RT_STATS`,
  `RT_MINOR_KB`, `RT_OLD_MB` as natively, and `RT_VERIFY=1` checks the old
  space around each collection and that the barrier missed no young
  reference, and fills the free nursery with a pattern as natively, see
  "Tests and their oracle"), `Boxes` (boxes, array growth and stores), `Names` (field
  names and the inline-cache miss of rt_dyn.c), `FloatText` (strtod and
  `hx_format_float` on big integers: the same text as the C library's
  printf/strtod; 900k random doubles, short decimals and scaled values
  compared with the native output, identical), `LibM` (musl's sin, cos,
  tan, asin, acos, atan, atan2, exp, log, pow, fmod; its MIT notice in the
  file), `Libc` (rand, gmtime/localtime, mktime, clock_gettime), `Wasi`
  and `hxmc.rt.WasiSys` (NativeSys over WASI: arguments, environment, files
  and directories through the preopened directories, clocks),
  `Threads` (one thread), `NoSslUv` and `hxmc.rt.WasiNet` (failing stubs).
- Not available (each fails with an exception, or a socket error): threads
  (`Thread.create` throws; mutexes, locks and semaphores work for the one
  thread, waits nothing can end throw), sockets and host resolution (WASI
  preview 1 has none), processes (`Sys.command`, `sys.io.Process`), sys.ssl
  and eval.luv. Local time is UTC (no time zone database), finalisers are
  registered but never run, `Gc.objsize` throws. The corpus
  excludes ThreadNatives and NetNatives on this target (`run.py`).
  wasmtime refuses symbolic links to absolute paths inside a preopened
  directory (node follows them).
- The port builds as a module (`-D hxmc.target=wasm32-wasi` on its HXB as
  well; 17100 functions, 19.4 MB, 4.2 MB gzipped, built in 11 s) and
  compiles its own source to the reference's HXB, byte-identical, under
  node and wasmtime (also with 256 and 16 KB nurseries under node; CI runs
  it through `selfcheck.py --runner`). It takes 15.3-16.3 s under either
  engine against 8.4 s for the native x86-64 port. The site/ playground's
  Emscripten build of hxc's C (wasm64, clang -O2) took 9.0 s under node 24
  for the same workload (site/bench/results.json, 2026-10-09; native hxc
  with clang 5.2 s then) with a ~2 MB gzipped module: hxmc's module is
  about twice as large and 1.7-1.9x slower against native, as for the
  benchmarks below.
- The playground's configuration (2026-10-15, at 7738d9c; measured, no
  code generation changed): the port with `-D hih_no_generators
  -D disable-parallelism` (the Makefile's `web-c` arguments; hxc's
  `hxc/js` stand-ins are not needed) as a wasm32-wasi module is
  13,540,832 bytes, 3,092,150 gzipped (`gzip -9`), against 11,528,418 and
  2,245,711 for the deployed Emscripten module (origin/site-dist, hih.wasm
  of 2026-10-12: wasm64, clang -O2, C++ exceptions): 1.17x raw, 1.38x
  gzipped. It works (compiles and runs programs with `--interp`, compiles
  the port's source to the reference's HXB under node in about 20 s).
  Where the bytes go (`HXMC_SYMBOLS=1` for the name section, then the code
  section decoded instruction by instruction; the savings marked
  "simulated" are the module's bytes with the instructions in question
  removed or shortened, gzipped again):

  | | hxmc | Emscripten |
  | --- | ---: | ---: |
  | code | 11.57 MB (2.86 MB gzipped) | 10.45 MB (1.96 MB) |
  | data | 1.93 MB (0.21 MB) | 1.05 MB (0.27 MB) |
  | the rest (types, imports, table, ...) | 0.04 MB | 0.03 MB |
  | functions | 19,390 (8,274 of them allocation stubs) | 8,252 |

  Code by group: typing 22.5%, macros (the eval interpreter and the
  macro API) 15.8%, optimization, filters and coro 14.0%, core 12.6%,
  compiler (arguments, HXB, server) 8.2%, syntax 8.0%, context (common,
  display) 7.8%, codegen 3.4%, libs (swflib, ...) 2.5%, the runtime 3.4%
  (allocation stubs 174 KB, `hxmc.rt` 103 KB, entry points 120 KB), std
  1.5%. By instruction: `local.get` 25.1%, loads 10.7%, `local.set`
  10.3%, `i64.const` 8.2%, stores 7.7%, `i32.wrap_i64` 6.2% (714,987
  wraps), `i32.const` 5.6%, calls 4.5%, `br` 3.9%. The 817 functions with
  a `try` (4% of them) are 3.49 MB of code (30%) and declare 126,313 of
  the 180,103 locals (not coalesced): 253,540 bytes of two-byte local
  indices, 52 KB of local declarations. The data is 80% zero bytes, the
  upper halves of 8-byte slots holding 32-bit values for the most part
  (zero runs of 64 bytes or more: 816 KB); it gzips to 213 KB.

  What the planned changes would save (estimates, not additive in every
  detail): the i32 pointer type 715 KB raw (the wraps) but only 57 KB
  gzipped (simulated: they compress well); local coalescing in functions
  with a `try` about 300 KB raw (indices and declarations), 157 KB
  gzipped (simulated: every index in those functions one byte, as with
  fewer than 128 locals); size-aware inlining, at most what inlining
  costs: without it (`HXMC_INLINE=0,0,0`) 12,625,651 bytes, 2,799,906
  gzipped (-915 KB, -292 KB), with `4,16,0` -812 KB and -262 KB, while
  the port's self-compile under node takes the same time with all three
  (19.9-20.4 s; inlining buys the playground's workload nothing). The
  three together: about 11.6 MB raw (Emscripten's size) and 2.58 MB
  gzipped. Not in the plans yet: `local.set x; local.get x` written as
  `local.tee x` (188,150 pairs: -415 KB raw, -124 KB gzipped, simulated),
  data segments split at runs of zeros (about -0.75 MB raw, little
  gzipped), and the allocation stubs (21 bytes each) as direct calls of
  `hxmc_alloc_slow` from the cold sites. With these too: about 10.5 MB raw
  and 2.46 MB gzipped, still 10% above Emscripten's module gzipped: its
  code compresses better (1.96 MB against 2.86 MB for similar raw sizes;
  clang's inlining leaves fewer, larger functions).

Benchmarks (`hxmc/bench/measure.py -n 3 --target wasm32-wasi --runner
node|wasmtime`, best of 3, the same VM and session as the x86-64 column;
node 22.22 with the flags above, wasmtime 38.0.1; run times include each
engine's compilation of the module):

| case | x64 run | node run | wasmtime run | x64 size | wasm size | wasm build |
| --- | --- | --- | --- | --- | --- | --- |
| alloc | 1.42 | 1.71 | 1.71 | 97 | 85 | 0.14 |
| bcrypt | 2.88 | 3.16 | 3.94 | 340 | 325 | 0.15 |
| binarytrees | 0.70 | 1.08 | 1.01 | 96 | 80 | 0.14 |
| json | 0.43 | 0.71 | 0.66 | 170 | 163 | 0.17 |
| mandelbrot | 0.56 | 0.79 | 0.96 | 101 | 86 | 0.16 |
| mandelbrot_anon | 0.95 | 2.03 | 1.54 | 113 | 90 | 0.13 |
| nbody | 0.70 | 1.04 | 0.84 | 101 | 84 | 0.13 |
| sha256 | 0.16 | 0.30 | 0.30 | 310 | 293 | 0.14 |
| sha512 | 0.024 | 0.139 | 0.095 | 323 | 303 | 0.18 |
| formatter_noio | 5.65 | 7.75 | 7.73 | 1364 | 1345 | 0.52 |
| port (self-compile) | 8.4 | 15.3 | 15.6 | 19603 | 19891 | 10.6 |

Modules are a little smaller than the executables (no C runtime; the
Haxe runtime is compiled with the program and only what is reached is
kept); a hello world is about 37 KB. Run time is 1.2-2.1x x86-64's
(sha512's 0.1 s is mostly the engines' start-up), similar under both
engines. Builds take about as long as native ones for small programs;
the port takes 10.6 s against 7.7 s (WasmGen's code generation: 21 s of
CPU over the 4 jobs, not yet profiled).

### CI

`.github/workflows/hxmc.yml` runs on pushes to the hxmc branch: one Linux
job builds the reference compiler (cached with build.yml's key),
bootstraps the tool from it (`make -f hxmc/Makefile bootstrap`, node),
checks the fixpoint, builds the six runtime objects, cross-builds the
corpus (`run.py --stage`, with the golden files) and the port for every
target, and runs the reference's self-compile of the port in
`/Users/runner/hih`. A job per target then runs the corpus on a machine of
that target (`check.py`: ubuntu-24.04, ubuntu-24.04-arm, windows-2025,
windows-11-arm, macos-15-intel, macos-15) and the port's self-compile
(`selfcheck.py`): on macOS and Linux in the same directory, so the
archives must be byte-identical; on Windows, whose absolute paths differ,
identical once the root is replaced (`hxbcmp.py --roots`; the sources come
from Linux, as a Windows checkout has CRLF line ends). Failures land in
the job summary. Logs: `gh api repos/<owner>/<repo>/actions/jobs/<id>/logs`.

## Origin

hxmc began as a second back end of hxc (the C target, `hxc/` on main):
it read hxc's IR, used hxc's program-wide preparation and runtime, typed
programs against hxc's std, was built by hxc's tool, and its tests
compared with hxc's output. On 2026-10-14 it was separated (main at
1620799, branch hxmc at 7c74113):

| hxmc | from |
| --- | --- |
| `src/hxmc/ir/Ir.hx`, `Lower.hx`, `FnLower.hx` | `hxc/src/backend/` (package `backend`), with hxmc's `Lower.lowerBody` hook and the per-class subclass lists of `needsDispatch` that were branch-local edits of hxc's Lower |
| `src/hxmc/ir/Facts.hx` | the preparation part of `hxc/src/backend/EmitC.hx` (names, layouts, type indices, field ids, no-GC functions, cold sites, `Roots.gcPoint`/`nestedGc`); none of its C writing |
| `rt/` | `hxc/rt`, with `RT_CALL_ON_STACK` (main's stack switch without ucontext, for musl) and `rthxmc.c`/`rtlibc.c` (from `hxmc/tools`); externs renamed `hxc_Native*` -> `hxmc_Native*`, `HXC_NO_*` -> `HXMC_NO_*` |
| `std/`, `tools/mkstd.py` | `hxc/std` and `hxc/tools/mkstd.py`; package `hxc` -> `hxmc`, `target.name == "hxc"` -> `"hxmc"` |
| `tools/bootstrap/js` | `hxc/js` (the stand-ins of hxc's JavaScript tool) |
| `test/cases/Bench.hx`, `Exc.hx`, `Regress.hx` | `hxc/test`, `hxc/test/exc`, `hxc/test/regress` |
| `test/expected/` | hxc's outputs of the corpus (the oracle until then), frozen |

The development mode that wrote C for the functions hxmc did not compile
yet (hybrid builds, `HXMC_HYBRID`) was removed with it: every function
compiles natively. The port's sources know the target by name where they
use host natives (`#if (target.name == "hxc" || target.name == "hxmc")`
and the externs of either std, a branch-local change of `src/`). Fixes to
hxc's lowering or runtime on main no longer reach hxmc by themselves: they
are ported here by hand.

## Numbers (2026-10-14, one 4-core VM)

Run time (s, best of 3) and size (KB): hxc's C compiled by tcc and by
clang -O2 against the same runtime (clang -O2), dynamically linked with
glibc, stripped (measured with hxc before the separation; `measure.py` no
longer builds C); hxmc's static executables (musl, runtime included, no
symbol table; `hxmc/bench/measure.py -n 3`, after the separation, with the
self-built tool). Build: hxmc's cold build of the archive (4 jobs). Bold:
hxmc at least as fast as clang -O2. The VM is noisy (±3-5% between runs).

| case | run tcc | run O2 | run hxmc | size O2 | size hxmc | hxmc build |
| --- | --- | --- | --- | --- | --- | --- |
| alloc | 1.51 | 1.37 | 1.56 | 156 | 119 | 0.09 |
| bcrypt | 8.06 | 2.17 | 2.56 | 391 | 358 | 0.12 |
| binarytrees | 1.74 | 0.61 | 0.67 | 156 | 118 | 0.09 |
| json | 0.69 | 0.42 | 0.47 | 193 | 180 | 0.10 |
| mandelbrot | 2.94 | 0.46 | 0.50 | 156 | 119 | 0.09 |
| mandelbrot_anon | 4.71 | 1.26 | **0.98** | 164 | 135 | 0.11 |
| nbody | 1.92 | 0.74 | **0.64** | 160 | 118 | 0.09 |
| sha256 | 0.57 | 0.19 | **0.16** | 366 | 332 | 0.11 |
| sha512 | 0.082 | 0.022 | 0.024 | 374 | 345 | 0.11 |
| formatter_noio | 10.75 | 5.29 | 5.84 | 1366 | 1382 | 0.53 |
| port (self-compile) | 16.57 | 8.52 | **8.28** | 18100 | 19854 | 6.3 |

tcc sizes: 158-430 KB for the small cases, 2097 KB formatter, 35134 KB
port. The separation from hxc changed no executable: every case, the port
included, is byte-identical to what the hxc-built tool wrote before it
(re-measured the same day: run times within noise, e.g. port 7.9-8.6 s;
cold build of the port 7.9 s by the self-built tool, 8.5 s by the earlier
tool's clang -O2 build, in the same session). Across runs hxmc is within about ±10% of clang -O2 everywhere but
bcrypt (15-20% behind).

Rebuilds (`hxmc/bench/rebuild.py`; before the separation with the clang
-O2 build of the tool, the port also after it with the self-built tool,
in a busier session):

| program | cold | no change | one module edited |
| --- | --- | --- | --- |
| small (test/cases/Regress) | 0.09 s | 0.01 s | 0.08 s |
| port (404 modules) | 5.5 s (7.1 s) | 0.01 s (0.00 s) | 2.7 s (3.1 s) |
| port through the server (`--server`, from source) | 12.0 s | 1.95 s | 2.25 s |

For comparison hxc + tcc built the port in ~11 s. The one-edit floor is
the front half: loading and typing (or the server's checks, filters and
DCE, ~0.5 s), lowering (0.6-0.8 s; the server replays cached bodies,
`LowerCache`), the preparation (`ir.Facts`, 0.15 s), module keys (0.2 s), data and
link (0.25 s). Not pursued further.

What closed the gaps (this round):

- Run time: inlining of small functions (to depth 2, templates shared by
  the threads), Mir optimizations (value numbering by memory class and
  version, store forwarding, loop-invariant code motion of pure operations
  and loads that cannot fault, branches decided by dominating branches),
  load folding into compares and ALU operations, rotations and haxe.crypto's
  16-bit split additions recognised, lifetime holes in the register
  allocator, a word-at-a-time memcmp/bcmp and a small-size memset in the
  runtime object (musl's are byte loops).
- Size: section garbage collection of the runtime object, no symbol table
  unless asked, slow paths that spill into their function's frame instead
  of pushing one, one stub per allocation (header and size) instead of
  three immediates per site, shared epilogues, x + constant folded into
  memory operands. The port went from 23.5 MB to 19.9 MB (clang -O2:
  18.1 MB). `HXMC_SIZE_STATS=1` prints where the bytes are.
- Compile time: no quadratic passes (batched occupancy merges in the
  allocator, marks and arrays instead of int maps): single-thread code
  generation of the port 9.1 s -> ~7 s after inlining and Opt landed.

## Stack maps: tried and reverted (2026-10-14)

Stack maps replaced the shadow stack for generated code at e91b276 (root
slots in machine frames, frame records, a table of frame descriptors per
code region, frameless thunks recording the last frame before C calls,
entries saving and restoring that record for C's calls into Haxe; the
design and the follow-ups that would make it pay are in
[PLANS.md](PLANS.md), "Stack maps"). They gave little and were reverted
for the shadow stack, which WebAssembly needs anyway (it cannot walk its
own stack): one root mechanism for every target. Kept from that work:
rooted locals that never live at the same time share a slot of the
shadow-stack frame (`Roots.assign`), calls during which nothing collects
leave the slots' values in registers (`MIns.keepsFrame`), `Mem.alloc`
with constant arguments allocates inline, `hx_box_bool` is not a GC point.

Instructions (callgrind) and sizes: the shadow stack before stage 5a
(stage 4), with stack maps (the cleanup milestone eaf3aa6) and the shadow
stack again (with the pieces kept):

| case | stage 4 | stack maps | shadow stack again | size KB (maps -> again) |
| --- | --- | --- | --- | --- |
| mandelbrot_anon | 12.31 G | 11.62 G | 12.31 G | 125 -> 113 |
| binarytrees | 6.35 G | 6.25 G | 6.38 G | 108 -> 96 |
| formatter_noio | 40.68 G | 40.12 G | 40.76 G | 1368 -> 1364 |
| bcrypt | 26.92 G | 26.85 G | 26.92 G | 348 -> 340 |
| alloc | 3.269 G | 3.269 G | 3.269 G | 109 -> 97 |
| json | 3.753 G | 3.754 G | 3.759 G | 182 -> 170 |
| nbody | 9.91 G | 9.94 G | 9.91 G | 113 -> 101 |
| sha256 | 2.58 G | 2.61 G | 2.57 G | 322 -> 310 |
| port (self-compile) | 49.10 G | 49.46 G | 48.64 G | 19615 -> 19603 |

Small programs lose the walker and its tables (12 KB, page rounding
included); the port's slot sharing makes up for the descriptors. Run times
and builds are within this VM's noise either way (port: built in 7.7 s
against 8.0 s, best of 3).

## Step 0: how much optimization is needed (2026-10-13)

Measured with hxc, before hxmc was separated from it (`hxmc/bench/measure.py`
then also built C): each case lowered to C once by hxc; the runtime
compiled once with clang -O2 (green threads, so tcc's code links with it);
only the generated C changes. Seconds, best of 3, one 4-core VM.

| case | tcc | clang -O1 -fno-inline-functions | clang -O1 | clang -O2 | hxmc (first version) |
| --- | --- | --- | --- | --- | --- |
| alloc | 1.67 | 1.30 | 1.42 | 1.45 | 2.67 |
| bcrypt | 7.56 | 3.50 | 2.30 | 2.18 | 5.89 |
| binarytrees | 1.74 | 0.82 | 0.64 | 0.61 | 0.79 |
| json | 0.72 | 0.47 | 0.44 | 0.42 | 0.42 |
| mandelbrot | 3.03 | 1.10 | 0.37 | 0.45 | 1.15 |
| mandelbrot_anon | 4.59 | 1.49 | 1.16 | 1.13 | 2.78 |
| nbody | 2.45 | 0.82 | 0.74 | 0.66 | 1.19 |
| sha256 | 0.55 | 0.24 | 0.19 | 0.19 | 0.47 |
| sha512 | 0.114 | 0.034 | 0.020 | 0.017 | 0.045 |
| formatter_noio | 10.19 | 5.91 | 5.27 | 5.24 | 6.76 |
| port (self-compile to HXB) | 18.98 | 11.00 | 10.74 | 10.50 | 15.5 |

What this says:

- clang -O1 is as good as -O2 everywhere: no vectorization, unrolling or
  aggressive scheduling is needed. What -O1 has over tcc is register
  allocation, instruction selection, constant folding and CSE, and inlining.
- Inlining of small Haxe functions matters for the numeric cases
  (mandelbrot 3×, bcrypt and sha512 1.5×, binarytrees and mandelbrot_anon
  1.3×), not for the port, the formatter, json or alloc.

## Status

Future directions (compact strings, WebAssembly, Android, iOS, C interop,
graphics, runtime code generation, ...) are in [PLANS.md](PLANS.md).

Done:

- x86-64 Linux: 100% native (corpus: 7 programs and 60 fuzzer programs,
  6550 functions; port: 16456), static executables from hxmc's own linker
  with the musl runtime object; outputs identical to the golden files
  (hxc's outputs when hxmc was separated from it); the port
  self-compiles to byte-identical HXB (514 modules), also with a 256 KB
  nursery (`hxmc/tools/portcheck.sh`).
- arm64 Linux: corpus passes under qemu and on arm64 hardware (CI); the
  arm64 port self-compiles to identical HXB.
- x86-64 Windows (PE, imports from kernel32/ws2_32/UCRT written directly):
  corpus passes under wine and on Windows (CI); the port self-compiles to
  the reference's HXB (roots normalized: Windows paths).
- arm64 Windows (PE32+ for AArch64, base relocations): corpus passes and
  the port self-compiles on windows-11-arm (CI).
- x86-64 and arm64 macOS (Mach-O from hxmc's own linker, libSystem, ad-hoc
  code signature): corpus passes and the port self-compiles to
  byte-identical HXB on macos-15-intel and macos-15 (CI).
- Optimizations: inlining, value numbering, store forwarding, LICM,
  dominating-branch folding, load folding, lifetime holes, scalars in try
  functions kept in memory only when a handler or what follows can see
  them; run time near clang -O2 on hxc's C (table above).
- Size: runtime section GC, allocation stubs, frame spills, merged
  returns; the port is 10% larger than clang -O2's.
- Rebuilds: per-module object cache keyed by fingerprints, whole-build
  skip, parallel code generation; resident mode (`hxmc --server`, the
  port's compilation server) with cached objects and cached lowered bodies
  (`LowerCache`, through the `Lower.lowerBody` hook).
- Self-contained and self-hosting: own IR, lowering, runtime and std
  (nothing from `hxc/`); the tool builds itself (a fixpoint after one
  rebuild), bootstrapped from the reference compiler through node.

Deferred:

- Incremental rebuilds beyond what is there: the one-edit floor (2.7 s, 2.25 s
  through the server) is the front half (typing, lowering, the
  preparation, keys, data, link), not code generation.
- Program-level dead code, data-table compaction and runtime member
  selection beyond section GC (size).
- Haxelib packaging, APE (cosmopolitan) builds; iOS/Android (the hooks
  above), chained fixups and a section-split runtime on macOS, unwind
  information for generated code on Windows.
- Thread-locals on macOS and Windows arm64 cost a call (macOS:
  `hxmc_tls_base`, through the TLV thunk) or three loads per function using
  them; an inline TLV thunk call and the 12-bit offset form when the TLS
  area is small would trim that.
- C interop design (calling C libraries from generated code beyond the
  runtime's own functions); mbedtls/libuv in the runtime objects (built
  with `HXMC_NO_SSL`/`HXMC_NO_UV`).
