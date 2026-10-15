# hxmc: low-level Haxe (design, not built)

C interop, native memory with lifetimes, and an opt-in manual-memory
dialect, as one design. hxmc-only: these APIs exist only in hxmc builds
(native and WebAssembly); no portable fallback for other Haxe targets is
planned. Current state of hxmc is in [README.md](README.md), other
directions in [PLANS.md](PLANS.md).

The three layers build on each other:

1. **C interop**: typed externs called directly in the platform's C
   convention, C structs, pointers.
2. **Native memory with lifetimes** (after Java's FFM API): arenas,
   bounds-checked segments, pinning and handles for the moving GC.
3. **Manual memory** (after Zig): an `Allocator` interface, containers
   over it, and `@:hxmc.noGc` as a checked boundary between GC code and
   code that never touches the GC heap.

The names below are illustrative.

## 1. How other languages do C interop

| Family | Examples | How | Trade-off |
| --- | --- | --- | --- |
| Embedded C compiler reads headers | Swift (Clang importer), Zig (`@cImport`, `translate-c`), Kotlin/Native (`cinterop`) | headers imported as native types; inline functions and macros work | seamless, but a whole C front end (tens of MB) inside the compiler |
| Bindings generated offline | Rust `bindgen`, Java `jextract`, Dart `ffigen`, ClangSharp, Clang.jl | libclang turns headers into declarations, checked in | users need no C toolchain |
| Declared signatures, direct calls | Crystal `lib`, Odin/Jai/C3 `foreign`, Julia `ccall`, .NET `[LibraryImport]` and `delegate* unmanaged`, Java FFM downcalls, Go `purego` | the compiler emits native calls from declarations | as fast as native; ABI lowering per platform in the compiler |
| Dynamic FFI at run time | libffi (`ctypes`, JNA, `cffi` ABI mode), LuaJIT FFI (`ffi.cdef` parses C declarations at run time), koffi, Deno FFI | the call is built at run time | flexible; libffi is slow per call, LuaJIT's JIT is not |
| C compiler at run or install time | Bun `bun:ffi` (TinyCC compiles glue at run time, `cc()` compiles C files), `cffi` API mode, Go cgo (system gcc/clang at build time) | C glue compiled on the user's machine | covers macros and inline functions; cgo calls are expensive |
| Compile to C or C++ | Nim, hxcpp, HL/C, hxc | generated code includes headers | free interop, which hxmc gives up by generating machine code |

Also relevant: HashLink's `.hdll` natives (`DEFINE_PRIM` with type
signatures), for a possible HashLink-native compatibility layer (heaps),
and the WebAssembly component model (WIT, canonical ABI).

hxmc's choice: declared signatures with direct calls (family 3), with
declarations written by hand, parsed from C declaration text, or generated
from headers offline (family 2), plus an optional embedded tcc at build
time for the C that cannot be declared (family 5, at build time only).

## 2. C interop

### Declarations

```haxe
@:hxmc.lib("SDL2")                              // the library providing the symbols
extern class SDL {
  @:hxmc.c("SDL_Init") static function init(flags:UInt32):Int;
  @:hxmc.c("SDL_CreateWindow") static function createWindow(title:CString, x:Int, y:Int, w:Int, h:Int, flags:UInt32):Ptr<SDL_Window>;
  @:hxmc.c("SDL_RenderFillRect") static function fillRect(r:Ptr<SDL_Renderer>, rect:Ptr<SDL_Rect>):Int;
}

@:hxmc.struct class SDL_Rect { var x:Int32; var y:Int32; var w:Int32; var h:Int32; }
@:hxmc.opaque class SDL_Window {}            // only ever behind a Ptr
```

- C declaration text, LuaJIT-style: a small C *declaration* parser in Haxe,
  used from a macro, turns pasted declarations (`int SDL_Init(Uint32
  flags);`, structs, enums, typedefs, function pointers) into the externs
  above. No preprocessor, no libclang.
- Full headers: a development-time generator over preprocessed headers
  (`zig cc -E` or `clang -E`), output checked into the library.
- Types: `Int8..Int64`, `UInt8..UInt64`, `Float32`, `Float`, `Bool`,
  `Ptr<T>`, `CString`, `@:hxmc.struct` classes (C layout, offsets per
  target), `@:hxmc.opaque`, function pointers (`Callback<F>`).

### Calls and linking

