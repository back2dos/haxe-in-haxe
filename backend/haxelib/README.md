# hxc (EXPERIMENTAL)

A C target for Haxe: your Haxe types the program, the
[haxe-in-haxe](https://github.com/benmerckx/haxe-in-haxe) C backend turns it
into C, and a C compiler builds a native binary. One `haxe` call:

```sh
haxelib install hxc.zip
haxe -lib hxc -cp src -main Main --custom-target hxc=bin/main
./bin/main
```

or in an `.hxml`:

```hxml
-lib hxc
-cp src
-main Main
--custom-target hxc=bin/main
```

`haxelib run hxc <args>` is the same as `haxe -lib hxc <args>`, adding
`--custom-target hxc=bin/main` when no output is given.

## How it works

`-lib hxc` adds an init macro (`extraParams.hxml`, `hxc.Boot`). With
`--custom-target hxc=<out>`, it asks your Haxe to write the typed, filtered
program as HXB (`<out>.hxb.zip`, removed afterwards). After generation, the
bundled `bin/hxc.com` reads that archive and writes `<out>.c`, and the C
compiler builds `<out>`. So typing, macros, `-lib` and the display/completion
services all come from your own Haxe.

`bin/hxc.com` is the haxe-in-haxe compiler with the C backend, compiled by
itself to C and with [Cosmopolitan](https://github.com/jart/cosmopolitan) to
one binary for Linux, macOS, Windows and the BSDs (x86-64 and arm64).

**Haxe version.** HXB is tied to the compiler that writes it, so your Haxe
must be the build `hxc.com` was made from: `hxc.json` names it (Haxe
5.0.0-preview.1, a specific commit). Another build can fail to type the hxc
std overrides or write an archive `hxc.com` cannot read; the error then names
the expected build.

## Options

| Define | |
| --- | --- |
| `-D hxc.cc=<command>` | C compiler. Default `$HXC_CC`, else the first of `cc`, `gcc`, `clang`, `tcc` (tcc compiles fastest, gcc/clang `-O2` run fastest). |
| `-D hxc.static` | Fully static, portable binary built with cosmocc (downloaded once into `~/.hxc/cosmocc`, about 420 MB unpacked; `HXC_COSMOCC_URL` overrides the source; `haxelib run hxc setup-cosmocc` downloads it now). The result runs on Linux, macOS, Windows and the BSDs. |
| `-D hxc.debug` | `-O0 -g` instead of `-O2`. |
| `-D hxc.c-only` | Stop after writing `<out>.c`. |
| `-D hxc.ssl`, `-D hxc.uv` | Link the system's mbedtls / libuv. Without them, `sys.ssl` and the libuv natives throw when called. |
| `-D hxc.keep-hxb` | Keep `<out>.hxb.zip`. With your own `--hxb <path>`, that archive is used and kept. |

Without any C compiler on `PATH`, cosmocc is used.

## Limits

- The target is experimental: the language and std coverage are what the
  haxe-in-haxe compiler needs to compile itself.
- A main class is required (`-main`).
- Windows: `hxc.com` runs, but the generated C needs a POSIX toolchain; use
  `-D hxc.static` from a POSIX shell, or WSL.

The compiler is a port of the Haxe compiler (GPL-2.0-or-later); the Haxe
standard library is MIT. See `LICENSE.txt`.
