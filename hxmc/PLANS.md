# hxmc: future plans

Ideas and directions discussed for hxmc, not scheduled. Each entry says
what it is, why it matters and what it needs. Current state is in
[README.md](../README.md); this file is what could come after.

## Medium term

The next performance steps after the runtime moves to Haxe; both are in
the code generator and help every target.

### Stack maps instead of the shadow stack (tried, reverted)

Tried at e91b276 (stage 5a), reverted to the shadow stack (README,
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

The collector itself stays C on the native targets (README, "Runtime in
Haxe").

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

### Cleanup after the runtime move (done)

Done (README, "Runtime in Haxe"):

- One source per runtime area: the haxe.atomic cells are written over
  the `Atomic` intrinsics, `hxmc.NativeZip` is the implementation,
  `hxmc.NativeSys`/`NativeNet` dispatch by `Mem.os()` to typed POSIX and
  Windows classes, `hxmc.Native` (reflection) calls `hxmc.rt.Dyn`. No
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
`@:hxmc.noGc` helpers, and the rule is in the README ("Runtime in
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

### The runtime in Haxe (in progress)

Moving `hxmc/c/` from C to Haxe compiled by hxmc, Go-style: strings, Dynamic
access and maps, std natives, OS wrappers, thread coordination, finally
the GC. Built on internal intrinsics (raw loads/stores, pointer
arithmetic, atomics, fences), compiler-checked no-GC functions and C-ABI
externs. What stays native: startup, stack switching, the thread
trampoline, exception unwinding (setjmp/longjmp or hxmc's own), the
Windows exception handler; libc/libm or the system libraries; mbedtls
and libuv.

Shims that cannot be intrinsics are written per architecture through
hxmc's own encoders, as "naked" functions:

```haxe
@:hxmc.naked static function switchStack(newSp:Ptr, fn:Ptr):Void {
  #if hxmc_x64
  X64.mov(R11, RSP); X64.mov(RSP, RDI); X64.push(R11); X64.call(RSI); X64.pop(RSP); X64.ret();
  #elseif hxmc_a64
  ...
  #end
}
```

Keep these to a handful: instruction sets, calling conventions and
memory models differ per architecture; everything else goes through the
machine-independent IR and intrinsics.

### Direct system calls on Linux

With the runtime in Haxe, static Linux executables could call the kernel
directly (as Go does) and drop musl. Windows and macOS keep going
through their system libraries (kernel32/ntdll, libSystem).

### Math: the `libm` branch's Haxe libm everywhere (eventually)

Today native targets use musl's libm (C, through zig) and WebAssembly a
Haxe port of it. musl differs from glibc by an ulp on some inputs
(`Math.sin(-2.5)`: -0.598472144103956438 against glibc's ...549), so the
port's `--interp` and macros can print a last digit different from the
reference on Linux (the fuzzer accepts printed floats an ulp apart).

The goal: the Haxe libm of the `libm` branch (98d9d82, and 374bb61 with
the `Mem.mulhi`/`umulhi`/`f64Bits`/`bitsF64` intrinsics and `Mem.fma`)
used everywhere — every native target, WebAssembly and the compiler's own
Eval natives — replacing musl's C, with the same results on every OS.
Not now: it lands once it is no slower than main at run time, compile
time and size.

- What it is: exp/log/pow from Arm's Optimized Routines (glibc's own code,
  MIT; bit-identical to glibc), sin/cos/tan/asin/acos/atan/atan2 from
  CORE-MATH (MIT, correctly rounded: equal to glibc except where glibc is
  an ulp off, about 1 input in 1,000), fma in hardware where the CPU has
  it. Tested exact against glibc and CORE-MATH's 9.5 million hard cases.
- Why not yet: CORE-MATH's trig is slower than musl even in C (cos 17 ns,
  tan 24 ns against 6.5 and 10.5 on x86-64), hxmc's code ran 1.3–2.5×
  gcc's on the same algorithms, and the ~166 KB of table literals were
  typed on every build (hello world 0.34 s to 0.5 s; a Math-heavy program
  118 KB to 292 KB).
- To get there: `mulhi` and 128-bit intermediates kept in registers (begun
  in 374bb61); the math modules loaded only when called; the tables as raw
  data instead of literals; one copy of each fast path. One math
  implementation only: where a CORE-MATH function costs too much, that
  function switches to a faster algorithm (musl's), no second variant
  behind a define.
- The compiler's Eval natives use the same library: the port then differs
  from the reference (glibc) only where glibc is an ulp off, about 1 input
  in 1,000 for trig; the fuzzer already tolerates printed floats an ulp
  apart (`Runner.sameOutput`), rather than a second, glibc-exact copy
  being kept for the compiler.

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

Done (2026-10-15, README "sys.ssl and libuv"): mbedtls and libuv built per
target with zig at our build time (`hxmc/c/deps.sh`), turned into
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

### Cached units per library

Most of a small program's build is the front half typing the std from
source on every build. Hello world (one 4-core VM): 0.375 s from source,
about 330 ms of it parsing and typing; 0.13–0.15 s when everything comes
from an HXB archive (76 ms to read it, codegen 47 ms). Go 1.24 on the same
machine: 4.8–5.7 s cold, 0.18–0.23 s rebuilding after an edit (warm build
cache). With only the std precompiled and the program typed from source,
expect about 0.15–0.2 s.

Plan, Go- and Rust-style (built lazily and cached rather than shipped):

- Units: the std, each `-lib`, and the user's code last. Each is stored per
  hxmc version and target (`~/.cache/hxmc/<version>/<target>/<lib>-<key>/`):
  its typed modules as HXB (the front half, loaded with `--hxb-lib`,
  upstream Haxe's mechanism for precompiled libraries; HXB modules load on
  demand, so a large cached std does not slow small programs), hxmc's IR
  and inline templates for inlining across units, and the compiled objects
  per module (the back half: the existing per-module object cache). hxmc
  writes the archives with its own built-in compiler, so the HXB version
  always matches.
- Key: the library's sources (a content hash; version plus hash for git and
  dev libraries), the hxmc version, the target, only the defines the unit's
  `#if` conditions actually read (recorded while parsing), and the
  interface hashes of the units it depends on (signatures, types, inline
  bodies, constants; not function bodies, as Go and Rust do).
- Hard parts, and how to solve them. The rule throughout: record what a
  unit's typing actually depended on, key on that, and type from source
  whenever something cannot be captured (a miss costs time, never
  correctness).
  - Macros from outside that change a unit's types. Init macros run before
    typing and their effects are data: `addGlobalMetadata` is a list of
    (path filter, metadata), `Compiler.define` changes the defines. The key
    takes the entries whose filter matches a module of the unit and the
    defines the unit reads, so a `--macro` touching only user code leaves
    the std's key alone. `Compiler.keep`, `nullSafety` and the like act
    after typing (DCE, checks) and stay out of the key. Build macros that
    run while a unit is typed (`@:build` on a library class, a library
    macro reading other types): record which macro modules executed (their
    sources and dependencies, hashed) and which types they looked at
    (`Context.getType` ...: module dependencies, as the compilation server
    records them), keyed by those modules' interface hashes. `@:autoBuild`
    runs on the subclass, in the user's unit. `onAfterTyping`/`onGenerate`
    run on the loaded program every build (the cache holds the state
    before them, as upstream's `--hxb-lib` does). `onTypeNotFound` firing
    during a unit, or anything else not captured, marks it volatile: typed
    from source.
  - Class-path shadowing. Every cached module records the lookups its
    typing made: the file each name resolved to, and the misses (names
    searched across packages, `import pkg.*`). Before a cached module is
    used its lookups are checked against the current class path (mostly
    directory listings, as the server checks modification times); a
    shadowed module comes from source and invalidates its dependents
    through the per-module dependency graph (HXB has it), with early
    cutoff as in Rust: a shadowing module with the same interface hash
    leaves its dependents valid. hxmc's own std overriding upstream files
    is then just part of the std unit's resolution.
  - Macro dependencies (files read through `Context`, defines, environment
    variables): recorded as the server does. Nondeterministic macros
    (time, network) are trusted as by the server, with an opt-out per
    library (`-D hxmc.no-cache=<lib>`).
  - DCE is whole-program: make the source path take the cached path's
    route, so the two are identical by construction. Every unit compiles
    all its functions once, before DCE, one section per function; DCE moves
    to link time (reachability over symbols with Haxe's rules: `@:keep`,
    implemented interfaces, overrides of reachable fields, reflection
    roots), and the reflection tables (`Reflect.fields`,
    `Type.getInstanceFields`) are generated at link time from the live set.
    Builds from source go through per-unit objects and link-time DCE too.
    Whole-program "features" (code that depends on whether something is
    used anywhere) must not be decided while a unit compiles: they become
    link-time switches (symbols the linker resolves, data flags).
  - Program-wide numbering is already symbolic and resolved at link time.
  - `@:generic` instances belong to the unit that instantiates them, named
    by their type arguments and emitted as mergeable (COMDAT-like) symbols:
    the linker keeps one when several units instantiate the same. Library
    inline functions inlined into user code are covered by the interface
    hash (inline bodies are part of it).
  - Typing order: some Haxe behaviour depends on it (monomorph resolution,
    anonymous type numbering, build macro order, static initialization),
    and loading from a cache changes it. Covered by the HXB conformance
    suite (typed ASTs survive the round trip) and the gate below.
- Order: link-time DCE and the shared pipeline first (needed anyway,
  testable alone); then the std as one unit with the lookup recording;
  then `-lib` units, with interface hashing, early cutoff and the tracking
  of defines; then the capture of init macros' effects. The user's code
  stays incremental per module (the server, the object cache). It also
  shortens the first run of the npm bootstrap (see "npm" under
  Packaging).
- Gate: the same executable, byte for byte, from the cached path and the
  source path (the Vector bug showed the two paths can differ subtly).
- Simpler than the compilation server for most of the gain; the server
  remains the route for large programs' one-edit rebuilds.

### Central object cache and quieter builds

Today every executable gets `<out>.hxmc/` next to it (per-module objects
keyed by code, tool and target, plus `build.key` for the up-to-date check;
`Driver.hx`, `UpToDate.hx`), and the Makefile's build rule writes
`<out>.log` (shown only on failure). Plan: one cache directory instead,
by default a project-level `.hxmc-cache/` (in the npm setup the user cache
directory), overridable with `-D hxmc.cache=<dir>`, keyed so different
outputs and targets can share it, with size-bounded cleanup; logs only on
request. Keeps users' output directories and `bin/` clean.

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

### C interop and low-level Haxe (designed, not built)

The design is in [LOWLEVEL.md](LOWLEVEL.md): a survey of how other
languages do C interop; typed externs called directly in each platform's C
convention, declarations from C declaration text or generated from
headers, an optional embedded tcc at build time; native memory with
lifetimes after Java's FFM API (arenas, segments, `pin`, `Handle`,
callbacks); and an opt-in manual-memory dialect after Zig (`Allocator`,
containers, `@:hxmc.noGc` as a checked boundary). hxmc-only.

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

Done (2026-10-14, README "WebAssembly"): `wasm32-wasi`, a linear-memory
module written from Mir (Ramsey-style structuring, SSA values as locals,
exception handling for `try`), linked by hxmc, with the whole runtime in
Haxe: the collector of rt.c single-threaded, malloc over `memory.grow`,
field names and inline caches, strtod and float formatting identical to
the C library's, musl's libm. The corpus passes under node 22 and wasmtime
(threads and sockets excluded), and the port as a module compiles itself
to the reference's HXB under both (15-16 s, native 8.4 s). Left:

- Threads: wasm threads (shared memory, atomics, `memory.atomic.wait`)
  under wasi-threads or a browser's workers; the collector's
  stop-the-world handshake would come back (rt_thread.c's other half, in
  Haxe this time). Until then `Thread.create` throws.
- A browser: done for the playground (2026-10-15, README "WebAssembly":
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
  port's self-compile is 1.8x native x64's (README "WebAssembly").
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

## Graphics

- Prerequisites: C interop (externs, pinned buffers, callbacks from the
  platform's event loop, main-thread handling on macOS) and a dynamic
  glibc output mode on Linux: GPU drivers (Mesa, NVIDIA) are glibc
  shared libraries a static musl executable cannot load.
- Layer: sokol (`sokol_app`, `sokol_gfx`, `sokol_audio`): small, Metal /
  D3D11 / GL / GLES / WebGPU back ends, precompiled per target into the
  runtime archives and linked only when used; shaders compiled ahead of
  time with `sokol-shdc` and embedded. SDL3 as the heavier alternative.
- Bindings generated from the headers; a first milestone is a triangle
  on all six desktop targets, then Android, iOS and WebAssembly come with
  those targets.
- Engines: a compatibility layer for HashLink's natives (`sdl.hdll`,
  `directx.hdll`, `fmt`) would run heaps unchanged.

## Code generation at runtime

The code generator compiles to in-memory objects with relocations, and
program-wide numbers stay symbolic, so these remain possible:

- **Native macros**: compile macro code with hxmc into the running
  compiler instead of interpreting it in Eval, calling the compiler's
  functions directly.
- **Hot reload / live patching**: replace changed modules in a running
  process (needs runtime registration of new types and dispatch rows).
- **A JIT library** for interpreters written in Haxe (ship only the code
  generator half). Compile speed (~0.5 ms per function single-threaded)
  suits compiling hot functions, not baseline JIT tiers.
- Platform limits: iOS and consoles forbid generating code at runtime,
  macOS hardened apps need the allow-JIT entitlement, browsers use
  WebAssembly instead.

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

### npm: a WebAssembly package that bootstraps itself natively

Done (2026-10-15, README "Using hxmc"): the package `hxmc` at the
repository root (`make npm`), with `hxmc-rebuild`; left: checking the
native build against a published hash. The plan as it was:

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
  ideally the cached std unit (see "Cached units per library") for a faster first run.
