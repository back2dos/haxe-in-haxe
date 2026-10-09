# backend/: hxc, a C backend for Haxe (EXPERIMENTAL)

hxc compiles a typed, filtered Haxe program (the data an HXB archive holds)
to C, and a C compiler turns that into a native binary or, with Emscripten,
WebAssembly. It is an explicit scope expansion beyond the port's HXB
conformance work; the go/no-go that started it is
[bench/WASM-BACKEND.md](../bench/WASM-BACKEND.md).

Its main program is the port itself: the C build of `haxe.Main` passes the
HXB conformance suites and every target-independent step of upstream's test
suite (test/TESTING.md), and compiles itself faster than the OCaml compiler
with a lower peak RSS (bench/README.md). It also builds other programs, for
example haxe-formatter (`tools/format-src.sh`), which then formats
`haxe/std` 1.6× faster than its C++ and Node builds with identical output.

| Path | |
| --- | --- |
| `src/backend/` | The backend tool: `Main.hx` runs the port's compiler and receives the filtered program through `compiler.Compiler.generateHook`; `Lower.hx`/`FnLower.hx` lower the typed AST to the IR (`Ir.hx`); `EmitC.hx` writes C. |
| `rt/` | The C runtime: `rt.c` (GC, allocation, exceptions, finalisers), `rt_thread.c` (threads), `rt_dyn.c` (Dynamic access, maps), `rt_str.c`, `rt_std.c`, `rt_sys.c`, `rt_net.c` (sockets), `rt_ssl.c` (mbedtls), `rt_uv.c` (libuv), `rt_census.c` (heap census); `rt.h`, `rt_gc.h`. |
| `std-hxc/` | The hxc target's std: overrides of the Haxe std (`sys.thread`, `sys.net`, `sys.ssl`, `sys.io`, `haxe.atomic`, `EReg`, ...) and the `hxc.Native*` externs implemented by the runtime. `tools/mkstd.py` merges it with the Eval originals needed for macros into `backend/std`. |
| `haxelib/` | The `hxc` haxelib package: the target for your own Haxe (below). |
| `bench/` | Test and benchmark programs: `threads/`, `natives/` (Luv, LuvThreads, Tls), `exc/`, `regress/`, `Bench.hx`. |
| `tools/` | `cosmo-deps.sh` (mbedtls/libuv for Cosmopolitan), `mkunicode.py` (regex tables), `besttime.py`, and the prototype's baseline builders and wasm runners. |

## Builds

`build.sh` builds the backend tool (with the reference compiler, to JS), runs
it on a program and compiles the C with `CC` (default tcc):

```sh
sh backend/build.sh port                                    # the port: bin/backend/hih/hih (tcc)
CC="clang -O2" BIN=hih_clang sh backend/build.sh port       # the fastest build
CC="gcc -O2" BIN=hih_o2 sh backend/build.sh port
RT_NO= RT_LIBS="-lmbedtls -lmbedx509 -lmbedcrypto -luv" sh backend/build.sh port   # link mbedtls/libuv
sh backend/tools/cosmo-deps.sh                              # bin/cosmo-deps (once, ~2 min)
CC="cosmocc -O2" RT_DEPS=bin/cosmo-deps BIN=hih.com sh backend/build.sh port       # portable APE
sh backend/build.sh backend/bench/threads Threads && bin/backend/Threads/prog_c    # another program
```

| Compiler | Use | Threads | Notes |
| --- | --- | --- | --- |
| tcc | development: the port's 16 MB of C compiles in about a second | green (M:1) | code 2–2.5× slower than clang/gcc -O2 |
| clang -O2 | fastest code (4–10% ahead of gcc -O2 on the self-compile, builds faster; -O3 adds nothing) | OS (1:1) | preferred by the haxelib package |
| gcc -O2 | release builds | OS (1:1) | |
| cosmocc -O2 | one binary for Linux, macOS, Windows, the BSDs (x86-64 + aarch64) | OS (1:1) | only Linux x86-64 tested (bench/COSMO.md) |
| Emscripten (em++) | the website's playground: wasm64, compiled as C++ so `RT_TRY` is wasm exception handling | none | `site/build.sh`; `EMXX=em++` in `build.sh` for linear-memory wasm |

