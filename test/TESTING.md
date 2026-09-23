# Goal: complete everything up to macro functionality — 2026-09-23

Finish the HXB-only milestone so the Eval macro milestone can start. Macro
execution, the Macro API bridge, and the macro context are explicitly out of
scope; macro-bearing cases stay recorded exclusions.

Done when all of the following hold:

1. The translated pipeline emits HXB for every macro-free,
   non-target-specific upstream-suite case the reference compiler accepts.
   The only exclusions are expected-failure, non-HXB-target, macro,
   haxelib, and display/server cases, each recorded with its reason.
2. Every emitted archive is consumable by the reference compiler without
   source classpaths (proves dependency completeness, not just emission).
3. Source-executed and Eval-HXB-executed port output identical member sets
   and uncompressed member payloads for the same coverage set.
4. Pinned-reference payload conformance: same normalized member set and
   byte-for-byte equal uncompressed `.hxb` members for every covered case.

Phases (in order; each must stay green before the next expands scope):

- Phase 1 — HXB writer fidelity. Fixed: statics-module aliases (`Class<...>` /
  `Enum<...>` / abstract equivalents) are written with tags 10/11/12 instead
  of bogus typedef references (this unblocked host consumption of broader
  archives: `haxe.io.Error` while loading `haxe.io.Bytes`). Any further
  member-level gaps found while expanding coverage go here.
- Phase 2 — Coverage expansion. Drive the translated pipeline over the
  smoke inventory (112 direct roots, 9 HXML configurations) plus the
  `test/unit/moduleload/` fixtures; record per-case status. Known gaps to
  close or explicitly exclude: pattern-matcher parity (`Issue2508`),
  abstract-constructor typing/inlining, `TIdent` confinement, inherited/
  `super`/import resolution (see `test/README.md`).
- Phase 3 — Host-execution parity and dependency completeness for the
  Phase 2 set (criteria 2 and 3).
- Phase 4 — Pinned-reference conformance (criterion 4). Blocked on
  environment: no OCaml/dune/opam toolchain here, so no `haxe/haxe`
  reference build exists. Everything else proceeds without it; conformance
  runs once a reference is available.

Rules throughout: no successful no-ops or omitted bodies, no faked passes,
exclusions recorded with reasons, results tracked here and coverage in
`TRANSLATION.md`.

# Runtime checkpoint — 2026-09-23

The translated pipeline now emits the previously blocked fixtures. `TryCatch`
exits 0 with 119 parsed/typed modules and 675 methods; `HelloWorld` (trace)
exits 0 with 119/119/674. `Basic` (40/40/115) and `Int64Basic` (67/67/408)
remain green, and source-vs-Eval-HXB execution still matches for `Basic`.
Bootstrap/all-module builds, the unit suite, and the parser corpus
(1,339/1,366) pass unchanged.

Three repairs in this checkpoint:

- `src/syntax/Grammar.hx` Pratt levels had bitwise operators binding looser
  than equality/comparison operators, inverting `haxe/src/syntax/parser.ml`.
  `n & 0x800000 != 0` parsed as `n & (0x800000 != 0)`, which surfaced as
  `Int should be Bool` / `Bool should be Int` errors in `haxe/io/Input.hx`.
  Equality/comparison operators now bind looser than `??`, which binds looser
  than `|`/`^`/`&`. Retained deviations from upstream are documented next to
  the table (`|`/`^`/`&` keep distinct C-like levels, `%` stays grouped with
  `*`/`/`, `in` stays loosest for the existing for-loop shape).
- `src/filters/exception/Exceptions.hx` `catchesToIfs` built
  `[declare_haxe_exception; declare_unwrap; transformed]` in one array
  literal. Upstream relies on OCaml right-to-left evaluation, so
  `declare_unwrap` runs first and the `haxe.Exception` temporary allocated
  while building the unwrap declaration is already known when
  `declare_haxe_exception` emits its declaration. Haxe evaluates array
  literals left-to-right, leaving generated catch variables (for example in
  `BalancedTree.remove`) referenced without a declaration; the HXB writer
  rejected the archive. The two declarations are now sequenced explicitly,
  keeping the same document order.
- `src/compiler/hxb/HxbWriter.hx` wrote statics-module aliases
  (`Class<...>` / `Enum<...>` / abstract equivalents) as typedef references
  instead of upstream's tags 10/11/12. The host reader could not resolve
  them (`Cannot resolve type haxe.io.Error.Enum<haxe.io.Error>` while
  loading `haxe.io.Bytes`). Decoded on the wire with a throwaway member
  inspector before fixing.

