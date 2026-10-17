# hxmc: future plans

Ideas and directions discussed for hxmc, not scheduled. Each entry says
what it is, why it matters and what it needs. Current state is in
[README.md](../README.md); this file is what could come after.

## Medium term

The next performance steps after the runtime moves to Haxe; both are in
the code generator and help every target.

### Stack maps instead of the shadow stack (tried, reverted)

Tried at e91b276 (stage 5a), reverted to the shadow stack (git history,
"Stack maps: tried and reverted"): root slots in machine frames, frame
records, a descriptor table per code region, frameless thunks recording
the last frame before C calls, entries for C's calls into Haxe. Measured
against the shadow stack: up to 5.6% fewer instructions
(mandelbrot_anon), binarytrees -1.6%, formatter -1.4%, but nbody +0.3%,
sha256 +1.3% and the port +0.8% (its walks cost 0.9 G instructions
against 0.7 G for the shadow stack's scan), 196 KB less code in the port
and 8-12 KB more in small programs. WebAssembly needs the shadow stack
anyway; one root mechanism is simpler. Conditions for trying again (the
follow-ups that would make it pay):

- Per-call-site liveness (descriptors per return address instead of per
  function): no zeroing of root slots, references in registers across
  calls that only maybe collect; larger tables.
- Frame records only where needed: a function that collects only on a
  slow path (an array access's) pays its record on every call (nbody,
  sha256); its descriptor could give its frame size instead, so the walk
  passes it without a record.
- A cheaper walk: the port's walks cost more than the shadow stack's scan
  (frames without references are visited too); frames not resumed since
  the last minor collection hold no young references (a watermark).

The collector is Haxe on the native targets too (`hxmc/std/hxmc/rt/Gc.hx`;
LOWLEVEL.md, "The runtime without C of our own").

### Escape analysis

Allocate objects that never escape their function on the stack, or
replace them by their fields in registers (scalar replacement): temporary
iterators, small structs and anonymous objects, closures called in place,
boxed values. Go relies on this to keep short-lived objects off its heap.
It removes allocation, write barriers and GC pressure at once, and is
likely the largest remaining gain for allocation-heavy code (alloc,
binarytrees, closure-heavy code, the port's own temporaries), more than
any tuning of the collector. hxmc's SSA IR and inliner make it practical:
inlining first exposes most non-escaping allocations. Stack-allocated
objects must stay visible to the GC when they hold references (as roots,
via the shadow stack or stack maps), and must never be stored where a
heap object or another thread can see them.

### Macro-heavy builds: what is left after the cheap fixes

Measured on the native port (Linux x86-64, `--times`, best of several
runs) after the macro-perf fixes (Eval's object encoding, calls and field
lookups, haxe.ds.Vector allocation): the `macro` timer is now at or below
the reference compiler's on every workload; the port's remaining gap is
in typing and the collector.

| Workload | macro share, port | macro share, reference |
| --- | --- | --- |
| tink_json, 12 nested types (JS) | 29% (0.97 of 3.32 s) | 34% (0.89 of 2.65 s) |
| tink_json, 24 nested types (JS) | 24% (3.27 of 13.4 s) | 24% (2.84 of 12.1 s) |
| upstream unit suite (JS) | 16% (0.54 of 3.33 s) | 17% (0.54 of 3.19 s) |
| upstream unit suite (--interp) | 14% (+ interp 32%) | 13% (+ interp 46%) |
| packages/gfx (GfxTest) | 8% | 7% |
| macro conformance cases (66, summed) | 39% | 37% |

Done: **nursery size** (docs/hxmc.md, "Runtime in Haxe"; Gc.hx). The
nursery adapts to what it promotes and to the threads that allocate:
from 4 MB, doubled after a collection that promoted more than a 16th of
what was allocated, halved after 8 that promoted less than a 64th,
between 4 MB per allocating thread and 16 MB plus 8 MB per other one (at
most 32 MB). Against the fixed 4 MB (with the old one-shot doubling),
native port on Linux x86-64, 4 cores, medians of 5 interleaved runs:

| Workload | time | peak RSS |
| --- | --- | --- |
| port typing itself | -5.9% | -31% |
| port, HXB self-compile (parallel passes) | -16.7% | -19% |
| tink_json, 12 types (JS) | -7.2% | 0% |
| tink_json, 24 types (JS) | -17.0% | -3% |
| upstream unit suite (JS) | -5.4% | 0% |
| tool building the port (it fixes 32 MB itself) | 0% (cpu) | -1% |
| tool building the port, `HXMC_GC_DEFAULTS=0` | -15.5% | -16% |
| benchmarks (hxmc, 10 cases) | alloc -6%, the others within ±4% (mandelbrot_anon +10%: code layout, the binaries match at a fixed size) | alloc -16%, sha512 +4 MB |

What the earlier measurement took for a loss in the tool was its own
setting: it runs itself with `RT_MINOR_KB=32768` (kept), so a 16 MB
nursery there was a smaller one (and 35% more memory: more objects
promoted, a major collection of the old space past `RT_OLD_MB`). A
fixed 16 MB nursery hurt programs whose objects die young (cache misses:
mandelbrot-like code); growing only on promotion keeps them at 4 MB.
Still open: the port at 32 MB types itself 8% slower than at 16 MB (so the
single-thread ceiling stays 16 MB) while its parallel HXB phase likes 32
MB; per-thread nurseries (TLABs sized per thread, not a 16th of the
shared nursery) were not needed for these workloads.

Done: **typing of generated code** (profiled with frame pointers, `perf
record -g`, against the reference's OCaml symbols). The gap that grew
with the code size was the port's own: `ctx.e.monomorphs` was an array
copied on every spawned monomorph (OCaml conses), most of the
allocation of tink_json's generated functions. It is now an immutable
list that conses in place onto shared arrays (`Typecore.MonomorphList`;
a linked list made the transactions' walk twice as slow, its loads
dependent); the compiler's callback lists stopped unshifting; hxmc's
maps share empty arrays until their first set and reserve their arrays
when they grow. Native port, Linux x86-64, medians of interleaved runs
(3 for 40 types, 5 otherwise), `--times`, `-D disable-parallelism`
(tink_json: N typedefs, each with nested anonymous structures, an enum,
a map and an array of the previous one, each stringified and parsed in
`main`; tink_json 0.11.0, tink_typecrawler 0.7.0, tink_macro 1.0.4,
tink_core 2.1.1):

| Workload | reference | before | after | typing: ref / before / after | peak RSS before / after | allocated before / after |
| --- | --- | --- | --- | --- | --- | --- |
| tink_json, 12 types (JS) | 3.26 s | 3.41 s | 3.14 s | 0.67 / 0.91 / 0.77 s | 367 / 372 MB | 3.4 / 3.0 GB |
| tink_json, 24 types (JS) | 12.71 s | 12.88 s | 11.50 s | 4.28 / 5.10 / 3.81 s | 917 / 726 MB | 14.2 / 10.0 GB |
| tink_json, 40 types (JS) | 42.50 s | 44.18 s | 34.13 s | 20.97 / 23.49 / 13.57 s | 2098 / 1918 MB | 54.1 / 26.5 GB |
| upstream unit suite (JS) | 3.23 s | 3.46 s | 3.17 s | 0.79 / 0.90 / 0.85 s | 424 / 422 MB | 2.70 / 2.60 GB |
| port typing itself | 7.60 s | 6.29 s | 6.29 s | 3.29 / 2.51 / 2.38 s | 613 / 615 MB | 4.86 / 4.63 GB |

(The 34.7 s against 20.0 s of the earlier measurement predates the
adaptive nursery.) The collector's share is 17-21% (minor collections
copying what survives one, about 12%; major ones, 4-6%), as in the
reference (its minor heap and marking: about 20% on tink_json, 27% on
the unit suite).

Ranked by estimated payoff, each needing more than a local fix:

- **monomorph_transaction**: upstream snapshots every unbound monomorph
  of the function for each optional argument passed
  (`CallUnification`), quadratic in a function's size in the reference
  too (its fold is the reference's top function on tink_json). 15% of
  tink_json at 40 types, 6% at 24, little elsewhere; the walk is
  memory-bound (each monomorph's header a cache miss). A trail of the
  monomorphs bound or constrained since the snapshot (the 12 places that
  set `tmType` or `tmDownConstraints`) would make it proportional to
  the changes; a departure from upstream's algorithm. Estimate: -12% at
  40 types.
- **Medium-lived objects in the collector**: a minor collection
  promotes whatever survives it (9% of what tink_json allocates, 2.5 GB
  at 40 types), and the old space's major collections stop the world
  (1.8 s at 40 types, charged to wherever an allocation lands: the
  "superlinear" functions of a scaling comparison, `BasicBlock.create`,
  `Abstract.findToFrom`, DCE's mark at 4x the reference's, are their
  pauses). An aging survivor space, or incremental major marking ("The
  collector, longer term"). Estimate: 5-10% on large builds.
- **Allocation in the typer and analyzer**: the rest is spread thin
  (texpr records, `InterferenceReport`'s four maps per expression,
  Eval's encoding of macro arguments); escape analysis (above) is the
  general answer.
- **Eval call frames**: each call allocates an Env, two slot vectors and
  the argument array, and stores the frame into the long-lived Eval
  record twice (two write-barrier slow calls): a quarter of a call's cost.
  A frame stack reused across calls is a redesign of EvalContext.
  Estimate: 20-30% on call-heavy macro code.
- **Eval instance layout**: a field read is four dependent loads
  (the VInstance box, the instance, the Array header, its data) against
  three in OCaml; on the Objects benchmark the field read is a quarter of
  the time, in cache misses. Instance fields as an object with inline
  slots (or hxmc arrays with inline data) would remove one.
- Tried and not kept: the write barrier testing the value for youth
  before its slow call (within noise, 2.6% more code); `encodeObjS`
  without its intermediate records (no measurable gain).
- Minor: `Finalization.sortTypes` and `TPrinting.sType` sort through
  `Reflect.compare` (2% of the unit suite); source lines for messages (a
  warning's excerpt) are read a byte at a time, each byte a poll and a
  read system call.

### Cleanup after the runtime move (done)

Done (docs/hxmc.md, "Runtime in Haxe"):

- One source per runtime area: the haxe.atomic cells are written over
  the `Atomic` intrinsics, `hxmc.NativeZip` is the implementation,
  `hxmc.NativeSys`/`NativeNet` dispatch by `Mem.os()` to typed POSIX and
  Windows classes, `hxmc.Native` (reflection) is an alias of `hxmc.rt.Dyn`,
  `hxmc.NativeSsl`, `NativeUv`, `NativeThread` and `NativeGc` are aliases
  of their implementations (`hxmc.rt.Ssl`, `Uv`, `ThreadApi`, `Gc`; on
  WebAssembly `hxmc.rt.wasm.NoSsl`, `NoUv`, `Threads`, `Gc`) instead of
  externs bound to them by symbol. No
  `@:keep`, no bindings: Haxe's dead-code elimination drops what a
  program does not use (75 KB less HXB and 8 to 12 KB less code for a
  small program, builds up to 5% faster). Bindings stay for the natives the code
  generator calls by name (String, Array, Bytes, Std, Date, Dynamic
  operations) and the exports C calls.
- Leftovers: the Emscripten, Cosmopolitan, tcc and green-thread variants
  are gone from `hxmc/c/`, `rt_str.c` is folded into `rt_dyn.c`, Facts' names
  no longer follow hxc's C emitter, the census is a debug build of the
  runtime object.
- Kept: `MkStd.hx` (a custom target gets no `_std` directory in the
  reference compiler, so the overrides still merge with the Eval
  originals); the tools and benchmarks, all still in use.

## Language and runtime

### A compiler check for raw addresses across GC points

Found during the runtime cleanup: inline std code that takes a raw heap
address (`Mem.addr`) was expanded into code that can collect. Lowering
may compute the address before an allocation among the same expression's
operands; the collector then moves the object and the code writes through
a stale address (about 13% of ThreadNatives runs failed after the first
haxe.atomic collapse). Fixed by moving the address work into
`@:hxmc.noGc` helpers, and the rule is in docs/hxmc.md ("Runtime in
Haxe"), but it is only a convention.

Make the compiler enforce it: track values derived from `Mem.addr`
(and pointer arithmetic on them) in the SSA IR and reject any that is
live across a GC point outside a `@:hxmc.noGc` function, naming the
expression, the way Facts already names a no-GC function's culprit.
Alternatively, lower `Mem.addr` as late as possible (after the
allocation it is mixed with), but a check catches the class of bug
rather than one instance.

### Compact strings (Latin-1 / UTF-16)

Strings are UTF-16 (32-bit length, 16-bit code units), as on hxc and
HashLink. Keep UTF-16 *semantics* (O(1) `charAt`/`charCodeAt`/`substr`,
`length` in code units, the same results as JS, HashLink, JVM, C#), but
store a string as Latin-1, one byte per character, when every character
fits, with a flag in the header (as JDK 9's compact strings and V8 do).

- Gains: about half the memory of ASCII-heavy text; UTF-8 I/O of ASCII
  text becomes a copy instead of a conversion (files, sockets, console,
  Linux/macOS APIs, C libraries).
- Cost: every string operation handles both representations (mixed
  concatenation, comparison, hashing).
- Not planned: switching to UTF-8 semantics. It gives up O(1) indexing or
  Haxe-compatible results (`"😀".length` is 2 on UTF-16 targets) for gains
  the compact representation mostly gets anyway.
- Measured context: in the port's self-compile, strings are 5.5 MB live,
  1.6 MB of which Latin-1 storage would save (under 1% of the heap).
  I/O-heavy programs gain more than the compiler does.

### The runtime in Haxe (done)

Done (2026-10-15): `hxmc/c/` holds no C of ours. Strings, Dynamic
access and maps, std natives, OS wrappers, the collector, threads and the
stop-the-world handshake, startup and `rt_throw` are Haxe compiled with the
program (`hxmc/std/hxmc/rt`), over internal intrinsics (raw loads and
stores, pointer arithmetic, atomics, `Mem.callOnStack` for the main
thread's big stack, `Mem.zero`), compiler-checked no-GC functions, C-ABI
externs and callbacks (thread entries, `atexit`, Windows fibers). What
stays native: the C library (musl's members, the UCRT and MinGW-w64,
libSystem), mbedtls and libuv. Details: LOWLEVEL.md, "The runtime without
C of our own". The collector runs as fast as the C one did (the
benchmarks, the port's self-compile); the runtime's typed modules are
cached (TypesCache), so builds are faster than with the C runtime.

### Direct system calls on Linux

With the runtime in Haxe, static Linux executables could call the kernel
directly (as Go does) and drop musl. Windows and macOS keep going
through their system libraries (kernel32/ntdll, libSystem).

### Math: one implementation, the libm branch's later

Done (2026-10-16): every target computes Math with the same Haxe code,
`hxmc/std/hxmc/rt/LibM.hx`, musl's algorithms as Linux executables got
them from zig's C library (musl's pow and atan2; zig's ports of musl in
its libc and compiler_rt for the others): sin, cos, tan, asin, acos,
atan, atan2, exp, log, pow and Float's `%` (fmod); sqrt and abs are
instructions, floor and ceil arm64's frintm/frintp, WebAssembly's
f64.floor/f64.ceil and inline code on x86-64 (no SSE4.1 assumed), all
exact. Nothing calls the C library's math any more (mkrt.sh roots none;
zig's compiler_rt, one object, still brings its unused copies into the
Linux rt.o). The
results are bit-identical to musl's C on Linux x86-64 for every function
(2 million random and edge inputs each, and the corpus's `MathLib`),
where main used other code: on arm64 musl's pow takes its fma path (5 in
2 million results an ulp apart), Windows has the UCRT's and macOS
libSystem's. NaNs keep the processor's sign and payload. Speed against
musl's C on x86-64 (ns per call, 4096 typical inputs): exp, acos, asin,
atan2, fmod, floor and ceil faster, log, atan and pow within 5%, sin, cos
and tan about 1.1-1.3x slower; a trig-heavy loop about 1.1x, nbody and
mandelbrot unchanged. The codegen work for it is general: Mem.f64Bits and
bitsF64, Mem.words (tables in read-only data), constant folding, float
constants as memory operands, jump threading, index constants in
displacements. Left: sin/cos/tan's switch on the quadrant as a jump
table, if-conversion (cmov), splitting live ranges around rare calls.

musl differs from glibc by an ulp on some inputs (`Math.sin(-2.5)`:
-0.598472144103956438 against glibc's ...549), so the port's `--interp`
and macros (Eval's Math is LibM too in the port built by hxmc) can print
a last digit different from the reference, widened by later arithmetic
(the fuzzer accepts printed floats a few ulps apart, `Runner.sameOutput`).

Later, the `libm` branch (98d9d82, 374bb61; parked): exp/log/pow from
Arm's Optimized Routines (glibc's own code, MIT; bit-identical to glibc),
sin/cos/tan/asin/acos/atan/atan2 from CORE-MATH (MIT, correctly rounded:
equal to glibc except where glibc is an ulp off, about 1 input in 1,000),
fma in hardware where the CPU has it, tested exact against glibc and
CORE-MATH's 9.5 million hard cases. It replaces LibM's functions once
it is no slower than them at run time, compile time and size:

- CORE-MATH's trig is slower than musl even in C (cos 17 ns, tan 24 ns
  against 6.5 and 10.5 on x86-64), and its ~166 KB of tables (as
  `Mem.words` now: read-only data, not literals typed with every build).
- One math implementation only: where a CORE-MATH function costs too
  much, that function keeps musl's algorithm, no second variant behind a
  define.
- The port then differs from the reference (glibc) only where glibc is
  an ulp off.

### The collector, longer term

Compared with Go (concurrent non-moving mark-sweep), Swift (reference
counting) and V (Boehm's conservative collector), our precise generational
copying collector is the best fit for Haxe's allocation patterns. Its weak
points and the ideas that address them:

- Major pauses grow with the live heap (a hitch for games and graphics
  with large heaps): incremental or concurrent marking of the old
  generation, as Go does.
- Peak memory: the copying old generation needs a to-space during a major
  collection. A mark-region (Immix-style) or mark-compact old generation
  removes it, and lets objects be pinned in place, which simplifies C
  interop.
- A memory limit (like Go's `GOMEMLIMIT`): collect harder as the process
  approaches a configured cap.

### sys.ssl and libuv (done)

Done (2026-10-15, docs/hxmc.md, "Targets"): mbedtls and libuv built per
target with zig at our build time (`hxmc/deps/deps.sh`), turned into
`ssl.o` and `uv.o` next to the runtime object and linked only into programs
that refer to them; the port and lix link both; WebAssembly keeps the
failing stubs. Left:

- Alternatives: the system's TLS on Windows (SChannel) and macOS
  (Security.framework) instead of mbedtls (smaller, OS-managed
  certificates; Linux has no system TLS a static executable can use, so
  mbedtls stays there); libuv replaced by an event loop in Haxe over
  epoll/kqueue/IOCP (large, and `eval.luv`'s API is libuv-shaped: only if
  libuv's size or build becomes a problem). Not mbedtls in Haxe: TLS needs
  constant-time, audited cryptography.
- Section-level selection on macOS (the Mach-O runtime objects are linked
  whole: `ssl.o` is 0.8-0.9 MB).
- The same mechanism (per-target prebuilt objects linked by hxmc) is how
  user C libraries would ship (see "C interop").

## Build times and size

### Cached modules

Most of a small program's build is the front half typing the std from
source every time (hello world: about 330 ms of 0.375 s). The compilation
server already caches per module, with upstream's rules: per-module
dependencies, file checks, the invalidation of dependents, and an HXB mode
that keeps the typed modules as HXB in memory (the Server and
ServerJsonRpc suites pass in both cache modes). The persistent cache is
that cache made durable on disk, not a new unit of caching: no library
boundaries, so the std, haxelib, lix and node_modules libraries and the
user's code are all modules alike.

- Step 1 (built, opt-in: `HXMC_MODULE_CACHE=1` or `-D hxmc.module-cache`;
  `hxmc/src/hxmc/ModuleCache.hx`): a successful build writes the modules it
  ends with as the server keeps them (HXB chunks, dependencies, kind, file,
  check policy) into a store in the user cache directory (the types cache's
  location, atomic writes and trim); the next build with the same key puts
  them in the server's cache before typing, and the server's checks decide.
- Measured (one 4-core VM shared with other builds; time to the start of
  lowering, then the whole build with the objects cached, and peak RSS):

  | | no cache | types cache | module cache cold | module cache warm |
  | --- | --- | --- | --- | --- |
  | hello world | 306 ms | 158 ms, 0.21 s, 75 MB | 367 ms | 85 ms, 0.14 s, 70 MB |
  | haxe-formatter | 848 ms | 704 ms, 0.86 s, 143 MB | 885 ms | 171 ms, 0.35 s, 105 MB |
  | the port | 6.4 s | 6.2 s, 8.4 s, 1013 MB | 7.6 s | 1.14 s, 3.3 s, 782 MB |

  A cold run pays the HXB encoding (the port: 0.86 s of 7.6 s). The port's
  warm front half: reading its 28 MB pack 0.1 s, decoding the HXB 0.54 s,
  DCE 0.26 s, typing what is left and the sort 0.26 s; validation (558
  modules checked) 15 ms.
- Storage: one pack per server context (the program's, its macros'), each
  an index of files (date, size, content hash) and modules, written whole
  and renamed into place; not a file per module. Later: content-addressed
  blobs shared across keys, and a trim per pack.
- Validation: lazy, only for the modules a build loads (the server checks a
  module when the typer asks for it; HXB decodes on demand). Beyond the
  server's checks (a hook in `ServerCache.checkModule`): the file's content
  hash where its date or size differ (a fresh checkout changes every date;
  a date within 3 s of the parse is not trusted), the file the module's
  path resolves to now (shadowing as a per-module resolution record:
  a new file earlier in the class path makes the module dirty, and its
  dependents through the server's graph), dependencies the store lacks.
- Key: the server's coarse signature (the defines) plus the class paths,
  the working directory and the std. Next: the defines each module's
  conditions read (recorded while parsing), so a define touching user code
  leaves the std's modules alone; then interface hashes of dependencies for
  early cutoff (a dependency typed again with the same signatures, types,
  inline bodies and constants leaves its dependents valid).
- What HXB does not keep and the gate needs: the modifiers of unbound
  monomorphs (`Null<Unknown>`; kept beside the chunks and given back to the
  reader's monomorphs), and what the sort of the types walks of a restored
  module, whose expressions are the filtered ones (its skeleton per field,
  kept and played back through a hook in `Finalization.sortTypes`). The
  upstream server's HXB cache has both differences (its outputs can differ
  from a build without the server); a third shows only in hxmc: an
  anonymous structure's fields in its map's order (now by name).
- Init macros: their effects are data (`addGlobalMetadata` filters,
  `Compiler.define`, class paths); until they are in the key, builds with
  `--macro` do not use the cache. Build macros and `Context` dependencies
  are recorded as the server records them (module dependencies, files
  registered with `registerModuleDependency`, cache-bound resources and
  messages replayed). Nondeterministic macros: see below.
  A macro registering `onGenerate`, `onAfterTyping` or `onAfterGenerate`
  while typing makes the build write nothing (a restored module would not
  register it again).
- Back half: per-module objects move to the same central store, keyed by
  the hash of the lowered IR (`Fingerprint`), shared by every output and
  target ("Central object cache" below). DCE is whole-program: move it to
  link time (reachability over symbols with Haxe's rules: `@:keep`,
  implemented interfaces, overrides of reachable fields, reflection roots;
  reflection tables generated from the live set), so a module's object does
  not depend on the rest of the program; whole-program "features" become
  link-time switches. Program-wide numbering is already symbolic.
  `@:generic` instances belong to the module that instantiates them, as
  mergeable (COMDAT-like) symbols; inline bodies are covered by the
  interface hash.
- Typing order: some Haxe behaviour depends on it (monomorph resolution,
  anonymous type numbering, build macro order, static initialization), and
  restoring changes it; covered by the gate.
- Gate: the same output, byte for byte, with and without the cache, cold,
  warm, after an edit of one module or of a std override, after a new file
  shadows a module (`hxmc/test/ModuleCacheCheck.hx`, `make
  test-module-cache`: hello world, several modules, macros, a
  `Null<Unknown>`, for hxmc and JS; `--port` adds the port itself).
- Not shipping the std as HXB in the distribution: there is no single typed
  std (per target, per define, again for the macro context), the sources
  have to ship anyway, init macros cannot change pre-typed modules, and an
  edited compiler (`hxmc-rebuild`) invalidates it.
- Nondeterministic macros, before the cache is on by default (the server
  trusts them: a macro embedding `Date.now()` keeps its value until its
  module changes; on by default, plain builds would inherit that). The
  macro std's natives are ours, so they decide per module:
  - Volatile: date and time (`Date.now`, `Sys.time`, `Timer.stamp`),
    randomness, the network (`Http`, sockets), processes (`Sys.command`,
    `sys.io.Process`) mark the module being typed as not cacheable; it is
    typed again every build (its macros run), its dependents stay cached
    unless its interface changes.
  - Dependencies instead of volatility: a file a macro reads becomes a
    dependency by content hash (stricter than upstream, where only
    `registerModuleDependency` does it); an environment variable read goes
    into the key with its value.
  - Escape hatches: `@:hxmc.noCache` on a class or module,
    `-D hxmc.no-cache=<lib>`, `HXMC_MODULE_CACHE=0`; `HXMC_MODULE_CACHE_LOG=1`
    says why a module was not cached (the call and its position).
  - `--wait` keeps upstream's behaviour (compatibility); the rule is the
    disk cache's.
  - Gate cases: a macro using `Date.now` runs every build, one reading a
    file only when the file changes, one reading an environment variable
    when its value changes.
- Then: on by default (replacing the types cache), the `npm` postinstall
  warming the std's modules, builds with init macros, `-lib` HXB archives
  as one more source of modules.

### Central object cache and quieter builds

Today every executable gets `<out>.hxmc/` next to it (per-module objects
keyed by code, tool and target, plus `build.key` for the up-to-date check;
`Driver.hx`, `UpToDate.hx`), and the Makefile's build rule writes
`<out>.log` (shown only on failure). Plan: one cache directory instead,
by default a project-level `.hxmc-cache/` (in the npm setup the user cache
directory), overridable with `-D hxmc.cache=<dir>`, keyed so different
outputs and targets can share it, with size-bounded cleanup; logs only on
request. Keeps users' output directories and `bin/` clean.

Done for the cache of the runtime's typed modules (`TypesCache.hx`): it
lives in the user cache directory (`HXMC_CACHE` overrides), one directory
per tool build, entries written by rename with the `.deps` last, tool
directories pruned by last use (14 days, 1 GB) at most once a day; the
module cache ("Cached modules") uses the same location and trim. The
per-module object cache (`<out>.hxmc/`) and the logs still live next to
the outputs; the objects move to that store, keyed by the hash of the
lowered IR.

### Other items

- One-edit rebuilds below 1 s: needs incremental program preparation,
  module keys, data tables and linking, and incremental DCE in the port
  (today 2.0 s through the resident server, 2.7 s without).
- Server builds from `--hxb-lib`: the port's server re-decodes HXB-library
  modules every build, or loses their function bodies with
  `-D disable-hxb-cache` ("static main is not a function"). A port bug to
  check against the reference compiler.
- Program-level dead-code elimination and data-table compaction (type
  info, field names, dispatch rows, string literals).
- macOS: split the runtime's Mach-O objects per function so unused
  runtime code is dropped (ELF does this already).
- Thread-locals: inline macOS's TLV thunk call (a call per function today)
  and trim Windows arm64's three loads per function.

## Interop

### C interop and low-level Haxe (partly built)

The design is in [LOWLEVEL.md](LOWLEVEL.md): a survey of how other
languages do C interop; typed externs called directly in each platform's C
convention, declarations from C declaration text or generated from
headers, an optional embedded tcc at build time; native memory with
lifetimes after Java's FFM API (arenas, segments, `pin`, `Handle`,
callbacks); and an opt-in manual-memory dialect after Zig (`Allocator`,
containers, `@:hxmc.noGc` as a checked boundary). hxmc-only. Built: the
runtime's internal subset, structs by value in C calls on every ABI, and
struct values in the language (2026-10-17: locals, parameters, results,
inline fields, statics, `Slice`, scalar replacement; LOWLEVEL.md,
"Struct values"). Next there: instance methods on structs, specialized
generics for containers of structs (`ArrayList<Particle>`), value enums,
the `Allocator` family.

### Using hxmc's built-in compiler

HXB ties the user's Haxe version to hxmc's. hxmc contains the whole
compiler port, so it (or the haxelib) can compile the user's sources
itself; the "HXB from your own Haxe" path stays for display/IDE use.

## Targets

### Android

ARM64 (and x86-64 for emulators) ELF shared library loaded through JNI or
`NativeActivity`: position-independent code with GOT/PLT, a TLS model for
`.so` (initial-exec/TLSDESC), imports of `libc.so`/`liblog`/`libandroid`
written directly (no NDK), 16 KB segment alignment (Android 15+),
runtime built against Bionic. Packaging without the SDK: binary-XML
manifest, `resources.arsc`, zipalign, APK Signature Scheme v2/v3;
`hasCode="false"` apps need no `classes.dex`. Google Play needs an
Android App Bundle (`.aab`: protobuf manifest/resources). Java glue
(permissions, billing) would need a DEX writer (the port has a JVM
generator) or Google's `d8`.

### iOS

ARM64 Mach-O like macOS arm64 with the iOS platform tag (and the
simulator as its own platform), TLV descriptors, `.app` bundle with
`Info.plist` (launch screen via `UILaunchScreen`, no storyboard), real
certificate signing with entitlements and provisioning profiles (as
`rcodesign` does without Apple tools), `.ipa` packaging. Build from Linux
or Windows; install on devices with libimobiledevice. Open questions:
the app icon's compiled asset catalog (`Assets.car`, undocumented), the
App Store's declared SDK/Xcode version checks, simulator testing (macOS
only). No JIT on iOS.

### WebAssembly

Done (2026-10-14, docs/hxmc.md, "WebAssembly"): `wasm32-wasi`, a linear-memory
module written from Mir (Ramsey-style structuring, SSA values as locals,
exception handling for `try`), linked by hxmc, with the whole runtime in
Haxe: the collector of rt.c single-threaded, malloc over `memory.grow`,
field names and inline caches, strtod and float formatting identical to
the C library's, musl's libm. The corpus passes under node 22 and wasmtime
(threads and sockets excluded), and the port as a module compiles itself
to the reference's HXB under both (15-16 s, native 8.4 s). Left:

- Threads: wasm threads (shared memory, atomics, `memory.atomic.wait`)
  under wasi-threads or a browser's workers; the collector's
  stop-the-world handshake of the native targets (`Threads.hx`) would
  come back. Until then `Thread.create` throws.
- A browser: done for the playground (2026-10-15, docs/hxmc.md, "WebAssembly":
  WASI's imports from JavaScript, `hxmc/web/src/WasiHost.hx`; exnref exception
  handling, on by default in current Chrome, Firefox and Safari). Left:
  WebGPU and input for graphics (see "Graphics"); Firefox's throws walk the
  whole stack (0.17 us per frame each), which a lighter use of exceptions
  in the port's hot paths, or setjmp-free try blocks, would avoid.
- Sockets and processes need WASI preview 2 (or JavaScript imports).
- Speed: no tail calls; 485k `i32.wrap_i64` remain in the playground's
  module, of i64 values (parameters, locals) also used in full: a second,
  i32 local for those with many address uses, or an i32 pointer type in
  Mir, would remove most (about 480 KB raw, little gzipped). The
  port's self-compile is 1.8x native x64's (docs/hxmc.md, "WebAssembly").
- The playground: done (2026-10-15). The site's compiler is the port built
  by hxmc (10.8 MB, 2.1 MB gzipped, against the Emscripten module's 11.5 MB
  and 2.25 MB), with the browser glue above. Further size, if wanted:
  folding a call into its user (30 KB raw, but 16 KB more gzipped), fewer
  wraps (above).

#### WasmGC: a later, browser-focused second path

Not the first WebAssembly target, but worth revisiting. An earlier
prototype compiled the same IR to both (`docs/WASM-BACKEND.md`, removed in
ecb1af2; last version at 4a2c28c), Bench under Node 22:

| | Linear memory (C via Emscripten) | WasmGC |
| --- | --- | --- |
| Run time | 0.39 s | 0.36–0.40 s |
| Module size | 32.2 KB (runtime, malloc, printf) | 2.1 KB (no runtime) |
| Code per function | 1.7–3.2× larger | smaller |
| Peak memory | 146 MB | 86 MB |
| Wasmtime (Cranelift) | | 2.0 s (deferred reference counting) |

For WasmGC: much smaller modules (the engine's collector, `struct.new`
allocation, no shadow stack or barriers), direct JavaScript interop
(objects passed by reference), memory returned to the system. Against it:

- A different runtime, not only a different back end: hxmc's runtime in
  Haxe works on raw memory (`Mem.addr`, loads and stores, layouts), which
  WasmGC objects do not have. Strings, Dynamic access, maps, `Bytes` and
  reflection would need separate WasmGC implementations (the prototype
  never covered Dynamic, anonymous structures or strings).
- Browser-centric: non-browser engines lag (Wasmtime's collector 5× slower
  above); linear memory runs well everywhere, WASI included.
- No threads until shared-everything threads land (WasmGC objects cannot
  be shared between threads).
- Weaker finalizers and weak references.

Revisit when a concrete browser use makes module size or JavaScript
interop matter (the website playground, browser games). The structuring
pass and the module writer of the linear-memory target carry over; the
object model and the runtime would be new.

### APE (Cosmopolitan) executables (dropped)

Dropped (2026-10-15): one file for every system was the Cosmopolitan build
of hxc's C; hxmc builds the six desktop targets natively instead, and the
release binaries and lix ship per platform.

### Shared-library and position-independent output

Needed by Android and plugins: the relocation model, TLS model, output
kind and segment alignment are already parameters in `Abi`/`Target`.

### Windows unwind information

Generated code has no `.pdata`/`.xdata`; nothing needs it while
setjmp/longjmp do not unwind, but debuggers and SEH-based tools would.

### Unwind tables on ELF and Mach-O

Frame pointers are done (docs/hxmc.md, "Pipeline": `-D
hxmc.frame-pointers` on x86-64, always on arm64; `perf record -g` works).
Not done: `.eh_frame` CFI (or `__unwind_info` on macOS), which `perf
--call-graph dwarf`, gdb/lldb backtraces without frame-pointer heuristics
and sampling profilers that do not walk frame pointers need. The prologues
are regular (push rbp / pushes of the callee-saved registers / sub rsp;
stp x29, x30 / sub sp / stores), so one CIE and an FDE per function with a
few instructions each would do; the emitters know every offset. With frame
pointers on, the FDEs reduce to "CFA = rbp + 16" after the prologue.
Making frame pointers the default on Linux x86-64 (as Fedora and Ubuntu
now build): measured 0.8% more code and no difference beyond noise in
time (self-compile -0.5%, the tool's build of the port -1.1%, the
benchmarks between -5% and +4% either way, code-layout noise).

## Graphics

- Prerequisites: C interop (externs, pinned buffers, callbacks from the
  platform's event loop, main-thread handling on macOS) and a dynamic
  glibc output mode on Linux: GPU drivers (Mesa, NVIDIA) are glibc
  shared libraries a static musl executable cannot load. Done:
  `-D hxmc.libc=glibc` links against the system's glibc (`LinkDyn.hx`:
  PT_INTERP, DT_NEEDED, versioned imports pinned to glibc 2.17, bound
  eagerly), `@:hxmc.lib("libGL.so.1")` imports from a system library, and
  `Posix.dlopen`/`dlsym` load drivers at run time (libvulkan's loader).
  Left: a dynamic musl mode (`/lib/ld-musl-<arch>.so.1`, unversioned:
  `Abi.setLibc`), choosing the glibc mode by itself when a program imports
  a shared library, lazy binding (PLT) if startup with many imports needs it.
- Pure Haxe, no C library: back ends call the system APIs through externs
  (COM vtables, `objc_msgSend`, `dlopen`), shipped as source packages
  (Packaging: packages/). API comparison (Kore 3, SDL3 GPU, sokol, WebGPU,
  bgfx): Kore 3 is the model (zlib; WebGPU-shaped, automatic tracking,
  small back ends), without its window/device coupling and `.kong` tools.
- `@hxmc/os` (`hxmc.os`): raw OS bindings (`hxmc.os.win32`, objc + AppKit,
  X11, Wayland) plus windows, input and the app loop. The loop is callback
  driven (`App.run(onFrame, onEvent)`), since Cocoa, GTK and the browser
  own it; a `Surface` can be a window or a child of one (child HWND,
  NSView + CAMetalLayer, Wayland subsurface, canvas).
- `@hxmc/gfx` (`hxmc.gfx`): the portable GPU layer, its back ends, the GPU
  API bindings (`hxmc.gfx.d3d11`, metal, gl, vulkan, webgpu) and the shader
  macro. WebGPU-shaped with integer handles, immutable pipelines, slot
  binding and `setUniforms` into a per-frame ring; automatic sync, two
  frames in flight, no allocation per frame; main thread only. Bind
  groups, compute (behind `device.features`) and threading later.
- Shaders: a Haxe macro emitting HLSL (`D3DCompile` from the system's
  d3dcompiler_47.dll), MSL (`newLibraryWithSource`), GLSL ES and WGSL,
  plus vertex layouts and typed uniform writers (first slice done, below);
  SPIR-V for Vulkan later from a Haxe emitter. Against Heaps' hxsl: shaders
  are plain typed functions (inputs are parameters, outputs return values,
  no globals matched by name), compiled when the program is (no shader
  linker or compiler in the app), typed uniforms and layouts, the math
  runs on the CPU too, no engine.
- Back ends in order: GL 3.3 / GLES 3 on Linux first (glibc mode; EGL and
  libX11 imports; Mesa's llvmpipe and Xvfb run it without a GPU, here and
  on CI), then Metal (done, below), D3D11 (done, below), WebGPU (done,
  below) with WebGL2 for browsers without it (done, below: the GL back
  end), then Vulkan / D3D12.
- First milestone (done): a GL triangle in an X11 window
  (`packages/gfx/examples/Triangle.hx`), checked against a golden image
  headless (EGL pbuffer on Mesa's surfaceless platform, `glReadPixels`) and
  under Xvfb (`XGetImage`) on the Linux CI runners (`make gfx-check`).
  GLES 3.0 through EGL, GL entry points through `eglGetProcAddress`
  (`@:hxmc.indirect`, generated by a build macro). Next: the same program
  on each back end.
- Metal (done, 2026-10-16, macOS arm64): the same `Triangle.hx` in a
  Cocoa window, against the same golden image: exact, headless (an
  offscreen texture blitted to a shared buffer) and windowed (the drawable,
  and the window server's pixels from `CGWindowListCreateImage`, the
  rounded corners left out and the layer tagged with the screen's colour
  space so that nothing converts the values); Apple's GPU rasterizes and
  interpolates the triangle as llvmpipe does, to the byte. `hxmc.os.objc`:
  libobjc's externs, `objc_msgSend` through its address (`dlsym`) as one
  `@:hxmc.indirect` extern per shape (the `Sender` build macro), classes
  made at run time for delegates (`@:hxmc.callback` methods), an
  autorelease pool per frame. `hxmc.os.cocoa.CocoaWindow`: NSApplication,
  an NSWindow whose content view hosts a CAMetalLayer, events polled with
  `nextEventMatchingMask:` and a past date (the loop stays `App.run`'s,
  paced by the drawables; a display link would call back on another
  thread), sizes in pixels. `hxmc.gfx.metal`: MSL compiled at run time
  (`newLibraryWithSource`, entry point `main0`), pipelines from the vertex
  layout (vertex buffers at indices 16 + slot), BGRA8 targets. The back
  ends are chosen by `Mem.os()`, which the lowering folds: no field may
  have a back end's type (`hxmc.gfx.Impl`, an abstract over `Any`), or
  all its methods would be compiled and its libraries imported. Frameworks
  are imported by path (`@:hxmc.lib("/System/Library/Frameworks/Metal.framework/Metal")`,
  an `LC_LOAD_DYLIB` each, as any dylib); AppKit, whose classes are only
  found by name, through one C function (`NSApplicationLoad`). Left:
  macOS x86-64 (`objc_msgSend_stret` for results over 16 bytes: structs
  by value in the System V convention are done), frames during a live
  resize (AppKit's tracking loop runs inside `sendEvent:`: a timer in
  the event-tracking run loop mode), a menu (Cmd-Q).
- D3D11 (done, 2026-10-16, Windows x86-64 and arm64): the same
  `Triangle.hx` in a Win32 window, against the same golden image with the
  same tolerance, headless (an offscreen texture) and windowed (the back
  buffer, and the window's pixels from `PrintWindow` with
  `PW_RENDERFULLCONTENT`, else the screen's DC): exact, on WARP
  (`HXMC_GFX_SOFTWARE=1`; the x86-64 and arm64 CI runners) as under Wine 9
  (wined3d over llvmpipe, Xvfb: `make gfx-check GFX_TARGET=windows-x86_64`;
  Wine's PrintWindow paints no swap chain, the screen's DC has it). `hxmc.os.win32`: user32, kernel32 and gdi32 externs (DLL imports,
  `@:hxmc.lib`); `Win32Window`: one window class whose window procedure is
  a `@:hxmc.callback` (close, size, keys as X11 KeySyms, the mouse and
  wheel), the queue drained with `PeekMessageW` each frame of `App.run`, the
  process per-monitor DPI aware (sizes in pixels, `scale` the DPI / 96);
  user32 calls run in a safe region, since most call the window procedure.
  `hxmc.gfx.d3d11`: `D3D11CreateDevice` (hardware, else WARP),
  `D3DCompile` imported from d3dcompiler_47.dll (HLSL, entry point `main`,
  inputs at `TEXCOORD<location>`, shader model 5.0, 4.0 below feature level
  11_0), COM through vtables (`Com`: a build macro turns `@:slot(n)`
  declarations, the headers' vtable order, into `@:hxmc.indirect` calls
  through the object's vtable), the factory from the device's adapter
  (`IDXGIDevice`, `GetParent`) for a flip-model swap chain
  (`CreateSwapChainForHwnd`, `FLIP_DISCARD`, two RGBA8 buffers,
  `ResizeBuffers` when the window's size changes), `readPixels` through a
  staging texture and `Map`. No call needs a struct by value. Left: a lost
  device (`DXGI_ERROR_DEVICE_REMOVED` throws), the debug layer (frames
  during a live resize, `WM_DPICHANGED` and `WM_CHAR`: below).
- WebGPU (done, 2026-10-16, wasm32-wasi in the browser): the same
  `Triangle.hx` on a canvas, against the same golden image within GfxTest's
  tolerance (SwiftShader in headless Chromium: 422 pixels off by 1,
  `make gfx-web-check`), and on the site (hxmc/web, "Graphics": 64 KB of
  WebAssembly; WebGL2 where WebGPU is missing, below). The import
  convention: a package whose externs are imports of a module
  (`@:hxmc.lib("hxmc_gfx")`) ships `imports.mjs`, whose default export maps
  a host to import objects, possibly asynchronously (the adapter and device
  are requested before `main`); `packages/os/browser.mjs` merges them, gives
  WASI preview 1 without a file system and runs `_start`; JavaScript objects
  live in its handle table, Haxe sees integers. `hxmc.os.web.CanvasWindow`:
  a `Canvas` surface (`Surface.canvas(id)` for a page's own), the buffer
  following the displayed size (Resize), keys and the mouse queued and
  polled per frame; `App.run` returns, and `requestAnimationFrame` runs each
  turn of the loop through a `@:hxmc.callback` called by its index in the
  exported function table (hxmc: `__indirect_function_table`, the runtime
  intact after `_start` returns; corpus case `WasmCallback`), paused while
  the canvas is out of view. `hxmc.gfx.webgpu`: one import per call with
  integer arguments, pipelines from the vertex layout, WGSL with entry point
  `main` (`ShaderCode.wgsl`). `readPixels` cannot wait in a browser: the
  JavaScript side's `readPixels()` (copyTextureToBuffer, mapAsync) instead.
  Left: shader compilation errors are only logged (asynchronous in WebGPU),
  gfx programs in the playground (its compiler would need the packages'
  sources in its bundle, the worker the packages' imports and a canvas,
  e.g. an OffscreenCanvas), node has no WebGPU (the corpus runner stays
  WASI only).
- WebGL2 (done, 2026-10-16, wasm32-wasi in the browser): the triangle
  wherever WebGL2 exists (Firefox on Linux and macOS, older Safari,
  Chromium without WebGPU), with no second back end: WebGL2 is GLES 3.0,
  so `GLBackend` runs there unchanged but for the context, the same
  GLSL ES 3.00 (`ShaderCode.glsl`). `GL`'s build macro (`Loader`)
  makes each declaration an import of the module `hxmc_gl` when typed
  for wasm32-wasi (`-D hxmc.target`), an `@:hxmc.indirect` call through
  an eglGetProcAddress pointer elsewhere (native binaries unchanged in
  behaviour; the Linux checks stay exact). `packages/gfx/imports.mjs`
  implements them on a WebGL2 context: object names are handles of
  browser.mjs's table, strings, buffer data and glReadPixels go through
  the module's memory (`Ptr<Ptr>` entries 8 bytes, hxmc's Ptr), the
  `INFO_LOG_LENGTH` WebGL lacks from the log; `hxmc.gfx.gl.WebGL`: the
  context (`getContext('webgl2', {antialias: false, preserveDrawingBuffer})`
  on the canvas, or an OffscreenCanvas headless), make-current, swap
  (pending JavaScript readPixels) and release. Selection (`Impl`):
  WebGPU when the JavaScript side has a device (`WebGPU.ready`, requested
  before main), else GL (`Backend.WebGL2`), else Device.create throws;
  calls dispatch on the object's class, on wasm only (Mem.os() still folds
  natively). Forced with browser.mjs's option `gfx: 'webgl2'` (the site:
  `?gfx=webgl2`). `Device.readPixels` works there (synchronous
  glReadPixels). Tests: `make gfx-web-check` runs WebTest on both in
  headless Chromium (the same 422 pixels off by 1 on SwiftShader, and
  Device.readPixels' checksum equal to the harness's); browser-test.mjs
  checks the site's triangle through WebGL2 in Chromium (`?gfx=webgl2`),
  WebKit (exact) and Firefox (exact; headless Firefox on Linux has no
  WebGL, so CI runs its triangle headed under Xvfb on llvmpipe). Cost:
  the site's triangle.wasm from 66 to 85 KB (both back ends are in it).
  Left: glGetString (it would return memory), a lost context
  (`webglcontextlost`).
- Shader macro (first slice done, 2026-10-16; `hxmc.gfx.shader`): the
  triangle's shaders are Haxe (`examples/TriangleShader.hx`), exact on GL
  (llvmpipe), D3D11 (Wine), WebGL2 (Chromium, Firefox, WebKit's canvas)
  and as before on WebGPU (SwiftShader: the same 422 pixels off by 1).
  A class implementing `Shaders` (Haxe runs build macros from `@:build`
  or `@:autoBuild` only, so an interface rather than a `@:shader`
  metadata) holds static functions on the math types (`Vec2`, `Vec3`,
  `Vec4`, `Mat4`: inline abstracts over immutable `@:hxmc.struct` values
  since 2026-10-17, so CPU math allocates nothing; swizzles and operators
  written out by `VecBuild`) and `@:structInit` classes of them;
  `ShaderMath` has GLSL's builtins as overloads (`vec4(v.xy, 0, 1)`, `mix`,
  `normalize`, ...). The same functions run on the CPU. `@:vertex` takes
  the vertex (its fields: the attributes, Float32, packed in order) and
  returns the varyings (one `@:position`), `@:fragment` takes them and
  returns the colour; further parameters are uniform blocks. Generated
  members: `vertexCode`, `fragmentCode` (`ShaderCode` in the target's
  languages: GLSL on Linux, GLSL and WGSL on wasm32-wasi, MSL on macOS,
  HLSL on Windows, all four on other targets; `-D hxmc.gfx.shaders`),
  `layout`, `uniforms` (std140 offsets, a binding each), `pipeline()` (a
  `PipelineDesc` with `program`: `Device.createPipeline` compiles it),
  `vertexBytes(vertices)`, `write<Uniform>(u, bytes, offset)`. How:
  build time records each shader class's functions as written; an
  expression macro in the class (`__shaders`) types them again with
  `Context.withOptions({allowInlining: false})` in the class's own
  context, so calls to the math types and `ShaderMath` stay calls; `Lower`
  turns that typed AST into a small structured IR (`Ir.hx`: scalar,
  vector, matrix and struct values, locals, if, while, for over Int
  ranges, calls; expression blocks put their statements first), checking
  the stage interface and rejecting the rest with its position
  (allocation, arrays, closures, Dynamic, strings, recursion, field
  assignment, other classes' functions); four emitters print it (`Emit`
  and `Glsl`, `Wgsl`, `Msl`, `Hlsl`: HLSL's matrices transposed, so the
  columns' memory order is GLSL's; MSL's uniform structs padded to
  std140). Tests (`make gfx-shader-check`, `ShaderTest` on Eval, and CI's
  `gfx` job): shaders run on the CPU, the emitted sources of three shader
  classes against `test/shader/`, nine programs the compiler must reject
  (`test/reject/`, `// expect:` lines as hxmc/test/reject); GfxTest and
  WebTest also compile `LitShader` (uniform blocks, helpers from another
  module) and `BuiltinShader` (every builtin) on each back end (MSL: the
  `gfx-macos` CI job only). Cost (Triangle for Linux): 0.5 s to 0.77 s,
  of which typing the macro's own code in the macro context 0.06-0.1 s,
  running it 15 ms, typing the math types (their swizzles and overloads)
  about 0.08 s; the executable is 1 KB smaller (109 KB). Left
  (uniforms bound at run time, textures, the conventions: below): variants
  (compile-time constants per pipeline), integer vertex formats and flat
  varyings, `switch`, arrays of constant size, matrices other than 4x4,
  SPIR-V, caching emitted code across compilations (the compilation
  server).
- Usable for a real program (done, 2026-10-16): `examples/Cube.hx`, a
  textured, lit, depth-tested cube turning under a translucent panel, on
  every back end and on the site (in place of the triangle, which stays the
  package's simplest example). Uniforms at draw time
  (`Encoder.setUniforms(slot, bytes)`, the bytes from the shader class's
  `write<Block>`): a per-frame ring of 256-byte aligned blocks
  (`UNIFORM_RING`, 256 KB): GL two buffers (frames in flight) bound by
  range (`glBindBufferRange`), the blocks bound to their slots by name when
  a pipeline links (`ShaderCode.bindings`: ES 3.00 has no
  `layout(binding)`); D3D11 a dynamic buffer at constant buffer offsets
  (`VSSetConstantBuffers1`, Map with no overwrite, discarded at a frame's
  first block) where 11.1 has them (WARP), else a dynamic buffer per slot
  discarded at each block (wined3d; `HXMC_GFX_D3D11_NO_OFFSETS=1`); Metal
  `setVertexBytes`/`setFragmentBytes` (4 KB a block); WebGPU dynamic offsets
  into one buffer written before each submit (the queue orders it after the
  previous frames' reads), an explicit bind group layout from the shaders'
  bindings, a bind group per set of textures, made once. Index buffers
  (`setIndexBuffer`, `drawIndexed`, UInt16 and UInt32, a base vertex: GL
  ES 3.0 has none, so the attributes' offsets move); the device's depth
  buffer (GL the default framebuffer's 24 bits, the others a 32-bit float
  texture remade with the target's size; `PassDesc.depth`,
  `PipelineDesc.depthCompare` and `depthWrite`); `PipelineDesc.blend`
  (Opaque, Alpha, Additive, Premultiplied); `Device.writeBuffer`.
  Textures: `createTexture` (RGBA8, one level), `writeTexture`,
  `createSampler` (filter, wrap), `Encoder.setTexture(slot, texture,
  sampler)`; shaders take `Texture2D` parameters (a slot each, shared with
  the uniform blocks in order of appearance), read with `sample(t, uv)`
  (the first level: no derivatives, so WGSL's uniformity rule never
  applies) and passed on to helpers: GLSL `sampler2D` on unit n by name,
  WGSL `texture_2d<f32>` at binding n and its sampler at 16 + n, MSL
  `texture2d` and `sampler`, HLSL `Texture2D` and `SamplerState` at t<n>
  and s<n>; on the CPU the nearest texel. Conventions (WebGPU's, D3D's,
  Metal's): clip z from 0 to w, the fragment position from the target's
  top left, a texture's first row its top; the emitted GLSL maps clip z to
  GL's range and flips `gl_FragCoord.y` with the target's height (a
  uniform the GL back end sets with the pipeline; nothing else differs on
  screen, since NDC is y-up everywhere and readPixels already flips GL's
  rows); `Mat4`'s CPU transforms (perspective, orthographic, rotations).
  `@hxmc/os`: `Text` events (XLookupString, `WM_CHAR` with surrogate
  pairs, Cocoa's `insertText:` through `interpretKeyEvents:` on a
  content view subclass made at run time, a keydown's key), `Wheel` (dx,
  dy in notches, in place of buttons 4 and 5), `ScaleChange`
  (`WM_DPICHANGED` with the suggested size, a new backing scale, a new
  devicePixelRatio), frames during a drag of a window's edge or title bar on
  Windows (a timer inside Windows' loop). Tests: GfxTest and WebTest draw
  both examples against `triangle.png` and `cube.png` with the same rule
  (exact on llvmpipe and wined3d; WebGPU and WebGL2 on SwiftShader 7766
  pixels within 2, 6 beyond, of 245 allowed; Firefox and WebKit 169 within
  1), and check input sent to the window as events (X11, Win32, a posted
  key down on macOS, typing and the wheel in Chromium); `TexturedShader` and
  a texture local the compiler rejects in ShaderTest; CI runs
  `gfx-web-check` in the `gfx` job. Sizes: Cube 194 KB on Linux, 469 KB on
  Windows, 252 KB on macOS, 192 KB of WebAssembly (legacy exceptions);
  Triangle on Linux 109 to 134 KB, its WebAssembly 89 to 144 KB (both
  back ends' new paths are reached through `Impl`). Next: render targets
  (GL: rendering upside down into them, its front faces swapped, so that
  sampling them matches), mip maps and more texture formats, bind groups
  (fewer calls than a slot each), compute; an input method for X11
  (`XOpenIM`, `Xutf8LookupString`: variadic calls) and Cocoa
  (`NSTextInputClient`), frames during a live resize on macOS.
- Structs by value in C calls (done, 2026-10-16 for arm64, 2026-10-17 for
  x86-64 and wasm32; hxmc/LOWLEVEL.md, "Calls and linking"): AAPCS64,
  System V's eightbyte classes, Win64's registers and copies, clang's
  wasm32 rules, classified in `CAbi.hx`. Corpus cases `FfiStruct`,
  `FfiAbi` (against zig cc), `WasmStruct`.
- Later: `@hxmc/ui`, native widgets in an os window (comctl32, AppKit,
  GTK 4 through the glibc mode, DOM), with a GPU view widget built on a
  child `Surface`; a UI drawn with the GPU is a separate package on gfx.
- Engines: a compatibility layer for HashLink's natives (`sdl.hdll`,
  `directx.hdll`, `fmt`) on top of os and gfx would run heaps unchanged.

## Audio

- Output (done, 2026-10-16; `hxmc.os.audio` in `@hxmc/os` 0.3.0): a pull
  model, `Audio.open({sampleRate, channels, frames}, (buffer:Ptr<Float32>,
  frames) -> ...)`, `start`, `stop`, `close`, the rate, channels, period
  and latency the system gave; interleaved floats everywhere. The callback
  runs on an audio thread of the runtime's (`sys.thread.Thread`), never on
  the system's own threads, which the runtime does not know (no thread
  attach: a GC callback may only run on a runtime thread, LOWLEVEL.md):
  ALSA and WASAPI are written to from that thread (`snd_pcm_writei`
  blocking, WASAPI's event), and CoreAudio's render callback, on its I/O
  thread, is `@:hxmc.noGc` and only copies from a ring the audio thread
  fills (positions as atomics, a libdispatch semaphore signalled with a
  `@:hxmc.fast` call: a noGc function may call C only that way). The rule
  for the callback is documentation: no allocation, no locks, no blocking.
  Back ends, the target's chosen by `Mem.os()` as `Window`'s: ALSA on
  Linux (`libasound.so.2` through `dlopen`, a build macro, `hxmc.os.Dl`,
  filling function pointers: a program starts without the library; the
  glibc mode), CoreAudio's default output unit on macOS (AudioToolbox and
  CoreAudio imported by path), WASAPI in shared mode on Windows (COM
  through vtables as D3D11's, `AUTOCONVERTPCM`), WebAudio in the browser:
  an AudioWorklet node fed chunks posted by the main thread, which calls
  the module for one each time the worklet has played one (the module's
  memory is not shared without threads; about 50 ms queued). Tests without
  speakers (`AudioTest`, `make audio-check`, `make audio-web-check`): a
  known signal through the real API and compared where it lands: ALSA's
  file plugin (exact), CoreAudio's generic output unit rendered by
  `AudioUnitRender` (`"file:PATH"`), Wine's WASAPI through winealsa into an
  ALSA file (exact: Wine passes floats through), an `OfflineAudioContext`'s
  rendered buffer in headless Chromium (exact); the callbacks' rate where
  something paces them (Chromium's fake output, a device, CoreAudio's
  renderer; ALSA's null and file sinks take samples as fast as they come,
  and Wine's mixer over them). CI: ALSA on Linux x86-64 and arm64,
  WebAudio in Chromium, CoreAudio on the macOS arm64 runner (the file
  device, and its default output device in real time), WASAPI on the
  Windows runners up to the missing endpoint (none has one: a clear
  error, skipped). Sizes of `examples/Tone.hx`: 121 KB on
  Linux, 187 KB on macOS, 394 KB on Windows, 58 KB of WebAssembly. Left:
  input (capture), device choice and hot-plug (WASAPI's
  `AUDCLNT_E_DEVICE_INVALIDATED`, CoreAudio's default device changing),
  formats other than float, PipeWire or PulseAudio directly, a real-time
  priority for the audio thread (`pthread_setschedparam`, MMCSS's
  `AvSetMmThreadCharacteristics`), an AudioWorklet over shared memory
  once wasm threads exist, a checked `@:hxmc.noGc` callback type for user
  code (the callback running on the system's thread directly).

## Code generation at runtime

The code generator compiles to in-memory objects with relocations, and
program-wide numbers stay symbolic, so these remain possible:

- **Native macros**: compile macro code with hxmc into the running
  compiler instead of interpreting it in Eval. Prototyped (below): feasible.
- **Hot reload / live patching**: replace changed modules in a running
  process (needs runtime registration of new types and dispatch rows).
- **A JIT library** for interpreters written in Haxe (ship only the code
  generator half). Compile speed (~0.5 ms per function single-threaded)
  suits compiling hot functions, not baseline JIT tiers.
- Platform limits: iOS and consoles forbid generating code at runtime,
  macOS hardened apps need the allow-JIT entitlement, browsers use
  WebAssembly instead.

### Native macros (prototype, 2026-10-16)

`make native-macros` (`MACROS=native`). The macro engine is an interface
(`haxe/src/macros/MacroEngine.hx`, Eval by default and in the port's own
builds); `haxe` built with `-D hxmc.jit` (Linux x86-64, static) installs
`hxmc/src/hxmc/macro/NativeEngine.hx`, selected by `-D hxmc.macros=eval|native|verify`:

- **Guest**: on a class's first macro call, a child of the compiler types
  the class's module for hxmc in macro mode (`macro` defined,
  `isMacroContext`, `X.macro.hx`, the std's `Context` with `load(name, n)(args)`
  calling the compiler, entries per static function) and writes a
  relocatable object plus the program-wide facts (types, field names,
  signatures, globals, initializers, dispatch rows).
- **Loader**: links it into the running compiler with `<exe>.syms` (every
  symbol of the executable, written by `-D hxmc.jit` builds, which also keep
  every runtime function and spare `rt_types`, `rt_type_objs` and signature
  entries). The std's types and statics are the compiler's (layouts
  checked), the program's are new: spare type entries, run-time field names
  (the runtime's `Names` has them), new `rt_globals` slots, dispatch rows per
  bundle. Code and data are mapped below 2 GB (rel32, and dispatch rows are
  absolute disp32), then the code made executable (`mprotect`).
- **Bridge**: native objects to and from Eval values, so MacroApi stays the
  one implementation: anonymous structures, enums (positions as Eval keeps
  them: construction sites recorded by the guest, constructors without
  arguments by place), Refs (`GuestRef`), lazy values, API function values,
  positions and other values opaque; API exceptions catchable by macro code.
- **verify**: both engines per call, Eval's result used; Eval's API calls
  (and calls of the function values they return) recorded and replayed to
  the native run, so no side effect happens twice; results, positions,
  errors and the API call sequence compared.

Results: the 66 macro cases pass in verify mode: 119 macro calls, 115
native, 114 identical (positions included), 1 mismatch (Issue8466:
`Sys.programPath()` is null in Eval's macro std, not in hxmc's), 4 on Eval
(a module the child fails to type, a class missing from the macro
context, a class extending an earlier bundle's, values the bridge lacks). Native mode writes
byte-identical HXB for 65/66. GfxTest: its 40 macro calls compile and run
natively, the executable is identical in verify mode, 23 calls match; the
shader macro does not yet (verify: nested macro calls during the Eval run
advance the native statics too; native mode: output differs, not
investigated).

Time: compiling a macro class takes about 0.4 s (the child, typing with the
types cache); the macro cases' native execution is 3 ms against Eval's 11
ms, compiles 32 s. A compute-bound macro (a sieve) runs 20x faster
natively (16 ms against 346 ms for 3 calls); an API-bound one (2000
`makeExpr` calls per call) as fast as Eval: the conversions at the boundary
cost what interpretation saved. So the gain needs cached compiles and comes
from macro code that computes, not from macro code that mostly calls the API.

Blockers found and what a production version needs:

- Macro code is typed for Eval (its std's externs): it has to be typed
  again for hxmc. Do it in process (or from HXB) and cache the objects per
  macro module on disk, keyed by sources, tool and defines; tier: Eval
  first, compile the classes that run often.
- A macro std with Eval's semantics (`Sys.programPath`, integer overflow,
  negative array indices, ...), else native and Eval results differ.
- Static state belongs to one engine: a class's functions run all natively
  or all on Eval, and a fallback after a native run started is unsafe.
- A new class extending a class of an earlier bundle: instance tests use
  index spans compiled into code, so new classes need spare index ranges
  (slack after each class) and earlier dispatch rows patched.
- Crashes in macro code (a null access is a SIGSEGV in hxmc code) must
  become errors: a signal handler returning to the macro call, or null
  checks in macro mode.
- W^X per platform: macOS `MAP_JIT` with `pthread_jit_write_protect_np`
  (and the allow-JIT entitlement when hardened), Windows `VirtualAlloc` and
  `VirtualProtect` plus `FlushInstructionCache`, arm64 instruction cache
  maintenance and branch ranges (ADRP is ±4 GB, BL ±128 MB: veneers or a
  mapping near the image), PIE executables (the symbol map relative to the
  load address).
- The bridge's maps of positions keep their objects alive (weak maps), and
  bundles are never unloaded (the compilation server).
- The bigger win: the compiler's own AST and types as native haxe.macro
  values (encoding and decoding without Eval values), which an engine that
  shares the compiler's heap allows.

### Bootstrap plus bundled program

Executables made of a small native bootstrap (runtime, code generator,
loader) and the program as a portable archive, compiled at first launch
(then cached per CPU and version), lazily per function (self-patching
stubs), or tiered. One program archive for every platform, code tuned for the actual CPU,
plugins and mods, small updates. Costs: first-launch latency, runtime
code generation limits above, a larger footprint than one AOT executable
for small programs.

Archive format: hxmc's own lowered IR rather than HXB. When the bootstrap
and the archive always ship together the format is private and needs only
a version stamp (no long-term spec), but HXB would still mean a larger
bootstrap (HXB reader, typed-AST structures, lowering), lowering on every
user's machine, and compiler internals and absolute paths in shipped
programs. A versioned format matters only if archives and bootstraps are
built separately (plugins, patches from a newer hxmc, a shared installed
bootstrap).

## Packaging

- The `hxmc` haxelib (`-lib hxmc`, `--custom-target hxmc=out`,
  `-D hxmc.target=<os>-<arch>`), as hxc had one.
- Release builds of the hxmc tool for the six desktop targets.

### packages/: everything published to npm

npm first, haxelib later. One folder per package, published by the same
CI job (versions not yet on npm), each with its own version:

- Done (2026-10-16): `packages/cli` (`@hxmc/cli`, laid out as its tarball:
  package.json, the launcher in hxmc/bootstrap, `dist/haxe`), `wasm`,
  `source`, `platform` (the template for the six platform packages), all
  packed by `packages/pack.mjs` at the build's version; hxmc/bootstrap keeps
  stage0, wasi.mjs and rt.mjs. Any other `packages/<name>` with a version of
  its own is packed as it is and published at that version.
- `packages/os`, `packages/gfx`, later `packages/ui` (Graphics): sources
  only, a peer dependency on a range of `@hxmc/cli`; for WebAssembly in the
  browser, an `imports.mjs` each (and `@hxmc/os`'s `browser.mjs`, the
  runner: Graphics, WebGPU).
- Done (2026-10-16): `-lib hxmc.gfx` from node_modules (a `"haxe"` field in
  package.json: class path, extra hxml, dependencies), in the compiler
  (`hxmc/src/hxmc/NodeLibs.hx`, through `compiler.HighLevel.libraryHook`):
  lix's haxe_libraries first, then node_modules, then haxelib (docs/using.md (  hxmc").

### npm: a WebAssembly package that bootstraps itself natively

Done (2026-10-15, docs/using.md): the package `hxmc` at the
repository root (`make npm`), with `hxmc-rebuild`; left: checking the
native build against a published hash. Since 2026-10-16 split in nine
(`packages/`, above): `@hxmc/cli` (launcher, std, runtime objects),
the six platform packages, `@hxmc/wasm` (the fallback, installed or
downloaded and checked against a pinned integrity) and `@hxmc/source`
(`hxmc-rebuild`, with the native compiler). The plan as it was:

One platform-independent npm package containing the compiler (the port
with hxmc) as a WebAssembly module, a small JavaScript launcher, the std
and the per-target runtime objects (runtime, mbedtls, libuv; a few MB
uncompressed for the six targets).

- First use on one of hxmc's six targets: the launcher runs the
  WebAssembly compiler under node's WASI to build the native compiler for
  the host, caches it per version and platform (e.g.
  `~/.cache/haxe/<version>/<os>-<arch>/`, with a lock and an atomic rename
  for concurrent first runs); later calls run the native binary directly.
  The first command can run in WebAssembly (about 1.7–2× native time)
  while the native build happens in the background.
- Other platforms keep running the WebAssembly build.
- Verifiable: builds are deterministic (the port self-compiles to
  identical HXB, the tool rebuilds itself identically), so the binary built
  on the user's machine can be checked against the hash published with the
  package — stronger than trusting a downloaded binary.
- Compared with esbuild's model (one optional-dependency package per
  platform): one artifact to publish, no install scripts (often disabled)
  and no downloads (works offline and air-gapped).
- Costs and constraints: a one-time native build per version and machine
  (estimated 15–25 s under WebAssembly; less with the cached std unit);
  node 22 needs flags for WebAssembly exception handling and a workaround
  flag for large memories (the launcher passes them; or hxmc emits the
  legacy exception-handling encoding); the WebAssembly fallback has no
  processes or sockets (compilation server, `sys.io.Process` in macros,
  haxelib's git/HTTP work only natively); a freshly written unsigned `.exe`
  may draw antivirus scans on Windows (no download mark, though); macOS
  binaries carry hxmc's ad-hoc signature and no quarantine flag.
- Needs: the launcher, the runtime objects packaged per target, mbedtls
  and libuv linked into the native compiler (see "sys.ssl and libuv"),
  ideally the std's modules from the module cache (see "Cached modules") for a faster first run.