Every build passes `-fno-strict-aliasing` (slots are read through casts).
Without `RT_NO=`/`RT_DEPS` the mbedtls and libuv natives are stubs that throw
when called (`-DHXC_NO_SSL -DHXC_NO_UV`). The port itself is compiled with
`-D disable-parallelism` only for its own typing; the resulting binary runs
its parallel passes unless *its* invocation passes that define.

## The emitter

- **Lowering** (`Lower.hx`, `FnLower.hx`): everything reachable from `main`.
  `Int`, `Bool` and `Float` are unboxed; everything else is a pointer.
  Generics are erased (a type parameter is `Dynamic`), with boxing,
  unboxing and adapter closures where a declared type and a use-site type
  differ (calls, returns, field and enum-argument access). Function bodies
  are lowered to A-normal form: calls and allocations only as the value of
  an assignment, so evaluation order and GC points are explicit.
- **Objects**: classes and anonymous structures are a header word plus
  8-byte slots; Int/Bool fields are packed two per slot (`EmitC.layout`).
  Virtual calls go through a dispatch table indexed by the header's type
  index; anonymous and `Dynamic` field access use field ids and inline
  caches. Dynamic methods have a slot holding their current function, so
  they can be reassigned.
- **Roots** (`EmitC.Roots`): only references live across a call or an
  allocation get shadow-stack slots; everything else is a plain C local.
- **Exceptions**: `try` becomes the `RT_TRY` macros: `_setjmp`/`_longjmp`
  natively (GCC treats `__builtin_setjmp` too optimistically at `-O2`), a
  C++ `try`/`catch` under Emscripten.
- `HXC_SURVEY=<file>` records unsupported constructs and the natives a program needs.

## The runtime

### Objects and memory

Object layouts (`rt/rt.h`): a header word, then 8-byte slots.

- Classes and anonymous structures pack Int/Bool fields two per slot (in
  field order, the second fills the free half of the previous one; a
  subclass's layout extends its superclass's). Generated code and the
  runtime address them by 4-byte index (`FH`), which is what
  `rt_field.slot` holds for 'i'/'b' fields of every type. `core.Pos` is 24
  bytes instead of 32.
- Enum values have no tag slot: the constructor is the header's type index
  (constructors of an enum have consecutive indices in tag order, so
  `Type.enumIndex` of a known enum is `TINDEX(v) - base`). Argument-less
  constructors are shared values.
- An `Array` is 24 bytes (length, element kind, data); its capacity is the
  data block's slot count. `[]` has no data block; literals and copies get
  exactly their length, growth from empty goes 2, 4, 8...
- Strings are UTF-16, as on HashLink. One byte per character would save 1.6
  MB of the 5.5 MB of strings live at the end of the self-compile, less than
  1% of the heap, for a change touching every string native; the port's
  lexer interns identifiers per file instead (13.6 → 5.5 MB). A GC that
  deduplicates promoted strings saved 2 MB more but cannot be used: string
  identity is observable in the port (`StrTools.physNeq`, OCaml's `!=` on
  position file names, changes HXB output).

### GC and memory policy

