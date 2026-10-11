# fuzz: differential fuzzer for the port

`test/fuzz/` generates random, well-typed, terminating Haxe programs and checks
that the port behaves exactly like the pinned reference compiler on them. It is
written in Haxe and built with hxc. Its first job is checking target
generators as they are ported: a `diff:<target>` lane requires the port's
generated JS, Lua, PHP, ... to be byte-identical to the reference's output for
the same program.

```sh
sh test/fuzz/build.sh                         # bin/fuzz/fuzz (hxc, clang -O2; ~10 s)
bin/fuzz/fuzz -j 4 -n 500                     # diff:hxb on 500 programs
bin/fuzz/fuzz --lane diff:js --run -j 4       # port JS output (and its run output) vs the reference
bin/fuzz/fuzz --lane diff:interp --lane diff:hxb --time 600 -j 4
bin/fuzz/fuzz --lane exec:interp,hxc -j 4     # hxc-compiled programs vs reference --interp
bin/fuzz/fuzz --help
```

It needs the reference (`haxe/haxe`, or `HAXE_REFERENCE`) and a build of the
port (`bin/hxc/hih/hih_clang` from `hxc/build.sh port`, or
`HAXE_IN_HAXE_PORT`/`--port`). The generator also runs on Eval
(`haxe -cp test/fuzz --run Fuzz --emit DIR -n 10`); a seed produces the same
program on every host.

## Lanes

A lane compares two sides on each program. Programs are written to
`<out>/work/w<N>/src`, and each side compiles in turn from the same directory,
`<out>/work/w<N>/cwd` (afterwards renamed to the side's label, `ref` or `port`),
with `-cp ../src -main Main -D disable-parallelism`, so paths embedded in output
(including the working directory) are the same for both sides.

| Lane | Sides | Compared |
| --- | --- | --- |
| `diff:<target>` | reference and port, same target | exit code; compiler output (warnings, errors); the output files: `.hxb` payloads for `hxb`, every member for `zip`, every file for `dir`, bytes for `file`; with `--run`, the program output of both builds |
| `exec:<a>,<b>` | `[ref:\|port:]<target>` each (default `ref`) | only what the program prints when run (from its `start` line, after any compiler warnings) and the exit code |

Built-in targets (`--list`): `hxb`, `interp`, `js`, `lua`, `python`, `neko`,
`hl`, `hlc` and `cpp` (both `-D no-compilation`), `php`, `jvm`, `swf`, and `hxc` (the
program compiled to C by the hxc tool, `bin/hxc/wbk.js`, and tcc;
`HXC_CC` picks another C compiler; see `hxc.sh`). Add others with
`--target-def 'name|--flag {out}/file|file:file|runner {out}/file'`.

`exec` lanes turn on `--portable`: the programs then avoid behavior the targets
legitimately disagree on (32-bit overflow, float printing, `>>>`, map
iteration order, enum/object printing, non-ASCII strings, out-of-range string
and array access), so any difference is a bug in one of the sides.
`exec:interp,js` on the reference alone checks that profile itself.

## Verdicts

| Kind | Meaning |
| --- | --- |
| `ok` | identical |
| `invalid` | the reference (side `a`) rejected the program: a generator bug unless `--mutate` injected an error. The first 5 are saved under `<out>/invalid/` |
| `rejected-alike` | an injected error (`--mutate`), reported identically by both |
| `reference-failure` | the reference crashed ("Compiler failure"; the port must fail alike, backtraces aside). Saved and reduced under `<out>/reference-failures/`; does not fail the run |
| `port-rejects`, `port-accepts` | only one side accepted the program |
| `port-crash`, `port-timeout` | the port died (signal, exit code ≥ 125) or exceeded `compileTimeout` |
| `diagnostics-differ`, `log-differs` | both rejected (or accepted) with different compiler output |
| `output-differs` | different output files (or `--interp` program output) |
| `run-differs`, `run-crash`, `compile-fails` | `--run`/`exec`: different program output, a crash, or side `b` not compiling |

Failures are grouped by a signature (lane, kind, detail with names and numbers
blanked). The first `--keep` cases (default 2) of a signature go to
`<out>/failures/<signature>/<seed>/`: the sources (`src/`), both sides'
compiler and run logs, `verdict.txt` (features, the injected error) and
`repro.sh`. The first case of each new signature is also reduced (below) into
`reduced/`. The exit code is 1 when there was any port (side `b`) failure.

A program is reproducible from its seed: `--seed S -n 1` with the same
`--size`, `--portable`, `--feature` and `--mutate` options regenerates it, as
long as the generator is unchanged (saved cases keep their sources for that
reason).

## Generator

`fuzz/Gen.hx` builds a typed tree (`fuzz/Ast.hx`: every node is source text with
typed child nodes and blocks) from a type-directed grammar:

- declarations in up to four modules (`Main`, `p.M1`, `p.q.M2`, `p.Ext`):
  classes with inheritance, interfaces, abstract classes and methods,
  overrides with `super` calls, properties, static and final fields,
  constructors; enums with recursive constructors; typedefs of anonymous
  structures; an abstract over `Int` with `@:op` operators and a property;
  an enum abstract; the generic `Box<T>`; `@:generic`, inline, static
  extension (`using`), optional, default and rest arguments;
- expressions: arithmetic, bitwise and comparison operators, `++`/`+=` side
  effects inside expressions, string methods and interpolation, `StringBuf`,
  array methods and comprehensions, maps, lambdas and local functions
  (including bounded recursion), `bind`, `Lambda`, `Std`/`Math`/`Reflect`/`Type`
  calls, `cast`, type checks, `Std.isOfType`/`downcast`, `match`, `??`,
  ternaries, `if` and `switch` expressions, block expressions;
- statements: loops (`for` over ranges, arrays and key-value pairs, `while`,
  `do`/`while`, `break`/`continue`), `switch` with constructor, nested, or-,
  guard, array and structure patterns, `try`/`catch` by type with thrown
  strings, ints and `haxe.Exception` subclasses, early returns.

Each program enables a random subset of the feature groups (swarm testing,
`--list`; force with `--feature`/`--no-feature`). The reference accepts about
99.5% of the generated programs.

Programs always terminate: calls between user functions form a DAG, lambdas
only call "tier-0" functions that never call function values, loops are
bounded, and every function and loop iteration calls `H.tick()`, which throws
once a global fuel budget is spent. String and array assignments are capped at
1,000 elements, so values cannot double in every loop iteration. Programs are
deterministic (no clocks, randomness or hashing) and print through `H.out`.

`--mutate P` injects one error into P% of the programs (a value of the wrong
type, an unknown identifier or field, an extra argument), which both compilers
must report with identical diagnostics.

## Reduction

`fuzz/Reduce.hx` shrinks a failing program while the lane keeps reporting the
same failure kind: it removes chunks of declarations, members and statements
(halving the chunk size down to one), replaces statements by the contents of
their blocks (unwrapping `if`, loops, `try`), replaces expressions with the
default value of their type, and hoists same-typed sub-expressions.
Candidates the reference rejects are never kept. `--reduce N` bounds the test
runs (default 200; `--reduce 0` disables reduction).
