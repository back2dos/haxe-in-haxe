# archive/

Code kept for reference only. Nothing here is built or tested, and paths in
these files refer to the repository layout of their time (`backend/` is now
`hxc/`, `bench/js-shims/` is `runtime/js/`).

| Path | |
| --- | --- |
| `deferred/` | Early drafts of compiler parts outside the HXB milestone (target dispatch, full compiler entry, display typing, memory diagnostics), superseded by the translated modules in `src/` or waiting for their milestone. |
| `examples/` | The first playable examples (bootstrap pipeline, before the full typer); `site/examples/` replaces them. |
| `hx2go/` | Building the port with hx2go (Haxe → Go): the fix-up scripts and patch used for the comparison in `bench/README.md`. |
| `generational-gc/` | The HashLink generational GC prototype (libhl and hl2c patches) that preceded hxc's own collector. |
| `wasm-prototype/` | Prototypes for the native/wasm backend decision (`docs/WASM-BACKEND.md`): Go and OCaml reference programs, WAMR/wasmtime runners and timing scripts. |
