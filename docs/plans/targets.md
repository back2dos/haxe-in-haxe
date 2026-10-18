# Targets

Built: Linux, Windows and macOS on x86-64 and ARM64, the glibc mode on
Linux, and wasm32-wasi ([docs/hxmc.md](../hxmc.md), "Targets" and
"WebAssembly"). Dropped: APE (Cosmopolitan) executables; the six targets
are built natively and the releases ship per platform.

## WebAssembly

Built: a linear-memory module from Mir with the whole runtime in Haxe;
the corpus passes under node and wasmtime, the port as a module compiles
itself (about 1.8x native time); the playground runs it in browsers
(WASI's imports from JavaScript, `site/client/WasiHost.hx`; exnref, or
the legacy encoding). Left:

- Threads: wasm threads (shared memory, atomics, `memory.atomic.wait`)
  under wasi-threads or a browser's workers; the collector's
  stop-the-world handshake of the native targets (`Threads.hx`) would come
  back. Until then `Thread.create` throws.
- Sockets and processes need WASI preview 2 (or JavaScript imports).
- Firefox's throws walk the whole stack (0.17 us per frame each): a
  lighter use of exceptions in the port's hot paths, or setjmp-free try
  blocks, would avoid it.
- Speed: no tail calls; 485k `i32.wrap_i64` remain in the playground's
  module, of i64 values also used in full: a second, i32 local for those
  with many address uses, or an i32 pointer type in Mir, would remove most
  (about 480 KB raw, little gzipped).
- The playground's module size (10.8 MB, 2.1 MB gzipped): folding a call
  into its user (30 KB raw, but 16 KB more gzipped), fewer wraps.

### WasmGC: a later, browser-focused second path

Not the first WebAssembly target, but worth revisiting. An earlier
prototype compiled the same IR to both (`docs/WASM-BACKEND.md`, removed in
ecb1af2; last version at 4a2c28c), Bench under Node 22:

| | Linear memory (C via Emscripten) | WasmGC |
| --- | --- | --- |
| Run time | 0.39 s | 0.36–0.40 s |
| Module size | 32.2 KB (runtime, malloc, printf) | 2.1 KB (no runtime) |
| Code per function | 1.7–3.2× larger | smaller |
| Peak memory | 146 MB | 86 MB |
| Wasmtime (Cranelift) | | 2.0 s (deferred reference counting) |

For WasmGC: much smaller modules (the engine's collector, `struct.new`
allocation, no shadow stack or barriers), direct JavaScript interop
(objects passed by reference), memory returned to the system. Against it:

- A different runtime, not only a different back end: hxmc's runtime in
  Haxe works on raw memory (`Mem.addr`, loads and stores, layouts), which
  WasmGC objects do not have. Strings, Dynamic access, maps, `Bytes` and
  reflection would need separate implementations (the prototype never
  covered Dynamic, anonymous structures or strings).
- Browser-centric: non-browser engines lag (Wasmtime above); linear
  memory runs well everywhere, WASI included.
- No threads until shared-everything threads land.
- Weaker finalizers and weak references.

Revisit when a concrete browser use makes module size or JavaScript
interop matter (browser games, `@hxmc/web`). The structuring pass and the
module writer carry over; the object model and the runtime would be new.

