# lix for hxc

A port of [lix](https://github.com/lix-pm/lix.client) (the lix client, 17.0.3,
commit `c866a77`) and [haxeshim](https://github.com/lix-pm/haxeshim) (commit
`6ffddf8`) from Haxe on Node.js to Haxe without dependencies besides hxcoro,
compiled by hxc to one native binary. The binary is `lix`, `haxe`, `haxelib`
and `neko` at once: it acts as the command it is invoked as (links named so),
like the four scripts of the lix npm package.

```sh
make lix                        # bin/lix/lix, and bin/lix/{haxe,haxelib,neko} links to it
export PATH=$PWD/bin/lix:$PATH
lix scope create && lix install haxe 4.3.6 && lix +lib tink_core
haxe -lib tink_core --run Main
```

The Makefile's lix targets (`make help`): `lix-c` writes the C with the JS
backend tool (as `make port-c` does for the port), fetching hxcoro at a pinned
commit into `bin/hxcoro` unless `HXCORO` names a checkout; `lix` compiles it with
`LIX_CC` (default `clang -O2`) against the system's libuv and mbedtls
(Debian/Ubuntu: `libuv1-dev libmbedtls-dev`) or a `make deps` directory
(`LIX_TLS_UV`); `lix-cosmo` makes `bin/release/cosmo/lix.com`, one Cosmopolitan
binary for Linux, macOS, Windows and the BSDs (with `make deps TARGET=cosmo`).
The native binary is about 1.6 MB, `lix.com` about 6 MB. CI builds `lix.com`
and publishes it on the website, under Tools.

The `haxe` shim adds about 2 ms to a compiler call; the npm package's adds
about 60 ms (measured with `haxe -version` and `haxe --run resolve-args`).

## Layout

| Path | |
| --- | --- |
| `src/haxeshim/` | haxeshim: scopes (`.haxerc`), argument and `-lib` resolution, the `haxe`/`haxelib`/`neko` shims, the compiler server proxy (`CompilerServer.hx`). |
| `src/lix/` | the lix client: `lix.cli` (commands; `Main.hx` picks the command by the program's name), `lix.client` (downloads, archives, Haxe versions, the haxelib/GitHub/GitLab/git/web sources). |
| `src/shim/` | what the npm package got from other libraries, as small classes: `Error`/`Outcome` (tink_core), `Url` (tink_url), `SemVer` (tink_semver), `Ansi` (ansi), `Http` (node's http/https), `Archive` (tar, yauzl). |
| `src/uv/` | libuv for single-threaded programs over `hxc.NativeUv`: loops, timers, signals, file watchers, TCP, pipes, processes (`Uv.hx`); hxcoro on a libuv loop (`Coro.hx`); a buffered stream reader for coroutines (`Reader.hx`). |
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
  Windows: `lix.com` (Cosmopolitan) sees POSIX paths (`/C/dir`) where Windows
  programs need Windows' (`C:/dir`), finds no `.exe` by itself and has no
  `/bin/sh`. So lix asks the runtime for the real system (`hxc.NativeSys.hostSystem`;
  `Sys.systemName()` is "Linux" there, which would also pick Linux builds of
  Haxe and neko on macOS), converts paths in the arguments and environment of the
  programs it runs (`Os.hostPath`, `Exec.spawn`), looks them up in PATH as Windows
  does, runs `lix`/`haxe`/`haxelib`/`neko` as itself, and runs plain hook commands
  directly (others through cmd.exe). The root is `%APPDATA%\haxe`, as with the
  npm package. CI runs `scope create`, `download`, an install and a compile on
  Windows and macOS.
- `lix shims [<dir>]` (not in the npm package, where npm installs the four
  commands) creates `haxe`, `haxelib` and `neko` next to the binary (or in
  `<dir>`): symbolic links, or on Windows hard links (copies when that fails),
  as `.exe`. Existing files are replaced only with `--force`, directories never.
  For `lix.com` downloaded from the website, that is the whole installation.
- `lix download` (`haxe --run install-libs`) runs the libraries' install
  commands in parallel, 8 at a time (`LIX_JOBS`; 1 runs them one by one as
  upstream does), each distinct command once; post-install hooks still run one
  by one afterwards. For tink_web's 14 libraries: 3.6 s instead of 19.2 s.
  The limit is a fixed count, as in other package managers' network
  concurrency (yarn 8, pnpm 16), rather than the number of cores.
- `haxe --run install-libs` (and so `lix download`) names each command that
  failed and why, where upstream reports only how many failed.

## Gaps in the Haxe standard library

What std (or hxc's std) lacked, and what the port does instead:

| Missing | Used instead |
| --- | --- |
| argv[0] (`Sys.args()` leaves it out), needed for one multi-command binary | `hxc.NativeSys.argv0` (added) |
| starting processes with a working directory, an environment, an inherited terminal | libuv's `uv_spawn` |
| `isatty`, `chmod`, symbolic links | libuv (`uv_guess_handle`, added as `hxc.NativeUv.guessHandle`; `uv_fs_chmod`, `uv_fs_symlink`) |
| reading from a non-blocking stdin, sockets and child pipes concurrently | libuv streams (`uv_pipe_open` added as `hxc.NativeUv.pipeOpen`) |
| TLS on an established connection (an HTTPS proxy tunnel) | hxc's `sys.ssl.Socket` internals (`shim.Http.startTls`) |
| an HTTP client with proxies, progress, streaming | `shim.Http` (std's `sys.Http` has none of these) |
| inflate on hxc (`haxe.zip.Uncompress` and with it `haxe.zip.Reader.unzip`) | `haxe.zip.InflateImpl`, pure Haxe: Haxe 4.3.6's archive (10 MB, 39 MB unpacked) inflates in 0.44 s (clang -O2), gzip takes 0.19 s |
| tar | `shim.Archive.untar` (about 100 lines; the `format` haxelib has one) |
| URL, semver parsing | `shim.Url`, `shim.SemVer` |

Better vendored: **zlib's inflate** in the hxc runtime (behind
`haxe.zip.Uncompress`, as the port already has deflate in `src/libs/extc`),
and a way to **start TLS on a connected socket** in `sys.ssl.Socket`. Both are
target work rather than lix work.

hxc's std itself had gaps that this port ran into and that are fixed in hxc/:
`StringTools.urlEncode`/`urlDecode` returned null, `StringBuf.clear` and
`Date.fromString` were missing, `haxe.Exception.stack` was read-only, and the
backend did not lower coroutine types (hxcoro did not compile).

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
exit codes, `.haxerc`, `haxe_libraries/` and library cache: all 26 match, for
the native build and for `lix.com` (`PORT_BIN=<directory with lix linking to lix.com>`). The
compiler server modes (`--wait` with `--connect`, `--server-listen stdio`,
`--server-connect`, switching Haxe versions per request and on `.haxerc`
changes) give byte-identical responses to the npm package's with a test client.

Not covered: GitHub and GitLab archive downloads (blocked by the test
environment's network policy; their URLs and hxml lines are built as upstream),
Windows and macOS.
