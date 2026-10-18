# The dev loop: `hxmc dev`

Save a file, see the change, keep where you were. `hxmc dev` builds the
program, runs it, and on every save builds it again and reloads it; the
reload starts the new build fresh, with the old build's state carried over
by key (fast refresh). The design and what comes next:
[plans/dev-loop.md](plans/dev-loop.md) (steps 1 and 2 are built).

```sh
npx haxe --dev build.hxml          # the npm package
bin/hxmc/hxmc dev build.hxml       # the repository's tool
```

The arguments are the build's, as for `haxe` (an hxml file, or options);
the output, `--custom-target hxmc=<out>`, says how the program runs:

- `<out>.wasm` (`-D hxmc.target=wasm32-wasi`): in the browser. The dev
  server serves a page at `http://localhost:4321/` (`--port <n>`, or
  `HXMC_DEV_PORT`; on this machine only, `--host 0.0.0.0` for a phone on
  the network) that runs the module with the browser modules of the
  packages the build uses (their `imports.mjs`, `@hxmc/os`'s
  `browser.mjs`, DejaVu Sans for `@hxmc/text`). WasmGC (`-D hxmc.wasm-gc`)
  works the same way.
- anything else: a native program, started by the dev server (its output
  in the terminal). On Linux a window needs the glibc mode (`-D
  hxmc.libc=glibc`), as always.

What happens:

- The compiler stays resident: the dev server starts it as a compilation
  server (`--wait`) and each build is a request to it, with `-D hxmc.dev`
  added. Typed modules, lowered bodies and compiled objects stay in memory;
  a build types again only the modules that changed and those that depend
  on them.
- The class paths and libraries the build names (and its hxml files) are
  watched; a change builds again (several changes close together: one
  build).
- A build that compiles reloads the program. In the browser the page asks
  the running module for its snapshot, keeps it in `sessionStorage` and
  loads again with the new module. Natively the program writes its
  snapshot to a file and exits, and the new build starts with it.
- A build with errors changes nothing: the last good build keeps running.
  The errors show in the terminal and, in the browser, in an overlay over
  the page, which goes away with the next build that compiles.
- Each reload prints its time, from the change seen to the new build's
  first frame: `hxmc dev: reloaded in 1043 ms (build 896 ms)`.

A program that ends by itself (its window closed) starts again with the
next build. A native program without hxmc.os's app loop (a command-line
program) cannot hand its state over: it is stopped and started again.

## Fast refresh: state carried by key

A reload is never a patch of running code: the new build runs its own
`main`, and what it gets from the old one is data, restored by key. So a
reload behaves like a cold start with the same values, on every target, and
there are no stale closures or half-migrated objects. State that cannot be
carried is reset, visibly (a line in the terminal or the console).

**Signals.** Every `signal(...)` of `@hxmc/view` is keyed with no code
written for it:

- its static name: the type and function it is made in and the variable it
  is assigned to (`var open = signal(false)` in `App.Menu`:
  `App.Menu.open`; a field `public final count = signal(0)`: `Gallery.count`),
  else its order among the unnamed ones of that function (`#0`, `#1`).
  Names, not line numbers: edits around a signal keep its key;
- inside the component instance it is made in: each component runs in a
  scope of its name, `Card`, a second one in the same place `Card#1`; with a
  `key` attribute (`<Card key={item.id}/>`) the scope is `Card[<key>]`,
  so a list keeps each item's state even when the items move. `key` is no
  prop: the component does not declare it;
- the rows of `For` and `Index` in a scope of their position, and each
  computation (an effect, a reactive region, `Show`) in a scope of its own,
  so that what a region shows later (a `Show` turned on after a click) is
  keyed as when it first showed, and finds its state when the new build
  shows it at once.

A signal's value is saved with its type's hash; a new build whose signal
has another type (`signal(0)` became `signal("")`, a structure got a field)
resets it and says so:

```
hxmc.dev: Counter.main.count reset: its type changed
```

Values go through `haxe.Serializer`, so a signal keeps data: numbers,
strings, booleans, arrays, maps, structures, enums and class instances of
data. A signal whose type is not data (a function, `Dynamic`, a node of the
UI, a native handle) is not kept and starts again from its initial value
(the dev server lists them at each reload); so is one whose type is not
known where it is made (`signal([])` with nothing saying what the array
holds: give the type, `var s:Signal<Array<String>> = signal([])`). A value
the old build saved and the new one never asks for (a signal removed) is
dropped after the first frame, and listed.

**State outside components** (models, stores, app-level values) opts in
with a key of its own:

