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
