# Haxe in Haxe

A port of the Haxe compiler from OCaml to Haxe, and hxmc, a Haxe target that
compiles it (and other programs) to machine code and WebAssembly.

- `src/`: the port, module by module after upstream's `haxe/src/`.
- `hxmc/`: the machine-code target: its code generators, linkers, runtime and
  std ([hxmc/README.md](hxmc/README.md)). It builds the port for six
  targets (Linux, macOS and Windows on x86-64 and ARM64) and as a
  WebAssembly module, and it builds itself.
- `haxe/`: upstream Haxe (submodule, commit `995a7d1fe`), the reference
  compiler the port is tested against.
- `test/`: test harnesses. `site/`: the website and its playground,
  `site/bench/` the benchmarks.
- `tools/lix/`: [lix](tools/lix/README.md) (the lix client and haxeshim) ported to
  build with hxmc, a program of its own that uses the target (`make lix`).

The port should produce the same output as the reference compiler for the
same arguments. This is tested for HXB output, all targets (JS, Lua, Python,
PHP, Neko, HashLink, JVM, C++, SWF), `--interp`, macros, display requests and
the compilation server. Results: [test/TESTING.md](test/TESTING.md).

## Build

```sh
git submodule update --init --recursive
make reference                     # haxe/haxe, the reference compiler (OCaml 5, opam; needs pcre2)
make bootstrap                     # bin/hxmc/hxmc, the hxmc tool (from the reference compiler and node)
make port                          # bin/port/haxe: the port built by hxmc (seconds after an edit)
make release TARGET=macos-arm64    # bin/release/<target>/haxe-in-haxe[.exe], with mbedtls and libuv
make wasm                          # bin/wasm/hih.wasm: the port as WebAssembly (the playground's)
make site                          # bin/site, the website
make lix                           # bin/lix/lix
```

The [Makefile](Makefile) is the entry point for every build: `make help`
lists the targets and variables. It needs node with the hxnodejs haxelib (for
the bootstrap only), zig and ld.lld (the runtime objects, mbedtls and
libuv). The targets are linux-x86_64, linux-arm64, windows-x86_64,
windows-arm64, macos-x86_64 and macos-arm64, all cross-built from Linux.

Use it like `haxe`, with `HAXE_STD_PATH` pointing to `haxe/std`:

```sh
HAXE_STD_PATH=haxe/std bin/port/haxe -cp src --main Main --interp
```

## Test

```sh
make test                          # HXB conformance of bin/port/haxe
make test-fuzz LANE=diff:js        # the fuzzer (bin/fuzz/fuzz) on one lane
make quick                         # hxmc's checks after an edit (check, full: more)
```

See [test/README.md](test/README.md) for the other harnesses. CI also runs
upstream's own test suite (`RunCi` for every target) with the release
binaries as `haxe` on Linux, macOS and Windows:
`.github/workflows/upstream-tests.yml`.

## License

GPL-2.0-or-later, like the Haxe compiler it is ported from; hxmc's runtime
and standard library, which end up in compiled programs, are MIT. Details:
[LICENSE](LICENSE).
