# Porting conventions for the macro runtime (`src/macros`)

Upstream: `haxe/src/macro/macroApi.ml`, `haxe/src/macro/eval/*.ml`,
`haxe/src/typing/macroContext.ml`. (`macro` is a Haxe keyword, so the package
is `macros`.)

Translate directly, keeping upstream order, branch structure and error
behavior (see AGENTS.md). These rules let modules call each other before all
of them exist:

- **Modules.** `evalFoo.ml` becomes class `EvalFoo` in
  `src/macros/eval/EvalFoo.hx` with static functions. `macroApi.ml` is
  `src/macros/MacroApi.hx`; its functor body (`MacroApiImpl`) is class
  `MacroApiImpl` in that module, calling Eval directly instead of `InterpImpl`.
  `macroContext.ml` becomes `src/typing/MacroContext.hx`.
- **Names.** `snake_case` → `camelCase`: `encode_string` → `encodeString`,
  `get_static_prototype` → `getStaticPrototype`. Keys keep their names:
  `EvalHash.key_length`. A function name that is a Haxe keyword gets a trailing
  `Value`/descriptive suffix and a comment (`throw` → `throwValue`).
  Upstream `exc_string`, `exc`, `throw` are `EvalContext.excString`, `exc`,
  `throwValue`; they return `Dynamic` (they never return).
- **Records** become classes (or `@:structInit` classes) with camelCase fields:
  `env_info` → `envInfo`, `pinstance_names` → `pinstanceNames`. Record types
  keep upstream's name capitalised when it would clash with a constructor:
  `vobject` → `Vobject` (constructor `VObject`), `vinstance` → `Vinstance`,
  `vprototype` → `Vprototype`, `venum_value` → `VenumValue`, `varray` → `Varray`,
  `vstring` → `Vstring`.
- **Values** are `macros.eval.EvalValue.Value` (see `EvalValue.hx`); helpers
  such as `vint`, `vbool`, `equals`, `vresolve` are in `EvalValueTools`
  (`using macros.eval.EvalValue.EvalValueTools` or call them qualified).
- **Exceptions.** OCaml exceptions become `haxe.Exception` subclasses
  (`RunTimeException` in `EvalContext`, `InvalidExpr` in `MacroApi`: throw
  `InvalidExpr.raise()`). `Not_found` is `core.ds.NotFound` (`throw NotFound.raise()`),
  `Exit` is `core.ds.Exit`, `Failure` is `core.ds.Failure`.
- **Maps.** `Globals.IntMap` (reversed comparison!) is `core.ds.GlobalsIntMap`;
  OCaml `Hashtbl` whose iteration order matters is `core.ds.OcamlHashtbl`;
  `IntHashtbl` used only for lookup can be `Map<Int, V>`. `PMap`/`StringMap`
  of strings: `haxe.ds.StringMap` with sorted iteration where order matters.
- **Lists** become arrays; keep the order upstream produces (folds that cons
  build reversed lists).
- **Strings.** Eval strings are `Vstring` (native string, code point length);
  use `EvalString.createAscii`, `createUnknown`, `createWithLength`.
  "Byte offsets" in upstream are native string indices here.
- **Positions** are `core.Globals.Pos`; AST/types are `core.Ast`/`core.TType`.
- **Not ported**: the debugger (`evalDebug*.ml`, debug socket), libuv
  (`evalLuv.ml`), mbedtls (`evalSsl.ml`). Code that would use them throws a
  clear error ("... is not supported by haxe-in-haxe"); never fake a result.
- Translate argument evaluation order explicitly where OCaml's right-to-left
  order is observable (side effects, allocations, ids).
- Each file starts with a comment naming its upstream file and any
  deliberate deviation.
- Check a module with
  `haxe/haxe -cp runtime/hl -cp src macros.eval.EvalFoo --no-output -hl /tmp/x.hl`.
