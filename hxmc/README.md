# hxmc: Haxe to machine code

hxmc is a custom target that turns a typed Haxe program (the HXB archive
your Haxe writes) into a native executable with its own code generator and
linker: no C compiler, assembler or system linker at build time. It shares
its front half with [hxc](../hxc/README.md): the HXB reader, the lowering to
hxc's IR (`backend.Lower`/`FnLower`, `backend.Ir`) and EmitC's
program-wide preparation (layouts, type indices, field ids, no-GC
functions, cold sites, shadow-stack roots), so native code follows the same
conventions as hxc's C and runs on the same runtime (`hxc/rt`), which is
compiled ahead of time per target into one relocatable object
(`tools/mkrt.sh`).

Status: development. Every function of the port and of the test corpus
compiles natively for the six desktop targets: x86-64 and arm64 Linux
(static ELF, own linker, musl), x86-64 and arm64 Windows (PE, imports
written directly) and x86-64 and arm64 macOS (Mach-O against libSystem,
ad-hoc signed); the port built by hxmc compiles itself to byte-identical
HXB (see "Targets" for how each is checked). Run time is near clang -O2 on
hxc's C, executables are about 10% larger than clang -O2's dynamic ones
(static, runtime included). Stack maps, deeper incremental rebuilds, the
haxelib, APE builds and C interop are deferred (see "Status").

## Design

```
HXB --(port: --hxb-lib)--> typed AST --(backend.Lower)--> hxc IR --(Prep: EmitC's preparation)
    --(MirBuild)--> Mir (SSA) --(Opt)--> --(x64|a64/Isel)--> LIR --(Regalloc)--> --(Emit, Asm)--> Obj (per module, cached)
    --(DataGen: tables, strings)--> Obj
    --(Link: ELF | LinkPE: PE | LinkMachO: Mach-O, with the runtime object)--> executable
```

