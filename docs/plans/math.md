# Math

One implementation on every target: `hxmc/std/hxmc/rt/LibM.hx`, musl's
algorithms in Haxe (docs/hxmc.md, "Runtime in Haxe"; why the port's
printed floats can differ from the reference's: docs/testing.md, "Printed
floats").

## Where it stands

sin, cos, tan, asin, acos, atan, atan2, exp, log, pow and Float's `%`
(fmod) are musl's (its pow and atan2; zig's ports of musl for the
others); sqrt and abs are instructions, floor and ceil arm64's
frintm/frintp, WebAssembly's f64.floor/f64.ceil and inline code on x86-64
(no SSE4.1 assumed). Nothing calls the C library's math (zig's
compiler_rt still brings its unused copies into the Linux rt.o). Results
are bit-identical to musl's C on Linux x86-64 (2 million random and edge
inputs per function, and the corpus's `MathLib`); NaNs keep the
processor's sign and payload. Speed against musl's C on x86-64 (ns per
call): exp, acos, asin, atan2, fmod, floor and ceil faster, log, atan and
pow within 5%, sin, cos and tan about 1.1-1.3x slower; nbody and
mandelbrot unchanged. The codegen it would still like is in
[codegen.md](codegen.md), "Smaller items".

## Later: the libm branch

The `libm` branch (98d9d82, 374bb61; parked): exp/log/pow from Arm's
Optimized Routines (glibc's own code, MIT; bit-identical to glibc),
sin/cos/tan/asin/acos/atan/atan2 from CORE-MATH (MIT, correctly rounded:
equal to glibc except where glibc is an ulp off, about 1 input in 1,000),
fma in hardware where the CPU has it, tested exact against glibc and
CORE-MATH's 9.5 million hard cases. It replaces LibM's functions once it
is no slower than them at run time, compile time and size:

- CORE-MATH's trig is slower than musl even in C (cos 17 ns, tan 24 ns
  against 6.5 and 10.5 on x86-64), and has ~166 KB of tables (as
  `Mem.words`: read-only data, not literals typed with every build).
- One math implementation only: where a CORE-MATH function costs too much,
  that function keeps musl's algorithm, no second variant behind a define.
- The port would then differ from the reference (glibc) only where glibc
  is an ulp off, and the fuzzer's float tolerance could shrink.
