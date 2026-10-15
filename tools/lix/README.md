# lix for hxmc

A port of [lix](https://github.com/lix-pm/lix.client) (the lix client, 17.0.3,
commit `c866a77`) and [haxeshim](https://github.com/lix-pm/haxeshim) (commit
`6ffddf8`) from Haxe on Node.js to Haxe without dependencies besides hxcoro,
compiled by hxmc to one native binary per platform. The binary is `lix`, `haxe`, `haxelib`
and `neko` at once: it acts as the command it is invoked as (links named so),
like the four scripts of the lix npm package.

```sh
make lix                        # bin/lix/lix, and bin/lix/{haxe,haxelib,neko} links to it
export PATH=$PWD/bin/lix:$PATH
lix scope create && lix install haxe 4.3.6 && lix +lib tink_core
haxe -lib tink_core --run Main
```

The Makefile's lix targets (`make help`): `lix` builds `bin/lix/lix` for the
host with hxmc (with mbedtls and libuv, which hxmc links into programs that
use them), fetching hxcoro at a pinned commit into `bin/hxcoro` unless
`HXCORO` names a checkout; `lix-release TARGET=<target>` cross-builds
`bin/release/<target>/lix[.exe]` for one of the six targets (Linux, macOS and
Windows on x86-64 and ARM64). The binary is about 2 MB. CI builds all six,
tests each on its system (`lix shims`, `scope create`, `download`, installs,
compiles with the `haxe` shim) and publishes them on the website, under Tools,
as `lix-<target>[.exe]`.

The `haxe` shim adds about 2 ms to a compiler call; the npm package's adds
about 60 ms (measured with `haxe -version` and `haxe --run resolve-args`).

## Layout