- hxmc emits direct calls in the target's C convention: System V, AAPCS64,
  Win64, Apple arm64 (variadic arguments on the stack, x18 reserved),
  Windows arm64. Structs by pointer first; by value later (System V's
  classification rules, tested against a C compiler's output).
- Static libraries: hxmc's linker reads ELF, COFF and Mach-O objects and
  archives already; per-target prebuilt objects ship in haxelibs, linked
  only when referenced.
- Dynamic libraries: import tables written directly (`DT_NEEDED` on ELF,
  import directory on PE, `LC_LOAD_DYLIB` on Mach-O): no SDK, no import
  libraries. On Linux this makes the executable dynamic (glibc's loader);
  static musl executables cannot load glibc libraries (GPU drivers, see
  PLANS.md "Graphics").
- WebAssembly: C functions become module imports (WASI or JavaScript).

### What declarations cannot cover: optional embedded tcc

`static inline` functions and function-like macros in headers, and small
C glue files a library ships, need a C compiler. Optionally, hxmc embeds
TinyCC (a few hundred KB) and compiles them at build time, as Bun does at
run time: no system toolchain, tcc's modest code quality only matters for
glue. tcc writes ELF and PE for x86-64 and arm64; Mach-O support is
limited, so macOS takes tcc's ELF objects through hxmc's linker or
precompiled glue. Inline C in Haxe source and C++ stay out of scope.

## 3. Native memory with lifetimes (after Java's FFM API)

hxmc's GC moves objects, so C must never keep a pointer into the GC heap
without the runtime knowing. Native memory comes from arenas instead, and
GC objects reach C only through two explicit doors.

```haxe
// Arena.scoped(a -> ...)  freed when the function returns or throws
// Arena.auto()            freed by the GC once unreachable (finalizer)
// Arena.global            never freed
// Segment<T>              a bounds-checked view over arena memory, tied to its arena
// Ptr<T>                  a raw typed pointer: what C takes and returns (unchecked)

function drawBox(renderer:Ptr<SDL_Renderer>) {
  Arena.scoped(arena -> {
    var rect = arena.alloc(SDL_Rect);           // zeroed, native memory
    rect.x = 10; rect.y = 10; rect.w = 100; rect.h = 50;
    SDL.fillRect(renderer, rect.ptr());
  });                                            // freed here, also on exceptions
}

Arena.scoped(arena -> {
  var title = arena.cstring("Hello");           // UTF-8 + NUL, copied once
  var buf = arena.allocBytes(4096);             // Segment<UInt8>
  var n = Posix.read(fd, buf.ptr(), buf.length);
  var text = buf.toString(0, n);                // copied back into a Haxe String
});
```

`Arena.scoped` takes a closure that hxmc inlines when it is called in
place: the arena is a bump allocator in the frame, with no closure or heap
allocation at run time (Haxe has no try-with-resources; this plays that
role).

### The two doors from the GC heap

```haxe
// pin: a GC object stays in place for the duration of a call
var pixels = haxe.io.Bytes.alloc(w * h * 4);
pixels.pin(p -> SDL.updateTexture(tex, null, p, w * 4));
// p must not be kept by C: after the closure the object may move again

// Handle: a stable token for a GC object that C keeps
var h = Handle.of(app);
SDL.addEventWatch(onEvent, h.ptr());
// ... later
h.release();
```

### Long-lived native resources

```haxe
class Window {
  final arena = Arena.auto();                   // freed when the Window is collected
  final handle:Ptr<SDL_Window>;
  public function new(title:String)
    handle = SDL.createWindow(arena.cstring(title), 0, 0, 640, 480, 0);
  public function close() {                     // deterministic cleanup, when wanted
    SDL.destroyWindow(handle);
    arena.close();
  }
}
```

### Callbacks

```haxe
@:hxmc.callback static function onEvent(userData:Ptr<Void>, event:Ptr<SDL_Event>):Int {
  var app:App = Handle.get(userData);           // GC-safe lookup
  app.handle(event.type);
  return 0;
}
```

- Static functions only (no captured state), as Swift's
  `@convention(c)`; state through `void *userData` handles.
- hxmc generates the C-callable trampoline: it leaves the runtime's safe
  region, sets up the thread's runtime state (shadow stack, exception
  handler), calls the function, and catches exceptions so they never
  unwind through C frames.
- Threads created by C attach to the runtime before calling GC code (a
  public attach/detach entry point); `@:hxmc.noGc` callbacks (section 4)
  need no attachment.

### Safety

- Use after free: a segment checks that its arena is open (an epoch
  compare); release builds may turn the check off.
- Bounds: segments know their length.
- Moving GC: native memory never moves; GC objects reach C only through
  `pin` (scoped) or `Handle` (long-lived).
- Leaks: scoped arenas free on any exit; auto arenas fall back to the GC.
- `Ptr<T>` stays the unchecked escape hatch, like C.

Differences from Java's FFM: struct types over memory give typed field
access compiled to plain loads and stores (Java needs `get`/`set` with
layouts); the scoped closure replaces try-with-resources.

## 4. Manual memory (after Zig)

An opt-in dialect for low-level code: no GC allocation, explicit
allocators passed as arguments, values and pointers only. Arenas from
section 3 are one kind of allocator, so C interop and low-level Haxe share
one memory model.

```haxe
interface Allocator {
  function alloc(bytes:Int, align:Int):Ptr<UInt8>;
  function resize(p:Ptr<UInt8>, old:Int, bytes:Int):Bool;   // in place, or false
  function free(p:Ptr<UInt8>, bytes:Int):Void;
}
// implementations: Arena, FixedBuffer, Pool<T>, Malloc (libc / Win32 heap /
// WebAssembly memory.grow), Debug (wraps another; detects leaks, double
// frees and use after free in debug builds)

@:hxmc.noGc class ArrayList<T> {
  var items:Slice<T>; var len:Int; final alloc:Allocator;
  public function new(alloc:Allocator) { this.alloc = alloc; items = Slice.empty(); len = 0; }
  public function push(v:T) { if (len == items.length) grow(); items[len++] = v; }
  public function deinit() alloc.freeSlice(items);
}

@:hxmc.struct class Particle { var x:Float32; var y:Float32; var vx:Float32; var vy:Float32; }

@:hxmc.noGc
function step(alloc:Allocator, ps:Slice<Particle>, dt:Float32):Slice<Particle> {
  var alive = new ArrayList<Particle>(alloc);
  for (p in ps) {                               // p points into the slice, no copy
    p.x += p.vx * dt; p.y += p.vy * dt;
    if (p.y < 1000) alive.push(p);              // copies the struct by value
  }
  return alive.toOwnedSlice();                  // the caller owns it, frees with the same allocator
}

// from GC code: Zig's per-frame arena
var frame = new Arena(Malloc.instance);
function onFrame() {
  frame.reset();                                // last frame's memory freed at once
  particles = step(frame, particles, 1 / 60);
}
```

### Rules the compiler enforces

- A `@:hxmc.noGc` function never touches the GC heap: no GC allocation
  (`new` of an ordinary class, capturing closures, string concatenation,
  `Array`, `Dynamic`, boxing), no calls to functions that may collect, no
  stores of references to GC objects. Facts already checks most of this
  for the runtime and names the culprit; it becomes a documented,
  complete rule.
- Allowed: scalars, `@:hxmc.struct` values, `Ptr<T>`, `Slice<T>`,
  `Segment<T>`, `Allocator` parameters, calls to other `@:hxmc.noGc`
  functions and to C.
- GC code calls manual code freely; manual code reaches GC objects only
  through `Handle.get` and `pin`.
- A `Ptr` derived from a GC object cannot be live across a GC point (the
  check in PLANS.md, "A compiler check for raw addresses across GC
  points", becomes part of this).
- Allocators are passed explicitly, as in Zig (not an implicit context as
  in Odin or Jai); an optional default (`Malloc.instance`) for
  convenience.

### What it needs from the compiler

- `@:hxmc.struct` values: stored inline in slices, arrays and other
  structs, passed and returned by value (copies), field access through
  pointers without copying.
- Generics specialized per type for structs (`ArrayList<Particle>`
  storing structs by value), as Zig does with `comptime` types; Haxe's
  `@:generic` is the starting point.
- No shadow-stack frame, safepoint or write barrier in `@:hxmc.noGc`
  functions (they hold no GC references): faster and smaller code, and
  safe to run on threads the runtime does not know (C callbacks on
  foreign threads, audio callbacks).

### What it buys

- The runtime (strings, maps, eventually the collector) in readable Haxe
  instead of raw `Mem` intrinsics: the collector stayed C partly because
  restricted no-GC Haxe was awkward to write.
- No GC pauses where they hurt: audio, per-frame game memory, real-time
  loops.
- Deterministic memory for subsystems that want it, next to GC code for
  everything else.

### Limits

- No borrow checker (as in Zig): use after free and leaks are possible in
  this subset. Mitigations: the `Debug` allocator in debug builds, segment
  lifetime checks, bounds checks that release builds may drop.
- hxmc-only, by design.

### Value enums (Zig's tagged unions)

Haxe enum values are immutable, so copying one cannot be observed except
through identity (`==` on enum values with arguments compares references)
and `null`. An enum can therefore opt into a value representation:

```haxe
@:hxmc.value enum Shape {
  Circle(r:Float32);
  Rect(w:Float32, h:Float32);
}

@:hxmc.noGc function area(s:Shape):Float32
  return switch s {                       // ordinary Haxe pattern matching
    case Circle(r): 3.14159 * r * r;
    case Rect(w, h): w * h;
  }
```

hxmc stores it as a tag plus room for the largest payload: inline in
structs and slices, in registers or copied, never allocated. The typer sees
a normal enum, so `switch`, exhaustiveness and constructors work
unchanged. Restrictions:

- no identity comparison (`==` rejected, or structural like
  `Type.enumEq`);
- never `null` (`Null<Shape>` boxes, which no-GC code rejects);
- no direct self-recursion (infinite size): recursive payloads go through
  `Ptr<T>` or stay ordinary GC enums, as in Zig;
- conversion to `Dynamic` or an interface copies into a heap box (a GC
  allocation);
- payload types must be value types (scalars, structs, `Ptr`, other value
  enums).

| Zig | Haxe on hxmc |
| --- | --- |
| `enum` / `enum(u8)` | enum abstracts (`enum abstract Mode(UInt8)`), available today |
| `union(enum)` | `@:hxmc.value` enums |
| `extern union` / untagged unions (C) | `@:hxmc.union` structs with overlapping fields, for C interop |

### Other Zig constructs and how they map

| Zig | Haxe on hxmc | Fit |
| --- | --- | --- |
| `comptime` generics (`fn ArrayList(comptime T: type) type`) | `@:generic` specialization (done by the typer) | good |
| `comptime` computation, `inline for` | macros (run in Eval, different semantics), inlining and constant folding | partial |
| `defer` / `errdefer` | a macro rewriting `@:defer expr` into cleanup on every exit (try/catch and rethrow: Haxe has no `finally`); `Arena.scoped` works the same way | good with a macro |
| error unions, `try`, `catch` | exceptions; no-GC code throws preallocated or static error values; `Result`-style enums with macro sugar where errors as values are wanted | acceptable |
| arbitrary-width and packed integers (`u3`, packed structs with bit fields) | abstracts over `Int` with masking | clumsy |
| overflow as an error, wrapping `+%`, saturating `+|` | Haxe's `Int` wraps; checked and saturating arithmetic as functions or abstracts | acceptable |
| `*const T`, `*T` vs `[*]T`, sentinel slices `[:0]u8` | distinct abstracts (`ConstPtr<T>`, `Ptr<T>`, `Slice<T>`, `CString`) | acceptable |
| no hidden allocations | Haxe allocates implicitly (closures, string concatenation, array literals, boxing): `@:hxmc.noGc` must be a compiler check | needs the check |
| `@Vector` (SIMD) | hxmc intrinsics | needs work |
| `anytype` | `@:generic` or macros | good |

The real gaps are value enums, `defer` (a macro), const pointers
(abstracts) and the hidden-allocation check (the compiler).

## Go's equivalents

Go is GC-only and has no allocator-passing convention, but it has close
equivalents of the GC-interop pieces, mostly for cgo and its own runtime:

| This design | Go |
| --- | --- |
| `Handle` | `runtime/cgo.Handle` (`cgo.NewHandle(v)`, `h.Value()`, `h.Delete()`) |
| `pin` | `runtime.Pinner` (Go 1.21+), plus cgo's rule that C may not keep Go pointers |
| `@:hxmc.noGc` as a checked rule | `//go:nowritebarrierrec`, `//go:nosplit`, `//go:systemstack` and a not-in-heap marker type, enforced by the compiler but only inside the runtime |
| arenas | the experimental `arena` package (`GOEXPERIMENT=arenas`, Go 1.20), on hold indefinitely: use after free and API composition proved hard to make safe in a GC language |
| implicit stack allocation | escape analysis |

Go validates the GC-interop half; its stalled arena experiment is why
segment lifetime checks and the `Debug` allocator are part of this design.

## Effort (estimated)

Calibrated on hxmc so far: the compiler is about 21k lines of Haxe (Mir
construction about 2.3k, the WebAssembly back end 2.3k, each linker
400–700, the optimizer about 1k), the runtime in Haxe about 10k; the
WebAssembly target with its all-Haxe runtime took one agent about 2.5
hours, macOS and Windows arm64 about 2.7 hours, the runtime move about 8.

| Step | Compiler | Std / runtime | Agent time |
| --- | --- | --- | --- |
| 1. C interop basics: types, direct calls on six ABIs and WebAssembly imports, static and dynamic linking | 1.5–2.5k | 0.3k | half a day to a day (new: dynamic ELF output; PE and Mach-O imports generalized) |
| 2. Native memory: arenas, segments, `pin`, `Handle`, callbacks, thread attach | 0.6–0.9k | 1–1.5k | about a day (`pin` in a copying collector needs a non-moving space, in the C and the Haxe collectors) |
| 3. C declaration parser, header generator | | 1.5–2k (macro code) | half a day |
| 4. Manual memory: `Allocator`, `Slice`, containers; struct values | 2–3k | 1.5–2.5k | 1.5–2 days (struct values touch lowering, Mir, all three back ends and the linkers' data) |
| 5. `@:hxmc.noGc` complete, raw-address check | 0.5–1k | | half a day |
| 6. Value enums, `defer` macro, structs by value across C calls, optional tcc | 2–3k | 0.3k | 1–2 days |
| 7. Runtime and collector rewritten in this style | | rewrite | open-ended, optional |

Total roughly 12–18k lines, comparable to hxmc's code generator: about 2
agent-days for steps 1–2 (usable C interop with safe memory), 1–2 weeks
for steps 1–6. Struct values and `pin` are where it could slip.

## First milestone: the basics

C interop basics and a checked way to rewrite hot paths of hxmc's own std,
without most of the design above.

Included:

1. Types: `Ptr<T>`, the scalar types (`Int8`..`UInt64`, `Float32`),
   `CString`, `@:hxmc.struct` with C layout accessed through pointers only,
   `@:hxmc.opaque`.
2. Externs with direct calls for scalars and pointers on the six ABIs;
   static linking of prebuilt objects; user DLLs (PE) and dylibs (Mach-O)
   by generalizing the runtime's existing system imports.
3. `@:hxmc.noGc` complete, plus the raw-address check (PLANS.md): the tool
   for rewriting std hot paths, already the runtime's style (`Mem`
   intrinsics in non-collecting functions), made a checked rule.
4. Minimal temporary memory: `Arena.scoped(a -> ...)`, a malloc-backed
   bump allocator returning raw `Ptr`s, for strings and buffers passed to
   C.
5. Fast C calls instead of `pin` for now: a call marked `@:hxmc.fast`
   stays in the GC-unsafe state instead of entering the safe region (as
   .NET's `SuppressGCTransition`), so no collection can run and no object
   can move during it. GC objects' memory can be passed directly
   (`Mem.addr(bytes)` to `memcpy`, `qsort`, hashing, codecs). The call must
   be short, must not block and must not call back. Calls that block copy
   their data through a scoped arena instead.

Deferred: `Segment` checks, `Arena.auto`/`Arena.global`, the `Allocator`
family, `Debug`, containers, struct values, specialized generics, value
enums; `pin`, `Handle`, callbacks and thread attach (until a library calls
back); the C declaration parser and header generator (externs written by
hand at first); structs by value across C calls; tcc; dynamic ELF output
on Linux (static libraries first); `defer`; the rest of the Zig mapping;
step 7.

Estimate: about 2–3.5k lines (types and extern lowering 1–1.5k compiler
lines, fast calls small, the `noGc` check 0.5–1k, the scoped arena a few
hundred lines of Haxe), roughly one agent-day. Each deferred piece can be
added later without redesigning these.

## Order

1. C interop: `Ptr`, `CString`, `@:hxmc.struct`, `@:hxmc.opaque`, direct
   calls (scalars and pointers), static and dynamic linking.
2. Native memory: arenas, segments, `pin`, `Handle`, callbacks with
   trampolines, thread attach.
3. The C declaration parser; the header-based generator.
4. Manual memory: `Allocator` and its implementations, `Slice`, struct
   values, specialized generics, the containers.
5. `@:hxmc.noGc` as a public, complete rule, including the raw-address
   check.
6. Structs by value across C calls; the optional embedded tcc.
7. The runtime, and eventually the collector, rewritten in this style.