A precise generational copying collector: a 4 MB nursery (`RT_MINOR_KB`)
and a copying old generation, roots from the shadow stack, a write barrier
recording old-to-young slots, depth-first copying (an object's descendants
land right after it, in the order the compiler's tree walks visit them).

- The from-space is returned to the kernel after a major collection
  (`RT_RELEASE=0` keeps it); the to-space is faulted in as the copy reaches
  it, with a populate-ahead batch of an eighth of the space in use (4–32 MB,
  `RT_AHEAD_MB`).
- `rt_barrier_range` remembers a whole object for ranges longer than 16
  slots (the port's `Array.insert` at the front of large arrays used to add
  the array's length to the remembered set at every call), and `rt_set_ptr`
  does not record a slot again that already held a young pointer.
- The first old-space limit is 256 MB (`RT_OLD_MB`), then 3× the live data
  after a major collection. Sizes stay generic rather than tuned to the
  self-compile.

Self-compile, gcc -O2 (bench/README.md, "hxc memory"): live heap at exit
214 → 170 MB, peak RSS 837 → 467 MB (the reference: 531 MB), CPU 5.7 → 5.0
s. With a copying old generation the peak is about the old space at the last
major collection plus what survives it; a mark-sweep or mark-compact old
generation would remove the to-space from the peak.

### Heap census and statistics

| Variable | |
| --- | --- |
| `RT_STATS=1` | each major collection (live, from-space, new limit), peak RSS, and thread counters: threads started, contended mutex acquisitions and their wait, stops of the world and the time to stop |
| `RT_CENSUS=1` | a heap census at exit, after a major collection (`RT_CENSUS=2`: also after every major collection; `RT_CENSUS_TOP=n` rows) |
| `RT_MINOR_KB`, `RT_OLD_MB`, `RT_AHEAD_MB`, `RT_RELEASE`, `RT_TLAB_KB` | nursery size, first old-space limit, populate-ahead batch, returning the from-space, TLAB size with several threads |
| `RT_STACK_MB` | the main thread's C stack (default 1 GB reserved, as OCaml 5's main fiber) |
| `RT_HUGE=1`, `RT_BFS=1` | transparent huge pages for the heap (costs more kernel time than it saves here), breadth-first copying (for comparison) |

The census (`rt_census.c`) reports bytes and counts per type, an estimate of
the same data in OCaml's representation (a word per field, 1-byte strings,
arrays as OCaml arrays), strings (Latin-1 share, length histogram,
duplicates), arrays (empty, length histogram, capacity slack),
arrays/strings/maps by the type and field that first refers to them, the
heap's sizes, malloc'd memory and RSS.

### Threads: OS threads (1:1) and green threads (M:1)

`rt/rt_thread.c` runs Haxe threads on **OS threads** (pthreads, in parallel)
in gcc, clang and cosmocc builds, and as **green threads** in tcc builds
(tcc has no `__thread`/`_Thread_local`; `-DRT_GREEN_THREADS` selects them
with gcc too). The wasm playground has no threads. Programs use them through
the hxc `sys.thread` package (`std-hxc/sys/thread`, over `hxc.NativeThread`)
and `haxe.atomic` (over `hxc.NativeAtomic`). In the port that is the
compilation server, the `--connect`/`--cmd` I/O threads, Eval threads
(`--interp`, `eval.luv`) and the parallel compiler passes (`TaskPool`/
`Parallel`: filters, analyzer, DCE marking, HXB writing; run without
`-D disable-parallelism`). Self-compile with clang -O2 (bench/README.md):
5.20 s sequential, 4.18 s with 4 threads (the OCaml compiler: 6.11 s
sequential, 4.03 s with 4 domains); the sequential cost is unchanged from
the green-threads runtime.

#### OS threads

- Thread-local runtime state: the shadow stack (`rt_sp`, `rt_stack_base`),
  the allocation buffer (`rt_young_ptr`, `rt_young_limit`), the handler chain
  (`rt_hcur`) and the pending exception (`rt_exn`) are `__thread` variables
  with the local-exec TLS model (`rt.h` `RT_TLS`): one `%fs`-relative access,
  as cheap as the global it replaces, so generated code is unchanged. A
  thread record holds its 64 MB C stack and 64 MB shadow stack (reserved,
  committed as touched); the main thread keeps its 1 GB ones.
- Allocation: the nursery is shared; each thread bumps through its own chunk
  (TLAB) taken from it with a CAS: with one thread the chunk is the whole
  free nursery, with several a 16th of it (`RT_TLAB_KB`). Large objects go
  to the old space with a CAS on its bump pointer. The fast path
  (`rt_alloc`) is unchanged.
