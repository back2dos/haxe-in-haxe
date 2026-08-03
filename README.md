# Haxe in Haxe

An in-progress, close-to-line-by-line port of the Haxe compiler from OCaml to
Haxe.

The only current deliverable is an HXB-emitting compiler. JavaScript, C++,
HashLink, Eval, and every other code-generation target are explicitly out of
scope until that goal is complete.

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
reference compiler.

## Build

```sh
haxe haxe-in-haxe.hxml
```

This currently validates the bootstrap entry point and writes
`bin/haxe-in-haxe.hxb`. As compiler modules are ported, this command remains

## Conformance contract

Correctness is measured against the HXB produced by the actual compiler, not
against program execution. The eventual test harness must discover every
compilable example in the upstream Haxe test suite, compile each one with both
compilers using identical effective arguments, and compare the resulting HXB
files byte-for-byte.

`test/README.md` specifies the harness behavior and artifact policy. A test
that cannot be compiled by the reference compiler is not an HXB comparison
case; target-specific tests are likewise outside the initial scope.

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
