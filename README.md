# Haxe in Haxe

A close-to-line-by-line port of the Haxe compiler from OCaml (`haxe/src`) to
Haxe (`src/`), plus an experimental C backend for it (`hxc/`, the "hxc"
target) and a website with an in-browser playground (`site/`).

## Current state

- **HXB output.** The port (`haxe.Main`) parses, types, finalizes and filters
  Haxe programs and writes HXB archives whose `.hxb` members are
  byte-identical to the pinned reference compiler's: 279/279 accepted
  conformance cases plus 7 the reference also rejects, 66/66 macro cases, and
  195 cases from the other upstream suites (135 identical, 60 rejected by
  both).
- **Ported services.** The Eval macro interpreter and Macro API (including
  `sys.ssl`/mbedtls, `eval.luv`/libuv and Eval threads), `--interp`/`--run`,
  HXB library input (`--hxb-lib`), display services (`--display` JSON-RPC),
  the compilation server (`--wait`, `--connect`, `--server-connect`) and
  haxelib (`-L`/`--library`). The Eval debugger and object-size memory
  statistics are not ported.
- **Target generators.** JS, Lua, Python, PHP, Neko, HashLink (bytecode and
  HL/C), JVM, C++ (and cppia) and SWF are translated from
  `haxe/src/generators/`; their output is byte-identical to the reference
  compiler's on the differential fuzzer (`diff:<target>` lanes) and the
  upstream cases tried (see `TRANSLATION.md` and `test/TESTING.md`).
  `--swf-lib` input and the HL bytecode interpreter are not ported.
- **Upstream test suite.** Every target-independent step of upstream CI
  (`tests/runci/targets/Macro.hx`) passes with the hxc build of the port,
  including the tink_core and hxcoro projects (unit 11372/11372, misc
  684/684, threads 144/144). The HashLink build misses 5 tests that need
  finalisers or a libuv loop.
- **hxc.** The port compiled to C by its own backend compiles itself faster
  than the OCaml compiler with less memory (clang -O2: 5.20 s vs 6.11 s, peak
  RSS 469 MB vs 531 MB), and in parallel mode with 4 threads in 4.18 s (OCaml
  with 4 domains: 4.03 s). The runtime has a precise generational GC, 1:1 OS
  threads (green threads with tcc), TLS and libuv. The same backend builds
  other programs: haxe-formatter built with hxc formats `haxe/std` 1.6× faster
  than its C++ and Node builds, with byte-identical output.

Results and dates: [`test/TESTING.md`](test/TESTING.md) (tests),
[`bench/README.md`](bench/README.md) (performance and memory),
[`TRANSLATION.md`](TRANSLATION.md) (module mapping),
[`hxc/README.md`](hxc/README.md) (hxc).

## Repository layout

| Path | |
| --- | --- |
| `haxe/` | The pinned `haxefoundation/haxe` submodule: the source being ported and the behavioral reference. Never edited here. |
| `src/` | The port, traceable to `haxe/src/` module by module. Comments that are not from upstream start with `// port:`. |
| `runtime/` | Host-specific std overrides for building the port with other targets: `hl/` (HashLink), `js/` (Node, for the JS build of the hxc tool). |
| `hxc/` | The hxc C target: the lowering and emitter (`src/`), the C runtime (`rt/`), the target's std (`std/`), tools (`tools/`), test programs (`test/`), the haxelib package (`haxelib/`). |
| `test/` | Conformance, upstream-suite, display, server and haxelib harnesses; `TESTING.md` records the results. |
| `bench/` | Benchmark harnesses (`run.py`, `haxebench.py`, `interp.py`), workloads, target patches, results. |
| `docs/` | Design notes: the HXB → native/wasm backend decision (`WASM-BACKEND.md`), Cosmopolitan builds (`COSMO.md`). |
| `site/` | The website and playground. |
| `tools/` | `format-src.sh` (with `hxformat.json`), `comment-only-diff.py`. |
| `archive/` | Code kept for reference, outside every build: earlier drafts, experiments and prototypes (see `archive/README.md`). |

## Setup

```sh
git submodule update --init --recursive
make -C haxe haxe                     # the pinned reference compiler (OCaml/Dune setup: haxe/README.md)
export HAXE_REFERENCE=$PWD/haxe/haxe
```

The reference compiler is always the one built from `haxe/`, not a system Haxe.

## Build the port

```sh
haxe/haxe haxe-in-haxe.hxml           # bootstrap build: bin/haxe-in-haxe.hxb
haxe/haxe test/compile-all.hxml       # every port module: bin/haxe-in-haxe.all.eval.hxb
haxe/haxe -cp runtime/hl -cp src -main haxe.Main -hl bin/haxe-in-haxe.hl   # HashLink build (HashLink master)
HAXE_STD_PATH=$PWD/haxe/std hl bin/haxe-in-haxe.hl -cp app --main Main --interp
```

The first two only check that the port compiles. `sh test/eval-hxb-execution.sh`
runs the port from an Eval HXB archive through the reference's `--hxb-lib`.
`sh archive/examples/run.sh hello` compiles and runs a small example
([`archive/examples/README.md`](archive/examples/README.md)).

