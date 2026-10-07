# Benchmarks

Wall-clock time of the pinned reference compiler (native OCaml) vs. the
translated compiler (`haxe.Main`) built for different Haxe targets. Every run
compiles a workload to HXB with `-D disable-parallelism`. A runner's timing
only counts if its archive matches the reference: same members and
byte-identical `.hxb` payloads.

```sh
make -C haxe haxe
HAXE=haxe/haxe sh bench/build.sh js hl jvm cpp   # needs hxnodejs, hxjava, hxcpp (git)
HAXE_REFERENCE=haxe/haxe python3 bench/run.py -n 3
```

## Results — 2026-10-07

4-core Linux container. Median of 3 runs, in seconds; the ratio is relative to
the reference.

| Runner | hello | trycatch | stdlib | vs. reference (stdlib) |
| --- | ---: | ---: | ---: | ---: |
| reference (native OCaml) | 0.13 | 0.12 | 0.23 | 1× |
| C++ (hxcpp) | 1.21 | 1.00 | 1.83 | 8× |
| JS (Node 22), no stack traces | 1.54 | 1.60 | 2.63 | 11× |
| JVM (OpenJDK 21) | 3.85 | 3.61 | 5.40 | 23× |
| JS (Node 22) | 3.60 | 3.70 | 7.15 | 31× |
| HashLink (JIT) | 3.93 | 4.17 | 7.62 | 33× |

Workloads:

- `hello`: a `trace("Hello, world!")` main (63 modules, mostly std).
- `trycatch`: `test/unit/moduleload/TryCatch.hx` (63 modules).
- `stdlib`: 32 std modules as bare roots (95 modules).

The port's own source can't be a workload yet: compiling it executes std
macros, which are outside the first milestone.

## Notes

- **Exceptions.** The port follows upstream in using exceptions for control
  flow (`Not_found`, `Exit`, stream parser failures). Those throws are cheap
  in OCaml, but on JS about half the run goes to capturing stack traces for
  them. `js-nostack` is the same build run with `node --stack-trace-limit=0`,
  and it's 2–2.7× faster. HashLink and the JVM probably pay a similar cost.
  Exceptions that don't capture a stack would be the cheapest broad speedup.
- **Go** isn't benchmarked. The pinned compiler has no Go target, and the
  [hx2go](https://github.com/go2hx/hx2go) custom target (git `2739b6c`)
  compiles a hello world but not the port. First, its `haxe.Exception`
  defines `error()` for Go's error interface, which clashes with the port's
  `ParserError.error` and `WithTypeError.error` fields. With those renamed,
  the generated Go still has 40 compile errors: `break`/`continue` outside
  their loop, missing `HxArray` methods (`concat`, `slice`, `join`), generic
  variance (`HxArray[T]` vs `HxArray[any]`) and missing returns.
- **HL/C** isn't benchmarked: the pinned compiler's `hl2c` generator fails on
  the port (`Globals.die` in `hl2c.ml` `rassign`).
- **JVM.** The pinned `genjvm` takes about 8 minutes on the port and emits a
  method (`typing.Typer.typeExpr`) the bytecode verifier rejects. The jar runs
  correctly with verification off (`-XX:-BytecodeVerificationLocal`), which
  `run.py` passes. Java can't change the working directory, so
  `core.Path.restoreCwd` skips `Sys.setCwd` when the directory didn't change.
- **JS** needs hxnodejs for `sys`. `bench/js-shims` holds single-threaded
  `sys.thread` stand-ins; the compiler only spawns workers when parallelism is
  enabled. Building with `-D analyzer-optimize` currently produces different
  (non-conforming) output on JS, so all targets are built without it. With
  the shell redirected to `/dev/null`, hxnodejs's `Sys.stdout().flush()`
  fails (`fsync` EINVAL).
- **C++** needs hxcpp from git: the 4.3.2 haxelib release doesn't support the
  pinned std.
- **Conformance on other targets.** `HAXE_IN_HAXE_PORT="node --stack-size=65500 bin/bench/hih.js" python3 test/conformance.py`
  runs the whole conformance suite on a prebuilt port. The JS build passes all
  282 cases.