- Stop-the-world collections: the thread whose allocation finds the nursery
  (or old space) full sets `rt_gc_requested` and waits under the world lock
  until every other thread is stopped at a **safepoint** (the allocation slow
  path `rt_alloc_slow`, where the caller's live references are rooted) or in
  a **safe region** (`rt_blocking_enter`/`leave` around blocking calls), then
  collects on its own thread: every thread's shadow stack, pending exception,
  Tls values and entry closure are roots (`rt_threads_scan`), every thread's
  remembered slots and objects are processed (`rt_mutators_foreach`), every
  TLAB is reset, and the threads resume. A second thread that wants to
  collect meanwhile waits as at a safepoint and retries its allocation. State
  changes use seq_cst atomics (Dekker-style: either the collector sees a
  thread safe, or the thread sees the request); the slow paths take the
  world lock.
- Safe regions hold no heap pointer outside the shadow stack (natives root
  what they need and read it again after leaving): waiting for a descriptor
  (`rt_wait_fd`, a `poll` in 100 ms slices so a `close` by another thread
  makes the wait fail with EBADF), sleeping, contended mutex/semaphore/
  condition waits, `waitpid`, `Sys.command`, host name resolution
  (serialized: `gethostbyname` is not reentrant), TLS BIO `send`/`recv`
  (`sslRead`/`sslWrite` go through a malloc'ed copy, since the heap buffer
  may move meanwhile) and libuv's backend wait in `Loop.run`. Leaving a safe
  region waits for a collection in progress.
- Write barrier: each thread appends to its own remembered set
  (`rt_mutator`), merged by the collector; a thread that ends hands its set
  to a "dead" mutator kept until the next minor collection.
- Shared runtime tables: field names added at run time live in chunks that
  never move (readers take no lock; adding takes a leaf lock), as does the
  `eval.luv` handle table. Inline caches are filled once with a CAS (0 →
  busy → type, published with release order) once a second thread exists; a
  miss on an entry filled for another type looks the field up in a
  per-thread table of immutable entries. Identity hashes are set with a CAS
  on the header; cached string hashes are a benign same-value race (relaxed
  atomics); finaliser registration/dequeuing and the native-handle list have
  leaf locks. Statics are initialized eagerly at startup. Leaf locks
  (`rt_lock`, taken only once a second thread was started) are never held
  across a safepoint.
- `sys.thread` primitives are natives: `Mutex` (re-entrant, a pthread mutex
  plus owner/depth), `Condition` (its own mutex and a pthread condition on
  `CLOCK_MONOTONIC`; spurious wakeups possible as on other pthread targets),
  `Lock`/`Semaphore` (a counting semaphore), `Deque` (Haxe over a mutex and a
  condition), `Tls` (per-thread slot arrays kept with the thread record).
  Handles are `T_NATIVE` objects freed by the collector once unreachable
  (`rt_native_new`); a thread waiting on one roots it. The primitives'
  internal pthread mutexes are taken "safely" (try, else wait in a safe
  region) because a holder may wait for a collection when it leaves a wait.
- `haxe.atomic` (`std-hxc/haxe/atomic`): `AtomicInt` is a raw cell and
  `AtomicObject` a one-slot reference array, with sequentially consistent
  `__atomic` operations (object stores go through the write barrier);
  `AtomicBool` is the std's, over `AtomicInt`.
- `TaskPool` (`src/core/ds/TaskPool.hx`) keeps persistent worker threads on
  hxc, as on HL/C. With `RT_STATS`, the self-compile in parallel mode shows
  3 workers, ~840 contended acquisitions (0.3 s waiting) and ~410 stops of
  the world (0.19 s in total, max 6 ms) on a loaded 4-core machine.
- Shared mutable state of Haxe code is the program's business, as on any
  threaded target: a Haxe `Array` mutated by two threads at once can lose
  elements. Upstream's OCaml leans on immutable lists (`l <- x :: l` is
  memory safe under races) where the port mutates arrays in place, so such
  spots need a lock in the port: the parallel filters' inline-call recording
  (`Inline.hx`, `mInlineCalls`) takes a mutex, shared `EReg`s (which keep
  their last match) were replaced by fresh ones (`RenameVars`,
  `AnalyzerTexpr`, hxc `EReg.escape`), and hxc `Regex`'s lazily built case
  sets are published whole.
