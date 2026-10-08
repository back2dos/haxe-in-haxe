# Benchmarks

Wall-clock time of the pinned reference compiler (native OCaml) vs. the
translated compiler (`haxe.Main`) built for different Haxe targets. Every run
compiles a workload to HXB with `-D disable-parallelism`. A runner's timing
only counts if its archive matches the reference: same members and
byte-identical `.hxb` payloads.

```sh
make -C haxe haxe
HAXE=haxe/haxe sh bench/build.sh js hl jvm   # needs hxnodejs, hxjava
# C++ needs hxcpp from git with bench/hxcpp-single-thread-mark.patch:
CPP_FLAGS="-D HXCPP_SINGLE_THREAD_MARK" sh bench/build.sh cpp
# HL/C needs a compiler with bench/hl2c-virtual-field-cast.patch and HashLink headers:
HAXE_HLC=/path/to/patched/haxe HL_INCLUDE=/path/to/hashlink/src sh bench/build.sh hlc
# with bench/libhl-allocator.patch applied to HashLink (built with -ftls-model=initial-exec):
HL_STATIC="libhl.a fmt.o dxt.o sha1.o" sh bench/build.sh hlc   # static link
# the HashLink JIT loads libhl.so: point it at the patched build
LD_LIBRARY_PATH=/path/to/patched/hashlink HAXE_REFERENCE=haxe/haxe python3 bench/run.py -n 7
```

## Results — 2026-10-08 (macros, `self` workload)

