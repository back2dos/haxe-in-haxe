# The dev loop: live reload and fast refresh

Save a file, see the change, keep where you were. Four steps, each useful on
its own; the first two give most of it.

## Principles

- **A reload is a fresh start with state carried over**, never a patch of
  live code. The new build runs from its own `main`; what survives is data,
  restored by key. So a reload behaves exactly like a cold start with the
  same values, on every target (native, linear wasm, WasmGC, JavaScript),
  and there are no stale vtables, closures or half-migrated objects.
- **State that cannot be carried is reset, visibly**: a type that changed, a
  signal that was removed, a value that does not serialize. It is logged,
  never guessed.
- **The last good build keeps running** while the new one has errors; the
  errors show in an overlay in the app and in the terminal.
- **Zero cost in release**: the dev client is linked only with `-D hxmc.dev`.
- **Measured**: edit-to-pixels latency is tracked like build time.

## 1. Live reload

`hxmc dev [build.hxml]` (and `npx haxe --dev ...`):

- Watches the class paths, libraries' sources and assets the build read
  (the module cache already records them, macros' file reads included).
- Keeps the compiler resident (the compilation server: typed modules,
  lowered bodies and compiled objects in memory; a no-change rebuild of a
  small program is about 0.4 s today). Rebuilds only what changed: retype the
  changed modules (early cutoff on unchanged interfaces), recompile their
  functions, relink.
- Runs the program and talks to it over a small protocol (a pipe or Unix
  socket natively, a WebSocket from a dev server in the browser): `reload`,
  `assets`, `error`, `ok`. In the browser the dev server serves the page and
  swaps the island's module; natively it restarts the process.
- A dev profile may skip optimisations that cost build time but not
  correctness, only where measured to help.

Targets: a counter-sized app under 500 ms from save to pixels, the gallery
under 1.5 s. Mobile: Android pushes the new `.so`/APK and relaunches; iOS
relaunches on the simulator (iOS forbids loading new code on devices).

## 2. Fast refresh: state carried by key

- **Keys.** Every `signal(...)` in a component gets a key: the component
  instance's path in the tree (parent path plus position or its `key` prop,
  so list items keep their own state) plus the signal's static name: the
  variable it is assigned to (`var open = signal(false)` → `open`), else its
  order in the component. Names, not line numbers, so edits around a signal
  keep its key. The markup and reactive macros (packages/view) assign the
  static part at compile time.
- **State outside components** (models, stores, app-level values) opts in
  with a key of its own: `Hot.keep("cart", () -> new Cart())`.
- **Snapshot and restore.** Before a swap the running program serializes its
  keyed values (`haxe.Serializer`) with each value's type hash from the
  compiler; the new build's signals read their value back by key when
  created, if the type hash matches. Closures, native handles and other
  non-data values are reset.
- **Disposal.** The old build's effects run their cleanups and its
  resources (timers, sockets, its GPU buffers) are released before the new
  one starts; what the host owns (window, GPU device) stays in step 3.
- **Focus, scroll and selection** are state of the UI engine, restored by
  node key the same way.

## 3. Seamless swaps

- **Native**: a host executable holds the runtime, the window, the GPU
  context and native views; the program is a shared library. On reload:
  snapshot, run disposal, drop the library's roots and collect (no object
  may keep the old library's code or type data), unload, load the new one,
  restore. The window never closes. Needs shared libraries beyond glibc
  Linux (`-D hxmc.shared` today): Mach-O dylibs and Windows DLLs.
- **Browser**: instantiate the new module against the same canvas and GPU
  device; the page does not reload.

## 4. Styles and assets without a rebuild

Theme rules are data (and CSS for the DOM renderer): a change to
`shadcn.json`, `extras.json` or the tokens sends new rules and the engine
restyles on the next frame. Images, fonts and icons reload the same way.

## Testing

CI runs the dev loop: start `hxmc dev` on an example, edit a file, check the
new code shows with the old signal values; change a signal's type and check
it resets with a notice; introduce an error and check the overlay and that
the last build keeps running; drop the connection and check the app recovers.
For each target: native, wasm, WasmGC once it is a browser path, JavaScript.

## Who builds what

- Here: `hxmc dev`, the compilation-server work, the protocol and dev
  server, the keys in packages/view's macros, snapshot and restore, the host
  and shared libraries (step 3), the tests.
- The UI session: the UI engine's part (focus, scroll and selection by node
  key; disposal of what ui owns; the theme's live update).

## Order

1, then 2, with 4 alongside; 3 last (the costliest: dylibs and DLLs).
