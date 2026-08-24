# HXB Execution and Conformance Tests

The oracle and initial execution host are the same executable: `haxe` built
from the sibling `haxe/` submodule at the pinned revision. Do not substitute an
unrelated system release when recording results.

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
