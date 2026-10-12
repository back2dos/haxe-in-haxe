# Haxe in Haxe

A port of the Haxe compiler from OCaml to Haxe, and a C backend (hxc) that
compiles it to a native binary.

- `src/`: the port, module by module after upstream's `haxe/src/`.
- `hxc/`: the C backend and its runtime.
- `haxe/`: upstream Haxe (submodule, commit `995a7d1fe`), the reference
  compiler the port is tested against.
- `test/`: test harnesses. `site/`: the website, `site/bench/` the benchmarks.
- `lix/`: [lix](lix/README.md) (the lix client and haxeshim) ported to build with
  hxc, a program of its own that uses the target.

The port should produce the same output as the reference compiler for the
same arguments. This is tested for HXB output, all targets (JS, Lua, Python,
PHP, Neko, HashLink, JVM, C++, SWF), `--interp`, macros, display requests and
the compilation server. Results: [test/TESTING.md](test/TESTING.md).

## Build

```sh
git submodule update --init --recursive
make -C haxe haxe                  # reference compiler (OCaml 5, opam; needs pcre2)

sh hxc/build.sh port               # bin/hxc/hih/hih (tcc)
CC="clang -O2" BIN=hih_clang sh hxc/build.sh port
```

Use it like `haxe`, with `HAXE_STD_PATH` pointing to `haxe/std`:

```sh
HAXE_STD_PATH=haxe/std bin/hxc/hih/hih -cp src --main Main --interp
```

## Test

```sh
export HAXE_REFERENCE=$PWD/haxe/haxe HAXE_IN_HAXE_PORT=$PWD/bin/hxc/hih/hih_clang
python3 test/conformance.py -j 8
sh test/fuzz/build.sh && bin/fuzz/fuzz -j 4 --lane diff:js
```

See [test/README.md](test/README.md) for the other harnesses.

## hxc for other programs

[hxc/haxelib/README.md](hxc/haxelib/README.md)

## License

GPL-2.0-or-later, like the Haxe compiler it is ported from; the hxc runtime
and standard library, which end up in compiled programs, are MIT. Details:
[LICENSE](LICENSE).
