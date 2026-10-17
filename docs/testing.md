# Testing and CI

## Harnesses

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
| `fuzz/` | random programs per target (`diff:<target>`) or by program output (`exec:<a>,<b>`), with reduction (`make test-fuzz LANE=diff:js`); `--cases haxe/test/fuzz/cases` checks the kept programs (failures fixed since, reduced, one directory each) on the lanes | |
| `Targets` | the website's target table (`hxmc/web/data/targets.json`): haxe-formatter and the port itself compiled for every target by both, CPU, wall and peak RSS, outputs compared (hl/c after `HlcNames`); `-p self -t hlc --merge --json hxmc/web/data/targets.json` replaces those rows only | 18/18 identical (the rows the reference compiles) |
| `Measure` | peak RSS, wall and CPU time: the self-compile (ours and the reference), the native build, the WebAssembly builds | self-compile 879 MB vs the reference's 1414 MB |
| `unit.hxml` | unit tests of port modules, in-process | pass |

Sequential runs pass `-D disable-parallelism`: the reference itself is not
deterministic in parallel mode. Upstream's compiler-side suite (RunCi `macro`:
the unit tests in the macro context with their HXB round trip, null safety,
misc, sys on Eval, threads, third-party projects) runs with the release
binaries as `haxe` (`.github/workflows/upstream-tests.yml`); no target runtime
is installed anywhere: target suites are compared, not run.

## hl/c digest names

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

## Printed floats

The port's Math is hxmc's port of musl's libm (`hxmc/std/hxmc/rt/LibM.hx`,
bit-identical to musl) wherever it runs, Eval included; the reference's is
glibc's. The two round some results an ulp apart (`Math.sin(-2.5)`), and the
arithmetic after them can widen that (`100 * Math.sin(-2.5)`: 2 ulps), so the
fuzzer's output comparison (`Runner.sameOutput`) accepts two printed floats at
the same place of a line when they are at most `Runner.MAX_ULPS` (4) apart,
both finite and of the same sign; every other character must match. The kept
case `interp-108625377` is that example.

## hxmc's corpus

hxmc's corpus (`hxmc/test`, `Corpus`): the programs of `cases/` and the frozen
fuzzer programs, compiled by the tool, run with a 64 KB nursery (a missing
root shows) and compared with their golden files, which are frozen (the
outputs of hxc, the C target hxmc came from): a new case gets one with
`--bless` (checked by hand), a changed output is an edit of its golden file
with the reason in the commit. `Crosshost`: the tool as a WebAssembly module
writes the same bytes as the native tool, for every target, itself included.
`RT_VERIFY=1` fills the free nursery with a pattern, so uninitialized
allocations and missed roots show at once. `ModuleCacheCheck` (`make
test-module-cache`; `PORT=1` adds the port): the persistent module cache
gives the same outputs, byte for byte, as a build without it, cold, warm,
after a new date, after an edit of a module and of a std override, after a
new file shadows a module, for hxmc (the tool and `haxe`) and JS.

## Graphics

