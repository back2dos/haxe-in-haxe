# Tests

Every harness compares the port with the reference compiler built from
`haxe/` (`HAXE_REFERENCE`, an absolute path). By default they build and run
the HashLink build of the port (`test/generated/conformance/haxe-in-haxe.hl`,
written by `conformance.py`); `HAXE_IN_HAXE_PORT=<command>` runs another
build, typically `bin/hxc/hih/hih_clang`. Generated files go to
`test/generated/` (ignored by Git). Current results: [TESTING.md](TESTING.md).

| Harness | What it compares |
| --- | --- |
| `conformance.py` | HXB archives for every case of a case list: member names and every uncompressed `.hxb` payload; rejected cases must be rejected alike. `--hxb-lib` also loads each archive back with both compilers; `--parallel N` runs the port in parallel mode and compares after normalizing variable ids; `--eval` runs the port from an Eval HXB archive through the reference's `--hxb-lib`. |
| `conformance-*cases.txt` | The case lists: `conformance-cases.txt` (286 configurations of the upstream test suite that compile to HXB), `-macro-` (66, run macros), `-hxblib-` (archives as libraries), `-upstream-` (upstream CI's macro job), `-party-` (tink_core, hxcoro). `discover-cases.py` (with `macro-probe.patch`) regenerates the main list; `upstream-hxb-exclusions.md` lists what is excluded and why. `display-snippet-cases.py` turns the display snippets into cases. |
| `fuzz/` | The differential fuzzer: random well-typed programs, compared per target (`diff:<target>`: diagnostics and every output file) or by program output (`exec:<a>,<b>`), with reduction of failures. See [fuzz/README.md](fuzz/README.md). |
| `unit-targets.py` | Upstream's unit suite compiled for each target (`compile-<target>.hxml`; C++, cppia host and HL/C stop at the sources): every output file, JAR members by name and bytes. Only the compile date of `unit.TestMainNow` is masked. Defaults to `bin/port/hih`. |
| `interp.py` | Program output and exit code of `--interp` runs. |
| `upstream.py` | Upstream CI's target-independent job (`tests/runci/targets/Macro.hx`): unit, misc, threads, display, server, the third-party projects. |
| `display.py` | `--display` JSON-RPC requests from upstream's display tests (completion, hover, definition, references, diagnostics…). Upstream removed `tests/display`; the corpus is extracted from the commit before (`HAXE_DISPLAY_CORPUS` overrides). |
| `server.py` | The compilation server (`--wait`/`--connect`/`--server-connect`): repeated compiles with cache reuse, edits and invalidation (with the verbose server logs), output, stdin, `--cmd`, errors. |
| `server-jsonrpc.py` | The `server/*` JSON-RPC methods through a running server, both cache modes. |
| `eval-debugger.py` | Scripted Eval debugger sessions (breakpoints, stepping, scopes, evaluate). |
| `haxelib.py` | `-L`/`--library` against a local haxelib repository, batch and through the server. |
| `unit.hxml`, `unit/` | Unit tests of port modules, run in-process on Eval: `haxe/haxe test/unit.hxml`. |
| `compile-all.hxml` | Types every port module, including those `haxe.Main` does not reach. |
| `hl/` | Std overrides for the HashLink build of the port. |

Sequential runs pass `-D disable-parallelism`: the reference itself is not
deterministic in parallel mode.