```haxe
var cart = Hot.keep("cart", () -> new Cart());   // the old build's Cart, else a new one
```

**Disposal.** Before the new build starts, the old one releases what it
owns: the roots `Render.render` made are disposed (every effect's cleanups
run), and the functions given to `Hot.onDispose` run, last given first.

**Release builds pay nothing.** All of this exists only with `-D
hxmc.dev`: without it `signal(v)` is `new Signal(v)` as before, components
are called as before, `hxmc.os.App`'s loop has no dev client, and every
`Hot` call compiles to nothing. The counter, the gallery and the cube built
before and after this was added are the same bytes, natively, as wasm and
as WasmGC.

## The primitives: `hxmc.dev.Hot`

Fast refresh is built on a small public layer in `@hxmc/os` (no view or ui
dependency): `hxmc.dev.Hot`. hxmc's signals (`hxmc.view.Refresh`) and
components (the markup macro) are its first clients and use nothing else,
so any state library (a store, another signal library, an ECS, a game's
world) gets fast refresh the same way, without hxmc knowing about it.

| Call | |
| --- | --- |
| `Hot.reloading` | true while this build starts from a snapshot (until its first frame); false on a cold start |
| `Hot.onSnapshot(f)` | `f` runs before the swap, to save values; returns a function that removes `f` (when what it saves is gone) |
| `Hot.onDispose(f)` | `f` runs after the snapshot, before the new build starts: release what this build owns (effects, timers, sockets, GPU buffers); returns a remover |
| `Hot.save(key, value, type, ?encode)` | `value` kept for the next build, by key; `haxe.Serializer` by default, or `encode: T->String` for a value that does not serialize as it is |
| `Hot.load(key, type, ?decode)` | the value the last build saved under `key`, once (`decode: String->T` to match `encode`); null when there is none or its type changed (logged), never cast |
| `Hot.typeOf((_ : T))` | `T`'s shape hashed when compiling (its fields and their types, recursively); `""` for a type that is not data, which `save` skips. Any other expression gives the hash of its type, unevaluated |
| `Hot.here()` | the static identity of the place it is written: `Type.method.variable` |
| `Hot.scope(name, f)` | runs `f` with `name` nested in the keys made inside it (a component instance, a list item); a name given twice in one scope becomes `name#1`, ... |
| `Hot.keep(key, init)` | a value kept as it is: `load`, else `init()`, saved again on each snapshot (a mutable object: its state at the snapshot) |
| `Hot.path()`, `Hot.at(path, f)` | the current scope, and `f` run in a scope taken earlier: for code that runs later (an effect running again, a row added after a click) |

Keys are relative to the scope: `save` and `load` resolve them against it,
and `load` numbers a key loaded twice in one scope (`key#1`), as `scope`
numbers names. The functions given to `onSnapshot` and `onDispose` run in
the scope, and with the key resolutions, of where they were given, so
`save(key)` there reaches what `load(key)` read.

For a library's own macros, `hxmc.dev.HotMacro` gives the same at compile
time: `HotMacro.hash(type)` (what `typeOf` gives) and
`HotMacro.here(Context.currentPos())`, the place of the macro's call
(`Hot.here()` written inside a macro's `macro` block is the place of that
block, as every expression there is). Both give `""` without `-D hxmc.dev`.

Where this differs from the plan's names: Haxe has no explicit type
arguments, so `Hot.typeOf<T>()` is written `Hot.typeOf((_ : T))`;
`onSnapshot` and `onDispose` return removers (a component's signal stops
being saved once the component is gone); `Hot.path()` and `Hot.at()` were
added, because computations that run again later must find their keys
where they first ran.

### A state library

A small store, written as a third-party library would be (it knows nothing
of hxmc.view), is reload-safe in three lines, and its users write nothing
(`packages/os/test/store/Store.hx`, tested in CI by `HotTest`):

```haxe
class Store<S> {
	public var state(default, null):S;

	public function new(key:String, initial:S, type:String) {
		var kept:Null<S> = Hot.load(key, type);           // the last build's state, if its type is the same
		state = kept != null ? kept : initial;
		Hot.onSnapshot(() -> Hot.save(key, state, type)); // and this build's, for the next
	}

	// `var cart = Store.create(...)`: keyed Type.method.cart, its state's type hashed where it is made
	public static macro function create(initial:haxe.macro.Expr):haxe.macro.Expr
		return macro new store.Store($v{hxmc.dev.HotMacro.here(haxe.macro.Context.currentPos())}, $initial,
			hxmc.dev.Hot.typeOf($initial));

	public function update(f:S->S) ...
}

var cart = Store.create(({items: [], total: 0.0} : Cart));
```

