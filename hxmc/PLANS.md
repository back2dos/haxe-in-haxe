# hxmc: future plans

Ideas and directions discussed for hxmc, not scheduled. Each entry says
what it is, why it matters and what it needs. Current state is in
[README.md](README.md); this file is what could come after.

## Medium term

The next performance steps after the runtime moves to Haxe; both are in
the code generator and help every target.

### Stack maps instead of the shadow stack

Measured: up to 21% fewer instructions (mandelbrot_anon), 11% binarytrees,
9% formatter; estimated real gain 5–10% on call- and allocation-heavy
code. The shadow stack is also the largest remaining size item, about
3 MB of the port's code. Design (OCaml-style): references live across
collecting calls in frame slots, descriptors keyed by return address and
registrable per code region, frame-pointer walk, Haxe→C transitions
recorded so the walk skips C frames, C runtime keeps a shadow stack for
its own roots. hxc and a WebAssembly target keep the shadow stack.

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

### Cleanup after the runtime move

Once the runtime is in Haxe and stack maps have landed, simplify what the
C-runtime era left behind:

- **One source per runtime area.** Today each area has an extern class
  with untyped `Dynamic` signatures (`hxmc.NativeAtomic`, `NativeSys`,
  `NativeNet`, `NativeZip`, ...) and a separate Haxe implementation
  exported under C symbol names (`hxmc.rt.Atomics` with
  `@:hxmc.host("hxmc_NativeAtomic_...")` and `@:keep`). Collapse each pair
  into one typed implementation used directly by the std (e.g.
  `haxe.atomic.AtomicInt` written over the `Atomic` intrinsics). Gains:
  calls inline instead of crossing an extern boundary; dead-code
  elimination drops unused runtime parts (no `@:keep`); the exported
  functions no longer get lowered and compiled for every program (the
  ~50 ms per build the move added). Keep `@:hxmc.host` exports only for
  functions the remaining C code calls.
- **Leftovers from hxc and other environments:** Emscripten, Cosmopolitan
  and tcc/green-thread code in `rt/`; the remaining small C files
  (`rt_str.c`, `rt_dyn.c`) folded into Haxe or the shims; names and
  structure inherited from hxc's EmitC in `hxmc.ir.Facts`; the census as a
  debug-only build.
- **Std layout:** the std overrides merged with the Eval originals by
  `mkstd.py`; see what can become plain sources once the extern layer is
  gone.
- **Tools and tests:** scripts and benchmarks that only mattered while
  hxc was the oracle or the build host.

## Language and runtime

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

A separate structured code generator from hxmc's IR (hxc's structured
form is kept long enough for this; no register allocation, locals
instead), a module writer far simpler than the ELF/PE/Mach-O linkers.
Linear memory with the shadow-stack GC (WebAssembly cannot scan its own
stack), or WasmGC (`WASM-BACKEND.md` has a prototype). Exceptions through
WebAssembly exception handling, threads via SharedArrayBuffer (COOP/COEP)
or green threads, WASI or JavaScript imports for the system. With the
runtime in Haxe, the runtime compiles along with the program (no
Emscripten build); intrinsics map almost one to one (`i64.load`, atomics).

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
  process (needs runtime registration of new types, dispatch rows and,
  with stack maps, frame descriptors).
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