- ThreadSanitizer: instrumenting the whole program does not work (libtsan's
  fixed-size shadow call stack overflows in the port's parser, and TSan then
  hangs in its signal handler). Instrumenting the runtime only does: the
  generated C compiled plainly with `-D__SANITIZE_THREAD__` (so `RT_TRY`
  uses the intercepted `setjmp`), `rt*.c` with `gcc -fsanitize=thread
  --param tsan-instrument-func-entry-exit=0`. That sees every access the
  runtime makes (allocation, barriers, arrays, strings, maps) and every
  lock; it found the `mInlineCalls` race (test/TESTING.md).

#### Green threads (tcc)

- Switching: `ucontext` (`makecontext`/`swapcontext`). A thread record holds
  its C stack and shadow stack (64 MB each, reserved), handler chain and
  pending exception; a switch saves the globals `rt_sp`, `rt_stack_base`,
  `rt_hcur` and `rt_exn` (`RT_TLS` is empty here) and loads the next
  thread's. One mutator (remembered set, TLAB) serves all of them.
- Scheduling points: parking in the primitives (queues of parked threads in
  C; they do not allocate between looking at a primitive and parking, so
  they need no atomics), `Sys.sleep` (0 yields), waiting for a descriptor,
  and each minor collection (`rt_alloc_slow`), so a spin loop that allocates
  does not starve the others; one that never allocates does.
- I/O while other threads exist: a blocking socket (`rt_net.c`) is used
  without blocking (`MSG_DONTWAIT`, a `poll` before `accept`, a non-blocking
  `connect`) and the thread waits for the descriptor in the scheduler,
  honouring `setTimeout`; `Socket.select` waits in the scheduler; pipe and
  terminal reads and writes wait until ready; `Process.exitCode()` polls the
  child; `close` makes a waiter fail (EBADF). When no thread can run the
  scheduler waits in `poll` up to the nearest timer; if none can ever be
  woken it prints `fatal: deadlock, every thread is blocked forever` and
  exits with 1. Still blocking the process: stdout/stderr writes,
  `Sys.command`, file system calls, host name resolution, TLS and libuv calls
  other than `Loop.run`.
- `haxe.atomic` operations are plain (no thread switches inside them).

#### Both

- `eval.luv` threads (`src/macros/eval/EvalLuv.hx`): `Thread.create` runs the
  Eval function on a new thread with its own Eval thread context;
  `ThreadPool.queueWork` hands the work to a pool of `UV_THREADPOOL_SIZE`
  threads (default 4), and a finished work signals a `uv_async_t` of its
  loop, whose callback (inside `Loop.run`) calls the after-work callback.
  `Mutex`, `RwLock`, `Semaphore`, `Condition`, `Barrier` and `Once` are Haxe
  over the hxc `sys.thread` primitives. Eval code itself is serialized by
  the port's Eval lock (`EvalLock.hx`, OCaml's runtime-lock semantics).
- Exit: the process exits when the main thread's `main` returns. An uncaught
  exception ends only its thread (`Thread.onAbort` prints it). Thread ids are
  small integers (main: 1); `Thread.events` is not available (the custom
  target does not define `target.threaded`).
- Under `__EMSCRIPTEN__` there are no threads: `Thread.create` throws
  "threads are not supported", a wait that would block forever throws, and a
  timed wait sleeps and times out.

`backend/bench/threads/Threads.hx` checks the package (`sh backend/build.sh
backend/bench/threads Threads && bin/backend/Threads/prog_c`; with
`CC="clang -O2"` on OS threads).

### Finalisers and regular expressions

