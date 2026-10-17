# Design docs

Open designs and decisions, with their reasoning, by area. What is next
and in which order: [ROADMAP.md](../../ROADMAP.md). What is built:
[docs/hxmc.md](../hxmc.md), [docs/using.md](../using.md),
[docs/testing.md](../testing.md).

| | |
| --- | --- |
| [compiler.md](compiler.md) | the module cache, the central object cache, macro-heavy builds, native macros and code generation at run time |
| [runtime.md](runtime.md) | the collector, stack maps, compact strings, system calls, TLS and the event loop |
| [codegen.md](codegen.md) | escape analysis, debugging information (PDB, `__unwind_info`, variables, wasm DWARF), small codegen items |
| [targets.md](targets.md) | WebAssembly (and WasmGC), Android, iOS, shared libraries, Linux and macOS items |
| [graphics.md](graphics.md) | `@hxmc/os`, `@hxmc/gfx`, shaders, audio, UI pointers |
| [web.md](web.md) | `@hxmc/view`, `@hxmc/web`, the site |
| [packaging.md](packaging.md) | npm, haxelib, verifying native builds |
| [math.md](math.md) | LibM and the libm branch |
| [lowlevel.md](lowlevel.md) | C interop, native memory, manual memory, struct values |
