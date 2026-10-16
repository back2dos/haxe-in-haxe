# hxmc

The Haxe compiler ported from OCaml to Haxe, and hxmc, a Haxe target that
compiles it (and other programs) to machine code and WebAssembly. hxmc builds
the port for six targets (Linux, macOS and Windows on x86-64 and ARM64) and as
a wasm32-wasi module, and it builds itself. Building everything from a clean
checkout needs only node.

The port behaves exactly like the reference compiler of its pinned upstream
commit: byte-identical HXB, byte-identical output of every target generator,
the same `--interp` runs, display requests and compilation-server answers.

## Layout

| Path | |
| --- | --- |
| `haxe/src/` | the port, module by module after upstream's `haxe/upstream/src/` |
| `haxe/upstream/` | upstream Haxe (submodule, commit `995a7d1fe`): the reference sources and std |
| `haxe/test/` | the port's tests: conformance against the reference (HXB, display, server, JSON-RPC, `--interp`, `-L`, upstream's target suites), the fuzzer (`fuzz/`), unit tests of port modules (`unit/`, `unit.hxml`), peak memory and times (`Measure.hx`) |
| `hxmc/src/hxmc/` | hxmc's sources (package `hxmc`, class path `hxmc/src`): the IR and lowering (`ir/`), the code generators (`x64/`, `a64/`, `wasm/`), the linkers, the driver, `Main.hx` (the tool) and `HaxeMain.hx` (`haxe` with hxmc built in) |
| `hxmc/std/` | hxmc's std: overrides of upstream modules and the runtime's Haxe part (`hxmc.rt`), merged with the Eval originals by `hxmc/src/hxmc/MkStd.hx` |
| `hxmc/deps/` | no C of ours: `deps.sh` (mbedtls and libuv), `mkrt.sh` (the runtime objects: the C library's members, or the glibc mode's import table, mbedtls, libuv), `Layouts.hx` (system and libuv struct layouts per target, checked against the C headers), `probe.c` (build-time layout probe), `zig-version` |
| `hxmc/test/` | hxmc's corpus (`cases/`, golden outputs `expected/`, frozen fuzzer programs `fuzz-1000.zip`), the encoder tests (`encoder/`), the scripts that run them (`Corpus`, `Check`, `Crosshost`, `Selfcheck`, `Tiers`, `EncCheck`), `-lib` from node_modules (`NodeLibs`), the release smoke test (`smoke.sh`), the benchmarks (`Bench`, with the cases' check programs in `bench/`) |
| `hxmc/web/` | the website and its playground (the port as a WebAssembly module in the browser) |
| `hxmc/bootstrap/` | the committed stage0 (`stage0.wasm.br`), node's WASI runner (`wasi.mjs`), the runtime objects by hash (`rt.mjs`) |
| `packages/` | everything published to npm, one folder per package, packed by `pack.mjs`: `cli` (`@hxmc/cli`, laid out as its tarball: `package.json`, the version of the build's packages; the launcher `hxmc/bootstrap/{haxe,launcher.mjs,wasm.mjs,postinstall.mjs,platforms.mjs}`; `dist/haxe` for lix), `wasm` and `source` (`@hxmc/wasm`, `@hxmc/source` with `hxmc-rebuild`), `platform` (the template of the six `@hxmc/<os>-<cpu>`); `os` and `gfx` (`@hxmc/os`: X11, Objective-C runtime and Win32 bindings, windows (X11, Cocoa, Win32), events, the app loop; `@hxmc/gfx`: the portable GPU layer, its back ends (GL over EGL on Linux, Metal on macOS arm64, D3D11 on Windows), `examples/Triangle.hx`, the golden-image test `test/`; pure Haxe: the dynamic glibc mode on Linux, the frameworks and `objc_msgSend` through externs on macOS, DLL imports and COM vtables on Windows, hxmc/PLANS.md "Graphics"); any other folder whose `package.json` has a version of its own is a source-only package, published as it is |
| `tools/lix/` | lix (the lix client and haxeshim) ported to build with hxmc |

## Using hxmc

```sh
npm i -D @hxmc/cli            # node 22 or later; then `npx haxe`, or haxe on PATH through node_modules/.bin
```

The package's `haxe` is the port's command line with hxmc built in: every
target works as usual (`--js`, `--interp`, ...), and `--custom-target
hxmc=<out>` writes an executable. A `build.hxml`:

```hxml
-cp src
-main Main
--custom-target hxmc=bin/app
# another of the seven targets than this machine's:
# -D hxmc.target=windows-x86_64
```

| Option | |
| --- | --- |
| `-D hxmc.target=<target>` | `linux-x86_64`, `linux-arm64`, `windows-x86_64`, `windows-arm64`, `macos-x86_64`, `macos-arm64`, `wasm32-wasi` (default: this machine) |
| `-D hxmc.libc=glibc` | Linux: an executable linked dynamically against the system's glibc (2.17 or later; the default is static with musl), which can import C functions of shared libraries (`@:hxmc.lib("libGL.so.1")`) and load them at run time (`hxmc.unsafe.Posix.dlopen`) |
| `-debug`, `-D hxmc.symbols` | a symbol table (profilers), wasm: a name section |
| `-D hxmc.shared`, `-D hxmc.pic` | a shared library, a position-independent executable (hooks: refused explicitly where not implemented yet) |
| `-D hxmc.jobs=<n>` | parallel module compilations (default: the cores) |
| `-D hxmc.wasm-eh=legacy` | wasm: the legacy exception-handling instructions (`try`/`catch_all`/`rethrow`: Chrome 95+, Firefox 100+, Safari 15.2+) instead of `exnref` (Chrome 137+, Firefox 131+, Safari 18.4+) |
| `HXMC_STATS=1` | what the build did and how long it took |
| `HXMC_CACHE=<dir>` | the cache directory (default `~/.cache/hxmc`, macOS `~/Library/Caches/hxmc`, Windows `%LOCALAPPDATA%\hxmc\cache`; "hxmc" below) |
| `HXMC_TYPES_CACHE=0` | no cache of the runtime's typed modules (every build types them) |

Packages, all published at one version:

| Package | Size (tarball, unpacked) | |
| --- | --- | --- |
| `@hxmc/cli` | 5.9 MB, 26 MB | what you install: the `haxe` launcher, the std (upstream's and hxmc's), the runtime objects of the six targets, `dist/` for lix; optional dependencies on the six platform packages |
| `@hxmc/linux-x64`, `@hxmc/linux-arm64`, `@hxmc/darwin-x64`, `@hxmc/darwin-arm64`, `@hxmc/win32-x64`, `@hxmc/win32-arm64` | 6.1-6.7 MB, 21-25 MB each | the native compiler built by CI for one platform (npm installs the one that matches, by their `os` and `cpu` fields) |
| `@hxmc/wasm` | 3.2 MB, 17 MB | the compiler as a wasm32-wasi module, with its WASI runner for node: the fallback where no native compiler runs |
| `@hxmc/source` | 1.9 MB, 7.5 MB | the compiler's sources (`haxe/src`, `hxmc/src`, `hxmc/std`) and `hxmc-rebuild`; a peer dependency on `@hxmc/cli` at the same version |

(Sizes of a nightly; CI's job summary lists each build's.) `haxe` runs, in
this order: the compiler `hxmc-rebuild` built, while `@hxmc/source` is
installed; the platform package's native compiler; else, when there is none
or it cannot start here (an unsupported machine, an install without optional
dependencies, a noexec file system, StackBlitz's WebContainers;
`HXMC_PLATFORM_PACKAGE=0` and `HXMC_NATIVE=0` force this path), the compiler
as a WebAssembly module under node: `@hxmc/wasm` when it is installed (`npm i
-D @hxmc/cli @hxmc/wasm` where no native compiler can run), else downloaded
on first use. The download is the `@hxmc/wasm` tarball of the same version
from the npm registry (`npm_config_registry`, which npm and npx set, else the
`registry` of an `.npmrc`, else registry.npmjs.org), checked against the
integrity hash pinned in `@hxmc/cli`'s `package.json` when it was packed,
and unpacked into the cache (`hxmc/npm/<version>/wasm/`); offline, `haxe`
prints one line saying so and exits non-zero. The cache is the user's
(`HXMC_CACHE` above; "hxmc").

Without node: on Linux and macOS a postinstall script (best effort, offline,
it only writes inside the package) checks that the native compiler runs and
copies it over `hxmc/bootstrap/haxe` and `dist/haxe`, so
`node_modules/.bin/haxe` (a link to it) starts the compiler directly; with
install scripts disabled (`--ignore-scripts`, pnpm's default) the first call
through node does the same. On Windows npm's `haxe.cmd` always starts node
(about 40-60 ms per call), which runs the native compiler; point editors and
lix at `node_modules/@hxmc/cli/dist/haxe.exe` to bypass it. Nothing but the
compiler's own output goes to stdout or stderr (editors run `haxe --wait
stdio`, whose answers are on stderr, and parse `haxe --version`); notices
(the WebAssembly fallback, its download) go to an interactive terminal only,
and a failure prints one line and exits non-zero. `HXMC_INSTALL=0` keeps the
launcher in place.

Changing the compiler: `npm i -D @hxmc/source`, edit its sources in
`node_modules/@hxmc/source`, and run `npx hxmc-rebuild`: the installed native
compiler builds the edited one (about 20 s, then only the changed modules
again) into the cache (`hxmc/npm/<version>/rebuild/<target>/`, with hxmc's
std merged from its `hxmc/std`), and `haxe` runs it from then on, through the
launcher, while `@hxmc/source` is installed. Without a native compiler that
runs, `@hxmc/wasm` builds it (installed or downloaded as above; about a
minute). `npx hxmc-rebuild --reset` returns to the published compiler. (On
Windows the WebAssembly path runs on node's WASI, whose gaps the launcher
fills: `fd_readdir`, drive roots, Windows paths in arguments; checked in CI
on Windows too.)

Libraries from npm: `-lib <name>` (also `-L`, `--library`, and in hxml files)
finds Haxe libraries in node_modules. A package is one when its package.json
has a `"haxe"` field, `{"name": "hxmc.gfx", "classPath": "src", "hxml":
"extraParams.hxml"}` (`hxml` optional); `-lib` takes that name or the
package's own (`-lib @hxmc/gfx`), and `-lib <name>:<version>` only that
version. It expands as haxelib's libraries do: the hxml's lines, the class
path, `-D <name>=<version>`, then its dependencies (the packages of its
`dependencies` and `peerDependencies` that have a `"haxe"` field), each
library once. For each name, in this order: lix's `haxe_libraries/<name>.hxml`
in the working directory or a parent (left to haxelib, which is lix's shim
there), else the nearest `node_modules` holding it (from the working
directory up, as node looks), else haxelib, as before. The compiler does this
itself (`hxmc/src/hxmc/NodeLibs.hx`), so it works without node too
(`node_modules/.bin/haxe` as the native compiler); lix's own `haxe` shim
resolves every `-lib` itself before the compiler sees it (from
`haxe_libraries`, or through `haxelib path`), so through it a library from
npm needs a `haxe_libraries/<name>.hxml` of its own.

Editors and lix: vshaxe with `"haxe.executable": "auto"` (the default) runs
the workspace's `node_modules/.bin/haxe` when there is one (as for the lix
npm package; expected from vshaxe's documentation of `auto`, not verified in
an editor here); on Windows set it to `node_modules/@hxmc/cli/dist/haxe.exe`.
`dist/` (`packages/cli/dist` in this repository) is an installation lix
accepts as a path version (`dist/haxe`, `dist/std`, `dist/platform.txt`,
written on install or first use): `lix use haxe ./node_modules/@hxmc/cli/dist`, or `.haxerc` with
`{"version": "./node_modules/@hxmc/cli/dist", "resolveLibs": "scoped"}`; lix's
`haxe` shim then runs hxmc (checked with this repository's lix on Linux and
macOS in CI). With the lix npm package in the same project both packages
declare a `haxe` bin: npm reports nothing and `node_modules/.bin/haxe` is
whichever it linked last (both orders occur), so use lix's shim with the
`dist/` version there.

Fast rebuilds: executables keep a `<out>.hxmc/` directory of compiled modules
(only changed modules are compiled again), and the compilation server keeps
typed modules, lowered bodies and compiled objects in memory:
`haxe --wait 6000`, then `haxe --connect 6000 build.hxml` (a no-change rebuild
of a small program in about 0.4 s).

## Building

```sh
git submodule update --init
make hxmc           # bin/hxmc/hxmc, the tool: on first use node runs the stage0, then the tool rebuilds itself
make port           # bin/port/haxe: the port with every generator (seconds after an edit)
make release TARGET=macos-arm64   # bin/release/<target>/haxe[.exe], with mbedtls and libuv
make lix            # bin/lix/lix
make npm            # bin/npm/*.tgz: the npm packages of packages/ (packages/pack.mjs)
make site           # bin/site
make help           # everything else
```

The [Makefile](Makefile) needs GNU make, node 22 and git; zig only for the
runtime objects. Everything is cross-built from Linux (macOS works as a host
too).

Bootstrap, as Zig does: `hxmc/bootstrap/stage0.wasm.br` is the tool built for
wasm32-wasi (brotli, 1.4 MB), committed and replaced only when the sources need
a newer one (`make stage0`). node runs it to build the first native tool from
source (`bin/hxmc/boot/hxmc1`, about 25 s), which builds `bin/hxmc/hxmc`; that
one rebuilds itself byte-identically (`make fixpoint`). `make bootstrap` does
all three (about a minute). Scripts run on the tool's Eval (`bin/hxmc/hxmc
-cp ... --run X`: a first argument starting with `-` makes the tool the
compiler's command line), or on the stage0's before there is a tool.

Runtime objects: `rt.o`, `ssl.o` and `uv.o` for the six targets are built by
zig from `hxmc/deps` (the C library's members, mbedtls, libuv), which a source-only
bootstrap cannot do. They are keyed by a hash of `hxmc/deps` (scripts, pinned
versions, flags, the zig version) and published as the GitHub release
`rt-<hash>` (`node hxmc/bootstrap/rt.mjs hash|fetch|pack`); `make rt` downloads
them and falls back to `make rt-build` (zig) when the release is missing. CI
builds them only then (one job per target), publishes the release from
pushes to main and hxmc, and passes them to its other jobs as an artifact.

The reference compiler is the official nightly of the pinned upstream commit
(build.haxe.org), downloaded by lix: `make reference` (`bin/reference/haxe`,
cached by CI). Nothing builds OCaml.

## Developer loop

| | |
| --- | --- |
| `make hxmc` | the tool after an edit of hxmc or the port: about 11 s (8 s of it typing the port; unchanged modules come from `bin/hxmc/hxmc.hxmc/`) |
| `make port` | the port after an edit: about 13 s (an edit of a central module such as the typer recompiles every module: 26 s) |
| `make quick` | after every edit of hxmc: the x64 corpus, again with `RT_VERIFY=1`, the wasm corpus under node, the types cache (about 20 s; `CASES="Int64Gc Bench"` restricts it) |
| `make check` | before a commit: quick, arm64 (qemu), x64 Windows (wine), a 16 KB nursery, the wasm corpus with legacy exception handling, ThreadNatives x30, crosshost on three cases (`PORT=1`: the port's self-compile) |
| `make full` | before a push: every nursery and `RT_VERIFY`, wasmtime, the port's self-compile natively and as a module, crosshost on everything, the fixpoint |
| `make test` | HXB conformance of the port against the reference (seconds per 100 cases) |
| `make portcheck` | the port built by hxmc self-compiles to the reference's HXB |

## Testing

Every harness compares the port (`PORT_BIN`, default `bin/port/haxe`) with the
reference (`bin/reference/haxe`); outputs go to `bin/test/`. They are Haxe
scripts on the tool's Eval (`make test-<name>`, or `bin/hxmc/hxmc -cp
haxe/test --run <Name> --help`-style options at the top of each file):

| Script | Compares | Result |
| --- | --- | --- |
| `Conformance` | HXB archives (member names, uncompressed payloads) of `conformance-cases.txt` (286 configurations of the upstream suites), `conformance-macro-cases.txt` (66, run macros), `conformance-hxblib-cases.txt` (`--hxb-lib`); `--hxb-lib`, `--eval`, `--parallel N` modes | 279 + 7 expected failures, 66/66, 7/7 |
| `Display` | `--display` JSON-RPC requests from upstream's removed display suite | 679/679 |
| `Server` | the compilation server: cases twice, edits and invalidation (with the verbose logs), stdin, `--cmd`, errors, `--server-connect` | 595/595 |
| `ServerJsonRpc` | the `server/*` methods, both cache modes | 107/107 |
| `UpstreamTargets` | upstream's unit suite compiled for js, lua, python, php, neko, hl, hl/c, cpp, cppia, cppia host, jvm, flash by both, every output file (jars by member, hl/c after `HlcNames`) | 12/12 identical |
| `Interp` | `--interp` runs of the case lists | 275/276 (`eval-eventLoop-compile` depends on thread timing) |
| `Haxelib` | `-L` through lix's haxelib shim, batch and server | 14/14 |
| `EvalDebugger` | scripted Eval debugger sessions (`-D eval-debugger`): breakpoints, stepping, scopes, evaluation, assignment, exception and function breakpoints, a macro | 6/6 |
| `fuzz/` | random programs per target (`diff:<target>`) or by program output (`exec:<a>,<b>`), with reduction (`make test-fuzz LANE=diff:js`) | |
| `Targets` | the website's target table (`hxmc/web/data/targets.json`): haxe-formatter and the port itself compiled for every target by both, CPU, wall and peak RSS, outputs compared (hl/c after `HlcNames`); `-p self -t hlc --merge --json hxmc/web/data/targets.json` replaces those rows only | 18/18 identical (the rows the reference compiles) |
| `Measure` | peak RSS, wall and CPU time: the self-compile (ours and the reference), the native build, the WebAssembly builds | self-compile 879 MB vs the reference's 1414 MB |
| `unit.hxml` | unit tests of port modules, in-process | pass |

hl/c's digest names (`HlcNames.hx`): hl2c names function, virtual and context
types `t$fun_`/`t$vrt_`/`t$ctx_` after the MD5 of the type's description
marshalled with closures. When the description reaches an object or virtual
prototype, it holds a PMap's comparison closure, which the reference writes
as a code pointer into its own machine code (an offset and the MD5 of its
code area); the port writes a fixed placeholder there
(`haxe/src/generators/Hl2c.hx`, `OcamlExtern`), so those names differ by
design (two in the port's self-compile, none in upstream's unit suite).
Wherever hl/c output is compared (`UpstreamTargets`, the fuzzer's
`diff:hlc`, `Targets`), the digest names found on one side only are renamed
on both sides in order of first appearance, with the context headers named
after them; every other byte must match, so the outputs still have to use
their names in the same places.

Sequential runs pass `-D disable-parallelism`: the reference itself is not
deterministic in parallel mode. Upstream's compiler-side suite (RunCi `macro`:
the unit tests in the macro context with their HXB round trip, null safety,
misc, sys on Eval, threads, third-party projects) runs with the release
binaries as `haxe` (`.github/workflows/upstream-tests.yml`); no target runtime
is installed anywhere: target suites are compared, not run.

hxmc's corpus (`hxmc/test`, `Corpus`): the programs of `cases/` and the frozen
fuzzer programs, compiled by the tool, run with a 64 KB nursery (a missing
root shows) and compared with their golden files, which are frozen (the
outputs of hxc, the C target hxmc came from): a new case gets one with
`--bless` (checked by hand), a changed output is an edit of its golden file
with the reason in the commit. `Crosshost`: the tool as a WebAssembly module
writes the same bytes as the native tool, for every target, itself included.
`RT_VERIFY=1` fills the free nursery with a pattern, so uninitialized
allocations and missed roots show at once. `make gfx-check`: the triangle of
`packages/gfx` rendered headless and in a window, compared with
`packages/gfx/test/triangle.png`: on Linux by Mesa's llvmpipe (an EGL pbuffer,
an X11 window under Xvfb), on macOS by Metal (an offscreen texture, a Cocoa
window; skipped without a Metal device or outside a GUI session), on Windows
by D3D11's WARP (an offscreen texture, a Win32 window);
`GFX_TARGET=windows-x86_64` runs the Windows build under Wine (wined3d over
llvmpipe, under Xvfb) (CI: the `gfx` and `gfx-arm64` jobs on Linux,
`gfx-windows` on Windows x86-64 and arm64, `gfx-macos` from the npm
packages).

CI (`.github/workflows/build.yml`) runs as parallel jobs, each waiting only
for what it uses: `changes` (what the run needs, `.github/select.sh`, and
whether the runtime objects' release exists), `rt-build` and `rt` (only when
it is missing: one job per target, `make rt-target`, then `make rt-layouts`
and the release), `build` (the bootstrap from the stage0, the fixpoint, the
release binaries and lix for the six targets) and next to it, each with a tool
of its own from the stage0: `corpus` (`make corpus-stage`: the corpus for
every target in three jobs, the port as a WebAssembly module, the reference's
self-compile), `crosshost` (`make crosshost`, the targets in two jobs),
`memory and time` (`make measure`), `npm-pack` (the npm packages), `site` and
`gfx` (`make gfx-check` on Linux x86-64, and the programs cross-built for
`gfx-arm64` to check on ARM64; `gfx-macos`, after `npm-pack`: built from the
npm packages with `-lib hxmc.gfx`, on Metal and in a Cocoa window). Then
`conformance` (the harnesses above; the Eval debugger in three shards,
`EvalDebugger --shard i/n`, and the fuzzer's diff lanes in three jobs), `test`
(on each of the six machines: the release binary's smoke test with a TLS
handshake and libuv, lix, the corpus, the self-compile), `wasm` (the corpus
and the self-compile under node and wasmtime, both also with legacy exception
handling under node), `playground` (the playground in three browser engines
with both modules and its fallback to the legacy one in a Chromium without
exnref), `npm` (the nine packages in fresh projects on each of the six
machines: native at once through the platform package, `-lib` from
node_modules (`hxmc/test/NodeLibs.hx`), `--ignore-scripts`; and on linux-x64,
or on all six on main, tags and the nightly run, lix with `dist/`, the
WebAssembly fallback, downloaded (from the local tarball: `HXMC_WASM_TARBALL`,
a path or URL in place of the registry's) and installed (with `-lib` by the
WebAssembly compiler), and `hxmc-rebuild` with `--reset`), `upstream-tests`,
and `publish-npm` (after every check; all nine at one version, skipping those
published already: the six platform packages, `@hxmc/wasm`, `@hxmc/source`,
then `@hxmc/cli`, with provenance: on `v*` tags as `latest`, from main as a
nightly prerelease `<version>-nightly.<date>.<commit>` tagged `next`; then the
source-only packages of `packages/` at their own versions when those are not
on npm yet; never from other branches), the nightly release and the website.

Main, tags, the nightly schedule (02:41 UTC) and dispatches run everything. On
other branches a push runs only what its changes need, since the last commit
whose run succeeded (else since the merge base with main): only `*.md`,
nothing beyond `changes`; only `hxmc/web`, `site` and `playground`; only
source-only packages (`packages/os`, `packages/gfx`: a version of their own),
`build`, `npm-pack` and the `gfx` jobs; anything else (`haxe/`, `hxmc/src`,
`hxmc/std`, `hxmc/deps`, `hxmc/test`, the workflows, the Makefile, the
compiler's npm packages), everything. A newer push to a branch cancels its
run; runs on main, hxmc and tags always finish.

Benchmarks (`make bench`, `hxmc/test/Bench.hx`): the
[HaxeBenchmarks](https://github.com/HaxeBenchmarks/benchmark-runner) cases
built by hxmc (x86-64, and wasm under node) and by the port for C++ (hxcpp),
the JVM, JS on node, HL/C and the HashLink JIT (HashLink, hxcpp, hxnodejs and
hxjava pinned in the script; the runner, libraries and HashLink go to
`bin/bench`): the median wall time of N interleaved runs, CPU time, peak RSS,
sizes and compile times (`haxe_s`: the Haxe compiler, hxmc's whole build for
its targets; `cc_s`: the C++ or C compiler for C++ and HL/C; `build_s`: their
sum), with each case's check program compared across the
targets. `.github/workflows/bench.yml` runs it nightly on main (skipped when
the commit is measured already) and on demand, apart from `build.yml`; from
main it appends `results/<date>-<commit>.json` to the `bench-data` branch and
regenerates `history.json` (per run, case and target: median, min, max,
peak RSS and the compile times) and `latest.json` there (`Bench --history`),
which the website build copies (`make site BENCH_DATA=<checkout>`) for its
table and charts. The first points on `bench-data` are earlier measurements
imported from this repository's history (`"source": "imported"`: a
development VM, best of the runs).

## Porting rules

- `haxe/upstream` is the canonical reference: never edit its files or commit
  inside it (the harnesses leave it clean). Moving the pinned revision is a
  deliberate change: it ports every upstream commit in between, must land on
  a commit with a nightly build on build.haxe.org (the reference), and updates
  the revision in `Version.version_extra`'s counterpart
  (`haxe/src/compiler/server/ServerCompilationContext.hx`).
- Read the upstream OCaml module before adding or changing its Haxe
  counterpart, at the matching path (`typing/typer.ml` becomes
  `haxe/src/typing/Typer.hx`; `macro/eval/evalFoo.ml` becomes
  `haxe/src/macros/eval/EvalFoo.hx`, `macro` being a keyword). Names go
  `snake_case` to `camelCase`, records become classes, a name that is a Haxe
  keyword gets a suffix (`throw` becomes `throwValue`).
- Preserve function order, branch order, data layout, error messages and
  exception behavior. Prefer a direct translation over a redesign.
- Reproduce OCaml semantics that reach the output: `Hashtbl` iteration order
  (`core.ds.OcamlHashtbl`), `PMap` order (sorted keys), right-to-left
  evaluation of arguments with side effects, float printing (`core.Numeric`,
  `core.ds.OcamlPrintf`), 31/63-bit integers. Never derive output order from
  Haxe `Map` iteration.
- Output that depends on the reference binary itself is the one exception
  to byte identity: hl/c's digest names of the types whose description
  holds a closure (Marshal writes code pointers and the digest of the
  reference's machine code). The port writes a documented placeholder
  instead of constants of one reference build, and the harnesses normalize
  only those names (the digest names found on one side only: README.md,
  "Testing"; `haxe/test/HlcNames.hx`); a new case of the kind extends
  both, never a general tolerance.
- Never stub out behavior with a silent success: what the port cannot
  support fails explicitly with a `// port:` note.
- Comments from upstream stay at the matching place with upstream's wording
  (`(** *)` becomes `/** */`); a ported file starts with its upstream
  module's license header; every other comment in `haxe/src` starts with
  `// port:` (continuation lines `// ...`) and stays true.
- `haxe/upstream/libs` holds OCaml dependencies: reproduce what the compiler
  reaches (`haxe/src/libs`: the Neko compiler, swflib, zlib's deflate,
  extlib IO, ziplib) rather than porting them.
- Before calling a change done, run the lanes it can affect: HXB conformance
  and macro cases for typing or filters, the fuzzer's `diff:<target>` lanes
  and `UpstreamTargets` for generators, display and server for those
  services, `quick`/`check` for hxmc, everything for broad changes. Never
  commit `bin/`.

## hxmc

hxmc turns a typed Haxe program into a native executable with its own code
generator and linker: no C compiler, assembler or system linker at build time.

```
typed AST --(ir.Lower)--> hxmc IR --(Prep: ir.Facts)--> --(MirBuild)--> Mir (SSA) --(Opt)-->
    --(x64|a64 Isel)--> LIR --(Regalloc, Emit)--> Obj (per module, cached) | --(wasm/WasmGen)--> wasm
    --(DataGen: tables, strings)--> Obj --(Link: ELF | LinkPE | LinkMachO | LinkWasm)--> executable
```

| File (`hxmc/src/hxmc/`) | |
| --- | --- |
| `Main.hx`, `Options.hx`, `Driver.hx` | the tool: runs the port's compiler with a generate hook, compiles every module (in parallel, cached) and links; `--server` keeps the compilation server resident |
| `HaxeMain.hx` | `haxe` with hxmc built in (the npm package): `--custom-target hxmc=<out>` |
| `ir/Ir.hx`, `Lower.hx`, `FnLower.hx` | the IR (structured statements in A-normal form, explicit GC points) and the lowering of the filtered typed AST |
| `ir/Facts.hx`, `Prep.hx` | the program-wide facts: names, layouts, type indices, field ids, no-GC functions, cold sites, GC points, as symbols |
| `UpToDate.hx`, `Fingerprint.hx`, `LowerCache.hx` | rebuilds: the whole build skipped when nothing changed, each module's object reused when its fingerprint is unchanged, lowered bodies reused by the server |
| `Mir.hx`, `MirBuild.hx`, `Opt.hx`, `Inline.hx` | the SSA IR, its construction, inlining, value numbering, store forwarding, LICM, dead code |
| `Lir.hx`, `Regalloc.hx`, `x64/`, `a64/` | instruction selection, linear-scan allocation, encoders (checked against llvm-mc: `EncCheck`), emission |
| `Obj.hx`, `ElfWriter.hx`, `*Reader.hx`, `Link*.hx`, `MkRt.hx`, `DataGen.hx` | objects, the linkers (static ELF, `LinkDyn.hx` dynamic ELF against glibc; PE with imports written directly; Mach-O with an ad-hoc signature), the runtime-object builder, the program's data |
| `wasm/` | wasm32-wasi: structured code from Mir, the linker, exception handling with `exnref` (or the legacy instructions) |
| `Target.hx`, `Abi.hx` | per-target facts |
| `MkStd.hx` | hxmc's std merged with the Eval originals (the macro context shares the program's class paths) |

Conventions: references live across a GC point are shadow-stack slots
(cold sites spill only on the slow path); `try` is `rt_handler` with the C
library's `_setjmp`; calls follow the target's C ABI; thread-locals use
local-exec TLS on Linux, `_tls_index` on Windows, the TLV template on macOS;
program-wide numbers (type indices, field ids, offsets) are absolute symbols
resolved by the linker, so a module's code does not change when the numbering
does.

Runtime in Haxe: most of the runtime is Haxe compiled with the program
(`hxmc/std/hxmc/rt`: strings, Dynamic access, reflection, arrays, bytes,
dates, inflate, the POSIX and Windows system layers, and Math: musl's libm
ported, `LibM.hx`, with the same results on every target), written with a
small internal API (`hxmc.unsafe`: `Ptr`, `Mem` loads, stores, allocation
and symbols, `Atomic`; `@:hxmc.c` and `@:hxmc.rt` externs of C functions,
`@:hxmc.noGc` functions, `@:hxmc.export`/`@:hxmc.host` implementations of
runtime functions, `@:hxmc.callback` functions C calls,
`@:hxmc.threadLocal` statics). The collector, threads and the stop-the-world
handshake, startup and `rt_throw` are Haxe too (`Gc.hx`, `Threads.hx`,
`Start.hx`; the heap census with `-D hxmc.census`): no C of hxmc's own is
linked, only the C library, mbedtls and libuv ([hxmc/LOWLEVEL.md](hxmc/LOWLEVEL.md),
"The runtime without C of our own"). The modules of hxmc's own package
of the std (the runtime, `hxmc.unsafe`, the natives) are typed once per
tool and configuration and cached as an HXB archive (`hxmc/src/hxmc/TypesCache.hx`;
`HXMC_TYPES_CACHE=0` turns it off): a build loads them instead of typing
them, and its executable is the same (`make fixpoint` checks it). The cache
is the user's (`$XDG_CACHE_HOME/hxmc` or `~/.cache/hxmc`, macOS
`~/Library/Caches/hxmc`, Windows `%LOCALAPPDATA%\hxmc\cache`; `HXMC_CACHE`
overrides; one that cannot be written is not used), shared by every build
of the tool, each in its own `types/<tool>/`; once a day a build removes
those unused for 14 days, and the least recently used beyond 1 GB
(`hxmc/test/CacheCheck.hx` checks it). A change of the runtime's
interface or of the IR's conventions needs a tool that knows it: build once
against the previous runtime first, or bootstrap again.

