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
2. For wasm, use the same runtime design in linear memory (option c). On
   the benchmarks, the C compiled with Emscripten ran as fast as the WasmGC
   output and faster than today's HL/C→wasm. It needs no
   `--spill-pointers`, and both targets share one GC and one set of
   semantics. Exceptions must map to wasm exception handling, not `setjmp`
   (§4). The emitter now does this: the generated file uses `RT_TRY`
   macros, which become `setjmp` natively and C++ `try`/`catch` when compiled
   as C++ by Emscripten (`backend/build.sh` builds `prog_linear.js`). In a
   40-call test function this gives 3.3 KB of wasm, against 80.7 KB with
   `setjmp` and 3.1 KB without exceptions. Run times are unchanged (Bench
   0.39s, Exc 0.46s vs 0.42s). No separate wasm emitter is needed for this
   route.
3. Keep the WasmGC emitter (already working for the subset) as an optional
   second wasm path. It should write the binary format directly; the WAT
   text and Binaryen's assembler are a prototype shortcut (§2.7). It is worth finishing if module size or JS interop
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
| V8's optimizing tier stalls ~20 s on HL/C's huge functions | `bench/README.md` | §4: the functions are huge because of Emscripten's `setjmp` lowering of `hl_trap`, and the stall happens at exit. Neither new route uses `setjmp` on wasm, and our emitter can bound function size. A custom section brings today's build from 25–31 s to 17.5 s. |
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

**No-go for WasmGC modules** through these runtimes: slower and less
complete than emitting C.

**Viable for linear-memory modules (b+c), measured with Wasmtime/Cranelift.**
A standalone (WASI) Emscripten build of the C output
(`backend/tools/wasmtime_wasi.py`, exceptions translated to exnref) runs in
Wasmtime 49 from a precompiled artifact (101 KB). Run times, excluding
process start:

| Program | gcc -O2 native | Cranelift (Wasmtime AOT) | V8 (Node, incl. startup) |
| --- | ---: | ---: | ---: |
| Bench | 0.315s | 0.338s | 0.394s |
| Bench -D retain | 0.534s | 0.595s | 0.682s |
| Exc | 0.026s | 0.357s | 0.415s |