| File | |
| --- | --- |
| `src/hxmc/Main.hx`, `Options.hx`, `Driver.hx` | the tool: runs the port's compiler with a generate hook, then compiles every module (in parallel, cached) and links; `--server` keeps the port's compilation server resident (objects kept in memory) |
| `src/hxmc/LowerCache.hx` | resident builds: lowered function bodies reused while the server keeps their fields, through hxc's opt-in `Lower.lowerBody` hook (calls into the lowering replayed, objects rebound) |
| `src/hxmc/UpToDate.hx`, `Fingerprint.hx` | rebuilds: the whole build is skipped when archive (its ZIP directory), arguments and tool are unchanged; otherwise each module's object is reused when its fingerprint (its IR plus what its code reads of the rest of the program) is unchanged |
| `src/hxmc/Prep.hx` | EmitC's preparation (without writing C): the numbers native code and the runtime agree on, as symbols |
| `src/hxmc/Mir.hx`, `MirBuild.hx` | the machine-independent SSA IR and its construction from hxc's IR (Braun et al. on the structured statements); expands the runtime's inline helpers (allocation, write barrier, array access, inline caches) as EmitC's C does; tags loads and stores with a memory class |
| `src/hxmc/Opt.hx`, `Inline.hx` | machine-independent optimizations: inlining of small functions, global value numbering over the dominator tree (loads by memory class and version), store forwarding, loop-invariant code motion, branches decided by dominating branches, dead code |
| `src/hxmc/Lir.hx`, `Regalloc.hx` | target instructions over virtual registers; linear-scan allocation with lifetime holes, spill weights by loop depth, fixed ranges for physical registers, caller-saved registers kept across slow-path calls (saved around them) |
| `src/hxmc/x64/`, `src/hxmc/a64/` | x86-64 and AArch64: instruction selection (System V, Win64, AAPCS64), encoders (checked against llvm-mc), emission (frames, jump tables, constant pools) |
| `src/hxmc/Obj.hx`, `ElfWriter.hx`, `ElfReader.hx`, `CoffReader.hx`, `MachOReader.hx` | relocatable objects in memory, ELF output, ELF/COFF/Mach-O input |
| `src/hxmc/DataGen.hx` | the program's data: type tables, dispatch rows, strings, globals, and the absolute symbols of program-wide numbers |
| `src/hxmc/Link.hx`, `LinkPE.hx`, `LinkMachO.hx`, `A64Reloc.hx`, `MkRt.hx` | the linkers (static ELF; PE with import tables written directly, TLS directory, .pdata, base relocations on arm64; Mach-O with dyld's rebase/bind opcodes, stubs, TLV descriptors and an ad-hoc code signature) and the runtime-object builder (COFF member selection, COMDAT, imports; Mach-O objects merged) |
| `src/hxmc/Target.hx`, `Abi.hx` | per-target facts and the code-generator factory |
| `src/hxmc/CWriter.hx` | development builds: the C of what hxmc does not generate (none left) |

Conventions shared with hxc:

- GC roots: reference locals live across a GC point are shadow-stack slots
  (`fr[k]`, `EmitC.Roots`); cold sites (`SCold`) store the live references
  on the shadow stack only on the slow path (in spare slots of the
  function's frame when it has one). No stack maps (deferred).
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
- Symbols are the C names everywhere; Mach-O's leading underscore is
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
  be a separate structured code generator from hxc's IR (which keeps the
  structured control flow) or Mir, with linear memory and the shadow stack.
- Native macros / hot reload: a module compiles to an in-memory `Obj`
  (code, data, relocations) independent of file writing and linking, which
  a loader could relocate against live addresses; program-wide numbers stay
  symbolic so a runtime could register new types and dispatch entries and
  resolve them at load time; link-time dead-code elimination and table
  compaction belong in the linker, not in code generation. Stack-map frame
  descriptors, when they land, are to be registrable per code region.

## Iteration loop

```sh
make hxmc-dev                     # bin/hxmc/hxmc: the tool by the native hxc tool and tcc (seconds)
make hxmc-fast                    # bin/hxmc-fast/hxmc: the same C by clang -O2 (the speed users get)
sh hxmc/tools/mkrt.sh linux-x86_64   # bin/hxmc/rt/<target>/rt.o: the runtime object (zig cc -O2), once per target (any of the six)
python3 hxmc/tools/run.py --fuzz bin/hxmc-fuzz   # corpus + fuzz programs: hxc vs hxmc output (byte comparison), % native
python3 hxmc/tools/run.py --target linux-arm64 --fuzz bin/hxmc-fuzz     # under qemu-aarch64-static
python3 hxmc/tools/run.py --target windows-x86_64 --fuzz bin/hxmc-fuzz  # under wine64
python3 hxmc/tools/run.py --target macos-arm64 --fuzz bin/hxmc-fuzz --stage <dir>  # cross: build only (any target)
python3 hxmc/tools/check.py <dir>  # on the target's machine: run the staged programs, compare outputs
python3 hxmc/tools/enctest.py --arch x64|a64   # encoders against llvm-mc
sh hxmc/tools/hxmc.sh <case>      # rerun hxmc on a corpus case (HXMC_DUMP=<function> prints its Mir)
python3 hxmc/bench/measure.py -v tcc,O2,hxmcs   # run time and size against hxc's C (tcc, clang -O2)
python3 hxmc/bench/rebuild.py --tool bin/hxmc-fast/hxmc   # cold / no-change / one-module-edit build times (--server: through the resident tool)
SMALL=1 sh hxmc/tools/portcheck.sh  # the port built by hxmc self-compiles to the reference's HXB (also with a 256 KB nursery)
```

- Test cases are `test/cases/*.hx`, the hxc test programs listed in
  `run.py`, and fuzzer programs (`bin/fuzz/fuzz --emit bin/hxmc-fuzz -n 60`).
  Each case's HXB is written once by the reference compiler and cached; the
  oracle is the same archive compiled by hxc (tcc). A corpus run takes 4 s.
- The port check: the port built by hxmc compiles its own source to HXB,
  compared member by member with the reference's (also with
  `RT_MINOR_KB=256`, which makes missing or stale roots crash quickly).