Targets: Linux (static ELF with musl's members; with `-D hxmc.libc=glibc`, an
executable dynamically linked against the system's glibc: PT_INTERP, DT_NEEDED,
imports with the symbol versions of glibc 2.17 bound at load time, a
generated `_start` calling `__libc_start_main`; runtime objects of their own,
`<target>-glibc`, the runtime's Haxe code the same), Windows (PE over the UCRT,
imports written from the import libraries), macOS (Mach-O against
libSystem, ad-hoc signed), each on x86-64 and ARM64, and wasm32-wasi (the
whole runtime in Haxe; exception handling with `exnref`, or with
`-D hxmc.wasm-eh=legacy` the legacy `try`/`catch_all`/`rethrow`, which node 22
runs without flags and wasmtime not at all; run with
`node hxmc/bootstrap/wasi.mjs m.wasm` or `wasmtime run -W exceptions=y --dir . m.wasm`;
no threads, sockets or processes). mbedtls 2.28 and libuv 1.48
(`hxmc/deps/deps.sh`) become `ssl.o` and `uv.o`, linked only into programs that
use `sys.ssl` or `eval.luv`. Environment for development: `HXMC_OPT=0`,
`HXMC_INLINE=<flat>,<loop>,<runtime>`, `HXMC_SYMBOLS=1`, `HXMC_SIZE_STATS=1`,
`HXMC_DUMP=<function>`, `HXMC_MAP=<file>` (Windows), `RT_MINOR_KB`,
`RT_OLD_MB`, `RT_STATS`, `RT_VERIFY`.

hxmc began as the second back end of hxc, the C target this repository had
until 2026-10-14; its IR, runtime and std came from there, and its corpus's
golden files are hxc's outputs. Plans: [hxmc/PLANS.md](hxmc/PLANS.md); the low-level
API and C interop design: [hxmc/LOWLEVEL.md](hxmc/LOWLEVEL.md).

## License

GPL-2.0-or-later, like the Haxe compiler it is ported from; hxmc's runtime and
std, which end up in compiled programs, are MIT. Details: [LICENSE](LICENSE).