Started (2026-10-17) behind `-D hxmc.wasm-gc` to compare the two collectors
(docs/hxmc.md, "WasmGC"): the IR after Lower, emitted directly, with a
runtime of its own in Haxe over intrinsics. Every HaxeBenchmarks case runs,
its check identical on every target (`make bench`'s `hxmc-wasmgc` target);
`make wasmgc-check` compares `hxmc/test/wasmgc`'s programs with native.

#### Performance against linear memory (2026-10-18)

The question: can it come close enough to linear memory to be the
browser's default? First measured, it took a third to a half of the memory
and was as fast on half the cases, but up to twice as slow where small
objects are made and read in loops (mandelbrot, formatter_noio). What
closed the gap, in hxmc:

- Scalar replacement on the IR (`wasmgc/IrOpt`): a local that only holds
  objects made in the function, read through their fields, becomes a
  local per field (a constructor's writes, right after the allocation,
  allowed). Calls are inlined only where that lets it happen (a callee
  returning an object it makes, or passed one made here): Mir's `Inline`
  and `Sroa` cannot be reused, Mir being memory loads and stores already,
  and inlining more made the modules larger, not faster (V8 inlines small
  functions of a WasmGC module itself; it does not take objects out of the
  heap). Mandelbrot: 1.82 s to 0.70 s; the binaryen run that pointed here
  (`wasm-opt -O3`: inlining, heap2local) gave 1.10 s.
- Fewer casts (V8's own `--experimental-wasm-assume-ref-cast-succeeds`
  measures them: 14% of formatter_noio's time, now 5%): leaf classes'
  types final; arrays, enums, closures, Bytes typed in locals, fields,
  globals, signatures, enum arguments and captures (`GcModule.keyOf`);
  methods with their own typed signatures (the dispatch table holds
  wrappers); a local only ever cast to one type given it (`FuncGen.refine`:
  closure parameters, Dynamic read as a class).
- Inline fast paths: array reads, writes and pushes (kind and range tested,
  `br_on_cast_fail`, the helper only for another kind or growth);
  structural reads and writes test the layouts that have the field (they
  all went through the runtime by name for writes).
- Runtime: identity hashes (ObjectMap had one bucket: keyed lists were
  quadratic), Ints of -128...1023 boxed once as `hxmc.rt.Boxes` does,
  `Null<Int>` loop counters in GcStr typed Int, UTF-8 conversions in one
  pass, Bytes.compare eight bytes a step, `Type.enumEq` casting once.
- Size: literals of 24 characters and more made from passive data segments
  (a byte a character for Latin-1): bcrypt's module 306 KB to 133 KB.

HaxeBenchmarks under node 22 (V8 12.4), wall time, median of 5 runs
interleaved (native, linear, WasmGC before and after), peak RSS, module
size (linear without a name section). `make bench` (`-n 3`) agrees, every
check identical:

| case | native s | linear s | WasmGC before s | WasmGC s | / linear | native MB | linear MB | WasmGC MB | linear KB | WasmGC before KB | WasmGC KB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| alloc | 1.59 | 2.45 | 2.91 | 2.53 | 1.03 | 749 | 1556 | 678 | 42 | 9 | 10 |
| bcrypt | 2.97 | 3.45 | 3.10 | 3.11 | 0.90 | 4 | 151 | 55 | 278 | 306 | 133 |
| binarytrees | 0.71 | 1.10 | 0.94 | 0.96 | 0.87 | 117 | 183 | 85 | 38 | 8 | 8 |
| json | 0.52 | 0.79 | 0.80 | 0.77 | 0.97 | 140 | 337 | 194 | 117 | 29 | 33 |
| mandelbrot | 0.75 | 0.98 | 1.82 | 0.70 | 0.71 | 11 | 152 | 54 | 43 | 10 | 10 |
| mandelbrot_anon | 1.28 | 2.42 | 3.91 | 0.91 | 0.38 | 11 | 152 | 54 | 46 | 10 | 10 |
| nbody | 0.75 | 1.04 | 1.22 | 0.99 | 0.95 | 0 | 149 | 51 | 42 | 11 | 12 |
| sha256 | 0.19 | 0.35 | 0.38 | 0.34 | 0.97 | 21 | 155 | 67 | 250 | 291 | 116 |
| sha512 | 0.02 | 0.14 | 0.08 | 0.07 | 0.50 | 9 | 151 | 56 | 256 | 296 | 120 |
| formatter_noio | 6.29 | 8.08 | 14.32 | 8.86 | 1.10 | 261 | 258 | 104 | 1092 | 501 | 548 |

Every case is now within 10% of linear memory or faster (seven of ten
faster), with a third to a half of its memory and modules 2 to 8 times
smaller. Build time: the formatter's WasmGC build 3% longer than before
(scalar replacement, the second emission of refined functions; 1.2 s,
about the linear build's). The native and linear paths are unchanged.

What is left of the gap: formatter_noio (10%) spends it spread thin: the
casts left (5%: values read from arrays of references, anonymous
structures' fields, which share layouts across types, and Dynamic), null
checks (4%, `--experimental-wasm-skip-null-checks`), `array.copy` of
references (Array.concat in a loop) and Type.enumEq against hxmc's own.
alloc's collection of half a million 100-byte to 1 KB arrays costs V8
more than hxmc's nursery, and a byte array has no wider reads. All
measured on V8 only, and an older one than Chrome's (node 22: no
Turboshaft for wasm, inlining only for WasmGC modules); SpiderMonkey and
JavaScriptCore are unmeasured.

#### A real program: the UI stack

Neither ui-counter nor gfx-cube builds. `HXMC_GC_SURVEY=1` lists what each
lacks (=2 writes the module, those functions trapping):

- ui-counter, 34 constructs, all at the browser boundary, none in the
  ui, text and view code: imports that take pointers (`@hxmc/os`'s canvas
  window, text input, clipboard and cursor; the accessibility mirror;
  WebGPU's shader, buffer and texture uploads; the page's fonts read into
  a Bytes), raw memory (`Mem`, `malloc`/`free`, `Arena`, `CString`,
  strings as UTF-8 through memory), and the GL back end (reached because
  `Device` picks its back end at run time; its calls take pointers too).
  Imports of numbers only are now supported (`scale`,
  `prefers_dark`, `font_count`...).
- gfx-cube, 31: the same, plus `@:hxmc.struct` values (the shaders' Vec2,
  Vec3, Vec4 and Mat4 data, written into GPU buffers through field
  addresses).

What does build is the engine itself. StressTest's list of 1000 rows
without the GPU (markup, signals, styles, flex layout, text shaped with
DejaVu Sans by `@hxmc/text`, the accessibility tree; a program outside the
repository: the fonts added from a file, the page's font lookup skipped),
median of 5, node 22:

| | native | linear | WasmGC |
| --- | --- | --- | --- |
| mount (markup to nodes) ms | 17 | 39 | 32 |
| first layout (styles, flex, text) ms | 33 | 59 | 61 |
| toggle, relabel, scroll, append (each) ms | 0.7-1 | 0.6-1.1 | 0.5-1.3 |
| 5 accessibility trees ms | 7 | 7 | 8 |
| whole run (5 rounds) s | 0.32 | 0.72 | 0.73 |
| peak RSS MB | 102 | 261 | 204 |
| module KB (gzip -9) | 2163 | 1609 (396) | 775 (251) |

Frame times (an update's layout and text) are at parity with linear
memory, the module half the size; painting and the GPU's part could not be
measured. Getting there needed four fixes found by this program (a
structural call to a method of another representation, Vector reads in
generic code, Std.int out of range, BytesBuffer) and the identity hashes.

#### What making it the browser's default would take

1. **Interop with raw memory.** The packages talk to the browser through
   C-ABI imports with pointers into linear memory, and keep GPU data in
   memory (`@:hxmc.struct` values, `Arena`). A WasmGC module may also have
   a linear memory: the plan would be WasmGC objects for Haxe values and a
   small linear memory for what crosses the boundary, `hxmc.unsafe`
   (`Mem`, `Ptr`, `Arena`, struct values) working on it as it does now, an
   allocator for it (the linear runtime's `malloc`), and imports taking
   addresses in it. What cannot carry over is `Mem.addr(bytes)`: a GC
   array has no address and JavaScript cannot see into it, so the call
   sites that hand a Bytes to the browser (WebGPU's buffer and texture
   writes, the page's fonts, clipboard and text input) would copy through
   that memory instead (in wasm, a loop; a frame's vertex data copied
   once more). Strings: through the same memory as UTF-8, or JS String
   Builtins where every browser has them.
2. **Bytes and typed arrays.** Keep Bytes a GC i8 array: Haxe code reads
   and writes it as fast as linear memory and the collector frees it;
   only the boundary copies. A Bytes that must live in linear memory
   (vertex buffers rewritten each frame) would be an `hxmc.unsafe` buffer
   in the package, not a Bytes.
3. **One implementation of each thing.** The runtime's natives are
   duplicated (the table below): 1,300 lines of Haxe against the
   linear runtime's own. Shareable: the algorithms of Str, Arr, Bytes,
   Date and StringBuf, if they were written against a small layer
   (length, read a unit, write a unit, allocate, copy) that each runtime
   implements, one over `Mem` and one over `W`, chosen at compile time;
   Dyn's reflection and comparison could share their logic but not their
   tables (descriptors in memory against Meta's generated functions).
   Not shareable, and needing none: the collector, the shadow stack, the
   barriers. As the default, that refactoring should come first: two
   copies of string handling are two places for each bug.
4. **JavaScript interop.** WasmGC can hand Haxe objects to JavaScript by
   reference (and hold JavaScript objects as `externref`) where linear
   memory needs handle tables; worth having for `@hxmc/web`'s islands,
   not needed to run what exists.
5. **WASI and everything outside the browser stays linear memory**:
   node's CLI, wasmtime, the npm compiler module and the playground's
   compiler (WASI's files and processes, engines without WasmGC or with a
   slow one). The default would change for browser builds only (the
   site's examples, `@hxmc/web`'s islands, `@hxmc/os`'s canvas programs).
6. **Threads**: neither path has them in the browser; linear memory's
   route (shared memory, workers) exists, WasmGC's waits for
   shared-everything threads. A program that needs threads would stay
   on linear memory.
7. **Engines**: Chrome 119, Firefox 120 and Safari 18.2 have WasmGC; the
   speeds here are V8's. Before a switch: the site's examples measured in
   all three (the playground's intermittent WebKit crash, under
   investigation, is a reason to watch Safari).

**Recommendation.** Speed and memory are no longer the obstacle: WasmGC is
at parity or faster on HaxeBenchmarks and on the UI engine, with half the
memory and smaller modules. The obstacle is the packages' boundary with
the browser. So: not the default yet; next, the hybrid module (a linear
memory for `hxmc.unsafe` and the imports, copies where a Bytes crosses),
which makes ui-counter and gfx-cube build; then frame times and sizes of
the site's examples in Chrome, Firefox and Safari; switch browser builds
to WasmGC when those hold, with the shared natives (item 3) done first.
Linear memory stays the WASI target and the fallback.

#### The runtime it duplicates

What the runtime duplicates (hxmc/std/hxmc/rt/gc against hxmc/std/hxmc/rt),
and why. The rule: reuse the Haxe source where only the memory layer
differs; write new code where the object model forces it.

| GC module | duplicates | why |
| --- | --- | --- |
| GcStr | Str's string natives (concat, compare, hash, substr, split, parseInt, Std.string...) | Str reads units through Mem over the string's header and chars (77 Mem calls); a WasmGC string is an i16 array. The algorithms (FNV hash, Int64 digits, parseInt) are kept the same, line for line where possible |
| GcArr | Arr's Array methods | Arr works on the slot/data layout with element kinds in the header (30 Mem calls); here the kinds are wasm types |
| GcDyn, GcNative | Dyn's comparison and reflection (as hxmc.Native) | Dyn reads type descriptors and slots through Mem (146 calls); here the tables are Meta's and fields are reached by generated code |
| GcBytes, GcBytesBuffer | Bytes' and BytesBuffer's natives | a Bytes is an i8 array, not malloc'd memory |
| GcDate, GcSys | Date and WasiSys | the host's calendar and node's fs instead of libc/WASI over linear memory |
| GcBuf | StringBuf's buffer | the same reason as GcStr |

Not duplicated: everything above the natives (Std, Type, Reflect, the
maps, haxe.Json, haxe.crypto...) is the same Haxe source. `sys.io.File`
streams and processes are not supported.

## Android

ARM64 (and x86-64 for emulators) ELF shared library loaded through JNI or
`NativeActivity`: position-independent code with GOT/PLT, a TLS model for
`.so` (initial-exec/TLSDESC), imports of `libc.so`/`liblog`/`libandroid`
written directly (no NDK), 16 KB segment alignment (Android 15+), runtime
built against Bionic. Packaging without the SDK: binary-XML manifest,
`resources.arsc`, zipalign, APK Signature Scheme v2/v3;
`hasCode="false"` apps need no `classes.dex`. Google Play needs an Android
App Bundle (`.aab`: protobuf manifest/resources). Java glue (permissions,
billing) would need a DEX writer (the port has a JVM generator) or
Google's `d8`.

Order:

1. GPU only (done, [hxmc.md](../hxmc.md#android)): `NativeActivity`
   (`hasCode="false"`), EGL and the GLES back end on its `ANativeWindow`,
   the cube; the APK writer (binary XML, an aligned zip, v2 signing with a
   generated debug key: ECDSA P-256 in plain Haxe rather than through
   mbedtls, so that the WebAssembly tool writes APKs too); `adb` only to
   install. No `resources.arsc` was needed (the label a plain string, a
   framework theme). TLS: TLSDESC on arm64, the general dynamic model on
   x86-64 (Bionic implements TLSDESC on arm64 and riscv64 only), never
   initial-exec (refused for a dlopen'ed library); the floor is API 29, the
   first Bionic with ELF TLS. CI: AndroidTest on an x86-64 emulator with
   KVM on a Linux runner, not a required check yet. Left from this step:
   several ABIs in one APK, release signing with the developer's keystore
   (PKCS#12, v3 for key rotation), icons and a `resources.arsc`, the `.aab`
   for Google Play, `DT_RELR` (API 30+) or Android's packed relocations to
   shrink the RELATIVE table, RELRO for the data that holds addresses.
2. Native controls (done, [hxmc.md](../hxmc.md#android)): JNI bound in
   Haxe (`JNIEnv` and `JavaVM` through `hxmc.os.VTable`, COM's macro),
   a minimal DEX writer in hxmc (`Dex.hx`) for the glue (`org.hxmc.Glue`,
   one listener class whose methods call a static native registered with
   `RegisterNatives`; `org.hxmc.Activity`, a `NativeActivity` whose window
   draws views), `hxmc.ui.native`'s Android backend (`android.widget`'s
   button, label, field, checkbox, slider, progress bar in an
   `AbsoluteLayout`, laid out by our flexbox). Views live on Java's main
   thread: the runtime attaches it (`NativeThread.attach`), the program's
   thread hands it work through its looper, and `NativeHost.run` is
   driven by Choreographer's frames there (`AChoreographer`: no Java
   `Runnable`s needed). CI: the form's checks on the emulator, taps,
   text through the input method, uiautomator's accessibility dump. Left:
   lists and scrolling (no backend of `hxmc.ui.native` has them yet),
   edge-to-edge insets on Android 15 (the root fits the system bars), the
   theme following a dark mode change while running (the activity keeps
   `uiMode` changes).
3. Mixing, as on the desktop (done, [hxmc.md](../hxmc.md#android); the UI
   design, [ui.md](ui.md)): a GPU view inside native controls (a
   `SurfaceView` giving an `ANativeWindow` to the GL back end:
   `ChildSurface`, ui's `GpuView`); a native control inside a drawn tree
   only for text input (a hidden `EditText` for the keyboard and the input
   method: `Window.startTextInput`, `TextInput`). CI: the cube among views
   through Home and back; the soft keyboard shown and hidden, a composition
   and a commit through the field's `InputConnection`. Left: several GPU
   views in one window (each frame does not make its context current),
   a `TextureView` for a GPU view under other views or animated with them,
   the input method's candidates placed at the caret (`CursorAnchorInfo`),
   a drawn UI's text on Android checked in CI (`hxmc.text` does not look in
   `/system/fonts` yet), `GpuView` on the desktop backends (a child
   window or view where gfx draws).

## iOS

ARM64 Mach-O like macOS arm64 with the iOS platform tag (and the
simulator as its own platform), TLV descriptors, `.app` bundle with
`Info.plist` (launch screen via `UILaunchScreen`, no storyboard), real
certificate signing with entitlements and provisioning profiles (as
`rcodesign` does without Apple tools), `.ipa` packaging. Build from Linux
or Windows; install on devices with libimobiledevice. Open questions: the
app icon's compiled asset catalog (`Assets.car`, undocumented), the App
Store's declared SDK/Xcode version checks, simulator testing (macOS
only). No JIT on iOS.

## Shared libraries and position-independent output

Needed by Android and plugins: the relocation model, TLS model, output
kind and segment alignment are already parameters in `Abi`/`Target`.

## Linux

- A dynamic musl mode (`/lib/ld-musl-<arch>.so.1`, unversioned:
  `Abi.setLibc`), beside the glibc mode.
- Choosing the glibc mode by itself when a program imports a shared
  library (today an import in the static mode is a compile error naming
  the mode).
- Lazy binding (PLT) if startup with many imports needs it.
- Direct system calls instead of musl: [runtime.md](runtime.md).

## macOS

- Split the runtime's Mach-O objects per function (or select sections) so
  unused runtime code is dropped, as on ELF; today they are linked whole
  (`ssl.o` is 0.8-0.9 MB).
- x86-64 for the gfx back end: `objc_msgSend_stret` for results over 16
  bytes ([graphics.md](graphics.md)).
