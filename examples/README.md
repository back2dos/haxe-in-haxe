# Playable examples

These examples exercise two useful parts of the current project state:

1. the Haxe-in-Haxe compiler is built and loaded from `bin/haxe-in-haxe.hxb`;
2. that compiler emits `port.cross.hxb` for the selected example.

The translated full typer is not complete yet. The currently usable bootstrap
pipeline emits a portable `cross/` archive, which cannot itself be selected by
the Eval runtime. The script therefore also asks the installed Haxe host to emit
`host.eval.hxb`, then runs that archive without the example source class path.
This keeps the boundary visible instead of presenting host execution as
self-hosting.

From the repository root, run:

```sh
sh examples/run.sh hello
sh examples/run.sh shapes
sh examples/run.sh fibonacci
```

Set `HAXE_HOST=/path/to/haxe` to choose the host executable. Generated archives
are written below `examples/generated/` and are ignored by Git.

The source files are intentionally small and editable:

- `Hello.hx` is the minimal trace example.
- `Shapes.hx` uses an enum, pattern matching, loops, and arithmetic.
- `Fibonacci.hx` uses functions, loops, local mutation, and interpolation.
