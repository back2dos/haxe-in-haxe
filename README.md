# Haxe in Haxe

An in-progress, close-to-line-by-line port of the Haxe compiler from OCaml to
Haxe.

The only current code-generation deliverable is an HXB-emitting compiler.
JavaScript, C++, HashLink, Eval, and every ordinary output target are explicitly
out of scope until that goal is complete. During development, the pinned Haxe
compiler can compile the port to Eval-flavoured HXB and execute it through
`--hxb-lib`; this is a host strategy, not an Eval generator in the port. The
Eval machinery eventually required for macro execution is likewise separate
from exposing Eval as a user target.

## Repository layout

- `haxe/` is the pinned `haxefoundation/haxe` Git submodule. It is the source
  being ported and the behavioral reference.
- `src/` holds the Haxe port. Its structure should remain traceable to
  `haxe/src/`.
- `haxe-in-haxe.hxml` builds the bootstrap compiler to
  `bin/haxe-in-haxe.hxb`.
- `test/` defines the HXB conformance harness and its ignored artifacts.

## Setup

Clone with submodules, or initialize them after cloning:

```sh
git submodule update --init --recursive
```

The project needs a Haxe compiler capable of emitting HXB and, for conformance
testing, a native reference compiler built from the pinned `haxe/` submodule.
Follow the upstream build instructions in `haxe/README.md` to build that
reference compiler. With its OCaml/Dune dependencies installed, the direct
compiler-only build is:

```sh
make -C haxe haxe
export HAXE_REFERENCE="$PWD/haxe/haxe"
```

## Build

```sh
haxe haxe-in-haxe.hxml
```

This currently validates the bootstrap entry point and writes
`bin/haxe-in-haxe.hxb`. HXB is a serialized compiler artifact rather than an
executable, so this build is not by itself a self-hosting or conformance test.

## Execute the compiler from HXB

The shortest functional feedback loop uses the pinned compiler as the Eval HXB
loader and runtime:

```sh
HAXE_REFERENCE=/absolute/path/to/pinned/haxe \
  sh test/eval-hxb-execution.sh
```

The test first asks the pinned compiler to compile the port's source to an
Eval-target archive containing `eval/haxe/Main.hxb`. It executes the source form
to compile a fixture, then loads that archive with `--hxb-lib`, executes
`haxe.Main` again, and verifies that both runs emit identical HXB member sets
and payloads. This proves that the compiler can run from HXB without requiring
HashLink, Go, or another independent host.

The batch compiler also expands nested `.hxml` files, including their class
paths, defines, main class or bare module roots. When an HXB output is present,
ordinary execution markers such as `--interp` and `--no-output` are accepted as
configuration input but do not add another output target. Multi-part builds,
libraries, macros, and display/server options still fail explicitly.

## Conformance contract

Correctness has two immediate checks. Eval-HXB execution must behave identically
to executing the same port directly from source. Compiler conformance must
match the HXB produced by the pinned compiler for the same effective
invocation. The eventual harness must discover every compilable example in the
upstream Haxe test suite and apply both checks. `test/conformance.sh` already
produces its candidate output by loading the compiler through `--hxb-lib`, so a
future passing result covers execution and serialization together.

HXB comparisons normalize archive member names and compare each uncompressed
`.hxb` member payload byte-for-byte. The ZIP containers themselves are not
compared because timestamps, member ordering, headers, and compression output
are not HXB semantics.

`test/README.md` specifies the harness behavior and artifact policy. A test
that cannot be compiled by the reference compiler is not an HXB comparison
case; target-specific tests are likewise outside the initial scope.

## Test lanes

```sh
haxe test/unit.hxml
haxe test/upstream-parser-corpus.hxml
HAXE_REFERENCE="$PWD/haxe/haxe" sh test/upstream-hxb-smoke.sh
HAXE_REFERENCE="$PWD/haxe/haxe" sh test/conformance.sh
```

These are different goalposts: unit tests check ported subsystems; the parser
lane currently accepts 1,339/1,366 upstream sources; smoke requires 112 direct
roots and 9 HXML configurations to emit loadable HXB; only the final command
requires exact member sets and uncompressed member payloads. Macro, runtime,
target-specific, and expected-failure tests remain recorded exclusions rather
than simulated passes.

## Porting approach

Keep each port mechanically close to its counterpart in `haxe/src/`. Preserve
control flow, data representation, error behavior, and module boundaries unless
a documented language difference requires a deviation. Reference the upstream
path in the ported file or its adjacent documentation when the relationship is
not obvious.

There is an older exploratory implementation at
[`elnabo/haxe_in_haxe`](https://github.com/elnabo/haxe_in_haxe). It may be used
for research, but this repository should not inherit its design without first
checking it against the pinned upstream source and the HXB conformance contract.
