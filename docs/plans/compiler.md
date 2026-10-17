# Compiler and cache

Open designs for the front half (typing, macros) and for build caching.
What is built is described in [docs/hxmc.md](../hxmc.md) ("Module cache",
"Runtime in Haxe") and [docs/using.md](../using.md) ("Fast rebuilds").

## Cached modules

Most of a small program's build is the front half typing the std from
source every time (hello world: about 330 ms of 0.375 s). The compilation
server already caches per module, with upstream's rules (per-module
dependencies, file checks, invalidation of dependents, an HXB mode). The
module cache is that cache made durable on disk, not a new unit of
caching: no library boundaries, so the std, haxelib, lix and node_modules
libraries and the user's code are all modules alike.

Built (docs/hxmc.md, "Module cache"; `hxmc/src/hxmc/ModuleCache.hx`,
`ModuleStore.hx`, `ModuleInterface.hx`), on by default since 2026-10-17
(it replaced the types cache, an HXB archive of hxmc's own package typed by
a separate run of the tool): the store, lazy validation (content hashes
where dates or sizes differ, shadowing, missing dependencies), what HXB
does not keep (the modifiers of unbound monomorphs, the sort's walk of each
module; also an anonymous structure's fields are now in name order, which
showed only in hxmc), and the gate (`make test-module-cache`,
docs/testing.md). CI keeps the source path tested: the npm-pack job builds
the packages' compilers with the cache off, the fixpoint builds the tool
cold, warm and off, and crosshost compares the native tool (cached) with
the WebAssembly one (WASI: never cached). The corpus builds from HXB
archives, without it.

