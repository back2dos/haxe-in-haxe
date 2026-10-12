# Test results

Against the reference compiler built from `haxe/` at `995a7d1fe`
(2026-10-11). How to run each harness: [README.md](README.md). Dated history:
the Git log of this file.

## Current matrix

| Lane | HashLink build | hxc build (clang -O2) |
| --- | --- | --- |
| HXB conformance (`conformance-cases.txt`, 286) | 279 + 7 expected failures | 279 + 7 |
| `--hxb-lib` round trip / hxblib cases | 279 + 7 / 7/7 | – |
| Macro cases (66) | 66/66 | 66/66 |
| Parallel mode (`--parallel 3`) | n/a | 279 + 7, identical after normalizing |
| Other upstream suites (195) / display snippets (406) / party (2) | 135 + 60 rejected by both / 117 + 289 / 2/2 | not run |
| `interp.py` (352 cases, 76 do not execute) | 276/276 | – |
| `display.py` | 679/679 | 679/679 |
| `server.py` | 595/595 | 595/595 |
| `server-jsonrpc.py` (both cache modes) | – | 107/107 |
| `eval-debugger.py` | – | 6/6 |
| `upstream.py` (target-independent CI job) | all but 5 tests (finalisers, libuv) | 14/14 steps: unit 11372/11372, misc 684/684, threads 144/144, tink_core, hxcoro |
| Unit tests (`unit.hxml`) | pass | – |
| `unit-targets.py` (upstream unit suite per target) | – | js, lua, python, php, neko, hl, hlc, jvm, cpp, cppia, cppia host, flash without SWC: identical; flash with SWC skipped (needs `compc`) |

Fuzzer, `diff:` lanes on the hxc build (150 programs each, size 5, seed 2026):
hxb, interp, js, lua, python, neko, hl, hlc, cpp, jvm and swf 150/150; php
149 + 1 crash of the reference that the port reproduces. Each generator was
also checked on 500–2,750 programs while it was ported, on its target's
options and on the upstream cases listed below.

Release builds (`.github/workflows/build.yml`, 2026-10-12): `hxc/tools/smoke.sh`
passes on Linux x86_64/aarch64 and macOS x86_64/aarch64 (zig cc builds) and
on Linux, macOS and Windows x86_64/arm64 (Cosmopolitan build), including its
`sys.ssl` check (system CA certificates, a verified TLS handshake with
github.com) and `eval.luv` check (timer, TCP echo). Locally after the move to
the Makefile: `make test` 279 + 7, `make test-fuzz LANE=diff:js N=100` 100/100.

### Upstream's CI suite (2026-10-12)

Upstream's `linux-test` and `mac-test` jobs, `haxe --run RunCi <target>` with
the release binaries as `haxe` and haxelib built by the port
(`.github/workflows/upstream-tests.yml`, [README.md](README.md)). Run
https://github.com/benmerckx/haxe-in-haxe/actions/runs/38308728809 (with all the
fixes below; 26 of 30 jobs pass, the 4 hl jobs fail on one known case):

| Target | Linux x86_64 | Linux arm64 | macOS arm64 |
| --- | --- | --- | --- |
| macro | pass | pass | pass |
| js | pass | pass | pass |
| hl | pass (1) | pass (1) | pass (1); macOS x86_64 too |
| cpp | pass | pass | pass (3) |
| jvm | pass | pass | pass |
| php | pass | pass | pass |
| python | pass | pass | pass |
| lua | pass | pass (2) | pass |
| flash | pass | – (as upstream) | pass |
| neko | pass | pass (2) | pass |

1. Everything up to the last step passes (unit on HL/JIT and HL/C, threads,
   sys, event loop, hlcode, misc hl); in misc hlc, 7 of 8 projects pass and
   `Issue11689` fails explicitly: its function type `hl.Ref<String> -> Void`
   is named after an MD5 of an OCaml `Marshal` with closures (hl2c.ml
   `make_sign`), which contains a code pointer of the reference binary
   itself, so no port can reproduce the name (see "Known differences"). CI
   skips that project (upstream-tests.yml removes it before RunCi hl).