The port compiling its own source (`self` in `bench/run.py`: 229 files,
~52k lines, 382 modules, std macros executed by the port's Eval). The archives
are byte-identical to the reference. 4-core container, median of 5 runs
(JIT: 3 runs).

| Runner | wall | user | sys | peak RSS | vs. reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| reference (native OCaml) | 4.32s | 4.05s | 0.27s | 404 MB | 1× |
| HL/C (static patched libhl) | 8.68s | 7.64s | 2.22s | 1803 MB | 2.0× |
| HashLink JIT (stock libhl) | 13.46s | 13.13s | 1.62s | 1486 MB | 3.1× |

HL/C's first run took 14.6s (cold page cache). The gap is wider than on
`stdlib` (1.5×). From `--times` (timers add overhead and GC pauses land
anywhere, so these are rough):

| Phase | reference | HL/C | ratio |
| --- | ---: | ---: | ---: |
| DCE mark | 0.13s | ~1.5s | ~11× |
| HXB generation | 0.66s | ~2.9s | ~4× |
| analyzer | 0.95s | ~2.6s | ~2.7× |
| typing | 1.32s | ~2.5s | ~2× |
| macro | 0.05s | ~0.24s | ~4× |

DCE mark stood out. It was allocation rather than an algorithm problem.
`markT` built a new type stack array per recursion level and a closure per
call, `expr` made two closures per expression, and `Meta.has` did a checked
`Dynamic`→enum cast for every metadata entry. After removing those, DCE mark
takes 0.36s (from ~1.45s; reference 0.12s; 1.6G → 0.66G instructions).
Head to head over 8 alternating runs, end to end goes from 9.2–9.35s to 8.6s
and peak memory from 1.80 GB to 1.55 GB. Part of the time charged to DCE was
GC collections, which now run in later phases. Memory is still about 4× the
reference.

Binary sizes:

| Binary | size | stripped |
| --- | ---: | ---: |
| reference `haxe` (OCaml, every target generator) | 30.5 MB | 21.3 MB |
| `hih-hlc` (HL/C, libhl linked statically, HXB only) | 14.3 MB | 10.8 MB |
| `hih.hl` (HashLink bytecode; needs `hl` + libhl, 0.7 MB) | 2.7 MB | — |

The generated C for HL/C is 37 MB of source.

## Results — 2026-10-08 (fifth round)

4-core Linux container. Median of 7 runs, in seconds. Both HashLink runners
use the patched libhl (`libhl-allocator.patch`): HL/C links it statically,
the JIT loads it through `LD_LIBRARY_PATH`. (Earlier rounds' JIT numbers
used the stock libhl.) C++ uses hxcpp git `cd5dc3b` with
`hxcpp-single-thread-mark.patch`.

| Runner | hello | trycatch | stdlib | vs. reference (stdlib) | stdlib, fourth round |
| --- | ---: | ---: | ---: | ---: | ---: |
| reference (native OCaml) | 0.13 | 0.12 | 0.24 | 1× | 0.23 |
| HL/C (HashLink compiled to C) | 0.17 | 0.17 | 0.37 | 1.5× | 0.53 |
| C++ (hxcpp) | 0.43 | 0.43 | 0.96 | 4× | 1.02 |
| HashLink (JIT) | 0.59 | 0.66 | 1.04 | 4.3× | 1.12 |
| JS (Node 22) | 1.25 | 1.23 | 2.11 | 9× | 2.16 |
| JVM (OpenJDK 21) | 2.01 | 1.94 | 2.96 | 12× | 3.13 |

The JIT's runs vary a lot (0.85–1.35s on `stdlib`).

Instruction counts (callgrind, stdlib): the reference executes 1.10G, HL/C
2.25G (2.61G before this round; the lexer changes in item 11 came after
the table above). Of HL/C's instructions, 38% are
allocation and GC: about 9.2M allocations at roughly 30–55 instructions
each (OCaml's minor-heap allocation is an inline pointer bump), plus a
non-generational major collection. 24% are
runtime type checks, dynamic casts and closure/enum/array allocation in
libhl, 10% libc (mostly zeroing), and 25% the compiled program itself. C++
executes 5.36G: about a third of that is C++ exception unwinding in libgcc
(see the C++ note below).

Memory for speed: with the default `HAXE_IN_HAXE_GC_FACTOR=1` HL/C peaks at
141 MB on `stdlib` (the reference: 52 MB). A factor of 2 skips the one
major collection for about 10% more speed at 216 MB.

Every build above passes the full conformance suite (282 cases) through
`HAXE_IN_HAXE_PORT`.

Workloads:

- `hello`: a `trace("Hello, world!")` main (63 modules, mostly std).
- `trycatch`: `test/unit/moduleload/TryCatch.hx` (63 modules).
- `stdlib`: 32 std modules as bare roots (95 modules).

The port's own source can't be a workload yet: compiling it executes std
macros, which are outside the first milestone.

## What made it faster

In rough order of impact:

1. **Exceptions without stack traces.** The port follows upstream in using
   exceptions for control flow (about 119k throws for `stdlib`: parser
   backtracking, `Not_found`, `Exit`). OCaml exceptions are nearly free;
   Haxe targets capture a stack trace for each one.
   - `Not_found`, `Exit`, `Stream.Failure` and `MetaNotFound` are thrown as
     shared instances (`throw NotFound.raise()`).
   - Like OCaml, stack traces are only recorded with `OCAMLRUNPARAM=b`: JS
     sets `Error.stackTraceLimit = 0`, and `runtime/hl/haxe/Exception.hx`
     skips capture in the constructor.
   - On HashLink, `raise()` and `haxe.Exception.thrown` throw through
     `hl.Api.rethrow`, which skips libhl's native stack capture. That capture
     was 80% of the HL/C run.
2. **HashLink GC trigger.** libhl starts a full, non-generational mark after
   every 20% of heap growth, so a heap full of typed modules is marked over
   and over. `core.ds.GcPolicy` disables that and collects once allocation
   since the last major exceeds half the heap size
   (`HAXE_IN_HAXE_GC_FACTOR`, default 0.5). This took HL from 2.0s to 1.4s on
   `stdlib`, with peak memory going from 86 MB to 130 MB.
3. **Algorithms.** `Hashtbl` was a list scanned with reflective structural
   comparison; it's now indexed by a canonical key string.
   `PersistentMap` uses binary search. The lexer no longer allocates a
   substring for each operator candidate on every token.
4. **Static types.** `TExpr`, `Pos`, `Expr`, `TVar`, `TClassField` and
   `TMono` are `@:structInit` classes instead of anonymous structures. The
   typer's `com` field and the `scom` and `ctx` parameters are typed instead
   of `Dynamic`. This helps HL a little and the JVM a lot. It also cut the
   pinned compiler's JVM generation from about 8 minutes to 90 seconds.
5. **Counters.** `allocVar` and `allocMid` use `haxe.atomic.AtomicInt`
   (upstream's `Atomic.fetch_and_add`) instead of a mutex.
6. **libhl allocator** (`libhl-allocator.patch`, second round). Fixed-size
   classes go up to 128 bytes instead of 40, so typical compiler objects use
   the thread-local slice fast path instead of the locked free-list
   allocator. The fast path is a small separate function. Slices are zeroed
   once when created rather than per allocation. Sweeping skips whole bitmap
   bytes. Built with `-ftls-model=initial-exec` and linked statically, it
   cuts HL/C from 0.86s to about 0.6s on `stdlib`.
7. **Fewer allocations and conversions** (second round). More records became
   classes (`GlobalTypePath`, `UnificationContext`, `LexedToken`,
   `MetadataEntry`, `PlacedName`, `PlacedAccess`, `TypeHint`, map entries).
   `RecStack` is the array itself. `Record.copy` resolves `clone()` at
   compile time. The lexer's operator table is typed and its line table
   avoids O(n) prepends and per-character strings. `Stream.peek` no longer
   copies. Some hot local helpers became static functions. The default GC
   factor is 1.0 (peak memory on `stdlib` about 140 MB, against the
   reference's 53 MB).
8. **Records as classes everywhere** (third round). The AST, typed AST,
   typer contexts and the analyzer, matcher, coroutine and filter records
   are all `@:structInit` classes. `CommonContext` stays a structure because
   its 62-argument constructor exceeds the HashLink JIT's argument limit.
   `Record.copyDynamic` clones any record class reflectively. Also made
   the JVM build (genjvm) take seconds instead of minutes.

9. **Allocator, fifth round** (`libhl-allocator.patch`). New pages come
   zeroed from `mmap`, so neither the page nor slices carved from untouched
   blocks are cleared again (a per-page `zero_from` mark tracks this).
   Slices are 8 KB instead of 2 KB. Pages are carved from 2 MB-aligned
   32 MB chunks marked `MADV_HUGEPAGE`, which cuts page faults on `hello`
   from 21k to 1.3k. The global GC lock skips its `setjmp` context save when
   the lock is uncontended (the collecting thread saves its own context in
   `gc_stop_world`). The lazy sweep scans the mark bitmap 64 bits at a time.
   `hl_alloc_obj` bumps the thread's slice directly. Together: `stdlib`
   0.53s → 0.37s on HL/C.
10. **Fewer dynamic checks** (fifth round). On HashLink `Std.isOfType` casts
   its class argument from `Dynamic` before checking, about 200
   instructions per call; `haxe.Exception.caught`/`thrown`, `Key` and
   `Meta` use `Std.downcast` instead, a direct type check.
   `newRecStack` is inline, so each unification context no longer converts
   five arrays from `Array<Dynamic>`. `TUnification.updated` (a copy plus
   reflective field sets) became `Record.withFields`, which sets the
   fields statically.

11. **Lexer** (fifth round). A token only tries the operators starting with
   its first character instead of all of them; comments are found with
   `indexOf` and copied at once instead of a one-character string per
   character; `skipWhitespace` compares code units. `ZipOutput` computes
   the CRC-32 with a table instead of `haxe.crypto.Crc32`'s bitwise loop.
   `Lexer.token` went from 80M to 18M instructions on `stdlib`.

12. **Inline allocation** (sixth round). `libhl-allocator.patch` adds an
   allocation fast path to `hlc.h`: generated code allocates objects, enums,
   closures, small arrays, virtuals and bytes by bumping the thread's slice
   directly instead of calling into libhl (about 70 instructions per
   allocation before). After a collection free runs are short, so a slice
   refill now takes several runs under one lock and queues them. HL/C
   `stdlib`: 2.25G → 1.90G instructions, 0.38s (reference 0.24s); with
   collection disabled it is about 1.25× the reference in CPU time. What
   remains is mostly memory management: the non-generational major
   collections, zeroing reused memory, and first writes to fresh memory,
   which OCaml's cache-resident minor heap avoids.

13. **Dynamic typing and boxing** (seventh round). HashLink compiles an
   `Array<T>` of a type parameter to `ArrayDyn` and a structure to a virtual,
   so generic helpers boxed every array argument (an allocation and a dynamic
   call per element access) and generic structures went through
   `hl_to_virtual` on every use. `Stream` is now `@:generic`; the generic
   `List`/`Texpr`/HXB-writer list helpers and the parser combinators
   (`tryHead`, `plist`, `psep*`) are inline; two hot private structures
   became classes. `tryHead` tests the shared `Stream.Failure` by identity
   instead of a typed catch, and string tests use the type pointer instead
   of `Std.downcast`. Runtime side: `runtime/hl` overrides `StringBuf.add`
   (the same string test) and `ArrayObj.__expand` (grow from 4 and double
   while small, instead of reallocating at 1, 2, 3, 4, 6, 9, 13…), and
   `hlc.h` gains an inline `hl_dyn_castp` fast path for exact-type casts.
   HL/C `stdlib`: 1.81G → 1.57G instructions (reference 1.10G). Minimum CPU
   time over 21 runs: 0.37s (reference 0.24s); with collection disabled
   (`HAXE_IN_HAXE_GC_FACTOR=1e9`) its user time is 0.22s against the
   reference's 0.20s. What is left is memory management: the major
   collections, and zeroing recycled memory when slices are refilled
   (about 80M instructions of `memset`).

14. **Generational GC: tried, not adopted** (2026-10-08). A sticky-mark-bit
   generational mode with an hl2c write barrier works (all 282 conformance
   cases pass even with a 1 MB nursery) but is slower: 0.42s or more of user
   time on `stdlib`, against 0.32s. The barrier costs about 0.03s, and the
   live set is so small (6–12 MB for 260 MB allocated) that the current rare
   majors already mark little. Details, data and patches:
   [experiments/generational-gc](experiments/generational-gc/README.md).

Where the time went after the first round (HL/C, callgrind): libhl allocation and GC were about
45% of the run. libhl takes a global lock and a TLS lookup on every
allocation, which is far more expensive than OCaml's pointer bump. The rest is
spread over the typer, filters and analyzer with no dominant hotspot. The
next steps would be allocating less in the filter/analyzer passes (52% of
all allocation) or a cheaper allocator.

## Notes

- **Go** (hx2go). The pinned compiler has no Go target; the
  [hx2go](https://github.com/go2hx/hx2go) custom target (git `2739b6c`)
  generates Go that only builds and runs after patching:
  `HAXE=haxe/haxe sh bench/hx2go/build.sh` produces `bin/bench/hih-go`. With
  those patches it passes the full conformance suite (282 cases) and runs
  every workload, but it's the slowest build: `stdlib` 5.10s (20× the
  reference; HL/C 0.48s, JS 2.21s, JVM 3.09s in the same run), `hello`
  2.34s. About a third of its time is Go panic/recover unwinding for the
  port's exception-based control flow, and a quarter is GC; much of the rest
  goes through reflection-based dynamic calls.
  The fixes, all specific to hx2go 2739b6c:
  - Source (`bench/hx2go/source.patch`, applied to a copy of `src`): rename
    two exception fields called `error` (hx2go's `haxe.Exception` defines
    `error()`); explicit null checks for the two enum-valued default
    arguments (hx2go drops callee-side defaults); `catch (e:NotFound)`
    instead of `catch (e:Dynamic)` plus `Std.isOfType` (a caught subclass
    arrives as its base `haxe.Exception`); `exists` before calling a
    function read from a map (hx2go's adapter makes it non-null).
  - Generated Go: `trybreak.py` (a `break` out of a loop inside a `try` body
    left the whole `try` body, skipping e.g. class field initialization),
    `tryreturn.py` (`return f()` inside `try` marked the function as returned
    before evaluating `f()`, so a caught exception made it return nil),
    `staticorder.py` (static initializers ran before the statics they read),
    `autofix.py` (generic array variance, dead `break`/`continue`, missing
    returns, `any` assertions), and `manual.py`: a name clash between
    `core.Texpr` and `core.TExpr`, `super` inside closures, typed `catch` on
    a typedef alias, `Map` values stored as concrete maps, a recursion limit
    for `Std.string` (types are cyclic), void functions behind dynamic
    closure adapters, and the string runtime. hx2go's `charCodeAt` counted
    runes from the start of the string on every call (quadratic lexing) and
    `indexOf` returned byte offsets while `substr` used code points; the
    patched runtime has O(1) paths for ASCII strings and code-point-correct
    `indexOf`. Mutex ownership formatted a stack trace (`runtime.Stack`) per
    acquire to get the goroutine id; with a single goroutine it's now constant.
  - Debugging aids in the patched runtime: `HXGO_TRACE=1` prints the Go
    stack of every thrown Haxe value (except the control-flow singletons) and
    runtime error; `HXGO_CPUPROFILE=file` writes a pprof CPU profile.
- **HL/C.** The pinned compiler's `hl2c` dies (`Globals.die` in `rassign`)
  when a `Dynamic` field of a structural type is read into a typed register.
  `hl2c-virtual-field-cast.patch` converts through `hl_dyn_cast` there, like
  `OSafeCast`. HL/C is the fastest build, but only once throws skip the stack
  capture: before that it was slower than the JIT (4.75s), because the C
  build captures stacks through libgcc unwinding. Static linking of libhl and
  `-O3 -march=native` made no measurable difference.
- **C++.** Needs hxcpp from git: the 4.3.2 haxelib release (and 4.3.99)
  don't support the pinned std's zip API.
  - **Crash.** Release builds crashed or hung on random runs: segfaults in
    random places (hxcpp's string hash, the GC, field reads from objects that
    had been collected) and deadlocks. The cause is hxcpp's multi-threaded GC
    marking. With a single marker thread every run passes; disabling only
    the hand-off of large arrays to other marker threads doesn't help.
    `hxcpp-single-thread-mark.patch` adds `HXCPP_SINGLE_THREAD_MARK`,
    which turns parallel marking off, the same as `HXCPP_GC_VERIFY` does
    without that define's verification work. Debug builds also mark on one
    thread, which is why they never crashed.
  - **Port fixes.** `switch` directly on a call through a function-typed
    field with an enum result generated invalid C++ (`.StaticCast` on the
    callable), so `InstanceBuilder` stores the result in a local first. On
    hxcpp `StringTools.fastCodeAt` on a structure field calls `cca`
    dynamically and failed at startup, so the lexer's first-character table
    is built from its typed operator texts. Also fixed earlier: a C++
    trigraph (`"??="`) in the lexer.
  - **Speed.** `StringTools.lpad` reads `StringBuf.length`, which is O(n)
    on hxcpp, so `ParserEntry.parseExprString` padding a string by `pmin`
    spaces was quadratic: half of all instructions for `hello`. It now
    builds the spaces directly (upstream's `String.make`). What remains is
    mostly exceptions: parser backtracking throws (about 119k throws for
    `stdlib`) unwind through libgcc's table-driven unwinder, which costs
    about 19k instructions per throw on the deep recursive-descent stacks.
    `HXCPP_SINGLE_THREADED_APP` (no TLS lookup per allocation) saves about 8%
    more, but it's unsafe once the compiler runs parallel filters.
- **JVM.** `genjvm` emits a method (`typing.Typer.typeExpr`) that the
  bytecode verifier rejects. The jar runs correctly with verification off
  (`-XX:-BytecodeVerificationLocal`), which `run.py` passes. The JVM
  initializes classes lazily, so `haxe.Main.initHooks` installs every forward
  reference explicitly. Java can't change the working directory, so
  `core.Path.restoreCwd` skips `Sys.setCwd` when the directory didn't change.
- **JS.** Needs hxnodejs for `sys`. `bench/js-shims` holds single-threaded
  `sys.thread` stand-ins; the compiler only spawns workers when parallelism is
  enabled. Building with `-D analyzer-optimize` currently produces different
  (non-conforming) output on JS, so all targets are built without it. Larger
  V8 semi-spaces and `-D js-enums-as-arrays` made no difference. When stdout
  is a pipe or `/dev/null`, hxnodejs's `Sys.stdout().flush()` fails
  (`fsync` EINVAL).
- **Conformance on other targets.** For example,
  `HAXE_IN_HAXE_PORT="node --stack-size=65500 bin/bench/hih.js" python3 test/conformance.py`
  runs the whole conformance suite on a prebuilt port.
