# Testing status

Earlier checkpoints are in the Git history of this file.

## Display services: `--display` JSON-RPC — 2026-10-09

```sh
HAXE_REFERENCE=haxe/haxe python3 test/display.py -j 2 [--extended]
```

`test/display.py` uses the upstream display test corpus
(`haxe/tests/display/src/cases/*.hx`) as input. Each documented test method
holds a snippet with `{-N-}` markers. The harness extracts the snippet like
`Marker.hx`, writes it where `RpcDisplayTestContext`'s Vfs would (one
directory per method), and sends each request that the method body names
(`fields`/`toplevel` → display/completion, `type`/`doc` → display/hover,
`position` → display/definition, `usage` → display/references, `signature`
→ display/signatureHelp, `diagnostics()`, `documentSymbols()`) as a batch
`--display '<json-rpc>'` invocation to both compilers, with the arguments of
`BaseDisplayTestContext.runHaxe`. `initialize`, display/metadata and
display/defines are sent once. Exit code, stdout and stderr must be
identical after the response `timestamp` is zeroed. The upstream assertions
are not evaluated: the reference's answer is the oracle, so a case that
upstream marks as failing still has to be reproduced.

`--extended` also sends every position method (completion, hover,
definition, typeDefinition, implementation, references, signatureHelp) at
every marker, and diagnostics, documentSymbols, statistics and package for
every snippet.

| Run | Requests | Identical | Differ |
| --- | ---: | ---: | ---: |
| Default | 679 | 679 | 0 |
| `--extended` | 7325 | 7325 | 0 |

The default run takes about 4 minutes and the extended run about 70 minutes
with `-j 2`.

Notes:
- In the pinned upstream, `--display` always takes JSON-RPC; the legacy
  `file@pos` form (still used by `XmlDisplayTestContext` and
  `documentSymbols()` there) is a JSON-RPC parse error in both compilers.
- Batch mode runs with a compilation cache like upstream
  (`Server.setup_server_context`/`enable_cache_mode`): toplevel completion
  lists the types of every cached file, so it depends on the parse cache.
- Output order follows OCaml `Hashtbl` iteration, reproduced with
  `core.ds.OcamlHash` (`caml_hash`).
- Not covered: the `server/*` methods (server milestone) and memory
  statistics (`server/memory`, which needs OCaml object sizes).

