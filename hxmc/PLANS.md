# hxmc: future plans

Ideas and directions discussed for hxmc, not scheduled. Each entry says
what it is, why it matters and what it needs. Current state is in
[README.md](README.md); this file is what could come after.

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
  are gone from `rt/`, `rt_str.c` is folded into `rt_dyn.c`, Facts' names
  no longer follow hxc's C emitter, the census is a debug build of the
  runtime object.
- Kept: `mkstd.py` (a custom target gets no `_std` directory in the
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

Moving `rt/` from C to Haxe compiled by hxmc, Go-style: strings, Dynamic
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

### sys.ssl and libuv

The runtime objects are built with `HXMC_NO_SSL`/`HXMC_NO_UV`; precompile
mbedtls and libuv per target and link them only when referenced.

## Build times and size

### Precompiled std as cached HXB

Most of a small program's build is the front half typing the std from
source on every build. Hello world (one 4-core VM): 0.375 s from source,
about 330 ms of it parsing and typing; 0.13–0.15 s when everything comes
from an HXB archive (76 ms to read it, codegen 47 ms). Go 1.24 on the same
machine: 4.8–5.7 s cold, 0.18–0.23 s rebuilding after an edit (warm build
cache). With only the std precompiled and the program typed from source,
expect about 0.15–0.2 s.

Plan, Go-style (built lazily and cached rather than shipped):

- On first use, hxmc writes the std modules a program needs as HXB into a
  cache directory; later builds load them with `--hxb-lib` (upstream
  Haxe's mechanism for precompiled libraries) and type only the program.
- Cache key: the target (the std has per-OS code), the defines the std's
  conditionals read (`-debug`, user `-D` flags), and the hxmc version.
  hxmc writes the archive with its own built-in compiler, so the HXB
  version always matches.
- HXB modules load on demand: a large cached std does not slow small
  programs.
- Modules the user's class path overrides (shadowed std types) must come
  from source, never the cache.
- Gate: the same executable, byte for byte, from the cached path and the
  source path (the Vector bug showed the two paths can differ subtly).
- Simpler than the compilation server for most of the gain; the server
  remains the route for large programs' one-edit rebuilds.

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

### C interop (designed, not built)

Swift-inspired, without embedding Clang:

- Externs generated from C headers at development time (libclang offline,
  or a small C front end with a preprocessor), checked into the library.
- Calls in the platform's C convention (System V, AAPCS64, Win64, Apple
  arm64), static libraries via hxmc's linker (ELF, COFF, later Mach-O),
  dynamic libraries via import tables written directly (no SDK, no
  import libraries); prebuilt per target in haxelibs.
- `hxmc.Ptr<T>`, `hxmc.CString`; structs by pointer first, by value later
  (the System V classification rules, tested against a C compiler).
- Moving GC: scoped pinning for the duration of a call
  (`withPointer(buf, p -> c_fn(p))`), pinned buffers for shared data,
  handles for long-lived references (the `Unmanaged` equivalent).
- Callbacks: static Haxe functions only (`@convention(c)`-style), state
  through `void *userData` handles; trampolines leave the runtime's safe
  region and catch exceptions; threads created by C attach to the
  runtime first.
- Inline C and C++ are out of scope (no C compiler); C glue is
  precompiled per target by library authors.

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

In progress: a linear-memory target with the shadow-stack collector
(WebAssembly cannot scan its own stack), a structured code generator from
hxmc's IR (no register allocation, locals instead) and a module writer far
simpler than the ELF/PE/Mach-O linkers. Aimed at a module produced from
Haxe only: the runtime in Haxe including a single-threaded collector, a
musl-derived libm subset, an allocator over `memory.grow`; exceptions
through WebAssembly exception handling; WASI or JavaScript imports for the
system; threads later via SharedArrayBuffer (COOP/COEP). Intrinsics map
almost one to one (`i64.load`, atomics).

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

### APE (Cosmopolitan) executables

One file for Linux, macOS, Windows and the BSDs, x86-64 and arm64: link
against the runtime built with cosmocc, System V convention everywhere,
Cosmopolitan's TLS conventions (verify against its source), and the APE
polyglot layout (MZ/PE, shell script, ELF, Mach-O, zip;
`ape/specification.md`) written by hxmc's linker; the zip part can carry
assets (`/zip/`). On hold.

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
stubs), or tiered. One program archive for every platform (with an APE
bootstrap, one file for all of them), code tuned for the actual CPU,
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
  `-D hxmc.target=<os>-<arch>`), like hxc's.
- Release builds of the hxmc tool for the six desktop targets.
