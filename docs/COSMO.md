# Experiment: Cosmopolitan builds of the hxc port (2026-10-09)

Can the C output of `hxc/` (the hxc target, `sh hxc/build.sh port`)
ship as a single portable binary built with [Cosmopolitan](https://github.com/jart/cosmopolitan)'s
`cosmocc`? **Status: experiment, not adopted.** It works on x86-64 Linux.
The aarch64 half, macOS and Windows are untested.

## Setup

- cosmocc 4.x bundle (GCC 14.1.0) from `https://cosmo.zip/pub/cosmocc/cosmocc.zip`
  (420 MB zip), unpacked anywhere and put on `PATH`.
- Build: `CC="cosmocc -O2" BIN=hih.com sh hxc/build.sh port`. `build.sh`
  always passes `-fno-strict-aliasing`, which any optimizing compiler needs
  for the runtime's slot casts (`FI`/`FD`/`FP`). `cosmocc` builds a fat APE
  binary (x86-64 + aarch64); `x86_64-unknown-cosmo-cc` builds an x86-64-only one.
- Without `binfmt_misc` an APE file can't be `exec`ed directly, but a shell
  starts it (`sh hih.com ...`), and the `bench/run.py` runners do exactly that.
- Source changes needed: `_GNU_SOURCE` in `rt.c` for `madvise`. GCC 14 also
  rejects int-to-pointer conversions, which exposed a real lowering bug (`!x`,
  `-x` and `~x` on `Null<T>` values returned the unboxed value under the boxed
  type), now fixed for every compiler.

## Results

The same `prog.c` (16 MB, 467k lines) plus `hxc/rt/*.c` on 4 cores.
Builds ran one at a time.

| Compiler | compile + link | binary | stripped | gzip -9 | libc |
| --- | ---: | ---: | ---: | ---: | --- |
| tcc 0.9.27 | 0.6 s | 14.6 MB | 14.6 MB | 3.2 MB | glibc, dynamic |
| gcc 13.3 -O0 | 30 s | 13.0 MB | | | glibc, dynamic |
| gcc 13.3 -O2 | 132 s | 8.8 MB | 8.2 MB | 3.0 MB | glibc, dynamic |
| cosmocc -O2, x86-64 only | 148 s | 8.5 MB | | 3.1 MB | cosmo, static |
| cosmocc -O2, fat (x86-64 + aarch64) | 203 s | 17.0 MB | | 6.3 MB | cosmo, static |

The fat build compiles both architectures in parallel: 203 s wall, 334 s
CPU. Stripping an APE file drops its aarch64 half, so the `.com` rows show
raw sizes only.

Run time: `bench/run.py -n 3`, median, `-D disable-parallelism`. Every
output is checked byte-for-byte against the reference.

| Workload | reference (OCaml) | tcc | gcc -O2 | cosmo fat | cosmo x86-64 |
| --- | ---: | ---: | ---: | ---: | ---: |
| hello | 0.15 | 0.27 | 0.11 | 0.12 | 0.12 |
| trycatch | 0.13 | 0.28 | 0.11 | 0.11 | 0.12 |
| stdlib | 0.24 | 0.63 | 0.23 | 0.24 | 0.25 |
| self | 4.88 | 12.08 | 5.03 | 5.67 | 5.75 |

The fat APE build passes the full HXB conformance suite (275 pass,
7 expected failures) and all 66 macro cases, the same as the gcc and tcc
builds.

## Observations

- On the self-compile, cosmo is 5–13% slower than the glibc gcc -O2 build
  (single runs: 5.42 s vs 5.13 s, nearly all of it user time). Not
  investigated yet. Candidates: GCC 14 vs 13 code generation, and cosmo's
  `memset`/`memcpy`/`_setjmp` (the runtime zeroes every allocation and enters
  a `setjmp` for each `try`).
- For release, a fat binary costs about 1.5× the x86-64-only compile time and
  twice the download (6.3 MB gzipped vs 3.1 MB).
- Risk for Windows: the GC reserves two 16 GB address ranges with `mmap`
  (`rt.c`, `REGION`), which may need a smaller reservation or on-demand
  growth there.
- chibicc was also tried as a fast-build compiler. It compiled and ran the
  port, but took 52 s (preprocessing 8 s, code generation 35 s into 290 MB of
  assembly, `as` 14 s), so it was dropped in favour of tcc's 0.6 s. Upstream
  chibicc also can't use cosmo's headers.

## mbedtls and libuv (2026-10-09)

The APE builds now link real mbedtls and libuv instead of the throwing stubs
(`-DHXC_NO_SSL -DHXC_NO_UV`), so `sys.ssl`/`mbedtls.*` and `eval.luv` work in
macros and `--interp` of `hxc.com` and `haxe-in-haxe.com`, and `-D hxc.static`
user programs can use `sys.ssl` (`-D hxc.ssl`) and the libuv natives
(`-D hxc.uv`). Design, patches and limits: hxc/README.md, "TLS and
libuv".

- `hxc/tools/cosmo-deps.sh` builds mbedtls 2.28.10 (the API of
  `rt_ssl.c`, as upstream's bindings and the system's 2.28) and libuv 1.48.0
  (the native builds' version) with `cosmocc -O2` into fat static libraries
  (`bin/cosmo-deps/lib/*.a` and `lib/.aarch64/*.a`, headers in `include/`),
  from tags fetched with git and checked against pinned commits, with the
  patches in `hxc/tools/cosmo-patches/`: mbedtls takes its entropy from
  `getrandom()`; libuv is built as a generic unix port (`poll(2)` backend,
  run-time errno translation, a `cosmo.c` platform file). 2 minutes on 4
  cores. Wired into `hxc/haxelib/build.sh` and `site/build.sh`
  (`NO_DEPS=1`: stubs) and `hxc/build.sh` (`RT_DEPS=bin/cosmo-deps`).
- The haxelib package bundles the libraries and headers (`cosmo/`: 4.1 MB,
  1.6 MB compressed) rather than building them on first use: building needs
  git, patch, network access and 2 minutes, and the package already ships
  a prebuilt `hxc.com`.

Sizes (fat APE, `cosmocc -O2`, the port as of this change):

| Binary | stubs | mbedtls + libuv |
| --- | ---: | ---: |
| the port, `hxc/build.sh port` (`hih.com`; `haxe-in-haxe.com` adds its std zip) | 19.5 MB (gzip 7.1 MB) | 21.2 MB (gzip 7.9 MB) |
| `haxe-in-haxe.com` (`site/build.sh`, with its std zip; the site's limit is 25 MiB per file) | | 21.6 MB |
| haxelib package `hxc.zip` (`hxc.com` + `cosmo/`) | about 8.1 MB (estimated) | 10.4 MB |
| `-D hxc.static` user program (`hxc/test/natives/Tls.hx`) | | 3.0 MB (`-D hxc.ssl`), 3.3 MB (`hxc.ssl` + `hxc.uv`) |

Checked on Linux x86-64 (the APE started through `sh`):

- Conformance with the real-ssl/uv `hih.com`: 275 PASS + 7 EXPECTED-FAILURE;
  macro cases 66/66; `tests/threads` 138/139 (unchanged: `TestEval.testNative`
  needs `eval.luv.Thread`).
- `hxc/test/natives/Luv.hx` in `--interp` and in a macro (`hih.com` and
  the package's `hxc.com`; `haxe-in-haxe.com` in `--interp`): timers, a TCP echo between two handles, file
  system requests (write, stat, read, unlink, ENOENT), `Process.spawn` with a
  pipe and the exit status, idle handles, uptime/CPU/memory queries. All
  pass, with the same output as the reference compiler.
- `hxc/test/natives/Tls.hx` (`--run`) against a local `openssl
  s_server` with a certificate signed by a local CA: handshake and GET
  without verification, verified with the CA, wrong host name rejected,
  system CAs loaded (512 from `/etc/ssl/certs/ca-certificates.crt`) and not
  trusting the local CA, and a real HTTPS GET of `https://example.com/`
  verified with the system CAs. All pass in `hih.com`, `haxe-in-haxe.com`, in the package's
  `hxc.com`, in a `-D hxc.static -D hxc.ssl` program built through the
  installed package (`haxelib newrepo`), in the same program built natively
  (tcc, `-D hxc.ssl`, system mbedtls) and in the reference compiler.
- The stub builds still build (`eval.luv` throws "not supported" in them),
  and native builds with the system libraries still work.
- Not run: the aarch64 half (no `qemu-aarch64` here), macOS, Windows and
  the BSDs. Their CA certificate sources (macOS `/etc/ssl/cert.pem`, the
  BSD lists, Windows' "Root" store through `crypt32.dll`) and libuv's poll
  backend on them are untested.

## Next steps, if adopted

- Find the source of the slowdown (perf on a cosmo build, or a glibc build
  with GCC 14 for comparison).
- Run the aarch64 half (`hih.aarch64.elf`, or the APE on an arm64 host), and
  try the binary on macOS and Windows, including the 16 GB reservations, TLS
  (system CA certificates) and `eval.luv`.
- Set up a release job: tcc stays the development compiler; cosmocc builds
  the downloadable binary.