Bugs found by the corpus besides the display port itself: the lexer lost
lines of the line table on a lexer error, `Std.isOfType(e, StreamError)` in
the grammar tested against an enum constructor, a Dynamic-typed for-loop
display callback received an anonymous structure instead of an `Expr`,
`Path.getRealPath` returned null for a missing file on HashLink, type
metadata prepends mutated the parsed declaration, and
`ClassPaths.relativePath` resolved symlinks (PosInfos file names became
absolute with a symlinked std; the HXB conformance suite caught this in a
worktree whose `haxe/` is a symlink). The extended run also found:
`OcamlHashtbl.hashInt` hashed the untagged int (caml_hash mixes 2n+1, which
also affects Eval's int-keyed tables), statistics read the inline-call pairs
swapped, `ExtString.String.nsplit ""` is `[]`, `magic_type_path` is compared
structurally, and uncaught exceptions print `Printexc` text.

HXB conformance after this work: 275 identical + 7 expected failures; macro
cases 66/66; `test/interp.py`: 269 identical, the 3 known differences below.

## Execution: `--interp` and `--run` — 2026-10-08

The port now executes programs on its own Eval (`Generate.generate` →
`MacroContext.interpret`, as upstream). Other code generators are still
missing and fail explicitly.

```sh
HAXE_REFERENCE=haxe/haxe python3 test/interp.py -j 4
```

`test/interp.py` runs every conformance case with both compilers.
Direct/module cases get `--interp`, and hxml cases run when they execute. Each
hxml case runs in a scratch copy of its directory. Exit code, stdout and stderr
must be identical.

| Result | Cases |
| --- | ---: |
| Identical exit code, stdout and stderr | 268 |
| Differ | 4 |
| Skipped (the hxml doesn't execute) | 76 |

The known differences:
- `process-nonexistent` (×2): spawning a missing command exits 127 under
  OCaml's `Unix.create_process` and 1 under HashLink's process API (a host
  runtime difference).
- `eval-eventLoop-compile`: a race. A task scheduled with
  `EventLoop.addTask` runs on a worker thread, and the point where its event
  joins the main loop depends on thread timing. It passes in some runs.
- One run showed "Null access .meta" on two small cases; it didn't reproduce
  in later runs. The harness runs without `-D disable-parallelism`, so the
  parallel filter paths are suspected.

Eval threads (`Thread.create`, and domains used by `createWithEventLoop`) run
on host threads, and `Thread.join` waits on a completion lock.

## Macro milestone: Eval macro runtime — 2026-10-08

The port now runs macros (`--macro`, `@:build`, `macro` functions) in its own
Eval interpreter (`src/macros/eval/`, a translation of `macro/eval/*.ml`), with
the Macro API bridge (`src/macros/MacroApi.hx`) and the macro context
(`src/typing/MacroContext.hx`). See `src/macros/PORTING.md`.

```sh
HAXE_REFERENCE=haxe/haxe python3 test/conformance.py --cases test/conformance-macro-cases.txt -j 8
```

| Check | Result |
| --- | --- |
| Macro-context cases (`test/conformance-macro-cases.txt`): same member set and byte-identical `.hxb` payloads, including the `macro/` modules | 66/66 |
| Regular conformance set (`test/conformance-cases.txt`) | 275/275 accepted, 7/7 expected failures |

The macro list holds the 67 cases that `test/discover-cases.py` excludes for
creating a macro context, minus `eval-Pull11784-compile`, whose hxml sets its
own `--hxb` output.

**Supported host: HashLink.** Conformance is maintained on the HashLink build
(`hl`) only. The JS, JVM, C++ and Go builds are no longer kept passing:
- JS has no string identity. Upstream writes positions with a physical file
  name comparison (`p.pfile != pw.p_file`), so 10 macro cases differ there.
- The JVM build fails bytecode verification. Since the AST records became
  classes, genjvm switches on `Dynamic` values without a cast.

Not supported: mbedtls (TLS) and libuv natives, and the Eval debugger. Code
reaching them throws "... is not supported by haxe-in-haxe". The mbedtls enum
constants are registered.

### Porting pitfalls behind the macro fixes

- OCaml's physical equality on strings matters for HXB output. Positions from
  macros carry freshly decoded file name strings
  (`core.ds.StrTools.physNeq`).
- HashLink's `StringMap` truncates keys at NUL, so `"\x00"` and `""` collided
  in the HXB string pool (`core.ds.StringPool`).
- In `make e :: loop el tl`, OCaml evaluates the recursive tail first. Enum
  pattern arguments are therefore typed last to first, and that order decides
  variable ids (`ExprToPattern`).
- Upstream iterates immutable field lists. Filters that add fields
  (`local_statics`) must not see their own additions (`SafeCom`).
- `t_infos` returns the live record. The port's projection had to be re-read
  after build macros replaced metadata (`TypeloadFields`).
- HashLink can't cast optional arguments in function-typed record fields, so
  compiler API callbacks take explicit `depth` arguments.

## First milestone: HXB compile without the macro runtime — 2026-10-07

The translated compiler (`haxe.Main`, a port of the batch path in
`haxe/src/compiler/haxe.ml`) now produces HXB that matches the pinned
reference compiler byte for byte across the whole conformance set.

```sh
export OPAMROOTISOK=1; eval $(opam env --switch=5.2.1)   # or any OCaml setup
make -C haxe haxe                                          # pinned reference
HAXE_REFERENCE=haxe/haxe python3 test/conformance.py -j 8          # HL host
```

Results (`test/conformance-cases.txt`, 282 cases):

| Check | Result |
| --- | --- |
| Same member set and byte-identical uncompressed `.hxb` payloads as the reference | 275/275 accepted cases |
| Reference consumes every port archive through `--hxb-lib` without the case's class path | 275/275 |
| Cases the reference rejects are rejected by the port too (expected failures) | 7/7 |

The case list holds the smoke inventory (optimization issues, `misc/eval`
projects, `test/unit/moduleload` fixtures) plus every configuration found by
`test/discover-cases.py`. Discovery classifies 543 upstream candidates under
`tests/misc/eval/projects`, `tests/misc/eval/resolution`,
`tests/misc/eval/compiler_loops` and `tests/optimization`: 147 are included
and the rest are recorded in `upstream-hxb-exclusions.md` (306 only have
compile-fail configurations, 67 create a macro context, 10 are rejected by the
reference, 6 need haxelib, 4 are multi-part, 2 make the reference write no
archive, 1 times out). The other upstream suites (`tests/unit`,
`tests/nullsafety`, `tests/threads`, `tests/benchs`, `tests/display`,
`tests/server`, `tests/sys`, target `misc` folders) need `--macro`, haxelib
libraries, display/server services, or a non-HXB target.

The same suite also runs on other builds of the port through
`HAXE_IN_HAXE_PORT` (see `bench/README.md`). The HashLink, HL/C, JS and JVM
builds each pass all 282 cases. So does Go (`bench/hx2go/build.sh`, hx2go
with patches), and C++, built with
`bench/hxcpp-single-thread-mark.patch`; stock hxcpp's parallel GC marking
crashes it (see `bench/README.md`).

Other lanes, all passing:

- `haxe haxe-in-haxe.hxml` (bootstrap build) and `haxe compile-all.hxml`
- `haxe test/unit.hxml`
- `haxe test/upstream-parser-corpus.hxml`: 1,355/1,366 with the translated
  parser (`src/syntax/Grammar.hx`, `src/syntax/Lexer.hx`)

### How the harness runs the port

- The port is compiled to HashLink (`test/generated/conformance/haxe-in-haxe.hl`)
  and run with `hl`, which is roughly ten times faster than Eval. `HAXE_HL`
  selects the VM. HashLink 1.15 fails with "Invalid opcode", so build HashLink
  from master.
- Every invocation uses `-D disable-parallelism`. With parallel filters the
  reference takes variable IDs from a global counter shared between workers,
  so even the reference doesn't produce the same output twice.
- The reference gets the checkout's `haxe/std` explicitly. Otherwise its
  built-in std path leaks into serialized positions.

### Porting pitfalls behind the fixes in this milestone

Most payload differences came from upstream relying on OCaml semantics:

- OCaml evaluates constructor, tuple and function arguments right to left.
  For example, `TVar (fv v, Option.map f eo)` in `Texpr.map_expr_type`
  allocates the initializer's variables before the declared one. Haxe goes
  left to right, so the port names the order explicitly (`Texpr.mapExprType`,
  `Inline`, `Exceptions.catchesToIfs`).
- `Globals.IntMap` uses a reversed comparison, so it iterates in descending
  order. `PMap` iterates in ascending key order using OCaml string comparison
  (`HxbWriter.sortedKeys`).
- `TLazy` is a mutable `tlazy ref`. It is now a `TLazy` class with a mutable
  state, so resolving a lazy type updates every holder.
- Labeled optional arguments (`~static:true`) were mistranslated as
  positional ones.
- `Filename.dirname "Main.hx"` is `"."`, and `Unix.getcwd` has no trailing
  slash.
- On a `Dynamic` subject, an unqualified enum constructor in a pattern can
  resolve to the wrong enum (`Custom` → `ErrorMsg.Custom`, `This` →
  `Keyword.This`). Constructors matched against metadata are qualified as
  `core.MetaList.StrictMeta.X`.
- HashLink doesn't pad missing optional arguments in dynamic calls, so hook
  references and callbacks have typed signatures.

The HXB writer (`src/compiler/hxb/HxbWriter.hx`), the grammar and the lexer
were replaced with direct translations of `hxbWriter.ml`, `grammar.ml` and
`lexer.ml`. The earlier versions are kept as `LegacyGrammar`/`LegacyLexer`
for the bootstrap entry point (`haxe.LegacyMain`) and its unit tests.

### Out of scope for this milestone

- Macro execution: done in the macro milestone above.
- Multi-part builds (`--next`/`--each`), haxelib, display/server, and
  HXB-library input in the port.