Without `-D hxmc.dev` the same code compiles to the store alone: `load` is
null, `onSnapshot` and `save` are nothing, `here` and `typeOf` are `""`.

The type is hashed where the store is made because a generic class only
knows `S` as a type parameter; a library whose primitive is a function
takes the hash as an argument from a macro, as `create` does, or asks its
users for `Hot.typeOf((_ : T))`. A library with code that runs later in its
own scope (as view's effects do) takes `Hot.path()` when it is made and
runs that code in `Hot.at(path, f)`.

## The protocol

The dev server and the program talk in JSON messages: JSON lines over a
TCP connection natively, WebSocket text messages in the browser (the
page's `/__hxmc/ws`), so editors and other tools can drive the loop:

| To the program | |
| --- | --- |
| `{"type":"reload"}` | a new build is ready: snapshot, dispose, hand over. Natively it carries `"snapshot": <file>`: write the snapshot there, answer `saved`, exit. In the browser the page asks the module for its snapshot and loads again |
| `{"type":"error","message":<text>}` | the build failed (the overlay); the program keeps running |
| `{"type":"ok"}` | the build compiles again (the overlay goes) |
| `{"type":"assets", ...}` | reserved: styles and images without a rebuild (step 4) |

| From the program | |
| --- | --- |
| `{"type":"saved"}` | natively: the snapshot is written |
| `{"type":"frame"}` | the first frame of a build is drawn (the reload's time) |
| `{"type":"log","text":<text>}` | the page: a line the module printed |

The snapshot is a string, `haxe.Serializer`'s encoding of an array of
strings: key, type hash, value (`Hot.save`'s encoding), key, ... A native
program finds the dev server in `HXMC_DEV=<host>:<port>` and starts from
the snapshot file in `HXMC_DEV_SNAPSHOT`; with only the latter, a program
starts from a snapshot without any dev server (as the tests do). In the
browser the page gives the module the imports of `hxmc_dev`:
`restore_length()` and `restore_take(p)` (the snapshot it was given, -1:
none), `register(f)` (the `@:hxmc.callback` the page calls for a reload),
`send(p, n)` (the snapshot) and `frame()`. hxmc.os's app loop reads the
dev server's messages at each turn (an idle loop wakes every 50 ms in a dev
build) and reports the first frame.

## Times

From the save to the new build's first frame, a one-line edit of the
program's `main` (`node packages/os/test/dev/dev-latency.mjs <compiler>
<example> web|web-gc|native`: the medians of six edits), on a 4-core x86-64
Linux machine, headless Chromium with SwiftShader, natively under Xvfb with
llvmpipe; ui's Counter (about 400 modules, 1700 functions) and Gallery (about
3300 functions):

| | build | save to frame | target |
| --- | --- | --- | --- |
| Counter, browser (wasm) | 0.92 s | 1.07 s | 0.5 s |
| Counter, browser (WasmGC) | 0.84 s | 1.01 s | 0.5 s |
| Counter, native | 0.94 s | 1.12 s | 0.5 s |
| Gallery, browser (wasm) | 1.49 s | 1.75 s | 1.5 s |
| Gallery, browser (WasmGC) | 1.31 s | 1.68 s | 1.5 s |
| Gallery, native | 1.48 s | 1.68 s | 1.5 s |

The build is most of it (the reload itself, the page loading again or the
process starting, is 0.15-0.25 s). Of the Counter's build, in the
compilation server: about 0.35 s reads every cached module back from its
HXB and caches the build's again (the server's HXB cache, as upstream's),
0.18 s lowers every function again, then DCE, the objects and the link;
the Gallery's edit also types its large module of markup again. Neither
target is met yet: what would close the gap is in
[plans/dev-loop.md](plans/dev-loop.md).

## Tests

`make dev-check` (CI: the `gfx` job): `HotTest` (the primitives and the
store across a reload, natively and on Eval, a changed type reset),
`RefreshTest` (view's keys: component instances, rows, `key`, a region
shown later), then `hxmc dev` on ui's Counter in headless Chromium (as wasm
and as WasmGC) and natively under Xvfb: an edit keeps the count, a changed
type resets it, a compile error shows in the overlay (the terminal) while
the last good build keeps running, the fix reloads with the count kept.

## Not yet

- Seamless swaps (step 3): natively the process restarts (the window
  closes and opens again), in the browser the page loads again. Android
  and iOS are not driven yet.
- Styles and assets without a rebuild (step 4).
- The UI engine's own state (focus, scroll and selection by node key) is
  the UI session's part of step 2; ui's widgets' own signals are keyed
  like any other already.
