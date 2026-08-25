# HXB Execution and Conformance Tests

The oracle and initial execution host are the same executable: `haxe` built
from the sibling `haxe/` submodule at the pinned revision. Do not substitute an
unrelated system release when recording results.

The exact conformance harness also passes the checkout's `haxe/std` explicitly
to the reference. Setting `HAXE_STD_PATH` alone is insufficient for native
Haxe: its compiled-in installation path can otherwise leak into serialized
source positions and produce a false first payload mismatch.

## Eval-HXB execution

Run:

```sh
HAXE_REFERENCE=/absolute/path/to/pinned/haxe \
  sh test/eval-hxb-execution.sh
```

This is expected to pass before full compiler conformance. It:

1. compiles the port's Haxe source to an Eval-target HXB with the pinned
   compiler;
2. executes the source form of `haxe.Main` to compile a fixture;
3. loads the compiler archive through `--hxb-lib` and executes `haxe.Main`
   again with the same arguments;
4. compares both emitted fixture archives member-by-member.

The compiler archive must contain `eval/haxe/Main.hxb`. A `cross/haxe/Main.hxb`
member is a portable serialized artifact, but the Eval loader will not select
it for `--run`. Renaming the prefix is invalid because target configuration is
part of typing.

This test proves host execution, not self-hosting: the pinned compiler still
types the port and supplies the Eval runtime. It also does not make the outer
compiler execute macros on behalf of the compiler under test.

## Compiler conformance

For every compilable Haxe test-suite example, the harness must:

1. run the reference compiler with the example's effective arguments plus an
   HXB output path;
2. build this project's compiler as Eval HXB with the reference compiler;
3. load it through `--hxb-lib` and run it with the identical effective
   arguments and an HXB output path;
4. compare the normalized ZIP member-name sets;
5. compare every uncompressed `.hxb` member payload byte-for-byte.

Do not compare the complete archive files. ZIP timestamps, member ordering,
headers, and compressor output can differ while the HXB payloads are identical.

The harness must use separate temporary output directories and a stable working
`test/reference/` only when deliberately cached; generated artifacts belong in
`test/generated/`. Both are ignored by Git.

The first concrete comparison case is available through:

```sh
HAXE_REFERENCE=/absolute/path/to/pinned/haxe sh test/conformance.sh
```

`HAXE_REFERENCE` must be the executable built from this checkout's `haxe/`
submodule. The harness invokes the port's batch driver from Eval HXB, normalizes
member names, and uses `cmp` on extracted member payloads. On failure it reports
the first differing member.

Both harnesses use `test/compare-hxb.sh`. It compares the complete normalized
member-name set and the uncompressed payload of each `.hxb` member; it never
compares ZIP container bytes.

For an immediate local comparison against the `haxe` executable on `PATH`, run
`haxe test/conformance.hxml`. This target is expected to fail until the port
matches the host compiler member-by-member; it reports the first differing
member or payload byte.

"Compilable" means the reference invocation exits successfully. Tests that
require a non-HXB target, a runtime, or external services may be discovered but
are not in the initial conformance set. Macro-bearing tests are likewise
excluded, with their reason recorded, until the Eval macro milestone. Do not
treat expected-failure compiler tests as HXB comparison cases.

## Reusing upstream tests before full conformance

The upstream suite is useful in three distinct lanes; do not merge their pass
criteria:

- `haxe test/upstream-parser-corpus.hxml` parses every pinned upstream unit
  source and guards the current breadth floor. It includes macro and
  expected-failure sources because parsing them does not execute or validate
  them. Its score is a directional parser metric, not compiler conformance.
- Source-only, macro-free cases may become HXB conformance cases only after the
  pinned reference compiler accepts their effective HXB invocation. Compare
  those archives member-by-member with `test/compare-hxb.sh`.
- Macro, target-runtime, display/server, external-library, and expected-failure
  cases remain explicitly excluded until their corresponding milestone exists.

The current parser-corpus floor is 1,339 of 1,366 source files. Increasing that
number is useful progress; it does not mean those files type or emit conforming
HXB.

Set `HAXE_PARSER_REPORT_FAILURES=1` to list each rejected source and its first
parser error while keeping the same coverage assertion.

`HAXE_REFERENCE=/absolute/path/to/pinned/haxe sh test/upstream-hxb-smoke.sh`
is the intermediate typing/emission lane. Each listed source-only case must be
accepted by the reference compiler, compile through the port, and produce an
archive the reference compiler can consume. Payload differences remain visible
work and do not become conformance passes merely because consumption succeeds.
Discovered exclusions and their current reasons are recorded in
`test/upstream-hxb-exclusions.md`.

The current breadth set contains 123 direct source roots and 10 effective HXML
configurations. A retained pass must type every non-extern field body; an
unsupported expression is a failure, never an omitted body or placeholder.
Reference consumption is still only a smoke check while source classpaths are
present: the reference compiler may load a dependency omitted from the archive
from source. Conformance still requires the complete reference member set.

Expression-local IDs and generated temporaries are serialized semantics. If a
payload differs only in these values, fix typer allocation and transformation
order; do not canonicalize the payload before comparing it.
