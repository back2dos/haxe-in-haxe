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
passes on Linux x86_64/aarch64, macOS x86_64/aarch64 and Windows
x86_64/arm64 (zig cc builds; Windows: native, MinGW-w64 and the UCRT, on
windows-latest and windows-11-arm) and on Linux, macOS and Windows x86_64
(Cosmopolitan build), including its
`sys.ssl` check (system CA certificates, a verified TLS handshake with
github.com) and `eval.luv` check (timer, TCP echo). Locally after the move to
the Makefile: `make test` 279 + 7, `make test-fuzz LANE=diff:js N=100` 100/100.

### Upstream's CI suite (2026-10-12)

Upstream's `linux-test`, `mac-test` and `windows64-test` jobs, RunCi for each
target with the release binaries as `haxe` and haxelib built by the port
(`.github/workflows/upstream-tests.yml`, [README.md](README.md)). Run
https://github.com/benmerckx/haxe-in-haxe/actions/runs/38318290103: all 40
jobs pass (with misc hlc `Issue11689` skipped, note 1), and with them every
job of build.yml (58 in all):

| Target | Linux x86_64 | Linux arm64 | macOS arm64 | Windows x86_64 |
| --- | --- | --- | --- | --- |
| macro | pass | pass | pass | pass |
| js | pass | pass | pass | pass |
| hl | pass (1) | pass (1) | pass (1); macOS x86_64 too | pass (1) |
| cpp | pass | pass | pass (3) | pass |
| jvm | pass | pass | pass | pass |
| php | pass | pass | pass | pass |
| python | pass | pass | pass | pass |
| lua | pass | pass (2) | pass | pass |
| flash | pass | – (as upstream) | pass | pass |
| neko | pass | pass (2) | pass | pass |

