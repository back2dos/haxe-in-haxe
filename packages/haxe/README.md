# haxe-in-haxe (npm)

The Haxe compiler ported to Haxe, with hxmc built in: native executables for
Linux, macOS and Windows (x86-64, arm64) and wasm32-wasi modules, cross-built
from any of them.

    npm i haxe-in-haxe
    npx haxe -main Main --custom-target hxmc=hello      # an executable for this machine
    npx haxe -main Main --custom-target hxmc=hello -D hxmc.target=windows-x86_64
    npx haxe -main Main --js main.js                    # the other targets as usual

The package is the same on every platform. It holds the compiler as a
WebAssembly module, the compiler's sources, the std and hxmc's runtime objects
for the six targets.

## First use

There is no install script. The first `haxe` call runs the WebAssembly
compiler under node's WASI and starts the native build for this machine in the
background: the WebAssembly compiler compiles its own sources with hxmc (about
a minute). The build goes to a cache shared by every project:
`~/.cache/haxe-in-haxe/<version>/<target>/` (macOS: `~/Library/Caches`,
Windows: `%LOCALAPPDATA%`; `HAXE_IN_HAXE_CACHE` overrides). Its log is
`build.log` there.

After that, `haxe` runs the native compiler. On Linux and macOS, when the
package directory is writable, the native compiler replaces `bin/haxe`
itself (an atomic rename), so npm's `node_modules/.bin/haxe` link starts it
without node. On Windows npm's `haxe.cmd` always starts node, and the
launcher runs the native compiler.

Variables:
- `HAXE_IN_HAXE_NATIVE=0`: the WebAssembly compiler only; `=wait`: build the
  native compiler first, in the foreground.
- `HAXE_IN_HAXE_INSTALL=0`: keep the launcher as `bin/haxe`.
- `HAXE_IN_HAXE_QUIET=1`: no notice when the build starts.

Requires node 22 or later.

## Building the package

From the repository root, after `make hxmc rt std`:

    packages/haxe/build.sh
    cd packages/haxe && npm pack

## Status

A prototype (hxmc/PLANS.md, "npm package"):
- the native build is not verified against a published hash yet;
- the WebAssembly compiler can run out of wasm32's 4 GB while compiling
  itself; the build then resumes from the modules it compiled (a second run);
- executables hxmc writes keep a `<output>.hxmc/` directory of compiled
  modules next to them (incremental builds).