- `HXMC_OPT=0` turns off Mir optimizations (`HXMC_LICM=0` only LICM,
  `HXMC_INLINE=<flat>,<loop>` the inlining limits); `HXMC_SYMBOLS=1` (or
  `-debug`) writes a symbol table (profilers: `valgrind --tool=callgrind`);
  `HXMC_SIZE_STATS=1` prints the bytes of code by instruction kind, memory
  class, hot and cold blocks; `HXMC_LOWER_CHECK=1` (server) compares the
  executable built from cached bodies with one from a fresh lowering.
- Hybrid development builds (`HXMC_HYBRID=1`) write C for what hxmc does not
  compile and link with the system's compiler; `HXMC_ONLY`/`HXMC_SKIP`
  select the functions compiled natively (bisecting).
- Windows: `HXMC_MAP=<file>` writes the address of every symbol (PE files
  get no symbol table); a crash prints its exception and image offset
  (`rthxmc.c`, installed by a TLS callback; `HXMC_TRACE=1` also says the
  image started); `HXMC_PE_DIAG=<variant,...>` writes loader-bisecting
  variants (`lowbase`, `fixed`, `nopdata`, `bssdata`, `notls`, `ret42`).

## Targets

Every target is cross-built on Linux: the tool, the runtime object of the
target (`hxmc/tools/mkrt.sh <target>`, zig cc) and the programs; no C
compiler, assembler, linker or SDK is involved when a program is built.

| target | output | runtime object | thread-locals | checked |
| --- | --- | --- | --- | --- |
| linux-x86_64 | static ELF (Link) | musl, partially linked (ld.lld -r) | local-exec | corpus and port here and on CI |
| linux-arm64 | static ELF, 64K segments | musl | local-exec | corpus and port under qemu and on CI |
| windows-x86_64 | PE32+ at 0x400000 (LinkPE) | UCRT/MinGW-w64 COFF members (MkRt) | gs:[0x58][_tls_index] | corpus and port under wine and on CI |
| windows-arm64 | PE32+ at 0x140000000, base relocations | as x86-64, arm64 COFF | x18+0x58, [_tls_index] | CI (windows-11-arm) |
| macos-x86_64 | Mach-O, PIE (LinkMachO) | Mach-O objects merged (MkRt.macho), libSystem bound | TLV template | CI (macos-15-intel) |
| macos-arm64 | Mach-O, PIE, 16K pages, ad-hoc signed | as x86-64, arm64 | TLV template | CI (macos-15) |

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

### CI

