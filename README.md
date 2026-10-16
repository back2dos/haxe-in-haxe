# hxmc

The Haxe compiler ported from OCaml to Haxe, and **hxmc**, a Haxe target that
compiles programs (the compiler included) straight to machine code and
WebAssembly, with its own code generator and linkers: no C compiler, assembler
or system linker.

- **Targets:** Linux, macOS and Windows on x86-64 and ARM64, and wasm32-wasi.
- **Faithful port:** it behaves exactly like the reference compiler of its
  pinned upstream commit: byte-identical HXB and target output, the same
  `--interp` runs, display and server answers.
- **Self-hosting:** hxmc builds itself; a clean checkout builds with only node.
- **No C of our own:** the runtime, collector and threads are Haxe.
- **Graphics in pure Haxe:** `@hxmc/os` and `@hxmc/gfx` draw with GL, Metal,
  D3D11, WebGPU or WebGL2 through the system's own APIs.

Website and playground: <https://haxe-in-haxe.ben.mk>

## Install

```sh
npm i -D @hxmc/cli      # node 22+; then `npx haxe`
```

`haxe` is the full Haxe command line with hxmc built in: every target works as
usual (`--js`, `--interp`, ...), and `--custom-target hxmc=<out>` writes an
executable.

```hxml
-cp src
-main Main
--custom-target hxmc=bin/app
# -D hxmc.target=windows-x86_64   # cross-compile to another target
```

npm installs a native compiler for your platform. Where none can run, `haxe`
falls back to a WebAssembly build under node. Details on the packages,
editors, lix and rebuilding the compiler from source:
[docs/using.md](docs/using.md).

### Options

| Option | |
| --- | --- |
| `-D hxmc.target=<target>` | `linux-x86_64`, `linux-arm64`, `windows-x86_64`, `windows-arm64`, `macos-x86_64`, `macos-arm64`, `wasm32-wasi` (default: this machine) |
| `-D hxmc.libc=glibc` | Linux: link dynamically against the system's glibc (2.17+) instead of static musl, so shared libraries can be imported (`@:hxmc.lib("libGL.so.1")`) or loaded at run time |
| `-debug`, `-D hxmc.symbols` | a symbol table for profilers (wasm: a name section) |
| `-D hxmc.jobs=<n>` | parallel module compilations (default: the cores) |
| `-D hxmc.wasm-eh=legacy` | wasm: legacy exception handling, for older browsers and runtimes |
| `HXMC_STATS=1` | what the build did and how long it took |
| `HXMC_CACHE=<dir>` | the cache directory (default: the user's cache folder) |
| `HXMC_MODULE_CACHE=1`, `-D hxmc.module-cache` | keep typed modules between builds (experimental): a rebuild types only what changed |

Rebuilds only recompile changed modules; `haxe --wait 6000` plus
`haxe --connect 6000 build.hxml` keeps everything in memory.

## Libraries

Haxe libraries install from npm and are found by `-lib`, through a `"haxe"`
field in their `package.json` (lix and haxelib still work):

```sh
npm i -D @hxmc/gfx
```

```hxml
-lib hxmc.gfx
```

| Package | |
| --- | --- |
| `@hxmc/os` | windows, input and the app loop: X11, Cocoa, Win32 and the browser canvas |
| `@hxmc/gfx` | a portable GPU API with back ends for GL/GLES (Linux), Metal (macOS), D3D11 (Windows), WebGPU and WebGL2 (browser), and shaders written in Haxe (compiled to GLSL, WGSL, MSL, HLSL); see `packages/gfx/examples/Triangle.hx` |

## Building from source

```sh
git submodule update --init
make hxmc        # the tool (node runs the committed stage0 on first use)
make port        # bin/port/haxe: the port with every generator
make release TARGET=macos-arm64
make help        # everything else
```

Needs GNU make, node 22 and git; zig only to rebuild the runtime objects
(normally downloaded). Everything cross-builds from Linux or macOS.

## Testing

```sh
make quick       # after every hxmc edit (~20 s)
make check       # before a commit
make test        # the port's HXB conformance against the reference compiler
```

Every harness compares against the official nightly of the pinned upstream
commit (`make reference`).

## Documentation

| | |
| --- | --- |
| [docs/using.md](docs/using.md) | npm packages, the launcher, editors and lix, libraries, fast rebuilds |
| [docs/development.md](docs/development.md) | repository layout, building, bootstrap, the developer loop |
| [docs/testing.md](docs/testing.md) | the harnesses, hxmc's corpus, graphics tests, CI, benchmarks |
| [docs/porting.md](docs/porting.md) | the rules for every change of the port |
| [docs/hxmc.md](docs/hxmc.md) | hxmc's pipeline, runtime, targets |
| [hxmc/LOWLEVEL.md](hxmc/LOWLEVEL.md) | C interop and low-level Haxe |
| [hxmc/PLANS.md](hxmc/PLANS.md) | what comes next |

## License

GPL-2.0-or-later, like the Haxe compiler it is ported from. hxmc's runtime and
std, which end up in compiled programs, and the packages in `packages/` are
MIT. Details: [LICENSE](LICENSE).
