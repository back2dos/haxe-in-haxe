# Haxe in Haxe

A close-to-line-by-line port of the Haxe compiler from OCaml (`haxe/src`) to
Haxe (`src/`), an experimental C backend that compiles it to a native binary
(`hxc/`, the "hxc" target), and a website with an in-browser playground
(`site/`).

The port is held to the reference compiler built from the pinned upstream
submodule (`haxe/`, commit `995a7d1fe`): for the same invocation it must write
the same output, byte for byte.

## Current state

- **HXB output.** The port parses, types, finalizes and filters Haxe programs
  and writes HXB archives whose `.hxb` members are byte-identical to the
  reference's: 279/279 accepted conformance cases plus 7 the reference also
  rejects, 66/66 macro cases, and 195 cases from the other upstream suites
  (135 identical, 60 rejected by both).
- **Target generators.** JS, Lua, Python, PHP, Neko, HashLink (bytecode and
  HL/C), JVM, C++ (and cppia) and SWF, plus `--xml`/`--json` output: output
  byte-identical to the reference's on a differential fuzzer (random
  well-typed programs, one lane per target), the upstream unit suite where it
  was compiled, and two real projects ([compile times](site/index.html#targets)).
- **Services.** The Eval macro interpreter and Macro API (with `sys.ssl`/mbedtls,
  `eval.luv`/libuv, Eval threads and the Eval debugger), `--interp`/`--run`,
  HXB library input (`--hxb-lib`), display services (`--display` JSON-RPC),
  the compilation server (`--wait`, `--connect`, `--server-connect`, the
  `server/*` methods), haxelib (`-L`), SWF and Java library input
  (`--swf-lib`, `--java-lib`) and the HashLink bytecode interpreter.
- **Upstream test suite.** Every target-independent step of upstream CI
  (`tests/runci/targets/Macro.hx`) passes with the hxc build of the port,
  including the tink_core and hxcoro projects (unit 11372/11372, misc
  684/684, threads 144/144).
- **hxc.** The port compiled to C by its own backend compiles itself faster
  than the OCaml compiler with less memory (clang -O2: 5.20 s vs 6.11 s, peak
  RSS 469 MB vs 531 MB), and with 4 threads in 4.18 s (OCaml with 4 domains:
  4.03 s). The runtime has a precise generational GC, 1:1 OS threads (green
  threads with tcc), TLS and libuv. The same backend builds other programs:
  haxe-formatter built with hxc formats `haxe/std` 1.6× faster than its C++
  and Node builds, with byte-identical output.

Test results: [`test/TESTING.md`](test/TESTING.md). Benchmarks and how to
reproduce them: [`site/bench/README.md`](site/bench/README.md). The C backend:
[`hxc/README.md`](hxc/README.md).

## Repository layout

| Path | |
| --- | --- |
| `haxe/` | The pinned `haxefoundation/haxe` submodule: the source being ported and the reference compiler. Never edited here. |
| `src/` | The port, module by module after `haxe/src/` (`src/libs/` reproduces the OCaml libraries the generators need). Comments that are not from upstream start with `// port:`. |
| `hxc/` | The hxc C backend: lowering and emitter (`src/`), C runtime (`rt/`), the target's std (`std/`), the std overrides for its JS-built tool (`js/`), tools, test programs, the haxelib package. |
| `test/` | Conformance, fuzzer, upstream-suite, display, server, debugger and haxelib harnesses, and the unit tests. |
| `site/` | The website and playground; `site/bench/` the benchmark harnesses and their results. |

## Setup

```sh
git submodule update --init --recursive
make -C haxe haxe                     # the reference compiler (OCaml 5 + opam, see haxe/README.md; needs the pcre2 package)
export HAXE_REFERENCE=$PWD/haxe/haxe
```

The reference is always the compiler built from `haxe/`, not a system Haxe.

## Build the port

```sh
sh hxc/build.sh port                                                      # native, tcc: bin/hxc/hih/hih
CC="clang -O2" BIN=hih_clang RT_NO= RT_LIBS="-lmbedtls -lmbedx509 -lmbedcrypto -luv" \
  sh hxc/build.sh port                                                    # native, optimized, with TLS and libuv
sh hxc/tools/dev-tool.sh && sh hxc/tools/port-dev.sh                      # fast rebuild loop: bin/port/hih
haxe/haxe -cp test/hl -cp src -main haxe.Main -hl bin/haxe-in-haxe.hl     # HashLink build
haxe/haxe haxe-in-haxe.hxml                                               # type-check only (writes HXB)
```

Run it like `haxe`:

```sh
export HAXE_STD_PATH=$PWD/haxe/std
bin/hxc/hih/hih_clang -cp app --main Main --interp
bin/hxc/hih/hih_clang -cp app --main Main --js out.js
```

Without `-D disable-parallelism`, a gcc/clang/cosmocc build runs upstream's
parallel passes (filters, analyzer, DCE marking, HXB writing) on OS threads.

## Tests

The harnesses take the reference from `HAXE_REFERENCE` and run the HashLink
build of the port by default; `HAXE_IN_HAXE_PORT=<command>` runs another build
(for example `bin/hxc/hih/hih_clang`).

```sh
python3 test/conformance.py -j 8                                          # HXB conformance (286 cases)
python3 test/conformance.py -j 8 --cases test/conformance-macro-cases.txt # also -hxblib, -party, -upstream
python3 test/conformance.py -j 8 --hxb-lib                                # plus the --hxb-lib round trip
python3 test/conformance.py -j 3 --parallel 3                             # parallel mode (threaded builds)
sh test/fuzz/build.sh && bin/fuzz/fuzz -j 4 --lane diff:js                # differential fuzzer, any target
python3 test/interp.py -j 4                                               # --interp program output
python3 test/upstream.py [--reference] [step ...]                         # upstream CI's target-independent job
python3 test/display.py -j 2                                              # display requests
python3 test/server.py -j 2                                               # compilation server scenarios
python3 test/server-jsonrpc.py                                            # server/* JSON-RPC methods
python3 test/eval-debugger.py                                             # the Eval debugger protocol
python3 test/haxelib.py [--server]                                        # -L/--library
haxe/haxe test/unit.hxml                                                  # unit tests of port modules
```

Conformance compares normalized ZIP member names and the uncompressed `.hxb`
payloads, never the container bytes; cases the reference rejects must be
rejected by the port. The fuzzer ([`test/fuzz/README.md`](test/fuzz/README.md))
compares diagnostics and every output file per target, and reduces failures.
Excluded upstream cases and the reasons: [`test/upstream-hxb-exclusions.md`](test/upstream-hxb-exclusions.md).

## hxc for your own programs

The haxelib package lets your Haxe type a program and hxc turn it into C
([`hxc/haxelib/README.md`](hxc/haxelib/README.md)):

```sh
sh hxc/haxelib/build.sh                       # bin/haxelib/hxc.zip (cosmocc on PATH)
haxelib install bin/haxelib/hxc.zip
haxe -lib hxc -cp src -main Main --custom-target hxc=bin/main
```

HXB is tied to the compiler that writes it, so your Haxe must be the build
`hxc.com` was made from (the pinned `haxe/`).

## Website

```sh
sh site/build.sh                   # bin/site: the playground (Emscripten), the download (cosmocc), the pages
cd bin/site && python3 -m http.server
```

## Formatting

`src/` is formatted with [haxe-formatter](https://github.com/HaxeCheckstyle/haxe-formatter),
built with hxc, using `hxformat.json`: `sh site/bench/formatter.sh` (in place)
or `--check`.

## Porting approach

Each module stays mechanically close to its counterpart in `haxe/src/`:
control flow, branch order, data layout, error behavior and module boundaries,
unless a language difference requires a deviation, which is then marked with a
`// port:` comment ([`AGENTS.md`](AGENTS.md)).
