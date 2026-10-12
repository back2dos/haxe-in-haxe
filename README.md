# Haxe in Haxe

A port of the Haxe compiler from OCaml to Haxe, and a C backend (hxc) that
compiles it to a native binary.

- `src/`: the port, module by module after upstream's `haxe/src/`.
- `hxc/`: the C backend and its runtime.
- `haxe/`: upstream Haxe (submodule, commit `995a7d1fe`), the reference
  compiler the port is tested against.
- `test/`: test harnesses. `site/`: the website, `site/bench/` the benchmarks.

The port should produce the same output as the reference compiler for the
same arguments. This is tested for HXB output, all targets (JS, Lua, Python,
PHP, Neko, HashLink, JVM, C++, SWF), `--interp`, macros, display requests and
the compilation server. Results: [test/TESTING.md](test/TESTING.md).

## Build

```sh
git submodule update --init --recursive
make reference                     # haxe/haxe, the reference compiler (OCaml 5, opam; needs pcre2)
make port                          # bin/hxc/hih/hih_clang (clang -O2)
make dev                           # bin/port/hih: rebuilt in seconds after an edit (tcc)
make release TARGET=aarch64-macos  # bin/release/<target>/haxe-in-haxe (zig cc, with mbedtls and libuv)
make cosmo                         # bin/release/cosmo/haxe-in-haxe.com (Cosmopolitan)
make site                          # bin/site, the website (Emscripten)
```

The [Makefile](Makefile) is the entry point for every build: `make help`
lists the targets and variables. It needs node with the hxnodejs haxelib,
tcc and clang; zig, cosmocc or Emscripten for the release and site builds.

Use it like `haxe`, with `HAXE_STD_PATH` pointing to `haxe/std`:

```sh
HAXE_STD_PATH=haxe/std bin/hxc/hih/hih_clang -cp src --main Main --interp
```

## Test

```sh
make test                          # HXB conformance of bin/hxc/hih/hih_clang
make test-fuzz LANE=diff:js        # the fuzzer (bin/fuzz/fuzz) on one lane
```

See [test/README.md](test/README.md) for the other harnesses.

## hxc for other programs

[hxc/haxelib/README.md](hxc/haxelib/README.md)

## License

GPL-2.0-or-later, like the Haxe compiler it is ported from; the hxc runtime
and standard library, which end up in compiled programs, are MIT. Details:
[LICENSE](LICENSE).