| Path | |
| --- | --- |
| `src/haxeshim/` | haxeshim: scopes (`.haxerc`), argument and `-lib` resolution, the `haxe`/`haxelib`/`neko` shims, the compiler server proxy (`CompilerServer.hx`). |
| `src/lix/` | the lix client: `lix.cli` (commands; `Main.hx` picks the command by the program's name), `lix.client` (downloads, archives, Haxe versions, the haxelib/GitHub/GitLab/git/web sources). |
| `src/shim/` | what the npm package got from other libraries, as small classes: `Error`/`Outcome` (tink_core), `Url` (tink_url), `SemVer` (tink_semver), `Ansi` (ansi), `Http` (node's http/https), `Archive` (tar, yauzl). |
| `src/uv/` | libuv for single-threaded programs over `hxmc.NativeUv`: loops, timers, signals, file watchers, TCP, pipes, processes (`Uv.hx`); hxcoro on a libuv loop (`Coro.hx`); a buffered stream reader for coroutines (`Reader.hx`). |
| `test/parity.sh` | runs `parity-cases.sh` with the npm package and with the port and compares them. |

## How it differs from the npm package

The port follows the upstream modules file by file; `// port:` comments mark
where it deviates. In general:

- **No Promises.** tink's Promises and Futures become blocking calls that throw
  `shim.Error` (an HTTP-like code, which is also the exit code, as upstream).
  The command line tools did everything in sequence anyway.
- **Processes on libuv.** `spawnSync`/`execSync` become `uv_spawn` on a loop of
  their own (`haxeshim.sys.Exec`): std's `sys.io.Process` cannot set the working
  directory or environment or let the child inherit the terminal.
- **The compiler server proxy on hxcoro.** `haxe --wait <port>`,
  `--server-listen stdio|<port>` and `--server-connect <host:port>` run as
  coroutines on the libuv loop (`uv.Coro.run`): connections, compiler processes,
  frames read with `uv.Reader`, the `.haxerc` watcher and signals. The rest is
  synchronous, where coroutines would add nothing.
- **HTTP without node.** `shim.Http` speaks HTTP/1.1 over `sys.net.Socket` and
  `sys.ssl.Socket` (mbedtls): redirects, chunked bodies, progress, and proxies
  (`HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY`, which node's `https.get` ignored).
  Trusted CA certificates: the system's, Mozilla's (as node bundles them; curl's
  extract, pinned and generated into `shim.CaBundle` by the Makefile, since
  Windows' preinstalled roots lack common ones) and `SSL_CERT_FILE`.
- **Archives in memory.** Downloads are buffered and extracted with
  `shim.Archive` (gzip, tar with GNU/pax long names and symlinks, zip from its
  central directory) using std's pure Haxe inflate. File modes from tar archives
  are applied (the haxe and neko binaries).
- **haxelib's API** (`haxe.remoting`, not in std since Haxe 4) is a POST of the
  serialized call (`lix.client.sources.Haxelib.getInfos`).
- Not ported: `haxeshim.exify` (the `.exe` stubs and `CHANGES.txt` the npm
  package installs next to its Windows `.cmd` files), and `lix.api`,
  `lix.server`, `lix.client.sources.npm`, which the client does not use.
  Windows: the code keeps upstream's Windows branches (hooks through cmd.exe,
  the root in `%APPDATA%\haxe`, as with the npm package), and the Windows
  builds are native executables.
- `lix shims [<dir>]` (not in the npm package, where npm installs the four
  commands) creates `haxe`, `haxelib` and `neko` next to the binary (or in
  `<dir>`), and `lix` when the binary has another name (as downloaded,
  `lix-linux-x86_64`): symbolic links, or on Windows hard links (copies when
  that fails), as `.exe`. Existing files are replaced only with `--force`,
  directories never. For a binary downloaded from the website, that is the
  whole installation.
- `haxe --run install-libs` (and so `lix download`) names each command that
  failed and why, where upstream reports only how many failed.

## Gaps in the Haxe standard library

What std lacked, and what the port does instead:

| Missing | Used instead |
| --- | --- |
| argv[0] (`Sys.args()` leaves it out), needed for one multi-command binary | `hxmc.NativeSys.argv0` |
| starting processes with a working directory, an environment, an inherited terminal | libuv's `uv_spawn` |
| `isatty`, `chmod`, symbolic links | libuv (`uv_guess_handle`, `hxmc.NativeUv.guessHandle`; `uv_fs_chmod`, `uv_fs_symlink`) |
| reading from a non-blocking stdin, sockets and child pipes concurrently | libuv streams (`uv_pipe_open`, `hxmc.NativeUv.pipeOpen`) |
| TLS on an established connection (an HTTPS proxy tunnel) | hxmc's `sys.ssl.Socket` internals (`shim.Http.startTls`) |
| an HTTP client with proxies, progress, streaming | `shim.Http` (std's `sys.Http` has none of these) |
| inflate (`haxe.zip.Uncompress` and with it `haxe.zip.Reader.unzip`, on targets without it) | `haxe.zip.InflateImpl`, pure Haxe |
| tar | `shim.Archive.untar` (about 100 lines; the `format` haxelib has one) |
| URL, semver parsing | `shim.Url`, `shim.SemVer` |

Better in the std: a way to **start TLS on a connected socket** in
`sys.ssl.Socket`. That is target work rather than lix work.

## hxcoro

hxcoro (Haxe Foundation, the coroutine library of Haxe 5) is fetched at commit
`4b1a4d4`. Its `haxelib.json` gives its license as "GPL" and it ships no license
file; lix and haxeshim are public domain (`LICENSE`). A binary that includes
hxcoro is therefore subject to hxcoro's license. Only `CompilerServer` uses it;
replacing it with plain libuv callbacks would make the binary public domain
again.

## Testing

`sh tools/lix/test/parity.sh` runs 26 cases (help, scopes, installs from haxelib, git
and URLs with dependencies, aliases, `--flat`, `--force`, errors, `download`,
`dev`, `use`, `run`, `haxe-versions`, `-lib` resolution and interpolation,
`haxelib path`/`libpath`, compiling and running with Haxe 4.3.6, scripts,
`install-libs`) with the npm package and the port and compares their output,
exit codes, `.haxerc`, `haxe_libraries/` and library cache: all 26 match
(`PORT_BIN=<directory>` tests another build). The
compiler server modes (`--wait` with `--connect`, `--server-listen stdio`,
`--server-connect`, switching Haxe versions per request and on `.haxerc`
changes) give byte-identical responses to the npm package's with a test client.

Not covered by the parity test: GitHub and GitLab archive downloads (blocked
by the test environment's network policy; their URLs and hxml lines are built
as upstream), Windows and macOS (CI's lix step covers installs and compiles
there).
