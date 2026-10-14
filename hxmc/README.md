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
compiles natively on x86-64 Linux (static ELF, own linker, musl), arm64
Linux and x86-64 Windows (PE); the port built by hxmc compiles itself to
byte-identical HXB. macOS, Windows arm64 and the haxelib are on hold (see
"Status").

## Design

```
HXB --(port: --hxb-lib)--> typed AST --(backend.Lower)--> hxc IR --(Prep: EmitC's preparation)
    --(MirBuild)--> Mir (SSA) --(Opt)--> --(x64|a64/Isel)--> LIR --(Regalloc)--> --(Emit, Asm)--> Obj (per module, cached)
    --(DataGen: tables, strings)--> Obj
    --(Link: ELF | LinkPE: PE, with the runtime object)--> executable
```

| File | |
| --- | --- |
| `src/hxmc/Main.hx`, `Options.hx`, `Driver.hx` | the tool: runs the port's compiler with a generate hook, then compiles every module (in parallel, cached) and links |
| `src/hxmc/UpToDate.hx`, `Fingerprint.hx` | rebuilds: the whole build is skipped when archive (its ZIP directory), arguments and tool are unchanged; otherwise each module's object is reused when its fingerprint (its IR plus what its code reads of the rest of the program) is unchanged |
| `src/hxmc/Prep.hx` | EmitC's preparation (without writing C): the numbers native code and the runtime agree on, as symbols |
| `src/hxmc/Mir.hx`, `MirBuild.hx` | the machine-independent SSA IR and its construction from hxc's IR (Braun et al. on the structured statements); expands the runtime's inline helpers (allocation, write barrier, array access, inline caches) as EmitC's C does; tags loads and stores with a memory class |
| `src/hxmc/Opt.hx` | machine-independent optimizations: global value numbering over the dominator tree (loads by memory class and version), dead code |
| `src/hxmc/Lir.hx`, `Regalloc.hx` | target instructions over virtual registers; linear-scan allocation with lifetime holes, spill weights by loop depth, fixed ranges for physical registers, caller-saved registers kept across slow-path calls (saved around them) |
| `src/hxmc/x64/`, `src/hxmc/a64/` | x86-64 and AArch64: instruction selection (System V, Win64, AAPCS64), encoders (checked against llvm-mc), emission (frames, jump tables, constant pools) |
| `src/hxmc/Obj.hx`, `ElfWriter.hx`, `ElfReader.hx`, `CoffReader.hx` | relocatable objects in memory, ELF/COFF input and output |
| `src/hxmc/DataGen.hx` | the program's data: type tables, dispatch rows, strings, globals, and the absolute symbols of program-wide numbers |
| `src/hxmc/Link.hx`, `LinkPE.hx`, `MkRt.hx` | the linkers (static ELF; PE with import tables written directly, TLS directory, .pdata) and the runtime-object builder (COFF member selection, COMDAT, imports) |
| `src/hxmc/Target.hx`, `Abi.hx` | per-target facts and the code-generator factory |
| `src/hxmc/CWriter.hx` | development builds: the C of what hxmc does not generate (none left) |

Conventions shared with hxc:

- GC roots: reference locals live across a GC point are shadow-stack slots
  (`fr[k]`, `EmitC.Roots`); cold sites (`SCold`) store the live references
  on the shadow stack only on the slow path. No stack maps (yet: queued).
- Exceptions: `try` is the runtime's `rt_handler` with the C library's
  `_setjmp` (jmp_buf layout per target); in functions with a `try` every
  local lives in memory, so its value survives the second return of setjmp.
- Calls follow the C ABI of the target; generated functions use it too.
- Thread-local runtime state (`rt_sp`, `rt_young_ptr`, ...) is reached with
  the local-exec TLS model on Linux, `_tls_index` + section offsets on Windows.
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
  addresses, so only the linker depends on the model (it refuses PIC
  output explicitly until it writes GOT/PLT, dynamic relocations and
  `DT_NEEDED`/`LC_LOAD_DYLIB`).
