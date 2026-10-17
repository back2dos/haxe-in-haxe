# Packaging and npm

Built: the npm packages (`@hxmc/cli`, the six platform packages,
`@hxmc/wasm`, `@hxmc/source`, and the source-only libraries in
`packages/`), `-lib` from node_modules, lix, release binaries for the six
desktop targets: [docs/using.md](../using.md) and
[docs/development.md](../development.md). npm first, haxelib later.

## Open

- **Verifying the native build**: builds are deterministic (the port
  self-compiles to identical HXB, the tool rebuilds itself identically),
  so a compiler built on the user's machine (`hxmc-rebuild`, or the
  WebAssembly fallback building a native one) can be checked against a
  hash published with the package: stronger than trusting a downloaded
  binary.
- **First run**: the std's modules from the module cache, warmed at
  install ([compiler.md](compiler.md), "Cached modules").
- **The `hxmc` haxelib** (`-lib hxmc`, `--custom-target hxmc=out`,
  `-D hxmc.target=<os>-<arch>`), as hxc had one, and the source-only
  packages on haxelib too.
- **New packages**: `@hxmc/ui`, `@hxmc/text`, `@hxmc/esx` (the UI branch),
  then `@hxmc/view` and `@hxmc/web` ([web.md](web.md)): sources only, a
  peer dependency on a range of `@hxmc/cli`, an `imports.mjs` each where
  they import from JavaScript.
- **Using hxmc's built-in compiler**: HXB ties the user's Haxe version to
  hxmc's. hxmc contains the whole compiler port, so it (or the haxelib)
  can compile the user's sources itself; the "HXB from your own Haxe"
  path stays for display/IDE use.
- **User C libraries** would ship as per-target prebuilt objects linked by
  hxmc, as mbedtls and libuv do ([lowlevel.md](lowlevel.md), "Calls and
  linking").
