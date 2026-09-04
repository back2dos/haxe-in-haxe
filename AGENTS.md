# Agent Guide

## Mission and scope

Port the Haxe compiler in `haxe/src/` to Haxe in `src/`, keeping the port close
to upstream. The first functional target is HXB. Do not implement, restore, or
test other code-generation targets unless a task explicitly expands the scope.

`haxe/` is a Git submodule and the canonical reference. Do not edit its files,
commit inside it, or update its revision as part of ordinary porting work.

## Milestones and boundaries

- The first functional milestone is a host-executed, source-only, macro-free
  compiler which types Haxe programs and emits conforming HXB archives. Use the
  pinned compiler to build an Eval-target HXB of the port, then execute it with
  `--hxb-lib` as the first runtime path. HXB is a serialized compiler artifact,
  not a standalone executable target; this host execution is not self-hosting.
- HXB-only still requires the complete parsing, module-loading, typing,
  finalization, and cross-target filtering path. It does not require ordinary
  target generators or target-specific code generation.
- Treat macro execution, HXB-library input in the port itself, haxelib
  integration, display/server services, and self-hosting as later explicit
  milestones. Loading the port through the pinned compiler's existing
  `--hxb-lib` support does not require porting HXB-library input. Exclude
  affected tests with a recorded reason until their milestone is implemented;
  never fake successful typing or macro results.
- Macro support requires a separate Eval macro context and Macro API bridge.
  The Eval runtime needed to execute macros is in scope for that milestone even
  though exposing `--interp` as a user target is not.
- `haxe/libs/` contains OCaml implementation dependencies, not modules to port
  mechanically. Reproduce required behavior with Haxe/runtime APIs. Neko, SWF,
  and object-size support are not required for HXB; regex, process, filesystem,
  compression, and TLS support may become necessary for compatible macros.

## Implementation rules

### Current phase: runtime testing and integration

The translation snapshot and compilation fixes are committed. The bootstrap
and all-module builds pass. Exercise the translated HXB pipeline at runtime,
preserving upstream declarations, branch order, and behavior. Do not replace untranslated behavior with successful no-ops or
empty stubs, and do not exclude in-scope modules to obtain a passing build.
Independent file groups may be handled by subagents.

Testing is now authorized. Keep `test/translated-pipeline.hxml` distinct from
the legacy bootstrap lanes: the existing bootstrap entry point does not execute
the new typer. Draft translations and successful compilation are not evidence
of compiler conformance. Track test results in `test/TESTING.md` and source
coverage in `TRANSLATION.md`.

- Read the corresponding upstream OCaml module before adding or changing a
  ported Haxe module.
- Preserve ordering, branch structure, exception/error behavior, and data
  layout whenever possible. Prefer a direct translation over a redesign.
- Preserve identity and insertion order for serialized HXB pools and reference
  indices. Do not derive binary ordering from unspecified `Map` iteration.
- Keep Haxe modules under `src/` traceable to their `haxe/src/` sources. Add a
  short source-path comment only when the mapping is not evident from names and
  layout.
- Isolate unavoidable semantic differences rather than spreading abstraction
  layers through the port.
- After the translation phase, restore and keep the bootstrap build working:
  `haxe haxe-in-haxe.hxml`.

## Testing rules

- The reference compiler is the executable built from the checked-out `haxe/`
  submodule, not an arbitrary system Haxe installation.
- HXB conformance means the same normalized ZIP member-name set and
  byte-for-byte equality of every uncompressed `.hxb` member payload for the
  same effective invocation. Never compare whole archive bytes: ZIP timestamps,
  headers, member order, and compressor output are container details.
- When supported, also verify that the pinned reference compiler can consume
  produced archives through `--hxb-lib`.
- Independently verify Eval-HXB host execution: compile the port to an
  `eval/...` archive with the pinned compiler, execute `haxe.Main` from that
  archive, and compare its output member-by-member with the source-executed
  port's output for the same invocation.
- Cover every upstream test-suite example that the reference compiler can
  successfully compile to HXB. Exclude expected-failure and non-HXB-target-only
  cases from that comparison set, while recording why a discovered case is
  excluded.
- Run focused conformance cases for a changed subsystem and the full available
  conformance suite before declaring broad changes complete.
- The bootstrap build only checks that the port can be compiled to HXB; it is
  not compiler conformance or proof that the generated artifact can execute.
- Never commit `bin/`, `test/generated/`, `test/reference/`, or local Haxelib
  state.

## Working conventions

- Treat generated HXB files as diagnostics, not source artifacts.
- Make the smallest mechanical change that preserves upstream behavior.
- Document deliberate deviations from upstream adjacent to the changed code or
  in the change description.
- The historical `elnabo/haxe_in_haxe` repository is reference material only;
  verify any idea from it against the current pinned upstream compiler.