Windows runs the native build (`haxe-in-haxe.exe` as `haxe.exe`, haxelib.exe
booted by nekotools). Its first run
(https://github.com/benmerckx/haxe-in-haxe/actions/runs/38316588536) passed 7
of 10 targets; the 3 others failed on port code that spelled OCaml's
`Filename` the Unix way on every host: nekoc's file argument quoted with
single quotes (misc neko `NekocPathWithSpaces`, server `RunCommandArgs` in
the js job) and import.hx positions joined with `/` (misc eval `Issue1138`,
`if-display`). `core.OcamlFilename` now picks the Unix or Win32 variant by
host, and `handle_import_hx` builds its candidates with `Path.path_sep` as
upstream. Locally with these changes: `make test` 279 + 7, macro cases 66/66,
`display.py` 679/679, `server.py` 595/595, fuzzer `diff:` lanes (60 programs
each: js, neko, hl, hlc, cpp, lua, python, php, jvm, hxb, interp, swf) all
ok. Under Wine, the Windows build's HXB of the port's own sources
(`-D disable-parallelism`) equals the reference's but for the spelling of
absolute paths (`Z:\...` against `/...`), and five parallel-mode compiles of
the same sources ran clean.

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

### hxc: unchecked `Vector` access through HXB (2026-10-13)

The lowering's `Vector` test (`FnLower.isVectorData`) now looks through
`TLazy` and bound monomorphs: the HXB reader (as upstream's) reads typedef
instances as lazy types, so through `--hxb-lib` (the haxelib flow) `Vector`
reads were bounds-checked. With the reference writing the HXB, the source and
HXB paths now generate identical C for a `Vector` loop, bcrypt, sha256 and
sha512 (HaxeBenchmarks), and `hxc/test` regress, threads and exc (all pass on
both paths). The C of the port and of the backend tool is unchanged, so the
port's lanes are unaffected. HXB path, clang -O2, best of 5: bcrypt 2.31 s ->
2.04 s, sha512 22.1 ms -> 18.8 ms, sha256 unchanged (no `Vector`).

### hxmc: macOS and Windows arm64 targets (2026-10-14, branch hxmc)

hxmc (the machine-code target, `hxmc/README.md`) now covers six targets.
The CI workflow `.github/workflows/hxmc.yml` (run 38529235230) cross-builds
the corpus (7 programs, 60 fuzzer programs of seed 1000) and the port on
Linux and runs them on each target's machine: 67/67 outputs identical to
hxc's on linux-x86_64, linux-arm64, windows-x86_64, windows-arm64,
macos-x86_64 and macos-arm64, and the hxmc-built port's self-compile gives
the reference's HXB (514 modules): byte-identical on Linux and macOS,
identical with the root normalized on Windows (absolute Windows paths).
hxc and the port are unchanged; nothing in the port's lanes is affected.

### hxmc separated from hxc (2026-10-14, branch hxmc)

hxmc has its own IR and lowering (copied from hxc's backend), runtime, std
(`--custom-target hxmc`), golden files (hxc's outputs, frozen) and build:
it builds itself, bootstrapped from the reference compiler through node
(`hxmc/README.md`, "Origin", "Bootstrap"). Locally: the corpus (67
programs) matches its golden files on linux-x86_64, linux-arm64 (qemu) and
windows-x86_64 (wine); the hxmc-built port's self-compile gives the
reference's HXB (514 modules) byte-identical on x86-64 (also with a 256 KB
nursery) and arm64 (qemu), identical with roots normalized under wine; the
tool rebuilt by itself is a fixpoint; every benchmark executable (the port
included) is byte-identical to the one the hxc-built tool wrote before.
The port's sources accept `target.name == "hxmc"` beside "hxc" where they
use host natives (imports of either target's externs); for the hxc, Eval,
HashLink and JavaScript builds the typed program is unchanged.
CI (run 38539555994, which bootstraps the tool from the reference compiler
on every run): build, fixpoint and all six target jobs green (corpus 67/67
and the port's self-compile on each target's machine).

### hxmc: the runtime moved into Haxe (2026-10-14, branch hxmc)

Strings, Dynamic access and reflection, the std natives, the system and
socket natives (POSIX and Windows) and the atomic cells moved from C
(`hxmc/rt`, 11.7k lines; 4.8k of them gone) into Haxe that hxmc compiles
with every program (`hxmc/std/hxmc/rt`, `hxmc/std/hxmc/unsafe`; README,
"Runtime in Haxe"). New corpus cases (Unsafe, StdNatives, SysNatives,
NetNatives, ThreadNatives) whose golden files are the C runtime's outputs
(built with the tool, std and runtime object from before the move): 72/72
on linux-x86_64, linux-arm64 (qemu) and windows-x86_64 (wine), cross builds
for macos-x86_64, macos-arm64 and windows-arm64; ThreadNatives also 300
runs with 16/64/256 KB nurseries on x86-64, 45 under qemu, 15 under wine.
The hxmc-built port's self-compile gives the reference's HXB (514
modules, byte-identical, also with a 256 KB nursery); the tool is a
fixpoint. CI: run 38555934736 (through the Windows system natives) green
on all six targets; later runs in the hxmc workflow.

Run times, best of 5, baseline (C runtime) / now, s: alloc 1.549 / 1.481,
bcrypt 2.577 / 2.601, binarytrees 0.750 / 0.737, json 0.461 / 0.413,
mandelbrot 0.498 / 0.494, mandelbrot_anon 0.925 / 1.012, nbody 0.702 /
0.576, sha256 0.155 / 0.149, sha512 0.024 / 0.025, formatter_noio 5.357 /
5.445, port 8.609 / 8.504 (one VM; code-layout noise alone moves a case
by 5-7%: mandelbrot_anon and nbody run the same instructions, callgrind).
Callgrind: the port's self-compile 50.50 G -> 49.10 G instructions
(-2.8%). Sizes, KB: small programs 112-117 (118-119), json 194 (180: the
reflection code), formatter_noio 1388 (1382), port 19819 (19854). Build
(cold, from HXB): +50 ms per program (alloc 0.07 -> 0.12 s: the larger std
HXB to read and the runtime's exported functions lowered and compiled
every time), port 5.84 -> 6.00 s.

### hxmc: stack maps instead of the shadow stack (2026-10-14, branch hxmc)

hxmc's frames keep their references in root slots found through frame
descriptors and frame-pointer chains (hxmc/README.md, "Stack maps"); the
C runtime keeps its shadow stack. Locally: the corpus (72 programs) 72/72
on linux-x86_64, linux-arm64 (qemu) and windows-x86_64 (wine), cross
builds for macos-x86_64, macos-arm64 and windows-arm64; the corpus under
16, 64 and 256 KB nurseries (216/216 on x86-64, 144/144 under qemu and
wine with 16 and 256 KB), also with every frame described and the walk
checked (`HXMC_FRAMES=all`, `RT_FRAMES_STRICT=1`); ThreadNatives 300 runs
(strict); the hxmc-built port's self-compile gives the reference's HXB
(514 modules, byte-identical, also with a 256 KB nursery); the tool is a
fixpoint. Against the runtime-in-Haxe milestone: instructions
mandelbrot_anon -5.6%, binarytrees -1.6%, formatter_noio -1.4%, bcrypt
-0.2%, alloc and json 0%, nbody +0.3%, sha256 +1.3%, port +0.8%; run times
within the code-layout noise; port 19819 -> 19623 KB, small programs
+0-8 KB (page rounding); building from HXB unchanged. CI: run 38586019919 green on all six targets.

### hxmc: cleanup after the runtime move (2026-10-14, branch hxmc)

One typed source per runtime area (haxe.atomic over the intrinsics,
NativeZip, NativeSys/NativeNet dispatching to the POSIX and Windows
classes, Native over hxmc.rt.Dyn), the hxc-era variants gone from `rt/`,
`rt_str.c` folded into `rt_dyn.c`, the census a debug build. Locally: the
corpus 72/72 on linux-x86_64, linux-arm64 (qemu) and windows-x86_64
(wine), cross builds for macos-x86_64, macos-arm64 and windows-arm64; the
corpus under 16, 64 and 256 KB nurseries (216/216 on x86-64, 144/144
under qemu and wine with 16 and 256 KB); ThreadNatives 300 runs; the
hxmc-built port's self-compile gives the reference's HXB (514 modules,
byte-identical, also with a 256 KB nursery); the tool is a fixpoint.
Against stage 5a: instructions unchanged (alloc, json, binarytrees,
nbody, sha256, formatter_noio within 5000 instructions); executables 8 to
12 KB smaller (port 19623 -> 19615 KB); HXB of small programs 75 KB
smaller (alloc 753 -> 677 KB); builds best of 5 alloc 0.12 -> 0.12 s,
json 0.13 -> 0.12 s, binarytrees 0.12 -> 0.11 s, formatter_noio 0.44 ->
0.43 s, port 6.29 -> 5.98 s. CI: CI_RUN.

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
- Windows hosts: covered by upstream's `windows64-test` (above) and the smoke
  tests; the local harnesses run on Linux. The generated programs run in the
  upstream CI suite only.
- Windows: without `HAXE_STD_PATH`, the std is looked up at the executable's
  own path plus `\std` (`get_std_class_paths` concatenates `Extc.executable_path`,
  the program file, with "std"), which is not a directory, so a `std` next to
  `haxe-in-haxe.exe` is not found (checked under Wine). How upstream's
  haxe.exe finds its std without the variable was not established; set
  `HAXE_STD_PATH` (the release zip's README says so, upstream-tests.yml sets it).
