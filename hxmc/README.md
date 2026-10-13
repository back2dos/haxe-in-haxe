# hxmc: Haxe to machine code

hxmc is a custom target that turns a typed Haxe program (the HXB archive
your Haxe writes) into a native executable with its own code generator and
linker: no C compiler, assembler or system linker at build time. It shares
its front half with [hxc](../hxc/README.md): the HXB reader, the lowering to
hxc's IR (`backend.Lower`/`FnLower`, `backend.Ir`) and EmitC's
program-wide preparation (layouts, type indices, field ids, no-GC
functions, cold sites, shadow-stack roots), so native code follows the same
conventions as hxc's C and runs on the same runtime (`hxc/rt`).

Status: development. x86-64 Linux compiles every function of the port and
of the test corpus natively; the port built by hxmc compiles itself to
byte-identical HXB. Development builds still use the system's C compiler
for the data tables and to link (see "Status").

## Design

```
HXB --(port: --hxb-lib)--> typed AST --(backend.Lower)--> hxc IR
    --(MirBuild)--> Mir (SSA) --(x64/Isel)--> LIR --(Regalloc)--> --(x64/Emit, x64/Asm)--> Obj
    --(ElfWriter)--> .o   (later: Link -> executable)
```

| File | |
| --- | --- |
| `src/hxmc/Main.hx`, `Options.hx`, `Driver.hx` | the tool: runs the port's compiler with a generate hook, then compiles every function |
| `src/hxmc/Prep.hx` | EmitC's preparation (without writing C): the numbers native code and the runtime agree on |
| `src/hxmc/Mir.hx`, `MirBuild.hx` | the machine-independent SSA IR and its construction from hxc's IR (Braun et al. on the structured statements); expands the runtime's inline helpers (allocation, write barrier, array access, inline caches) as EmitC's C does |
| `src/hxmc/Lir.hx`, `Regalloc.hx` | target instructions over virtual registers; linear-scan allocation with fixed ranges for physical registers and iterative spilling |
| `src/hxmc/x64/` | x86-64: instruction selection (System V ABI), encoder, emission (frames, jump tables, constant pool) |
| `src/hxmc/Obj.hx`, `ElfWriter.hx`, `Buf.hx` | relocatable objects in memory, ELF output |
| `src/hxmc/CWriter.hx` | development builds: the C of what hxmc does not generate yet |
| `src/hxmc/Abi.hx` | runtime struct layouts and per-target facts (`tools/probe.c` prints them) |

Conventions shared with hxc:

- GC roots: reference locals live across a GC point are shadow-stack slots
  (`fr[k]`, `EmitC.Roots`); cold sites (`SCold`) store the live references
  on the shadow stack only on the slow path of the allocation or array store.
  No stack maps.
- Exceptions: `try` is the runtime's `rt_handler` with the C library's
  `_setjmp` (jmp_buf layout per target); in functions with a `try` every
  local lives in memory (C: `volatile`), so its value survives the second
  return of setjmp; temporaries never live across statements.
- Calls into the runtime follow the C ABI (System V now; AAPCS64 and Win64
  later); generated functions use it too (the runtime calls them through
  its tables).
- Thread-local runtime state (`rt_sp`, `rt_young_ptr`, ...) is accessed with
  the local-exec TLS model (`fs:` on x86-64 Linux).

## Iteration loop

```sh
make hxmc-dev                     # bin/hxmc/hxmc: the tool by the native hxc tool and tcc
make hxmc-rt                      # bin/hxmc/rt-dev: the runtime objects of development builds (clang -O2, once)
python3 hxmc/tools/run.py         # the corpus: hxc vs hxmc output, % of native functions
python3 hxmc/tools/run.py --fuzz bin/hxmc-fuzz   # plus the fuzzer's programs (bin/fuzz/fuzz --emit bin/hxmc-fuzz -n 60)
python3 hxmc/tools/enctest.py     # the x86-64 encoder against llvm-mc (15070 encodings, < 1 s)
sh hxmc/tools/hxmc.sh <case>      # rerun hxmc on a corpus case (HXMC_DUMP=<function> prints its Mir)
python3 hxmc/bench/measure.py     # benchmarks: generated C at tcc / clang -O1 / -O2, and hxmc
```

- Test cases are `test/cases/*.hx` and the programs of the repository listed
  in `run.py` (`hxc/test`). Each case's HXB is written once by the reference
  compiler and cached under `bin/hxmc-t/<case>/`; the oracle is the same
  archive compiled by hxc (tcc), run once and cached. A run of the corpus
  takes seconds.
- Development builds are hybrid: a function hxmc cannot compile yet (it
  throws `Unsupported`) is written as C by EmitC and the system's compiler
  links everything (`HXMC_HYBRID=1`). `HXMC_ONLY`/`HXMC_SKIP` select the
  functions compiled natively (bisecting a miscompilation). The shipped
  path has no fallback.

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
- Inlining of small Haxe functions (`-fno-inline-functions` keeps only the
  runtime's inline helpers) matters for the numeric cases: mandelbrot 3×,
  bcrypt and sha512 1.5×, binarytrees and mandelbrot_anon 1.3×. It does not
  matter for the port, the formatter, json or alloc (calls are rarely the
  cost there).
- So hxmc needs: good register allocation and instruction selection
  (bcrypt, sha256, alloc, nbody: the gap to "O1 without inlining"), and an
  inliner for small functions (the gap from there to -O1). Loop
  optimizations beyond what falls out of those are not needed.

## Status

- x86-64 Linux, development builds: 100% of the functions of the corpus
  (64 programs, 7103 functions) and of the port (16509) compile natively;
  all outputs identical to hxc's; the port built by hxmc self-compiles to
  byte-identical HXB (514 modules).
- Next: the data tables natively (no C at all), the linker and the runtime
  archive (static musl ELF), caching per module, then performance (see
  step 0), arm64, Mach-O, PE, the haxelib.
