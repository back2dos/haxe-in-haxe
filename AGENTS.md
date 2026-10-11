# Contributor guide

This file is for people and coding agents changing the port.

## Scope

`src/` is a port of the Haxe compiler in `haxe/src/` that must behave exactly
like the reference compiler built from the `haxe/` submodule. `hxc/` is the C
backend that compiles the port (and other programs) to native code. `haxe/` is
the canonical reference: never edit its files or commit inside it; moving the
pinned revision is a deliberate change that also ports every upstream commit
in between and rebuilds the reference (`make -C haxe haxe`).

`haxe/libs/` holds OCaml implementation dependencies. Reproduce the behavior
they provide (`src/libs/` has the Neko bytecode compiler, swflib, zlib deflate,
extlib IO, ziplib) rather than porting them mechanically, and only what the
compiler reaches.

## Porting rules

- Read the upstream OCaml module before adding or changing its Haxe
  counterpart, and keep the counterpart at the matching path (`typing/typer.ml`
  becomes `src/typing/Typer.hx`).
- Preserve function order, branch order, data layout, error messages and
  exception behavior. Prefer a direct translation over a redesign.
- Reproduce OCaml semantics that reach the output: `Hashtbl` iteration order
  (`core.ds.OcamlHashtbl`), `PMap` order (sorted keys), right-to-left
  evaluation of arguments with side effects, float printing
  (`core.Numeric`, `core.ds.OcamlPrintf`), 31/63-bit integer behavior.
  Never derive output order from Haxe `Map` iteration.
- Never stub out behavior with a silent success. Code the port cannot support
  fails explicitly with a `// port:` note.

## Comments

- Comments from the upstream source stay at the matching place with upstream's
  wording (`(** *)` becomes `/** */`).
- Every other comment in `src/` starts with `// port:` (continuation lines
  `// ...`): deviations, host adaptations, OCaml-semantics emulation. Keep them
  true and remove them with the code they describe.

## Testing

- The reference is the binary built from `haxe/`, never a system Haxe.
- Conformance means the same normalized ZIP member names and byte-identical
  uncompressed `.hxb` payloads (never whole-archive bytes), and for the target
  generators byte-identical output files.
- Before declaring a change done, run the lanes it can affect
  (`test/README.md`): HXB conformance and macro cases for anything in typing
  or filters, the fuzzer's `diff:<target>` lanes for generators, display and
  server for those services, and the full matrix for broad changes.
- Fast loop: `sh hxc/tools/port-dev.sh` rebuilds `bin/port/hih` in seconds
  (`CC=tcc`), then `bin/fuzz/fuzz --port $PWD/bin/port/hih --lane diff:<target>`.
- Record results in `test/TESTING.md`. Never commit `bin/`, `test/generated/`,
  `test/reference/` or local haxelib state.
