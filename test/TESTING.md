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

Fuzzer, `diff:` lanes on the hxc build (150 programs each, size 5, seed 2026):
hxb, interp, js, lua, python, neko, hl, hlc, cpp, jvm and swf 150/150; php
149 + 1 crash of the reference that the port reproduces. Each generator was
also checked on 500–2,750 programs while it was ported, on its target's
options and on the upstream cases listed below.

## Target generators

| Target | Beyond the fuzzer |
| --- | --- |
| JS | upstream unit suite (`.js` and `.map`, modulo one `Date.now()` macro), `tests/misc/js`, `js-es`, `js-classic`, `js-unflatten`, source maps, `@:expose`, `@:jsRequire` |
| Lua | upstream unit suite, `tests/misc/lua`, `lua-vanilla`, `lua-jit`, `lua-ver` |
| Python | 153 conformance cases in three modes, `@:pythonImport`, `KwArgs`, `VarArgs` |
| PHP | `tests/misc/php` (8 projects), `php-prefix`, `php-lib`, `php-front`, source maps |
| Neko | upstream unit suite (modulo the compile date), `neko-source`, `neko-v1`, `use-nekoc` |
| HashLink, HL/C | the port's own sources to `.hl`, `hl-ver`, `hl-check`, `hl-profile`; `-D interp` runs the bytecode |
| JVM | std-heavy programs, `--jvm dir/`, `jvm.dynamic-level`, `--java-lib` |
| C++ | 109 conformance cases (also `cppia -debug`), the port's own sources (2,447 files, cppia script) |
| SWF | SWC, embedded files and bitmaps (JPEG, GIF, PNG), sounds, `--swf-lib` with SWCs from upstream and from the reference, compression levels |
| `--xml`, `--json`, `gen-hx-classes` | the API documentation build of the whole std for 10 targets, upstream unit suite |

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
  closure fail explicitly (the reference crashes on the one known input).
- `-D dump=pretty --swf`: about 10 dump files of flash std enum abstracts
  differ (an abstract and its implementation write the same file name).
- `--main lower.case`: "Type not found" where the reference reports an
  uppercase-letter error.
- Not covered: running the generated programs of the target generators (their
  output is compared instead) and Windows hosts.
