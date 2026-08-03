# HXB Conformance Tests

This directory will contain the conformance harness for the port. Its oracle is
the `haxe` executable built from the sibling `haxe/` submodule at the pinned
revision.

For every compilable Haxe test-suite example, the harness must:

1. run the reference compiler with the example's effective arguments plus an
   HXB output path;
2. run this project's compiler with the identical effective arguments and an
   HXB output path;
3. compare the resulting `.hxb` files byte-for-byte.

The harness must use separate temporary output directories and a stable working
`test/reference/` only when deliberately cached; generated artifacts belong in
`test/generated/`. Both are ignored by Git.

The first concrete comparison case is available through:

```sh
HAXE_REFERENCE=/absolute/path/to/pinned/haxe sh test/conformance.sh
```

`HAXE_REFERENCE` must be the executable built from this checkout's `haxe/`
submodule. The harness invokes the port's batch driver and uses `cmp` for a
byte-for-byte result. It intentionally keeps both generated outputs in a
temporary directory on failure for diagnosis.

For an immediate local comparison against the `haxe` executable on `PATH`, run
`haxe test/conformance.hxml`. This target is expected to fail until the port
matches the host compiler byte-for-byte; it reports the first differing byte.

"Compilable" means the reference invocation exits successfully. Tests that
require a non-HXB target, a runtime, or external services may be discovered but
are not in the initial conformance set. Do not treat expected-failure compiler
