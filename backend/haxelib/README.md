# hxc (EXPERIMENTAL)

Compiles Haxe to C, then to a native binary. The compiler is
[haxe-in-haxe](https://github.com/benmerckx/haxe-in-haxe), the Haxe compiler
ported to Haxe with a C backend, shipped here as one portable
[Cosmopolitan](https://github.com/jart/cosmopolitan) binary (`bin/hxc.com`,
Linux/macOS/BSD on x86-64 and arm64, with the Haxe standard library inside).
Your installed Haxe only runs this library's `Run.hx`; it does not compile
your program.

```sh
haxelib install hxc.zip          # or: haxelib dev hxc <unpacked dir>
haxelib run hxc build.hxml
haxelib run hxc -cp src -main Main --custom-target hxc=bin/main
./bin/main
```

The output is the path given with `--custom-target hxc=<path>` (default
`bin/main`): `<path>.c` and the binary `<path>`. Everything else in the
arguments or the `.hxml` is passed to the compiler as usual (`-D`, `-cp`;
`-lib` is not supported yet, haxelib integration is still being ported).

## Options

| Option | |
| --- | --- |
| `--hxc-cc <command>` | C compiler. Default `$HXC_CC`, else the first of `cc`, `gcc`, `clang`, `tcc` (tcc compiles fastest, gcc/clang `-O2` run fastest). |
| `--hxc-static` | Fully static, portable binary built with cosmocc (downloaded once into `~/.hxc/cosmocc`, about 420 MB unpacked; `HXC_COSMOCC_URL` overrides the source). The result runs on Linux, macOS, Windows and the BSDs. |
| `--hxc-debug` | `-O0 -g` instead of `-O2`. |
| `--hxc-c-only` | Stop after writing the C file. |
| `--hxc-ssl`, `--hxc-uv` | Link the system's mbedtls / libuv. Without them, `sys.ssl` and the libuv natives throw when called. |
| `setup-cosmocc` | Download cosmocc now. |

Without any C compiler on `PATH`, `--hxc-static` is used.

## Limits

- The target is experimental: the language and std coverage are what the
  haxe-in-haxe port needs to compile itself (see `backend/README.md` and
  `bench/README.md` in the repository).
- Macros run in the bundled Eval interpreter, without mbedtls and libuv.
- Windows: the bundled compiler runs, but the generated C needs a POSIX
  toolchain; use `--hxc-static` from a POSIX shell, or WSL.

The compiler is a port of the Haxe compiler (GPL-2.0-or-later); the Haxe
standard library is MIT. See `LICENSE.txt`.