- `rt.c` keeps OCaml's `Gc.finalise` semantics for Eval's `eval.vm.Gc`
  (`hxc.NativeGc`, used by `src/macros/eval/EvalStdLibA.hx`): a finaliser's
  function is a root and its value a root of minor collections only; a major
  collection that finds the value unreachable copies it back (it lives on
  for the call) and queues the call. Queued calls run at the next allocation
  slow path or after Eval's `Gc.minor`/`major`/`full_major`/`compact` (which
  collect). This is why upstream's `unit.TestGcFinalizer` passes on the hxc
  build of the port. Weak references are not provided.
- `hxc.Regex` (EReg) follows PCRE2 with `PCRE2_UCP`, as Eval and HashLink:
  `\d \w \s \b` and the POSIX classes use Unicode properties and caseless
  matching uses Unicode case variants (tables from `tools/mkunicode.py`). It
  matches UTF-16 code units: `.` and classes see the two halves of a
  surrogate pair separately.

### Sockets, TLS and libuv

`sys.net.Socket`/`Host` are real (`std-hxc/sys/net`, over `rt_net.c`; IPv4).
`rt/rt_ssl.c` (mbedtls 2.28 API, behind `hxc.NativeSsl`) backs the Eval
interpreter's `sys.ssl`/`mbedtls.*` (`src/macros/eval/EvalSsl.hx`) and the
hxc target's own `sys.ssl` (`std-hxc/sys/ssl`: `Socket`, `Certificate`,
`Key`; `setCertificate`, `addSNICertificate` and `Digest` are missing there,
as in Eval). `rt/rt_uv.c` (libuv 1.x, behind `hxc.NativeUv`) backs
`eval.luv` (`src/macros/eval/EvalLuv.hx`). `-DHXC_NO_SSL`/`-DHXC_NO_UV`
build stubs that throw when called.

