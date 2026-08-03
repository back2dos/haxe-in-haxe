# Agent Guide

## Mission and scope

Port the Haxe compiler in `haxe/src/` to Haxe in `src/`, keeping the port close
HXB. Do not implement, restore, or test other code-generation targets unless a
task explicitly expands the scope.

`haxe/` is a Git submodule and the canonical reference. Do not edit its files,
commit inside it, or update its revision as part of ordinary porting work.

## Implementation rules

- Read the corresponding upstream OCaml module before adding or changing a
  ported Haxe module.
- Preserve ordering, branch structure, exception/error behavior, and data
  layout whenever possible. Prefer a direct translation over a redesign.
- Keep Haxe modules under `src/` traceable to their `haxe/src/` sources. Add a
  short source-path comment only when the mapping is not evident from names and
  layout.
- Isolate unavoidable semantic differences rather than spreading abstraction
  layers through the port.
- Keep the bootstrap build working: `haxe haxe-in-haxe.hxml`.

## Testing rules

- The reference compiler is the executable built from the checked-out `haxe/`
  submodule, not an arbitrary system Haxe installation.
- HXB conformance means byte-for-byte comparison of reference and port output
  for the same effective compiler invocation.
- Cover every upstream test-suite example that the reference compiler can
  successfully compile to HXB. Exclude expected-failure and non-HXB-target-only
  cases from that comparison set, while recording why a discovered case is
  excluded.
- Run focused conformance cases for a changed subsystem and the full available
  conformance suite before declaring broad changes complete.
- Never commit `bin/`, `test/generated/`, `test/reference/`, or local Haxelib
  state.

## Working conventions

- Treat generated HXB files as diagnostics, not source artifacts.
- Make the smallest mechanical change that preserves upstream behavior.
- Document deliberate deviations from upstream adjacent to the changed code or
  in the change description.
- The historical `elnabo/haxe_in_haxe` repository is reference material only;
  verify any idea from it against the current pinned upstream compiler.