2. Runs before the race fixes below crashed now and then (segmentation
   faults compiling `tests/unit` or `tests/sys`, x86_64 and arm64: e.g. lua
   and neko arm64 in https://github.com/benmerckx/haxe-in-haxe/actions/runs/38279061784,
   js x86_64 and lua arm64 in https://github.com/benmerckx/haxe-in-haxe/actions/runs/38288063131).

3. Two earlier runs had hxcpp's cppia host crash in `-jit` mode on macOS
   arm64 (exit 138 or 255) after all 11658 unit tests passed without JIT;
   the cppia script is the one the reference writes (`unit-targets.py`), so
   this is hxcpp's JIT on Apple Silicon, not the port.

Upstream's tests compile without `-D disable-parallelism`, unlike the local
harnesses, so the release binary runs its parallel passes on OS threads.
A local stress loop of the failing compiles with the release binary crashed
about once per 170 compiles; the core dumps showed two writes that upstream
makes from several domains without a lock (OCaml stays memory safe, hxc's
maps and arrays do not): DCE's `__define_feature__` into a module's feature
table, and `s_mono` growing a print context shared by Dump's parallel
workers. Both now take a lock; 480 + 640 stress compiles ran clean after.
(ThreadSanitizer builds of the port hang: the GC's signals.)

The first run also found three port bugs, fixed since: project-wide
diagnostics after `server/setCwd` ("Display file does not exist": the display
file marker was resolved against the current directory at each use),
RenameVars raising strings where upstream raises `Failure` (no diagnostics
response for an unbound variable, server test `Issue11711`), and the ZIP
reader's pure Haxe inflate, three times slower than the reference's: the
server's background read of hxjava's jar delayed the following requests past
the server tests' 3 s setup timeout (`Issue11549` and every test after it on
macOS). Locally with the fixes: `make test` 279 + 7, `display.py` 679/679,
`server.py` 595/595, `server-jsonrpc.py` 107/107, `diff:jvm` 60/60.

### hxc changes for lix (2026-10-12)

The hxc changes made for `tools/lix/` (coroutine types in the lowering; in hxc's
std and runtime `haxe.Exception.stack` setter, `StringBuf.clear`,
`StringTools.urlEncode`/`urlDecode`, `Date.fromString`, and three new natives)
were checked without the reference compiler (not built in that environment), so
the matrix above was not rerun. Instead, the port built by the changed hxc
(clang -O1) and the `nightly` release (`ecd7581`, whose `src/` differs from
this commit only in comments) wrote identical HXB with `-D disable-parallelism`
for the port's self-compile (JS: 614 modules, hxc: 515), the backend tool
(JS) and lix with hxcoro (hxc: 215). Without that define both binaries vary
between runs on the same input. `hxc/test` regress, threads and exc pass. lix's
own results are in `tools/lix/README.md`.

## Target generators

Every target also compiles upstream's unit suite identically (`unit-targets.py`, above).

| Target | Beyond the fuzzer |
| --- | --- |
| JS |  `tests/misc/js`, `js-es`, `js-classic`, `js-unflatten`, source maps, `@:expose`, `@:jsRequire` |
| Lua | `tests/misc/lua`, `lua-vanilla`, `lua-jit`, `lua-ver` |
| Python | 153 conformance cases in three modes, `@:pythonImport`, `KwArgs`, `VarArgs` |
| PHP | `tests/misc/php` (8 projects), `php-prefix`, `php-lib`, `php-front`, source maps |
| Neko | `neko-source`, `neko-v1`, `use-nekoc` |
| HashLink, HL/C | the port's own sources to `.hl`, `hl-ver`, `hl-check`, `hl-profile`; `-D interp` runs the bytecode |
| JVM | std-heavy programs, `--jvm dir/`, `jvm.dynamic-level`, `--java-lib` |
| C++ | 109 conformance cases (also `cppia -debug`), the port's own sources (2,447 files, cppia script) |
| SWF | SWC, embedded files and bitmaps (JPEG, GIF, PNG), sounds, `--swf-lib` with SWCs from upstream and from the reference, compression levels |
| `--xml`, `--json`, `gen-hx-classes` | the API documentation build of the whole std for 10 targets |

Compile times of every target on two real projects: `site/bench/targets.py`.

## Known differences and limits

- `eval-debugger.py` and `server-jsonrpc.py` normalize what is runtime
  specific: OCaml's string offset caches, thread numbers, memory sizes (the
  hxc build measures its own heap, other hosts report 0).
- `interp.py`: `eval-eventLoop-compile` depends on thread timing and fails
  occasionally on both builds.
- HashLink build: a few upstream tests need `Gc.finalise` or a libuv loop,
  which that build does not provide.
- HL/C: type descriptors that upstream hashes from an OCaml `Marshal` of a
  closure fail explicitly: upstream's misc test `hlc/projects/Issue11689`
  (`hl.Ref<String>` in a function type) is one; the reference names the type
  after a code pointer of its own binary, so its name differs between
  reference builds too. The
  hashes depend on which field name strings are physically shared, which the
  port reproduces only on hosts with string identity (hxc, HashLink, JVM).
- HL/C: the reference writes `hl/hashes.c` in the order its parallel workers
  reach the strings; it matches the port when the reference runs on one CPU.
- `-D dump=pretty --swf`: about 10 dump files of flash std enum abstracts
  differ (an abstract and its implementation write the same file name).
- `--main lower.case`: "Type not found" where the reference reports an
  uppercase-letter error.
- Not covered: Windows hosts (upstream's `windows64-test` is not mirrored:
  test/README.md). The generated programs run in the upstream CI suite only.
