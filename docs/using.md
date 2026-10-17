# Using hxmc in depth

The short version is in the [README](../README.md). This covers the npm packages, how `haxe` picks a compiler, editors and lix, libraries from npm, and fast rebuilds.

## All options

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
| `HXMC_MODULE_CACHE=0`, `-D hxmc.no-module-cache` | no module cache: every build types its modules from source (the cache keeps typed modules between builds; macros are trusted as the compilation server trusts them) |

## The npm packages

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

## Without node

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

## Changing the compiler

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

## Libraries from npm

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

## Editors and lix

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

## Fast rebuilds

Fast rebuilds: executables keep a `<out>.hxmc/` directory of compiled modules
(only changed modules are compiled again), and the compilation server keeps
typed modules, lowered bodies and compiled objects in memory:
`haxe --wait 6000`, then `haxe --connect 6000 build.hxml` (a no-change rebuild
of a small program in about 0.4 s).
