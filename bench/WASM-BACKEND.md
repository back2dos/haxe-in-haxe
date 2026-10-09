# HXB → WasmGC / native backend: design note (EXPERIMENTAL)

This is an explicit scope expansion beyond AGENTS.md's HXB-only milestone. It
asks whether one typed IR, lowered from what HXB holds, can feed a WasmGC
backend and a native backend with nearly identical semantics. The aim is to
compile the way OCaml does: unboxed integers, cheap bump allocation into a
young generation, precise GC, cheap exceptions, direct calls and compiled
pattern matches. That would give a fast native binary and a wasm
distribution of the compiler.

The prototype is in `backend/` (about 2,500 lines including the runtime). The
only change to the port is a hook in `src/compiler/Compiler.hx`
(`Compiler.generateHook`). It is null in the compiler itself, so conformance
is unaffected.

All numbers come from the 4-core container used for `bench/README.md`. Node
is 22.22 (V8 12.4) and Emscripten is 6.0.12 (Binaryen 133). Times are the
best of 3–5 runs.

## Recommendation (short)

**Go**, staged, with the GC strategy turned around from the obvious plan:

1. Translate `hxbReader.ml` into the port. Build the IR and a **C backend
   whose runtime has an OCaml-style precise GC**: a copying nursery, plus a
   non-moving major heap still to be written. This is the native
   distribution.
2. For wasm, start by compiling that same C to linear-memory wasm
   (option c). On the benchmarks it ran as fast as the WasmGC output and
   faster than today's HL/C→wasm. It needs no `--spill-pointers`, and both
   targets share one GC and one set of semantics.
3. Keep the WasmGC emitter (already working for the subset) as an optional
   second wasm path. It is worth finishing if module size or JS interop
   matters, or if a large program shows V8's collector clearly ahead of
   ours.

Native through a wasm runtime (option b) is a no-go today, as measured
below. Details and caveats follow; the biggest unknowns are listed at the
end.

## 0. The problems being addressed