Current limits:

- Larger standard-library loads still need `-D eval-call-stack-depth=10000`
  on the host invocation (now baked into `test/translated-pipeline.hxml`);
  without it, typing fails with host stack overflow instead of a diagnostic.
- Host consumption of the newly emitted archives is partial: `Basic` and
  `Int64Basic` archives load and execute; `TryCatch`/`HelloWorld` archives
  load and type-check (`--no-output` passes) but executing them on the
  installed host fails at `StringMap.size`. That is host/std skew, not a
  port defect: the installed Haxe `5.0.0-preview.1` rejects `map.size()`
  even from source (`haxe.ds.StringMap<Int> has no field size`), while the
  pinned submodule std declares it. Executing size-calling code needs the
  pinned runtime; until a reference is built, load/type consumption (plus
  execution where the host supports it) is the bar. This is exactly why the
  reference must be the pinned-submodule build, never the system Haxe.
- Development-host breadth is 120/121: `issue-11164` fails identically on the
  clean tree, so it is pre-existing environment drift rather than a
  regression from this checkpoint.
- Pinned-reference execution and payload conformance remain unverified: no
  executable built from the pinned submodule was available.

Broader fixtures can be exercised with (exit code is the pipeline's; use a
file redirect rather than a pipe to preserve it):

```sh
haxe -D eval-call-stack-depth=10000 -cp src -cp test --run TranslatedPipeline \
  -cp test --main unit.moduleload.TryCatch --interp --no-output --hxb /tmp/trycatch.hxb
```

# Runtime checkpoint — 2026-09-09

The bootstrap build, all-module build, unit suite, and parser corpus still pass.
The parser corpus remains at 1,339/1,366. Three examples under `examples/` now
compile through the bootstrap compiler loaded from HXB; host-built Eval HXB
archives for the same sources execute without source class paths.

The translated pipeline now compiles the default `Basic` fixture and the focused
`Int64Basic` fixture to HXB. The latter reaches 67 parsed/typed modules and 408
typed methods, and the development host can consume the resulting archive.
Source execution and execution from an Eval HXB of the translated compiler also
produce matching `Basic` payloads when parallelism is disabled. Eval-hosted
integration runs need `-D eval-call-stack-depth=10000` for larger standard-library
loads; the default Eval call-depth can overflow while parsing `StringTools.hx`
from an already-deep typer call.

The broader `TryCatch` fixture reaches 119 parsed/typed modules and 675 methods.
Its current blocker is HXB expression scoping after exception filtering:
generated catch variables (for example in `BalancedTree.remove`) can be referenced
without a matching declaration in the serialized expression tree. The writer
correctly rejects this instead of emitting a corrupt archive.

Repairs in this checkpoint include:

- statement blocks no longer absorb a following prefix `++` or `--` as a
  postfix operator; the `haxe.CallStack.subtract` invalid-assignment error is
  gone and a grammar regression test covers this boundary;
- class-field kinds and nested property access records now use structural
  comparison where upstream uses OCaml structural equality;
- inline return wrapping catches the actual `Unify_error` exception, allowing
  Eval `Int64` abstract conversions to proceed;
- metadata AST serialization now covers the complete upstream expression tag
  set and structural type hints;
- unbound monomorphs are assigned HXB pool references instead of being rejected.

The missing abstract-extension errors were traced to another projection issue:
assigning `mtUsing` on the temporary `tInfos` record did not update the source
type. Mutating its shared ordered array restores `@:using(haxe.CallStack)` and
removes all three `CallStack` `toString` errors. The remaining translated-pipeline
former `Cannot call null` failure while flushing `PForce` is resolved.

# Initial runtime test results — 2026-09-04

Baseline: `9943ab5`, followed by the runtime fixes in this checkpoint.
Development host: installed Haxe `5.0.0-preview.1`.
Pinned upstream source: `b10fa6e93c0206cc0dc8f7abba98534e3edac248`.