- Native builds link the system's libraries: `RT_NO=
  RT_LIBS="-lmbedtls -lmbedx509 -lmbedcrypto -luv"` (Ubuntu:
  `libmbedtls-dev libuv1-dev`, mbedtls 2.28, libuv 1.48).
- Cosmopolitan builds link static libraries built with cosmocc by
  `tools/cosmo-deps.sh` (fat x86-64 + aarch64 `.a` files and headers in
  `bin/cosmo-deps`; pinned mbedtls 2.28.10 and libuv 1.48.0, fetched with git
  at their tags and checked against the pinned commits, patched with
  `tools/cosmo-patches/*.patch`). `haxelib/build.sh` (`hxc.com`) and
  `site/build.sh` (`haxe-in-haxe.com`) run it and link the result
  (`NO_DEPS=1` keeps the stubs). User programs built with `-D hxc.static
  -D hxc.ssl`/`-D hxc.uv` link the copy in the haxelib package (`cosmo/`,
  1.6 MB zipped).
- mbedtls under Cosmopolitan: entropy from `getrandom()` (the patch).
  System CA certificates (`Certificate.loadDefaults`): `Sys.systemName()` is
  "Linux" on every OS in an APE build, so `hxc_NativeSsl_certLoadDefaults`
  picks the source at run time: the std's Linux file list on Linux,
  `/etc/ssl/cert.pem` on macOS (keychain additions are not seen), the std's
  BSD list on the BSDs, and on Windows the system "Root" store through
  `crypt32.dll` (loaded with `LoadLibraryA`).
- libuv under Cosmopolitan is built as its generic unix port: the `poll(2)`
  backend, no file system events (`FsEvent` fails with ENOSYS; `FsPoll`
  works), interfaces through `getifaddrs` (no hardware addresses), memory,
  load and uptime through `sysinfo`, and `src/unix/cosmo.c` (the patch) for
  the executable path, CPU count, resident set size and random bytes.
  Cosmopolitan's errno constants are variables, so libuv's `UV_E*` codes take
  the fixed values of its Windows table and system errors are translated at
  run time (`uv__cosmo_err`); interface names in IPv6 scope ids are numeric
  only, and source-specific multicast is unsupported.
- `Loop.run` with one thread is `uv_run`. While other threads exist (e.g.
  `eval.luv` thread pool work or a thread that will `Async.send`), it runs
  `UV_RUN_NOWAIT` iterations and waits in between (in a safe region with OS
  threads, in the scheduler with green threads) for the loop's backend
  descriptor up to `uv_backend_timeout`, so an `Async.send` from another
  thread wakes it. A thread spawned by a callback during a plain `uv_run`
  stops it (`rt_spawn_hook`) and the run continues that way; `Loop.stop` is
  remembered across those iterations. libuv's own thread pool runs file
  system and DNS requests in C; their callbacks run on the loop's thread.

`backend/bench/natives/Luv.hx` (timers, a TCP echo, file system requests, a
child process with a pipe, idle handles, system queries), `LuvThreads.hx`
and `Tls.hx` (a local `openssl s_server`: handshakes with and without
verification, host name check, system CAs; an HTTPS GET) check a build:

```sh
sh bin/backend/hih/hih.com -cp backend/bench/natives -main Luv --interp
openssl s_server -accept 4433 -cert cert.pem -key key.pem -www &   # cert for localhost, signed by ca.pem
sh bin/backend/hih/hih.com -cp backend/bench/natives --run Tls 4433 ca.pem example.com
```

## The hxc haxelib package

`backend/haxelib/` packages the target for the user's own Haxe; usage and
options are in [haxelib/README.md](haxelib/README.md). The user's Haxe types
the program; the init macro (`hxc/Boot.hx`) makes it write the program as
HXB and, after generation, runs the bundled `bin/hxc.com` on the archive
(`--hxb-lib`) and then the C compiler (`-D hxc.cc`, else the first of clang,
cc, gcc, tcc; `-D hxc.static` for cosmocc). `hxc.com` is the port with the C
backend, compiled by itself to C and with cosmocc to one APE binary.

```sh
sh backend/haxelib/build.sh          # bin/haxelib/hxc.zip (cosmocc on PATH, or NATIVE_CC=clang; about 5 min)
haxelib install bin/haxelib/hxc.zip
haxe -lib hxc -cp src -main Main --custom-target hxc=out/main
```

The archive must come from the Haxe build `hxc.com` was made from (the
pinned `haxe/`; recorded in the package's `hxc.json`). The tool runs with the
user's std path as `HAXE_STD_PATH`: DCE reruns on the loaded modules and
treats classes outside the std path as user code (kept whole).

Checked: a Map/sort/exception program and a macro/Reflect/Json program with
cc, tcc and `-D hxc.static`; `--no-output`, `-D hxc.c-only`, type errors and
`haxelib run hxc`; `Tls.hx` with `-D hxc.static -D hxc.ssl` and with tcc and
the system's mbedtls, and `hxc.NativeUv` with `-D hxc.static -D hxc.uv`;
haxe-formatter (`tools/format-src.sh`). The backend tool built through the
package gives byte-identical C to the source build.

## Limits

- Coverage: the language and std features that the port and the programs
  above need. Weak references are missing; sockets are IPv4 only.
- Threads: a loop that never allocates and never blocks delays a
  collection (there are no polls at loop back-edges; every loop in the port
  allocates or calls something that does); a blocking call outside a safe
  region (a write to a full pipe, `accept` after another thread took the
  connection, file system calls) likewise. With green threads (tcc) such a
  loop starves the other threads. `Thread.create` ignores the stack size.
- Memory ordering: racy publication of new objects between threads (no lock
  or atomic) relies on x86-64's store order, as the port mirrors upstream's
  benign races (e.g. InlineConstructors reading another field's expression
  while it is rewritten; OCaml 5 guarantees this, C does not). The aarch64
  half of the APE build is not validated for it, and TSan reports these as
  occasional `Array_slice` races.
- Portability: only Linux x86-64 has run the binaries; the aarch64 half of
  the APE build, macOS, Windows and the BSDs are untested (Windows is the
  least likely to work: libuv's unix code depends on Cosmopolitan's
  emulation of `poll` on pipes, `fork` and Unix sockets). The generated C
  needs a POSIX toolchain.
- No heap verifier: the earlier `RT_VERIFY` checks were removed when the
  remembered set became per-thread.