- TLS model: `Abi.tls` (`LocalExec` now; `InitialExec`, `Desc` (TLSDESC),
  `MachoTlv`, `WinTlsIndex`); instruction selection fails explicitly on a
  model it does not implement.
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
sh hxmc/tools/mkrt.sh linux-x86_64   # bin/hxmc/rt/<target>/rt.o: the runtime object (zig cc -O2, musl), once per target
python3 hxmc/tools/run.py --fuzz bin/hxmc-fuzz   # corpus + fuzz programs: hxc vs hxmc output (byte comparison), % native
python3 hxmc/tools/run.py --target linux-arm64 --fuzz bin/hxmc-fuzz     # under qemu-aarch64-static
python3 hxmc/tools/run.py --target windows-x86_64 --fuzz bin/hxmc-fuzz  # under wine64
python3 hxmc/tools/enctest.py --arch x64|a64   # encoders against llvm-mc
sh hxmc/tools/hxmc.sh <case>      # rerun hxmc on a corpus case (HXMC_DUMP=<function> prints its Mir)
python3 hxmc/bench/measure.py -v tcc,O2,hxmcs   # run time and size against hxc's C (tcc, clang -O2)
python3 hxmc/bench/rebuild.py --tool bin/hxmc-fast/hxmc   # cold / no-change / one-module-edit build times
```

- Test cases are `test/cases/*.hx`, the hxc test programs listed in
  `run.py`, and fuzzer programs (`bin/fuzz/fuzz --emit bin/hxmc-fuzz -n 60`).
  Each case's HXB is written once by the reference compiler and cached; the
  oracle is the same archive compiled by hxc (tcc). A corpus run takes 4 s.
- The port check: the port built by hxmc compiles its own source to HXB,
  compared member by member with the reference's (also with
  `RT_MINOR_KB=256`, which makes missing or stale roots crash quickly).
- `HXMC_OPT=0` turns off Mir optimizations; `HXMC_SYMBOLS=1` (or `-debug`)
  writes a symbol table (profilers: `valgrind --tool=callgrind`).
- Hybrid development builds (`HXMC_HYBRID=1`) write C for what hxmc does not
  compile and link with the system's compiler; `HXMC_ONLY`/`HXMC_SKIP`
  select the functions compiled natively (bisecting).

## Numbers (2026-10-13, one 4-core VM)

Run time (s, best of 3) and size (KB) per case; hxc's C by tcc and by
clang -O2 against the same runtime (clang -O2), dynamically linked with
glibc and stripped; hxmc's static executables (musl, runtime included, no
symbol table). Build: hxmc's cold build of the archive (bin/hxmc-fast).

| case | run tcc | run O2 | run hxmc | size tcc | size O2 | size hxmc | hxmc build |
| --- | --- | --- | --- | --- | --- | --- | --- |
| alloc | 1.43 | 1.36 | 1.76 | 158 | 156 | 431 | 0.08 |
| bcrypt | 7.74 | 2.05 | 2.54 | 430 | 391 | 674 | 0.12 |
| binarytrees | 1.67 | 0.67 | **0.63** | 157 | 156 | 430 | 0.08 |
| json | 0.68 | 0.45 | **0.42** | 220 | 193 | 472 | 0.09 |
| mandelbrot | 2.73 | 0.43 | 0.78 | 163 | 156 | 431 | 0.09 |
| mandelbrot_anon | 4.45 | 1.21 | **1.05** | 171 | 164 | 435 | 0.07 |
| nbody | 2.23 | 0.68 | 0.68 | 167 | 160 | 435 | 0.08 |
| sha256 | 0.53 | 0.19 | 0.22 | 376 | 366 | 648 | 0.09 |
| sha512 | 0.078 | 0.019 | 0.029 | 396 | 374 | 653 | 0.11 |
| formatter_noio | 9.68 | 4.59 | 5.41 | 2097 | 1366 | 1734 | 0.22 |
| port (self-compile) | 16.2 | 7.02 | 8.85 | 35134 | 18100 | 22642 | 4.9 |

Notes:

- The C was generated from source; through HXB (what hxc's haxelib and
  hxmc read) `haxe.ds.Vector` reads lose their `VectorData` typedef and
  become bounds-checked (`EArrGet` instead of `EArrGetU`), which costs
  bcrypt and sha a compare and branch per access. (A port/HXB question, not
  hxmc's.)
- alloc is slower with the static musl runtime than with glibc (1.35 s in a
  hybrid build against glibc): the runtime's libc functions.
- Sizes: hxmc's include the whole runtime (static) and no dead-code
  elimination yet; O2's are dynamic. Size work is next to performance.

Rebuild times (`hxmc/bench/rebuild.py`, bin/hxmc-fast, 4 jobs):

| program | cold | no change | one module edited |
| --- | --- | --- | --- |
| small (hxc/test/regress) | 0.10 s | 0.01 s | 0.10 s |
| port (404 modules) | 4.85 s | 0.01 s | 2.6 s |

For comparison hxc + tcc builds the port in ~11 s (10 s C generation + 1 s
tcc). The one-edit floor is the front half, not code generation: the port
loading the archive and typing it (1.1 s), lowering (0.7 s), EmitC's
preparation (0.13 s), module keys and cached-object reads (0.25 s,
parallel), data and link (0.2 s). Getting it under 1 s needs a resident
process (the port's compilation server keeping modules) or incremental
lowering: not done yet.

Compile-speed work so far: code generation went from 1.3 ms to ~0.4 ms per
function single-threaded (sparse liveness, no quadratic passes, scratch
arrays reused across functions, GC settings: the tool re-executes itself
with a 32 MB nursery and a 2 GB first old-space limit, which saves most
collections), modules compile in parallel, keys and cached reads are
parallel, and an unchanged build is skipped from the archive's ZIP
directory.

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
reloads after calls that do not collect): worth building, after the
current performance work.

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

- x86-64 Linux: 100% native (corpus: 64 programs, 7103 functions; port:
  16456), static executables from hxmc's own linker with the musl runtime
  object; outputs identical to hxc's; the port self-compiles to
  byte-identical HXB (514 modules), also with a 256 KB nursery.
- arm64 Linux: corpus passes under qemu; the arm64 port self-compiles to
  identical HXB.
- x86-64 Windows (PE, imports from kernel32/ws2_32/UCRT written directly):
  corpus passes under wine.
- Not yet: mbedtls/libuv in the runtime objects (built with
  `HXC_NO_SSL`/`HXC_NO_UV`), macOS (Mach-O + ad-hoc signature), Windows
  arm64, the haxelib (on hold).
- Next: inlining of small functions, loop-invariant code motion, then
  stack maps (measured first); link-time dead-code elimination and runtime
  member selection (size); the one-edit rebuild floor.
