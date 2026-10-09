# Experiment: Cosmopolitan builds of the hxc port (2026-10-09)

Can the C output of `backend/` (the hxc target, `sh backend/build.sh port`)
ship as a single portable binary built with [Cosmopolitan](https://github.com/jart/cosmopolitan)'s
`cosmocc`? **Status: experiment, not adopted.** It works on x86-64 Linux.
The aarch64 half, macOS and Windows are untested.

## Setup

- cosmocc 4.x bundle (GCC 14.1.0) from `https://cosmo.zip/pub/cosmocc/cosmocc.zip`
  (420 MB zip), unpacked anywhere and put on `PATH`.
- Build: `CC="cosmocc -O2" BIN=hih.com sh backend/build.sh port`. `build.sh`
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

The same `prog.c` (16 MB, 467k lines) plus `backend/rt/*.c` on 4 cores.
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

## Next steps, if adopted

- Find the source of the slowdown (perf on a cosmo build, or a glibc build
  with GCC 14 for comparison).
- Run the aarch64 half (`hih.aarch64.elf`, or the APE on an arm64 host), and
  try the binary on macOS and Windows, including the 16 GB reservations.
- Set up a release job: tcc stays the development compiler; cosmocc builds
  the downloadable binary.