| Problem (current routes) | Measured before | What the prototype shows |
| --- | --- | --- |
| HL/C→wasm module is 51.5 MB; `--spill-pointers` adds ~21 MB | `bench/README.md` | No spill pass on any new route. The C/linear route roots values in a shadow stack, and WasmGC roots are managed by the engine. |
| ~38% of the wasm self-compile is libhl allocation and marking | profile | Bump allocation in a young generation on both routes (V8's on WasmGC, `backend/rt` in C) |
| V8's optimizing tier stalls ~20 s on HL/C's huge functions | `bench/README.md` | §4 below. Function size is a property of the code we emit, so our own backend can split functions. |
| self-compile: reference 4.53s, HL/C 7.67s, JS 23.4s, wasm 27s | `bench/README.md` | The prototype can't compile the compiler yet; the benchmarks below measure the same effects at small scale |

## 1. Prototype

Pipeline: the port's own compiler runs on the program (cross platform),
filters and all. It stops at the point where it would write HXB, and
`backend.Lower` lowers the filtered typed AST to the IR (`backend/src/backend/Ir.hx`).
Two emitters consume the same IR:

- `EmitWat`: WasmGC text, assembled and optimized with Binaryen
  (`wasm-as`, `wasm-opt -O3`)
- `EmitC`: C for `backend/rt`, compiled with gcc natively and also with
  Emscripten to linear-memory wasm

The prototype takes the typed AST in-process rather than from an HXB file.
That data is exactly what `HxbWriter` serializes; see §2.4 for the reader.

Supported subset: Int and Bool; classes with single inheritance,
constructors, `super`, overrides; interfaces; enums with arguments and
`switch`; `Array<T>` (literal, index, `push`, `length`); closures capturing
locals by reference (boxed when mutated); `throw` and `try`/`catch` by
class. Not supported yet: Float arithmetic, String, Dynamic, anonymous
structures, Map, Reflect/Type, statics other than enum singletons.

### Programs

- `backend/bench/Bench.hx`: builds random expression trees (enum), then
  simplifies them with nested pattern matches, evaluates them and measures
  their size. It also has virtual and interface calls, a closure over a
  loop variable, and a throw/catch every few iterations. With
  `-D retain` it keeps every tree alive (≈200 MB live), as a compiler keeps
  its typed AST.
- `backend/bench/exc/Exc.hx`: 2M `try` blocks with 667k throws through
  recursion, like the compiler's control-flow exceptions.

All variants print the same output on every route: Eval, JS, HL/C native,
HL/C→wasm, new C, new WasmGC, new C→linear wasm, Wasmtime and WAMR.

### Run time (best of 3–5, wall clock, including Node startup where applicable)

| Route | Bench | Bench -D retain | Exc |
| --- | ---: | ---: | ---: |
| HL/C native, stock libhl | 0.60s | 0.70s | — |
| HL/C native, patched libhl (`libhl-allocator.patch`) | 0.43s | 0.61s | 3.92s ¹ |
| HL/C → wasm (Emscripten, `--spill-pointers`) | 0.59s | 0.83s | 0.56s |
| same, `--liftoff-only` | 0.87s | 1.26s | |
| Haxe JS target (Node 22) | 1.12s | 1.93s | 4.40s |
| **new C (native)** | **0.30–0.32s** | **0.50–0.54s** | **0.027s** |
| **new WasmGC (Node 22)** | **0.36–0.40s** | **0.60–0.66s** | 0.60s |
| same, `--liftoff-only` | 0.54s | 0.82s | |
| **new C → linear-memory wasm (Emscripten, Node 22)** | **0.39s** | **0.65s** | 0.46s |
| new WasmGC in Wasmtime 49 (Cranelift; AOT artifact loads in 0.3 ms) | 2.0s | 0.98s ² | |
| new WasmGC in WAMR AOT (`wamrc --enable-gc`, `-D noexc`) ³ | 0.62s | 1.14s | |

¹ Stock HL std: every throw captures a native stack. The port's own HL
build avoids that (`runtime/hl`, `core.ds.FastThrow`), so this column is
not representative of the compiler.
² Wasmtime's default collector is deferred reference counting (DRC). The
Python binding can't select another one. Bench (short-lived garbage) is
slower than the retain variant under DRC.
³ WAMR implements only the legacy exception-handling proposal, and only in
its interpreter. AOT modules can't use `try`, so these runs use
`-D noexc`: the same program without throw/catch. Native C and Node take
0.30s and 0.34s on that variant.

Peak RSS: new C 37 MB / 220 MB (retain); WasmGC 86 / 230 MB; linear wasm
146 / 318 MB; HL/C 15 / 123 MB; JS 233 / 700 MB. The prototype's major GC
copies and keeps up to 3× the live size reserved, which explains the C
build's 1.8× memory against libhl on `retain` (§2.5).

### Size

| Route | Bench | Exc |
| --- | ---: | ---: |
| new WasmGC (`wasm-opt -O3`) | 2.1 KB (1.1 KB gz) | 0.2 KB |
| new C, stripped native binary (runtime included) | 22.8 KB | 18.6 KB |
| new C → linear wasm (runtime, malloc, printf included) | 32.2 KB | 17.0 KB |
| HL/C → wasm (libhl included) | 347 KB (105 KB gz) | 320 KB |
| HL/C native, stripped (libhl linked dynamically) | 346 KB | 329 KB |
| JS | 10.6 KB | 2.5 KB |

These are runtime-dominated except for WasmGC, so the numbers say little
about the compiler's size. They do confirm that the WasmGC output carries no
runtime at all.

### Optimizing-tier behavior at this scale

The new WasmGC module compiles in 0.3 ms. V8's optimizing tier is worth
1.4× over Liftoff (0.54 → 0.38s), and HL/C→wasm gains 1.5× (0.87 → 0.59s).
No stall is visible at this size: the stall is about function size (§4).

### What made the C route fast

Two optimizations from profiling, both straight from OCaml's design:

- **Only values live across a GC point are rooted.** A liveness pass over the
  IR (`Roots` in `EmitC.hx`) finds the reference locals that are live across
  a call or allocation; only those get shadow-stack slots. Slots are then
  colored so locals that are never live together share one, the way OCaml
  reuses stack slots. Everything else stays in C locals, so in registers.
  `Bench.simplify` went from 17 rooted slots to 2, and run time from 0.44s
  to 0.32s (frame zeroing had been 20% of instructions).
- **No zeroing of fully initialized objects** (`rt_alloc_init` for enum
  constructors, closures and boxes).

What remains in the C profile (callgrind, Bench): 28% minor GC (scan and
forward: the trees survive one or two minor collections), 10% frame zeroing
in `simplify`, and the rest program code. On `retain`, 43% is GC, mostly
promotion copying plus the copying major collections.

## 2. Design

### 2.1 IR shape (as prototyped)

- **Values.** `i32`, `f64`, and references with a precise kind: class
  instance, enum, one enum constructor (after a tag test), array, closure,
  box or any. These map to WasmGC struct types or to C slot layouts. Ints
  are never boxed except as `Dynamic` (§2.2).
- **Statements** are structured (`SIf`, `SLoop` with break/continue,
  `SSwitch`, `STry`, `SReturn`), and expressions are in A-normal form. Calls
  and allocations appear only as the right-hand side of an assignment or as
  a statement. This fixes evaluation order for C (where argument order is
  unspecified) and makes every GC point explicit, which is what the rooting
  analysis needs.
- **Classes.** A struct holds the class id in slot 0 followed by the
  fields; subclasses extend the prefix (WasmGC `sub` types; plain slots in
  C). Methods take `this` as the root object type and downcast once on
  entry.
- **Virtual and interface calls** use one global table indexed by
  `selector × class id`: `call_indirect` in wasm, a function-pointer array
  in C. Methods with no override in the closed world are called directly.
  For the compiler (633 classes, 205 enums, 9 interfaces) a dense table
  would be too large; row displacement, as in dart2wasm, keeps it compact.
- **Enums.** A base struct carries the tag, and each constructor is a final
  subtype with immutable fields. Constructors without arguments are
  preallocated singletons. OCaml uses immediates for those; WasmGC could use
  `i31ref` and C a tagged small integer, which is left for later.
- **Pattern matches** arrive from the typer's matcher already compiled to a
  decision tree: `TSwitch` on `TEnumIndex` plus `TEnumParameter` reads. The
  emitters turn dense integer switches into `br_table` or C `switch`, and
  sparse ones into if-chains. A parameter read is a field load after a
  `ref.cast` in WasmGC (checked; Binaryen removes repeats) and a plain load
  in C.
- **Closures.** A closure is a struct holding a typed function reference
  plus its captured values, subtyped per lambda. The code takes the closure
  as its first argument, like OCaml. Captured locals that are assigned after
  capture are boxed, because Haxe closures share variables.
- **Exceptions.** WasmGC uses one tag carrying `anyref`, with `catch`
  handlers that test the class using `ref.test` and rethrow otherwise
  (legacy instructions for Node 22; Binaryen's `--translate-to-exnref`
  produces the standard form for Wasmtime). C uses `setjmp` handlers chained
  through the C stack; the shadow-stack pointer is restored on catch.
  Functions containing `try` root all their reference locals and make
  scalars `volatile`.

### 2.2 Not prototyped: Dynamic, anonymous structures, strings

The port uses `Dynamic` 681 times, `Reflect` 96 times, `Type.*` 256 times,
58 anonymous `typedef`s, and many anonymous record literals. Both targets
need:

- **Dynamic** as a uniform reference: `anyref` on WasmGC, a pointer in C.
  Ints and floats are boxed when they become Dynamic (OCaml has tagged ints;
  Haxe's `Int` is 32 bits, so it doesn't fit `i31ref`). Dynamic field
  access goes through a per-type field table keyed by interned field names,
  and calls on Dynamic through a generic apply.
- **Anonymous structures** as objects with a shape id. In a closed world
  every structural type is known, so a field access on a known structural
  type compiles to a slot lookup in the object's shape: cached per access
  site, or a global field-id → slot table per shape. HL does this with
  `virtual`s; that dynamic path should stay off hot paths.
- **Strings.** The port relies on Haxe's UTF-16 string semantics, like HL.
  An immutable `i16` array works on both targets. JS string builtins on
  WasmGC would avoid copying at the JS boundary, but a command-line
  compiler barely crosses that boundary.
- **Object identity hashing** (`ObjectMap`, identity-keyed hash tables):
  WasmGC references have no address, so objects need a hash slot assigned
  lazily. The C runtime moves objects, so it needs one as well.

### 2.3 Which std platform to build HXB for

**Reusing `hl` std.** HL's String, Array, StringBuf, Bytes, Map and so on
are written in Haxe over `hl.Bytes` (a raw pointer with offsets),
`hl.NativeArray` and 312 `@:hlNative` primitives in 49 files.
- For the C/linear-memory route this is natural: `hl.Bytes` pointer
  arithmetic is just memory. The primitives would be reimplemented against
  `backend/rt` rather than libhl.
- On WasmGC, `hl.Bytes` (197 uses in the hl std) needs array-plus-offset
  pairs everywhere, and `String` is built on it.
- Typing for `hl` also brings HL-specific semantics into the program:
  `Null<Int>` boxing, `hl.Ref`, abstracts implemented natively. The port's
  `runtime/hl` already patches parts of that std.

**A new platform** (Haxe 5's `--custom-target`, or the cross platform plus
a target std, as in the prototype). Externs for String, Array, Bytes, Map,
StringBuf, Math, Std, Type/Reflect, Sys/File, EReg, Int64 and zlib map to IR
intrinsics plus a small runtime shared by both emitters. Haxe-level classes
from the hl std that don't touch raw pointers can be copied in.

**Recommendation: a new platform.** It keeps the IR target-neutral, which
the WasmGC path needs. Option (c), the main recommendation, could live with
the hl std, but taking it would close off WasmGC. The prototype already
works this way: cross platform, `extern class Host` for primitives.

### 2.4 Reading HXB

- **Translate `hxbReader.ml`** (2,130 lines of OCaml) into the port, next
  to the translated `HxbWriter` (2,309 lines). It produces the same
  `core.Type` structures the prototype consumes, so `Lower` would not
  change. It is also AGENTS.md's later "HXB-library input in the port"
  milestone, so the work counts twice. A backend can resolve every
  cross-module reference within one archive, because the archive holds every
  module of the compilation (all 55 for `Hello`, std included).
- **A minimal reader** would still have to decode nearly the whole format,
  because expressions, types, fields and their references are the payload.
  It would save only the parts a backend can skip (positions,
  documentation, display data). A translation is not much more work and
  stays checkable against upstream. **Recommended: translate.**
- **No reader:** run the backend in-process after filtering, as the
  prototype does. This works today and is the fastest way to iterate. HXB
  as the interchange format additionally lets the pinned reference compiler
  produce the backend's input, which separates "does the port type
  correctly" from "does the backend compile correctly".

### 2.5 GC decision per backend

**(a) WasmGC on wasm, our own GC natively.** On Node, V8's generational
collector performs well: WasmGC ran within ~20% of the native C build on
both Bench variants (0.36–0.40s vs 0.30–0.32s, 0.60–0.66s vs 0.50–0.54s). The cost is two GCs
with possibly diverging semantics: identity hashes, out-of-memory
behavior, and weak tables if ever needed. It also needs two lowerings for
bytes and strings. The existing WasmGC-to-native engines don't help on
native (option b).

**(b) wasm only; native through wasm2c, Wasmtime or WAMR.**
- wasm2c (wabt 1.0.34 from apt, and wabt main as of 2026-10-05): **no GC
  support**. It supports exceptions. It would only work for linear-memory
  modules.
- Wasmtime 49 (pip wheel `wasmtime`): GC and exceptions both work, and
  precompiled modules load in 0.3 ms. It ran 3–6× slower than the C build
  here with the default DRC collector. Its copying collector could not be
  selected through the Python API, so how it would compare is unknown.
- WAMR (main, built here against LLVM 18): `wamrc --enable-gc` AOT works
  and is 2× slower than the C build. It has **no standard exception
  handling** (legacy only, interpreter only), so exceptions would have to
  be lowered to return codes for it.

**No-go** for the compiler: slower and less complete than emitting C.

**(c) Linear memory with a precise shadow-stack GC on both targets.** This
is what `backend/rt` is: nursery bump allocation, copying minor collections
with a remembered set and write barrier, and a shadow stack holding only
live-across-GC-point references, colored. Compiled with Emscripten, the
same C ran as fast as WasmGC on Node (0.39 vs 0.38s; 0.65 vs 0.66s;
exceptions 0.46 vs 0.60s). It needs no `--spill-pointers`, and every wasm
engine can run it, including wasm2c and engines without GC. One GC
implementation means one set of semantics. The cost is that we write and
tune the GC ourselves, and the wasm module carries ~20–30 KB of runtime.

**Recommended native GC: OCaml's design.** A copying nursery, as
prototyped, plus a **non-moving mark-and-sweep major heap** with
size-segregated free lists that promotion allocates into. That would
replace the prototype's copying major heap, which costs up to 3× the live
size in reserved space and re-copies the whole live heap on every major
collection: 43% of `retain` is GC. A compiler keeps most of what it
allocates, so the major heap matters more than in Bench. libhl's patched
allocator shows how close a non-moving heap can get: HL/C with it is only
13% slower on `retain` while using 45% less memory.

## 3. Feasibility checks

- Emscripten 6.0.12 and Binaryen 133 handle the WasmGC text format,
  `-O3`, `--translate-to-exnref`, and legacy and new exception handling.
- **Node 22 has no supported way to cache compiled wasm between runs.**
  `v8.serialize(module)` returns a 2-byte placeholder: Node registers no
  wasm serializer delegate. V8 has caching flags
  (`--wasm-caching-threshold` etc.), but only an embedder implementing
  `WasmStreaming` can use them, and Node doesn't. The only reuse is in
  process: `postMessage` of a module to a worker. Wasmtime, by contrast,
  serializes compiled modules (0.3 ms load here).
- Wasmtime: no CLI here (GitHub release downloads are blocked by the proxy).
  The pip wheel's C library works and supports GC and exceptions. WAMR and
  wabt main can be cloned and built (`git clone` through the proxy works).

## 4. Function size and V8's optimizing tier

(filled in below from the stall experiment)

## 5. Unknowns and risks

- **Scale.** The prototype covers a subset and programs of a few hundred
  lines. Dynamic, anonymous structures, strings, Map, Reflect/Type and Float
  are designed (§2.2) but not built. Their speed relative to HL's
  implementations is unmeasured.
- **The compiler's actual speedup.** On these benchmarks the C route beats
  HL/C by 1.2–1.4× and WasmGC beats HL/C→wasm by 1.3–1.5×. The self-compile
  also has large strings, hash tables and Dynamic-heavy code, so
  extrapolating to the 7.67s and 27s figures is a guess.
- **Exceptions on wasm** cost at most ~0.7–0.9 µs per throw on V8 (the
  whole `Exc` run divided by its 667k throws), against at most ~0.04 µs
  natively with `setjmp`. That is about 0.1s for the ~119k throws of
  `stdlib`, but hot control-flow throws may be worth lowering to result
  values.
- **The major GC** (non-moving, mark-and-sweep) still has to be written.
- **Effort.** Translating the HXB reader is mechanical (~2k lines). The
  full IR lowering, the runtime (GC, strings, maps, regex via PCRE2, files,
  zlib) and a new std platform are a multi-week project, comparable to
  hl2c plus libhl's standard primitives.
