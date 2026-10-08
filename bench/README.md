# Benchmarks

Wall-clock time of the pinned reference compiler (native OCaml) vs. the
translated compiler (`haxe.Main`) built for different Haxe targets. Every run
compiles a workload to HXB with `-D disable-parallelism`. A runner's timing
only counts if its archive matches the reference: same members and
byte-identical `.hxb` payloads.

```sh
make -C haxe haxe
HAXE=haxe/haxe sh bench/build.sh js hl jvm cpp   # needs hxnodejs, hxjava, hxcpp (git)
# HL/C needs a compiler with bench/hl2c-virtual-field-cast.patch and HashLink headers:
HAXE_HLC=/path/to/patched/haxe HL_INCLUDE=/path/to/hashlink/src sh bench/build.sh hlc
HAXE_REFERENCE=haxe/haxe python3 bench/run.py -n 5
```

## Results — 2026-10-08

4-core Linux container. Median of 5 runs, in seconds.

| Runner | hello | trycatch | stdlib | vs. reference (stdlib) | stdlib on 2026-10-07 |
| --- | ---: | ---: | ---: | ---: | ---: |
| reference (native OCaml) | 0.13 | 0.13 | 0.24 | 1× | 0.23 |
| HL/C (HashLink compiled to C) | 0.38 | 0.49 | 0.87 | 3.6× | (no build) |
| HashLink (JIT) | 0.72 | 0.82 | 1.31 | 5.5× | 7.62 |
| JS (Node 22) | 1.23 | 1.20 | 2.16 | 9× | 7.15 |
| JVM (OpenJDK 21) | 2.14 | 2.20 | 3.10 | 13× | 5.40 |
| C++ (hxcpp) | — | — | — | — | 1.83 |

Every build above passes the full conformance suite (282 cases) through
`HAXE_IN_HAXE_PORT`. C++ is left out: release builds with current hxcpp
crash or hang (see below).

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

Where the time goes now (HL/C, callgrind): libhl allocation and GC are about
45% of the run. libhl takes a global lock and a TLS lookup on every
allocation, which is far more expensive than OCaml's pointer bump. The rest is
spread over the typer, filters and analyzer with no dominant hotspot. The
next steps would be allocating less in the filter/analyzer passes (52% of
all allocation) or a cheaper allocator.

## Notes

- **Go** isn't benchmarked. The pinned compiler has no Go target, and the
  [hx2go](https://github.com/go2hx/hx2go) custom target (git `2739b6c`)
  compiles a hello world but not the port. Its `haxe.Exception` defines
  `error()` for Go's error interface, which clashes with the port's
  `ParserError.error` and `WithTypeError.error` fields. With those renamed,
  the generated Go still has 40 compile errors: `break`/`continue` outside
  their loop, missing `HxArray` methods (`concat`, `slice`, `join`), generic
  variance (`HxArray[T]` vs `HxArray[any]`) and missing returns.
- **HL/C.** The pinned compiler's `hl2c` dies (`Globals.die` in `rassign`)
  when a `Dynamic` field of a structural type is read into a typed register.
  `hl2c-virtual-field-cast.patch` converts through `hl_dyn_cast` there, like
  `OSafeCast`. HL/C is the fastest build, but only once throws skip the stack
  capture: before that it was slower than the JIT (4.75s), because the C
  build captures stacks through libgcc unwinding. Static linking of libhl and
  `-O3 -march=native` made no measurable difference.
- **C++.** Needs hxcpp from git: the 4.3.2 haxelib release (and 4.3.99)
  don't support the pinned std's zip API. Release builds of the port corrupt
  hxcpp's heap: random segfaults inside hxcpp's string hash and GC, and
  deadlocks on mutexes that no other thread holds. Since the latest changes
  they crash on almost every run. Debug builds run correctly, and so do
  builds with `HXCPP_GC_VERIFY`. Ruled out: the port's mutexes and threads
  (single-threaded stand-ins still crash), GC parallel marking (a single
  marker thread still crashes), stack depth, and null-reference exceptions.
  Older hxcpp revisions don't run with the pinned std, so bisecting hxcpp
  wasn't possible. One real port bug turned up along the way: a C++ trigraph
  (`"??="`) in the lexer, now fixed.
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
