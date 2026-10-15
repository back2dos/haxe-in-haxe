# Tests

Every harness compares the port with the reference compiler built from
`haxe/` (`HAXE_REFERENCE`, an absolute path). By default they build and run
the HashLink build of the port (`test/generated/conformance/haxe-in-haxe.hl`,
written by `conformance.py`); `HAXE_IN_HAXE_PORT=<command>` runs another
build, typically `bin/port/haxe`, the port built by hxmc (`make port`;
`make test` runs `conformance.py` with it, `make test-fuzz` the fuzzer). Generated files go to
`test/generated/` (ignored by Git). Current results: [TESTING.md](TESTING.md).

| Harness | What it compares |
| --- | --- |
| `conformance.py` | HXB archives for every case of a case list: member names and every uncompressed `.hxb` payload; rejected cases must be rejected alike. `--hxb-lib` also loads each archive back with both compilers; `--parallel N` runs the port in parallel mode and compares after normalizing variable ids; `--eval` runs the port from an Eval HXB archive through the reference's `--hxb-lib`. |
| `conformance-*cases.txt` | The case lists: `conformance-cases.txt` (286 configurations of the upstream test suite that compile to HXB), `-macro-` (66, run macros), `-hxblib-` (archives as libraries), `-upstream-` (upstream CI's macro job), `-party-` (tink_core, hxcoro). `discover-cases.py` (with `macro-probe.patch`) regenerates the main list; `upstream-hxb-exclusions.md` lists what is excluded and why. `display-snippet-cases.py` turns the display snippets into cases. |
| `fuzz/` | The differential fuzzer: random well-typed programs, compared per target (`diff:<target>`: diagnostics and every output file) or by program output (`exec:<a>,<b>`), with reduction of failures. See [fuzz/README.md](fuzz/README.md). |
| `unit-targets.py` | Upstream's unit suite compiled for each target (`compile-<target>.hxml`; C++, cppia host and HL/C stop at the sources): every output file, JAR members by name and bytes. Only the compile date of `unit.TestMainNow` is masked. Defaults to `bin/port/haxe`. |
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

## Upstream's CI suite

`.github/workflows/upstream-tests.yml` (called by `build.yml` after the
release builds) runs upstream's GitHub Actions test jobs with the port as
`haxe`: RunCi in `haxe/tests` for macro, js, hl, cpp, jvm, php, python, lua,
flash and neko, as upstream's `linux-test` (x86_64 and arm64), `mac-test`
(arm64, plus hl on x86_64) and `windows64-test` (x86_64) do, with their
per-target packages, d8, Lua cache, MSYS2, msbuild, timeouts and
`fail-fast: false`. Each job:

- downloads the release archive of its platform (`haxe-in-haxe-linux-*`,
  `haxe-in-haxe-macos-*`, `haxe-in-haxe-windows-x86_64`) and puts its binary
  on `PATH` as `haxe` (`haxe.exe` on Windows), with `HAXE_STD_PATH` at the
  submodule's `haxe/std`;
- installs neko with upstream's composite action
  (`./haxe/.github/actions/setup-neko`) and builds haxelib as upstream's
  Makefiles do, but with the port: `haxe client.hxml` in
  `haxe/extra/haxelib_src` (the port's `run.n` is byte-identical to the
  reference's), then `nekotools boot -c run.n` and `cc run.c -lneko`
  (Windows: `nekotools boot run.n`, as `haxelib.exe`);
- runs RunCi straight from the submodule (checked out recursively), which
  installs each target's runtime and libraries itself: `haxe --run RunCi
  <target>`, on Windows `haxe RunCi.hxml` with `TEST` set, as upstream.

The release binaries are built by hxmc (`make release`): native
executables for each system with mbedtls and libuv. The Windows build is a
PE executable over the UCRT and the Windows API (hxmc's runtime,
`hxmc/std/hxmc/rt/WinSys.hx`): its Eval host reports `Sys.systemName()`
"Windows" and uses Windows paths, processes and environment as the
reference `haxe.exe` does.

Locally, the same runs need a haxelib built as above on `PATH` (with
`HAXELIB_PATH` pointing at a scratch repository, so `~/.haxelib` is left
alone) and the target's runtime; `test/TESTING.md` has the results.