| Check | Result | What it covers |
| --- | --- | --- |
| Bootstrap build | Pass | Existing `haxe.Main` entry point compiles |
| All-module build | Pass | Translated source modules compile |
| Unit suite | Pass | Existing checks plus new adapter, metadata, and filename regressions |
| Parser corpus | Pass: 1,339/1,366 | Meets the unchanged floor; 27 existing exclusions remain |
| Bootstrap source vs Eval-HXB execution | Pass | Complete emitted member sets and uncompressed HXB payloads match |
| Bootstrap development-host breadth | Pass: 121/121 | 112 direct roots and 9 HXML configurations emit HXB and the installed host accepts it |
| Translated full pipeline | Fail | The Basic fixture reaches 22 parsed/typed modules and 72 methods, then `Cannot call null`; no HXB emitted |
| Pinned-reference execution and conformance | Unavailable | No executable built from the pinned submodule was found |

The bootstrap and translated pipeline are distinct implementations. Passing the
bootstrap checks does not establish runtime correctness of the newly translated
typer, finalization, and filtering path. The new `TranslatedPipeline` entry invokes
that path directly and fails if its default fixture reports success without
typed modules and a nonempty Basic HXB member. It removes stale output first.

Development-host breadth is not compiler conformance: it does not establish
acceptance by the pinned reference, compare candidate payloads against an oracle,
or prove archive dependency completeness. Host consumption retains source
classpaths, so missing dependencies can be loaded from source. Every emitted
archive was additionally checked for its nonempty root module payload.

## Repairs found by execution

- Store the empty-module MD5 digest in the port's established hexadecimal
  representation; raw digest bytes are not valid Eval strings. Print the stored
  digest directly instead of encoding its hexadecimal text again.
- Initialize the split core type and typer callbacks explicitly before creating
  the translated context.
- Convert metadata to strict variants at the parser stream boundary used by the
  translated pipeline. Preserve the legacy parser interface used by the bootstrap.
- Read filenames from lazy path records in module import handling, finalization,
  and HXB serialization; preserve support for bootstrap string filenames.
- Access classpath properties through their typed interface so Haxe invokes the
  getter during local-variable shadow checks.
- Raise the canonical `NotFound` exception for missing native metadata so
  ordinary override checks can handle that expected absence.

New regression checks cover metadata variants, identical HXB serialization for
string/lazy filenames, fixed-width integer boundaries and rejection, persistent
map snapshots and ordering, structural table binding stacks, shallow record
identity, concurrent lazy evaluation, and worker exception propagation.

## Stopping point and next steps

The translated pipeline still fails during standard-library typing. Its last
verbose field is `haxe.Exception.set_stack`; the surfaced error is
`Cannot call null`. That is a diagnostic lead, not yet a proven failing source
location. At failure it reports 22 parsed modules, 22 typed modules, 20 classes,
and 72 methods. No HXB archive is emitted. The failing test is retained without
weakening its success conditions.

Next, locate and repair the remaining null callback and get this real pipeline
to emit the Basic fixture. Then verify execution from its Eval-HXB archive,
build or provide the pinned native reference, and compare complete member sets
and payloads. Expand full-pipeline coverage using the existing breadth inventory
and additional eligible upstream cases. Macro execution, HXB-library input in
the port, display/server services, and ordinary target generators remain later
milestones.

## Reproduce

Run from the repository root:

```sh
haxe haxe-in-haxe.hxml
haxe compile-all.hxml
haxe test/unit.hxml
haxe test/upstream-parser-corpus.hxml
python3 test/development-hxb-smoke.py
HAXEDEBUG=1 haxe test/translated-pipeline.hxml
```

The development breadth script rebuilds the compiler archive from the current
checkout, reads the case inventory from `upstream-hxb-smoke.sh`, runs every case,
and records individual failures instead of stopping at the first one. It uses
`HAXE_HOST` if set, otherwise `haxe` on PATH. It never treats that executable as
the conformance oracle.

Logs and generated archives are under `test/generated/testing/` and are ignored
by Git. The breadth script writes `breadth/results.json` and `breadth/summary.txt`.
The translated integration run is recorded in `translated-basic.log`.

The native reference executable, `opam`, `dune`, and `ocamlc` were not available
in the checked environment. Once a compiler built from the pinned source is
available, run the three reference lanes separately:

```sh
HAXE_REFERENCE=/path/to/pinned/haxe sh test/eval-hxb-execution.sh
HAXE_REFERENCE=/path/to/pinned/haxe sh test/upstream-hxb-smoke.sh
HAXE_REFERENCE=/path/to/pinned/haxe sh test/conformance.sh
```

These existing reference scripts still target the bootstrap driver. The new
pipeline needs to pass its integration fixture before it can replace that driver
in conformance runs. No reference result has been inferred from the installed
host's successful checks.