`.github/workflows/hxmc.yml` runs on pushes to the hxmc branch: one Linux
job builds the reference compiler (cached with build.yml's key), the
native tool (cached by its sources), hxmc and the six runtime objects,
writes the corpus' HXB and hxc's outputs (`run.py --stage`, 7 programs and
60 fuzzer programs of seed 1000), cross-builds the corpus and the port for
every target, and the reference's self-compile of the port in
`/Users/runner/hih`. A job per target then runs the corpus on a machine of
that target (`check.py`: ubuntu-24.04, ubuntu-24.04-arm, windows-2025,
windows-11-arm, macos-15-intel, macos-15) and the port's self-compile
(`selfcheck.py`): on macOS and Linux in the same directory, so the
archives must be byte-identical; on Windows, whose absolute paths differ,
identical once the root is replaced (`hxbcmp.py --roots`; the sources come
from Linux, as a Windows checkout has CRLF line ends). Failures land in
the job summary. Logs: `gh api repos/<owner>/<repo>/actions/jobs/<id>/logs`.

## Numbers (2026-10-14, one 4-core VM)

Run time (s, best of 3, `hxmc/bench/measure.py -n 3 -v tcc,O2,hxmcs`) and
size (KB): hxc's C compiled by tcc and by clang -O2 against the same
runtime (clang -O2), dynamically linked with glibc, stripped; hxmc's
static executables (musl, runtime included, no symbol table). Build:
hxmc's cold build of the archive (bin/hxmc-fast, 4 jobs). Bold: hxmc at
least as fast as clang -O2. The VM is noisy (±3-5% between runs).

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
port. Across runs hxmc is within about ±10% of clang -O2 everywhere but
bcrypt (15-20% behind).

Rebuilds (`hxmc/bench/rebuild.py`, bin/hxmc-fast):

| program | cold | no change | one module edited |
| --- | --- | --- | --- |
| small (hxc/test/regress) | 0.09 s | 0.01 s | 0.08 s |
| port (404 modules) | 5.5 s | 0.01 s | 2.7 s |
| port through the server (`--server`, from source) | 12.0 s | 1.95 s | 2.25 s |

For comparison hxc + tcc builds the port in ~11 s. The one-edit floor is
the front half: loading and typing (or the server's checks, filters and
DCE, ~0.5 s), lowering (0.6-0.8 s; the server replays cached bodies,
`LowerCache`), EmitC's preparation (0.15 s), module keys (0.2 s), data and
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
  three immediates per site, one return block per function with a frame,
  shared epilogues, x + constant folded into memory operands. The port went
  from 23.5 MB to 19.9 MB (clang -O2: 18.1 MB). `HXMC_SIZE_STATS=1` prints
  where the bytes are: the shadow stack (frame slot loads and stores,
  thread-local push and pop) is the largest remaining item, about 3 MB.
- Compile time: no quadratic passes (batched occupancy merges in the
  allocator, marks and arrays instead of int maps): single-thread code
  generation of the port 9.1 s -> ~7 s after inlining and Opt landed.

## Stack maps: what the shadow stack costs (2026-10-14)

Upper bound, measured before building stack maps: each case built normally
and with `HXMC_NOSHADOW=1` (no shadow-stack frames: references stay in SSA
values; correct only while nothing collects), both run with a 6-10 GB
nursery so that nothing collects (`RT_STATS` shows 0 collections).
Instructions executed (callgrind; wall time is dominated by page faults
of the huge nursery in this setup):

| case | with frames | without | saved |
| --- | --- | --- | --- |
| mandelbrot_anon | 13.39 G | 10.56 G | 21% |
| binarytrees | 6.18 G | 5.51 G | 11% |
| formatter_noio | 42.16 G | 38.21 G | 9% |
| json | 4.39 G | 4.23 G | 4% |
| alloc | 9.42 G | 9.42 G | 0% |
| nbody | 10.19 G | 10.19 G | 0% |

Stack maps keep part of this (references live across calls still go to
frame slots, but no frame push/pop, no stores of unchanged references, no
reloads after calls that do not collect): deferred. Code size adds to the
case: the shadow stack's frame traffic and thread-local push/pop are about
3 MB of the port's 18 MB of code (`HXMC_SIZE_STATS=1`).

## Step 0: how much optimization is needed (2026-10-13)

`hxmc/bench/measure.py`: each case lowered to C once by hxc; the runtime
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

Done:

- x86-64 Linux: 100% native (corpus: 67 programs plus 90 fuzzer programs,
  18014 functions; port: 16456), static executables from hxmc's own linker
  with the musl runtime object; outputs identical to hxc's; the port
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
  (`LowerCache`, through hxc's opt-in `Lower.lowerBody` hook).

Deferred:

- Stack maps (frame descriptors instead of the shadow stack): measured at
  5-10% run time on allocation-heavy code and about 3 MB of the port's
  code (the largest size item left); design in "Stack maps" above.
- Incremental rebuilds beyond what is there: the one-edit floor (2.7 s, 2.25 s
  through the server) is the front half (typing, lowering, EmitC's
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
  with `HXC_NO_SSL`/`HXC_NO_UV`).