- **Keys** (built): an index per working directory, class paths and std,
  of module variants, each with the defines it read: its file's conditions
  (recorded while parsing), its macros' `Context.defined`/`getDefines`
  (attributed to the module whose macro runs), and those the compiler read
  in the build that typed it (`Define.readHook`: the typer's and filters'
  options, the target's). A build restores the variant whose reads have
  its values, so a define one module reads leaves the others alone. The
  macros' context's defines are predicted as `MacroContext` makes them when
  it does not exist yet (checked when it is created). An edit undone
  restores the earlier variant (chosen by its file's content).
- **Early cutoff** (built): each variant keeps, per dependency, the hash
  of its interface as it was when the variant was typed: the parsed
  declarations without the bodies of functions whose type is written out
  (not inline, macro, @:generic, nor in a class a build macro makes),
  positions only for the expressions it keeps (inlining copies them), with
  its own dependencies' interfaces per strongly connected component; across
  contexts (a macro's module), the whole content. A module typed again
  whose interface did not change leaves its dependents restored; it is
  typed from its source where the server expects it cached. In a cycle,
  the restored modules a module typed from source loads while it is being
  created are typed from source too (decoded then, they would reach its
  types before they are ready); the rest of the cycle stays restored.
  Coupling found on the way: the typing of a module marks fields of its
  dependencies as maybe used through structures (`CfMaybeUsed`, which DCE
  reads); a dependency with such marks is restored only together with its
  cycle, so its marks stay those of its users.
  A module a build macro makes (`@:build`, `@:genericBuild`, `@:autoBuild`
  from what it extends or implements) is typed again every build: its
  macro may keep something other macros read (the gfx package's shaders:
  an `@:autoBuild` registers each shader class, a shader's macro looks it
  up); its interface hash (its whole content) still leaves its dependents
  restored. The macros' context's modules a macro run processes again are
  kept as they were when their encoding has not changed.
- Measured (one 4-core VM shared with other builds; time to the start of
  lowering, then the whole build with the objects cached,
  and the modules typed or processed again; before: the signature-keyed
  packs of the previous step):

  | | before | after |
  | --- | --- | --- |
  | hello, cold | 381 ms, 0.46 s | 461-580 ms, 0.56-0.67 s |
  | hello, warm | 95 ms, 0.16 s | 97-131 ms, 0.17-0.21 s |
  | hello, after `-D unrelated` | 375 ms, 0.44 s, 94 | 99-138 ms, 0.17-0.22 s, 0 |
  | formatter, cold | 952 ms, 1.31 s | 1176-1401 ms, 1.75-1.85 s |
  | formatter, warm | 182 ms, 0.36 s | 207-300 ms, 0.39-0.52 s |
  | formatter, after `-D unrelated` | 1015 ms, 1.22 s, 334 | 207-278 ms, 0.42-0.51 s, 0 |
  | formatter, a body edited (tokentree.TokenTree) | 535 ms, 0.81 s, 173 | 264-329 ms, 0.53-0.60 s, 6 |
  | formatter, an interface edited | 528 ms, 0.75 s, 173 | 622-710 ms, 0.89-0.96 s, 173 |
  | the port, cold | 8.3 s, 13.6 s | 9.2-9.8 s, 14.7-16.1 s |
  | the port, warm | 1.29 s, 3.31 s | 1.28-1.63 s, 3.4-4.0 s |
  | the port, after `-D unrelated` | 8.5 s, 10.9 s, 563 | 1.33-1.58 s, 3.5-3.9 s, 0 |
  | the port, a body edited (core.TFunctions) | 6.9 s, 9.4 s, 274 | 1.37-1.85 s, 3.5-4.1 s, 47 |
  | the port, an interface edited | 6.9 s, 9.5 s, 274 | 6.9-7.5 s, 9.1-10.3 s, 274 |
  | the port, the edit undone | 7.2 s, 9.6 s, 274 | 1.24-1.36 s, 3.5-3.6 s, 0 |

  The cold runs pay the interfaces (the port: 0.19 s, reflective over the
  syntax tree, in the encoding's parallel step), the define reads and a
  blob per module.

Open:

- **Nondeterministic macros**: the cache is on by default, and the server
  trusts them (a macro embedding `Date.now()` keeps its value until its
  module changes). The macro std's natives are ours, so they decide per
  module:
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
- **Structural marks** (`CfMaybeUsed`): a restored module keeps the marks
  its users' typing made on its fields in the build that typed it; a user
  typed again that no longer uses it through a structure leaves a stale
  mark, and DCE keeps a field the build without the cache drops (seen with
  `-dce full` on a user class, or on the std; the upstream server's HXB
  cache has the same). Fix: attribute each mark to the module whose typing
  made it (a current module in the typer) and replay them on restore
  instead of keeping them in the HXB.
- **Interface edits undone**: an undone edit of a module restores its
  earlier variant but not its dependents' (the newest variant of each is
  chosen by its own file); choosing among a module's variants by its
  dependencies' hashes would restore them too.
- **Cold runs**: the interface hash walks the syntax tree by reflection; a
  direct walker, and blobs in segments rather than a file per module.
- **Init macros**: their effects are data (`addGlobalMetadata` filters,
  `Compiler.define`, class paths); until they are in the key, builds with
  `--macro` do not use the cache. A macro registering `onGenerate`,
  `onAfterTyping` or `onAfterGenerate`, or defining something, while
  typing makes the build write nothing (a restored module would not do it
  again).
- **Back half**: the per-module objects are in the same store, keyed by
  the hash of the lowered IR (`Fingerprint`), shared by every output
  ("Central object cache" below). Next: DCE is whole-program: move it
  to link time (reachability over symbols with Haxe's rules: `@:keep`,
  implemented interfaces, overrides of reachable fields, reflection roots;
  reflection tables generated from the live set), so a module's object
  does not depend on the rest of the program; whole-program "features"
  become link-time switches. Program-wide numbering is already symbolic.
  `@:generic` instances belong to the module that instantiates them, as
  mergeable (COMDAT-like) symbols; inline bodies are covered by the
  interface hash.
- **Typing order**: some Haxe behaviour depends on it (monomorph
  resolution, anonymous type numbering, build macro order, static
  initialization), and restoring changes it; the gate covers it.
- **Then**: builds with init macros, `-lib` HXB archives as one more
  source of modules. The `npm` postinstall warming the std's modules does
  not pay while an index is per working directory and class paths (a
  warm-up in the package's directory serves no project): it needs the
  std's variants shared across keys.
- Decided against: shipping the std as HXB in the distribution. There is
  no single typed std (per target, per define, again for the macro
  context), the sources have to ship anyway, init macros cannot change
  pre-typed modules, and an edited compiler (`hxmc-rebuild`) invalidates
  it.

## Central object cache and quieter builds

Done for the objects (2026-10-17, `ObjectStore.hx`): the per-module
objects live in the module cache's store (`<cache>/modules/<tool>/o/`),
named by the hash of their lowered IR with the tool and the target
(`Fingerprint`) and the module, so every output and project compiling the
same code for the same target shares them; per output, `<hash>.objs` names
the objects its last build used (the trim removes the objects no `.objs`
names after a day, the `.objs` with their last use) and `<hash>.key` is the
up-to-date record (`UpToDate.hx`). `<out>.hxmc/` remains only where the
cache directory cannot be written (and under WASI). Left: logs only on
request (the Makefile's build rule still writes `<out>.log`, shown on
failure); `-D hxmc.cache=<dir>` beside `HXMC_CACHE`.

## Faster rebuilds, smaller outputs

- One-edit rebuilds below 1 s: needs incremental program preparation,
  module keys, data tables and linking, and incremental DCE in the port
  (today 2.0 s through the resident server, 2.7 s without).
- Server builds from `--hxb-lib`: the port's server re-decodes
  HXB-library modules every build, or loses their function bodies with
  `-D disable-hxb-cache` ("static main is not a function"). A port bug to
  check against the reference compiler.
- Program-level dead-code elimination and data-table compaction (type
  info, field names, dispatch rows, string literals).

## Macro-heavy builds

After the macro-perf fixes (Eval's object encoding, calls and field
lookups, `haxe.ds.Vector` allocation) the `macro` timer is at or below the
reference compiler's on every workload; the remaining gap is in typing
and the collector. Macro share of the build (native port, Linux x86-64,
`--times`):

| Workload | port | reference |
| --- | --- | --- |
| tink_json, 12 nested types (JS) | 29% (0.97 of 3.32 s) | 34% (0.89 of 2.65 s) |
| tink_json, 24 nested types (JS) | 24% (3.27 of 13.4 s) | 24% (2.84 of 12.1 s) |
| upstream unit suite (JS) | 16% (0.54 of 3.33 s) | 17% (0.54 of 3.19 s) |
| upstream unit suite (--interp) | 14% (+ interp 32%) | 13% (+ interp 46%) |
| packages/gfx (GfxTest) | 8% | 7% |
| macro conformance cases (66, summed) | 39% | 37% |

Done since: the adaptive nursery (docs/hxmc.md, "Runtime in Haxe") and
the typing of generated code (`ctx.e.monomorphs` as an immutable list
consing onto shared arrays, `Typecore.MonomorphList`; callback lists no
longer unshift; maps share empty arrays). The port now beats the
reference on tink_json (40 types: 34.1 s against 42.5 s) and types itself
in 6.3 s against 7.6 s. The collector's share is 17-21%, as in the
reference.

What is left, ranked by estimated payoff, each needing more than a local
fix:

- **monomorph_transaction**: upstream snapshots every unbound monomorph
  of the function for each optional argument passed (`CallUnification`),
  quadratic in a function's size in the reference too. 15% of tink_json
  at 40 types, 6% at 24, little elsewhere; the walk is memory-bound. A
  trail of the monomorphs bound or constrained since the snapshot (the 12
  places that set `tmType` or `tmDownConstraints`) would make it
  proportional to the changes; a departure from upstream's algorithm.
  Estimate: -12% at 40 types.
- **Medium-lived objects in the collector**: a minor collection promotes
  whatever survives it (9% of what tink_json allocates), and major
  collections stop the world (1.8 s at 40 types, charged to wherever an
  allocation lands: the "superlinear" `BasicBlock.create`,
  `Abstract.findToFrom` and DCE's mark are their pauses). An aging
  survivor space, or incremental major marking ([runtime.md](runtime.md)).
  Estimate: 5-10% on large builds.
- **Allocation in the typer and analyzer**: spread thin (texpr records,
  `InterferenceReport`'s four maps per expression, Eval's encoding of
  macro arguments); escape analysis ([codegen.md](codegen.md)) is the
  general answer.
- **Eval call frames**: each call allocates an Env, two slot vectors and
  the argument array, and stores the frame into the long-lived Eval record
  twice (two write-barrier slow calls): a quarter of a call's cost. A frame
  stack reused across calls is a redesign of EvalContext. Estimate: 20-30%
  on call-heavy macro code.
- **Eval instance layout**: a field read is four dependent loads (the
  VInstance box, the instance, the Array header, its data) against three
  in OCaml; instance fields as an object with inline slots would remove
  one.
- Minor: `Finalization.sortTypes` and `TPrinting.sType` sort through
  `Reflect.compare` (2% of the unit suite); source lines for messages are
  read a byte at a time, each byte a poll and a read system call.
- Tried and not kept: the write barrier testing the value for youth before
  its slow call (within noise, 2.6% more code); `encodeObjS` without its
  intermediate records (no gain).

## Code generation at run time

The code generator compiles to in-memory objects with relocations, and
program-wide numbers stay symbolic, so these remain possible:

- **Native macros**: macro code compiled by hxmc into the running
  compiler instead of interpreted by Eval (prototype below).
- **Hot reload / live patching**: replace changed modules in a running
  process (needs runtime registration of new types and dispatch rows).
- **A JIT library** for interpreters written in Haxe (only the code
  generator half). About 0.5 ms per function single-threaded: suits hot
  functions, not baseline tiers.
- Platform limits: iOS and consoles forbid generating code at run time,
  hardened macOS apps need the allow-JIT entitlement, browsers use
  WebAssembly instead.

### Native macros (prototype)

`make native-macros` (`MACROS=native`). The macro engine is an interface
(`haxe/src/macros/MacroEngine.hx`, Eval by default); `haxe` built with
`-D hxmc.jit` (Linux x86-64, static) installs
`hxmc/src/hxmc/macro/NativeEngine.hx`, selected by
`-D hxmc.macros=eval|native|verify`:

- **Guest**: on a class's first macro call, a child of the compiler types
  the class's module for hxmc in macro mode and writes a relocatable
  object plus the program-wide facts (types, field names, signatures,
  globals, initializers, dispatch rows).
- **Loader**: links it into the running compiler with `<exe>.syms` (every
  symbol of the executable; `-D hxmc.jit` builds also keep every runtime
  function and spare type and signature entries). The std's types and
  statics are the compiler's (layouts checked), the program's are new.
  Code and data are mapped below 2 GB (rel32, absolute disp32 dispatch
  rows), then made executable.
- **Bridge**: native objects to and from Eval values, so MacroApi stays
  the one implementation (anonymous structures, enums with Eval's
  positions, Refs, lazy values, API function values; API exceptions
  catchable by macro code).
- **verify**: both engines per call, Eval's result used; Eval's API calls
  recorded and replayed to the native run, so no side effect happens
  twice; results, positions, errors and the API call sequence compared.

Results: the 66 macro cases pass in verify mode (119 calls, 115 native,
114 identical; the mismatch is `Sys.programPath()`, null in Eval's macro
std); native mode writes byte-identical HXB for 65/66. GfxTest's 40 macro
calls run natively; the shader macro does not match yet (nested macro
calls during the Eval run advance the native statics too). Compiling a
macro class takes about 0.4 s; a compute-bound macro runs 20x faster
natively, an API-bound one (2000 `makeExpr` calls) as fast as Eval: the
conversions at the boundary cost what interpretation saved. So the gain
needs cached compiles and comes from macro code that computes.

What a production version needs:

- Macro code is typed for Eval (its std's externs) and has to be typed
  again for hxmc: in process (or from HXB), objects cached per macro
  module on disk, keyed by sources, tool and defines; tiered: Eval first,
  compile the classes that run often.
- A macro std with Eval's semantics (`Sys.programPath`, integer overflow,
  negative array indices, ...).
- Static state belongs to one engine: a class's functions run all natively
  or all on Eval; a fallback after a native run started is unsafe.
- A new class extending a class of an earlier bundle: instance tests use
  index spans compiled into code, so new classes need spare index ranges
  and earlier dispatch rows patched.
- Crashes in macro code (a null access is a SIGSEGV) must become errors:
  a signal handler returning to the macro call, or null checks in macro
  mode.
- W^X per platform: macOS `MAP_JIT` with `pthread_jit_write_protect_np`,
  Windows `VirtualAlloc`/`VirtualProtect` plus `FlushInstructionCache`,
  arm64 cache maintenance and branch ranges (veneers or a mapping near the
  image), PIE executables.
- The bridge's position maps keep their objects alive (weak maps), and
  bundles are never unloaded (the compilation server).
- The bigger win: the compiler's own AST and types as native haxe.macro
  values (no Eval values in between), which an engine sharing the
  compiler's heap allows.

### Bootstrap plus bundled program

Executables made of a small native bootstrap (runtime, code generator,
loader) and the program as a portable archive, compiled at first launch
(then cached per CPU and version), lazily per function, or tiered. One
archive for every platform, code tuned for the actual CPU, plugins and
mods, small updates. Costs: first-launch latency, the platform limits
above, a larger footprint than one AOT executable for small programs.

Archive format: hxmc's own lowered IR rather than HXB. When bootstrap and
archive ship together the format is private and needs only a version
stamp; HXB would mean a larger bootstrap (HXB reader, typed AST,
lowering), lowering on every user's machine, and compiler internals and
absolute paths in shipped programs. A versioned format matters only if
archives and bootstraps are built separately (plugins, patches from a
newer hxmc, a shared installed bootstrap).