`make gfx-check`: the examples of `packages/gfx`, the triangle and the cube
(textured, lit, depth-tested, with a uniform block and a blended panel,
turned by a fixed angle), rendered headless and in a window, compared with
`packages/gfx/test/triangle.png` and `cube.png` (a pixel matches when no
channel differs by more than 2, and at most 0.5% may differ by more), and
in the window the input sent to it (a key's character, the wheel) checked
as events: on Linux by Mesa's llvmpipe (an EGL pbuffer, an X11 window under
Xvfb), on macOS by Metal (an offscreen texture, a Cocoa window; skipped
without a Metal device or outside a GUI session), on Windows by D3D11's
WARP (an offscreen texture, a Win32 window); `GFX_TARGET=windows-x86_64`
runs the Windows build under Wine (wined3d over llvmpipe, under Xvfb) (CI:
the `gfx` and `gfx-arm64` jobs on Linux, `gfx-windows` on Windows x86-64
and arm64, `gfx-macos` from the npm packages).
`make gfx-web-check`: the same on WebGPU and on WebGL2 (forced), built for
wasm32-wasi, headless and in a canvas, in headless Chromium (SwiftShader;
`packages/gfx/test/web.mjs`; CI's `gfx` job); CI checks the site's cube the
same way (`hxmc/web/tools/browser-test.mjs`, the `playground` job: WebGPU
and WebGL2 in Chromium, WebGL2 in Firefox, under Xvfb, and in WebKit).
`make gfx-shader-check`: the shader macro on Eval (shaders run on the CPU, the
emitted sources, the programs it rejects: `packages/gfx/test/ShaderTest.hx`).
`gfx-check` and `gfx-web-check` also draw `FeatureScene` (buffer and texture
writes, R8 and RGBA8 textures, blending, scissor) against
`packages/gfx/test/features.png`.

## UI

On Eval: `make esx-check` (markup literals: templates, values, components,
HTML, the programs the macro rejects), `make text-check` (the rasterizer,
DejaVu Sans' tables and outlines, line layout, a text sample through the
atlas against `packages/text/test/sample.png`: the same pixels on every
machine with that font; Inter's CFF outlines and GPOS kerning against
`sample-cff.png`, when fonts-inter is installed, as in CI; Arabic, Hebrew and marks against Chromium's widths and ink, grapheme clusters against `Intl.Segmenter`), `make ui-check` (the flexbox layout against
Chromium's on 89 cases (29 of them CSS grids), `packages/ui/test/layout-expected.json`, which
`layout-ref.mjs` writes from `layout-cases.mjs`; text wrapping, events and
focus; PNG files of every colour type, depth, filter and interlacing,
`packages/ui/test/png/`, which `png-cases.mjs` writes with the pixels
expected, checked against Chromium's decoder when written; JPEG files of
every kind the decoder reads, `packages/ui/test/jpeg/`, which
`jpeg-cases.mjs` writes with the pixels Chromium decodes, matched exactly,
and GIF files the same way (`gif/`, `gif-cases.mjs`); SVG documents drawn
by `Svg` against Chromium's pixels (`svg/`, `svg-cases.mjs`; the shapes
must agree, edge anti-aliasing may differ); CSS colours and gradients
against Chromium's (`css/`, `css-cases.mjs`);
popups placed, hit and dismissed; then signals and markup rendered into
nodes, the popup widgets driven by pointer and keys, a VirtualList of
100000 rows scrolled; the examples of `packages/ui/GUIDE.md`, run by
`GuideTest.hx`). Natively: `make
ui-draw-check` (the sample UI, the todo example and the widget gallery,
the last two driven through their Ui, drawn headless against `draw.png`,
`todo.png` and `gallery.png`; Linux: llvmpipe, DejaVu
Sans; the sample in a window under Xvfb, whose loop must sleep once it has
nothing to draw; `StressTest`, a list of 1000 rows: the time of each step,
mounting, layout, frames, a change to one row, a scroll; `ClipboardTest`,
the clipboard between two windows under Xvfb, through X11's selection
protocol; also on Windows and macOS in CI; `TextInputTest`, key presses
typed through X11's input method under Xvfb, keys given other symbols: a
Cyrillic letter, a dead key composed with the next; `LinuxAccessTest`
and `AtspiProbe`, a window's accessibility tree read and pressed by
another process through libatspi, in a D-Bus session with AT-SPI's bus
(at-spi2-core); on macOS in CI
`TextInputTest` types through the window's text view and composes in it,
`MacAccessTest` reads the accessibility tree through NSAccessibility and
performs its actions; on Windows `WinAccessTest` calls the UI Automation
providers through their COM interfaces and asks UI Automation for the
window's element). In the browser: `make ui-web-check` (the native form on the DOM's own
controls, `native-web.mjs`; the todo example for
wasm32-wasi in headless Chromium on WebGPU and WebGL2, driven by real pointer
and keyboard events, an input method's composition through the DevTools
protocol, against `todo.png`). CI runs all five in the `gfx` job.

## CI

CI (`.github/workflows/build.yml`) runs as parallel jobs, each waiting only
for what it uses: `changes` (what the run needs, `.github/select.sh`, and
whether the runtime objects' release exists), `rt-build` and `rt` (only when
it is missing: one job per target, `make rt-target`, then `make rt-layouts`
and the release), `build` (the bootstrap from the stage0, the fixpoint, the types and module
cache checks, the
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

## Benchmarks

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