Cranelift's code is 7–11% behind gcc here, and the module's own GC means
the earlier 2.0s (Wasmtime's reference-counting collector on WasmGC) does
not apply. One wasm artifact could thus be both the wasm distribution and,
through `wasmtime compile` or an embedded Wasmtime, the native one. The
catch is exceptions: wasm exception handling costs the same in Wasmtime as
in V8, 14× the native `setjmp` route on `Exc`.

**Cranelift as a direct native backend** (IR → CLIF instead of IR → C) is
the other way it could help. Its user stack maps let a frontend mark GC
references at safepoints, as OCaml's frame tables do. That would replace
the shadow stack: references stay in registers, and the GC finds them
through the maps. Recent Cranelift also has `try_call` with landing pads
(Wasmtime's exception support uses it), tail calls, and compiles much
faster than gcc on a 50k-line program. The costs: Cranelift is a Rust
library with no stable C API, so the backend's code generator would be a
Rust program reading the IR (or HXB). It produces no wasm, so a wasm emitter
is still needed. And its code quality trails gcc/LLVM (7–11% above, through
wasm). This route has not been prototyped: the stack-map and exception
claims are from Cranelift's documentation and Wasmtime's use of them, not
measured here.

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

### 2.6 Code size: WasmGC vs linear memory

Per function, from the same IR (Bench, function sizes read from the binaries;
wabt 1.0.34's objdump can't parse GC modules):

| Function | C → wasm -O2 | C → wasm -Oz | WasmGC (Binaryen -O2/-O3) |
| --- | ---: | ---: | ---: |
| `simplify` | 1,820 B | 858 B | 530–538 B |
| `build` (allocation-heavy) | 1,060 B | 530 B | 179–181 B |
| `eval` | 271 B | 219 B | 183–197 B |
| `size` | 187 B | 148 B | 138–146 B |
| total | 3,338 B | 1,755 B | ~1,050 B |

WasmGC code is 1.7× (against `-Oz`) to 3.2× (against `-O2`) smaller. The
linear route pays for inlined bump-allocation fast paths, write barriers,
shadow-stack frames and address arithmetic, where WasmGC has `struct.new`,
`struct.set` and engine-managed roots. `-Oz` keeps most of the speed here
(0.43s at both `-O2` and `-Oz`, 0.41s at `-Os`). The linear runtime itself
(GC, malloc, libc pieces, ~27 KB) doesn't matter at the compiler's scale.
WasmGC instead adds a type section with one type per class, enum
constructor and closure.

At the compiler's scale, neither route has what made today's module
51.5 MB: `--spill-pointers` (~21 MB) and Emscripten's `setjmp` lowering
(the ten functions that are 45% of the code). So the main size win comes
from leaving HL/C, whichever route is taken. WasmGC would then be a further
~2× on code, probably less after compression. The real figure for the
compiler is unknown until the C route can compile it.

### 2.8 Alternative: generate OCaml source instead (measured)

Instead of our own IR, C and runtime, a generator could emit OCaml from
the typed AST. ocamlopt would give the native binary and `wasm_of_ocaml`
(6.4.1, WasmGC) the wasm one, with no GC or runtime of our own.
`backend/ocaml/bench.ml` is Bench translated by hand in the style such a
generator would produce. It uses records with a vtable for classes, an
`Obj.t` payload for `throw` and a growable record for `Array`, and every
Haxe `Int` goes through a swappable integer layer (`backend/ocaml/build.sh`).
All outputs match.

| Bench (best of 3) | Bench | retain | peak RSS |
| --- | ---: | ---: | ---: |
| ocamlopt, 63-bit int wrapped to 32 (`int63.ml`) | **0.28s** | **0.44s** | 12 / 86 MB |
| ocamlopt, `Int32` (`int32.ml`) | 0.38s | 0.53s | 16 / 115 MB |
| wasm_of_ocaml, `Int32` (Node 22) | 0.64s | 0.99s | 137 / 324 MB |
| for comparison: our C / our WasmGC / C → linear wasm | 0.32 / 0.38 / 0.39s | 0.53 / 0.66 / 0.65s | |
| for comparison: HL/C / HL/C → wasm | 0.43 / 0.59s | 0.61 / 0.83s | |

- **Natively, OCaml is the fastest route measured, and the leanest in
  memory.** Its non-moving major heap is the design §2.5 recommends for our
  runtime, and here it comes ready-made.
- **On wasm it is slower than our own emitters.** `wasm_of_ocaml`'s `int` is
  31 bits (an `i31ref`, `Sys.int_size = 31`), so Haxe's 32-bit `Int` needs
  boxed `Int32`. With the native 63-bit wrapping layer, the wasm build
  silently computed wrong results. The generator must therefore emit (or
  functorize) two integer layers. Its uniform value representation also
  costs casts. The wasm module is 42 KB (16 KB gzipped) for Bench, mostly
  runtime.
- **What it would take:**
  - mapping Haxe's object model onto OCaml with `Obj.magic`: subclass
    records sharing a prefix, `null`, `Dynamic`, structural types,
    interfaces through vtables;
  - mapping Haxe's UTF-16 `String` (the port's semantics on HL) onto OCaml's
    byte strings, or emulating it;
  - providing wasm versions of the C stubs a native build would use (PCRE,
    zlib).

  It saves writing and tuning a GC and runtime; the generator itself is
  comparable in size to the C emitter plus lowering.
- **Not measured:**
  - Haxe → JVM (existing `genjvm`) → GraalVM native-image. The JVM jar
    already needs bytecode verification disabled (`bench/README.md`), which
    native-image may not accept.
  - GraalVM's or TeaVM's WasmGC backends.
  - hxcpp. It exists and needs no work, but measured 4× the reference on
    `stdlib`, and its conservative GC has the same `--spill-pointers`
    problem on wasm.

### 2.9 Binary size and compile time: C vs OCaml (measured)

**Synthetic scale-up:** 200 renamed copies of Bench's four hot functions
(800 functions): 104,600 lines of our generated C against 8,900 lines of
the OCaml translation. Sizes are the growth per copy.

| | native code per copy | native compile, 800 functions | wasm code per copy | wasm compile, 800 functions |
| --- | ---: | ---: | ---: | ---: |
| our C, gcc -O2 (identical-code folding off) | 3.4 KB (stripped binary) | 11.7s | | |
| our C, gcc -O1 | 3.4 KB (.text) | 6.7s | | |
| our C, clang -O2 | 2.8 KB (stripped binary) | 7.7s | | |
| our C, em++ -O2 / -Oz | | | 4.0 / 2.0 KB | 5.2 / 3.8s |
| OCaml, ocamlopt | 4.1 KB object (2.1 code + 1.5 GC frame tables and closures + 0.4 unwind); 6.1 KB in a PIE binary | 1.3s | | |
| OCaml, wasm_of_ocaml (`Int32`) | | | 1.2 KB | 2.7s (incl. ocamlc) |
| our WasmGC emitter | | | ~1.05 KB | |

**Real scale:**
- The port's HL/C output is 891k lines of C in one translation unit.
  `gcc -O2` takes 150s for it (`emcc` 137s); the stripped binary is
  11.2 MB.
- The upstream OCaml compiler (135k lines including its libraries and every
  target generator) builds from scratch in 19.9s with `dune --profile
  release` on 4 cores. Its stripped binary is 21.3 MB: 7.2 MB code, 6.8 MB
  data (frame tables, closures, constants) and 3.8 MB of PIE dynamic
  relocations. Linking with `-ccopt -no-pie` would drop the relocations.
  It also contains all the generators the port doesn't have, so it is not a
  like-for-like comparison.

**Conclusions:**
- **Natively, C gives smaller binaries:** 1.2–2× less code per function.
  OCaml stores GC frame tables and closures as data, plus relocations in PIE
  builds.
- **On wasm it is the other way round:** WasmGC output (wasm_of_ocaml's or
  ours) is 1.7–3.4× smaller than C through Emscripten.
- **OCaml compiles 5–9× faster** than gcc/clang on equivalent code, and its
  separate compilation makes rebuilds incremental. Generated C should be
  split into many files so builds can run in parallel; `-O1` halves gcc's
  time. Our C is verbose (12× the lines of the OCaml for the same
  functions) because of the shadow stack, ANF temporaries and inlined
  allocation.

### 2.10 Other routes (measured: Go, tcc)

| | Bench / retain (wall) | compile, 800 functions | native code per function copy | exceptions (`Exc`) | wasm |
| --- | ---: | ---: | ---: | ---: | --- |
| our C, gcc -O2 | 0.32 / 0.53s | 11.7s | 3.4 KB | 0.027s | Emscripten, linear memory |
| our C, **tcc** | 0.55 / 0.90s | **0.45s** | 8.8 KB | 0.078s | — |
| OCaml (ocamlopt) | 0.28 / 0.44s | 1.3s | 4.1–6.1 KB | **0.020s** | wasm_of_ocaml (`Int32`) |
| Go 1.24 (`backend/go/bench.go`) | 0.30 / 0.43s (CPU 0.38 / 0.61s, concurrent GC) | ~1.0s | 3.5 KB (1.4 MB runtime) | 0.17s (panic/recover) | 2.5 MB module before any code; 0.79 / 0.99s in Wasmtime |

- **tcc** compiles C 26× faster than gcc -O2, and its code is ~1.7× slower.
  That makes it the development compiler, with gcc/clang for release
  builds. `backend/rt` builds with tcc: `setjmp` and a bit-scan fallback
  replace two GCC builtins.
- **Go** compiles fast and its code is fast natively. Its wasm output is
  heavy (its runtime and goroutine machinery in linear memory). A generator
  would also have to thread `break`/`continue`/`return` out of
  closure-based `try` blocks, and Go has no inheritance.
- **Not measured:**
  - QBE (a tiny optimizing backend, fast to compile; no GC support or wasm);
  - Cranelift as a direct backend (§2.5);
  - Chez Scheme (fast compiler, good GC, no wasm);
  - TinyGo (smaller Go wasm);
  - JVM + native-image (slow builds).

### 2.7 Output format of the wasm emitters

- **C/linear-memory route:** the wasm comes from Emscripten compiling the C
  (as C++ for exceptions), so there is no wasm emitter to write. Binaryen
  runs inside Emscripten's link step anyway.
- **WasmGC route, if pursued:** the prototype writes WAT and assembles it
  with Binaryen's `wasm-as`. That was quick to debug, but the text is ~17×
  the binary here (35 KB vs 2 KB before `-O3`). It adds a parser pass and an
  external tool, and it depends on Binaryen's evolving text syntax. A real
  emitter should write the binary format directly; an encoder for the needed
  sections, GC types, instructions and LEB128 is roughly 1–2k lines. It
  should then optionally run `wasm-opt -O3`, since Binaryen's GC
  optimizations (inlining, cast elimination, type refinement) are worth
  keeping. `wasm-dis` turns the binary back into text for debugging.

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

Measured on the existing HL/C→wasm build (`hih.wasm`, 8,534 functions,
50.1 MB of code) with Node 22's `--trace-wasm-compilation-times`. A
timestamped loader showed where the time goes; `backend/tools/wasm_hints.py`
is the fix described below.

- **The stall happens at exit, not during the run.** For `hello`, the
  compiler finishes in 2–3.4 s. Node then waits until T+27 s for TurboFan
  jobs already started on background threads, which can't be cancelled:
  21.6 s for `core_TUnification_unifyCustom` and 9.0 s for
  `typing_IterationKind_ofTexpr` (44 s of TurboFan CPU across 183
  functions). `process.exit`, `process.reallyExit` and `worker.terminate`
  all still wait. Only SIGKILL from `proc_exit` returns at once (2.2–2.7 s,
  identical output, exit code 137).
- **The 10 largest functions are 45% of the code** (7.3 MB, 7.0 MB, 2.3 MB,
  1.2 MB, …). The ten are `CoroFromTexpr.exprToCoro`, `unifyCustom`,
  `IterationKind.ofTexpr`, `typeObjectDecl`, `typeUnop`, `analyzeAliases`,
  `EvalJit.jitExprRec`, `unifyWithVariance`, `validRedefinition` and
  `ExprToPattern.make`. They take 76–81% of all TurboFan time, and functions
  of 100 KB and more take 92–97%. Compiling the whole module eagerly with
  TurboFan takes 29.2 s wall (87 s CPU); with the top 10 replaced by stubs,
  6.0 s.
- **Why they are so big:** every one of them contains `hl_trap`, which is
  `setjmp`. Emscripten's wasm-EH-based setjmp lowering
  (`-sSUPPORT_LONGJMP=wasm`) stores every live local to memory around every
  call in such a function. `unifyCustom` is 255 KB of C and 7 MB of wasm,
  roughly 780k stores. In a synthetic test, one `setjmp` made a function
  26× larger (80.7 KB vs 3.1 KB; 29 KB with the JS-based lowering, whose
  compile time is unusable at this scale).
- **Optimizing time grows mildly faster than size:** doubling a synthetic
  function costs 2.1–2.3× the TurboFan time, about 1 ms/KB below 1 MB and
  3–3.5 ms/KB above it. Splitting a 3.3 MB function into 16 pieces cut
  TurboFan CPU by 1.9× and wall time by 5.6× (parallel compile threads).
  Binaryen's `--outlining` pass can't be used: it asserts on the legacy
  exception instructions, and after `--translate-to-exnref` it saves 125
  bytes and Node 22 can't load the result.
- **The giant functions are not hot.** They are 2.8% of self time in a CPU
  profile of the self-compile. The hot spots are libhl's allocator:
  `gc_allocator_new_page` takes 18.8% (it walks the page list per new page,
  O(pages)), `hl_gc_alloc_gen` 10% and `__wasm_longjmp` 4.9%. Splitting or
  shrinking therefore removes the stall without making the run faster.
- **Mitigation for the existing build:** V8 12.4 has no flag that caps
  tier-up by function size, and raising `--wasm-tiering-budget` doesn't help.
  What works is V8's experimental `compilationHints` custom section, marking
  every function of 100 KB or more (67 functions) as Liftoff-only.
  `backend/tools/wasm_hints.py` adds it. Run with
  `node --experimental-wasm-compilation-hints --no-wasm-dynamic-tiering`,
  because dynamic tiering ignores the hints. The self-compile then takes
  17.5–18.0 s (default 25–31 s; `--liftoff-only` 24.6–25.2 s), and `hello`
  3.1–4.1 s. Both produce archives identical to the reference; I re-checked
  one self-compile run against a fresh reference. Thresholds from 30 KB to
  1 MB gave 18.6–20.7 s. This is an experimental V8 feature that may go away.

**Consequences for the backend design:**

1. **Never lower Haxe `try` to `setjmp` on wasm.** It is what made HL/C's
   functions huge. The WasmGC emitter uses wasm exception handling
   directly. The C emitter compiles `try` to C++ `try`/`catch` under
   Emscripten, which LLVM lowers to wasm exception handling without storing
   locals (measured above: +8% code instead of 26×). Natively, `setjmp`
   stays: it is cheap there (0.027s for `Exc`).
2. **Bound function size in the emitter.** Our own backend controls code
   layout, unlike hl2c. Large `switch` arms (the matcher's output for
   `unifyCustom`-style functions) can be outlined into separate functions
   when a function passes a size budget. It is also worth emitting the
   compilation hints (or `--liftoff-only` advice) for whatever remains huge.
3. **Allocation is where the time goes.** That supports the GC part of the
   recommendation, not just the stall fix.

## 5. Unknowns and risks

- **Whether newer V8 versions cap tier-up by function size** (untested;
  only Node 22 is available), and the exact reason LLVM's setjmp lowering
  stores every local (observed in the output, not traced in LLVM).

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