## Tests

All harnesses take the reference from `HAXE_REFERENCE` and run the port's
HashLink build by default; `HAXE_IN_HAXE_PORT=<command>` runs another build
(for example the hxc binary `bin/hxc/hih/hih_clang`).

```sh
python3 test/conformance.py -j 8                                          # HXB conformance (286 cases)
python3 test/conformance.py -j 8 --hxb-lib                                # plus the --hxb-lib round trip
python3 test/conformance.py -j 8 --cases test/conformance-macro-cases.txt # also -hxblib, -party, -upstream
python3 test/conformance.py -j 3 --parallel 3                             # parallel mode, threaded builds
python3 test/interp.py -j 4                                               # --interp output vs the reference
python3 test/upstream.py [--reference] [step ...]                         # upstream CI's target-independent job
python3 test/display.py -j 2 [--extended]                                 # display requests vs the reference
python3 test/server.py -j 2 [--hxb-cache]                                 # compilation server scenarios
python3 test/haxelib.py [--server]                                        # -L/--library with a local repository
sh test/fuzz/build.sh && bin/fuzz/fuzz -j 4 --lane diff:hxb --lane diff:interp  # differential fuzzer (hxc build)
```

`test/fuzz/` ([README](test/fuzz/README.md)) generates random, well-typed
Haxe programs and compares the port with the reference on each: `diff:<target>`
lanes require identical diagnostics and output files for any target (`hxb`,
`interp`, `js`, `lua`, `php`, ...: the conformance check for the target
generators), `exec:<a>,<b>` lanes identical program output across targets (e.g.
`exec:interp,hxc`). Failures are saved with a repro script and reduced.

Conformance compares normalized ZIP member names and the uncompressed `.hxb`
payloads, never the container bytes; cases the reference rejects must be
rejected by the port. Sequential runs use `-D disable-parallelism` (the
reference itself is not deterministic with parallel filters); `--parallel`
compares after normalizing variable IDs. Exclusions and their reasons are in
[`test/upstream-hxb-exclusions.md`](test/upstream-hxb-exclusions.md) and in
`test/upstream.py`.

Other lanes: `haxe test/unit.hxml`, `haxe test/upstream-parser-corpus.hxml`
(1,355/1,366 upstream sources parse), `HAXEDEBUG=1 haxe
test/translated-pipeline.hxml`.

## hxc: the port as a native binary

`hxc/build.sh port` compiles the port to C with the backend and then with
`CC` (default tcc). clang -O2 is the fastest build (4–10% ahead of gcc -O2);
tcc builds in about a second; cosmocc makes one portable binary for Linux,
macOS, Windows and the BSDs.

```sh
sh hxc/build.sh port                                                      # tcc: bin/hxc/hih/hih
CC="clang -O2" BIN=hih_clang RT_NO= RT_LIBS="-lmbedtls -lmbedx509 -lmbedcrypto -luv" \
  sh hxc/build.sh port                                                    # with system mbedtls/libuv
sh hxc/tools/cosmo-deps.sh && CC="cosmocc -O2" RT_DEPS=bin/cosmo-deps BIN=hih.com sh hxc/build.sh port
bin/hxc/hih/hih_clang -cp app --main Main --interp
bin/hxc/hih/hih_clang -cp app --main Main --hxb out.zip --no-output -D disable-parallelism
```

Without `-D disable-parallelism`, a gcc/clang/cosmocc build runs the parallel
compiler passes (filters, analyzer, DCE marking, HXB writing) on OS threads.
`RT_STATS=1` prints GC and thread statistics, `RT_CENSUS=1` a heap census.

## hxc for your own programs

The haxelib package lets your own Haxe type the program and hxc turn it into
C ([`hxc/haxelib/README.md`](hxc/haxelib/README.md)):

```sh
sh hxc/haxelib/build.sh                       # bin/haxelib/hxc.zip (cosmocc on PATH)
haxelib install bin/haxelib/hxc.zip
haxe -lib hxc -cp src -main Main --custom-target hxc=bin/main
```

HXB is tied to the compiler that writes it, so the user's Haxe must be the
build `hxc.com` was made from (the pinned `haxe/`).

## Formatting

`src/` is formatted with [haxe-formatter](https://github.com/HaxeCheckstyle/haxe-formatter),
built with hxc, using `hxformat.json`:

```sh
sh tools/format-src.sh             # format src/ in place (builds the formatter once)
sh tools/format-src.sh --check     # list files that would change
```

## Website

```sh
sh site/build.sh                   # bin/site: the playground (Emscripten), the APE download, the pages
cd bin/site && python3 -m http.server
```

`site/index.html` is the front page (playground, download, status,
benchmarks from `bench/results.json`); `site/story.html` is the long account
of how the port was made.

## Porting approach

Keep each module mechanically close to its counterpart in `haxe/src/`:
control flow, branch order, data layout, error behavior and module
boundaries, unless a documented language difference requires a deviation
(see [`AGENTS.md`](AGENTS.md)). An older exploratory implementation,
[`elnabo/haxe_in_haxe`](https://github.com/elnabo/haxe_in_haxe), is reference
material only.
