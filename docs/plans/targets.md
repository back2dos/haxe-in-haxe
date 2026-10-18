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
runtime of its own in Haxe over intrinsics. `make wasmgc-bench` under node 22,
median of 3 (`hxmc/test/wasmgc`):

| program | native s | WasmGC s | linear s | WasmGC RSS MB | linear RSS MB | WasmGC KB | linear KB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Basics | 0 | 0.03 | 0.1 | 46 | 147 | 11 | 57.2 |
| Mandelbrot | 0.07 | 0.15 | 0.18 | 52 | 147 | 2.4 | 35.9 |
| Nbody | 0.15 | 0.13 | 0.21 | 50 | 148 | 3.8 | 35.3 |
| Trees | 0.15 | 0.34 | 0.48 | 86 | 165 | 2.2 | 33.4 |

Every HaxeBenchmarks case runs, its check identical on every target
(`make bench`'s `hxmc-wasmgc` target). Its run here against linear memory
(median of 3, node 22; formatter_noio and json after the last runtime fixes):

| case | linear s | WasmGC s | linear MB | WasmGC MB | linear KB | WasmGC KB |
| --- | --- | --- | --- | --- | --- | --- |
| alloc | 2.82 | 3.27 | 1555 | 665 | 41 | 9 |
| bcrypt | 4.23 | 3.15 | 150 | 53 | 277 | 305 |
| binarytrees | 1.30 | 1.39 | 182 | 84 | 37 | 7 |
| json | 0.84 | 0.94 | 336 | 189 | 116 | 29 |
| mandelbrot | 1.09 | 2.27 | 151 | 57 | 42 | 9 |
| mandelbrot_anon | 3.21 | 4.14 | 151 | 57 | 45 | 9 |
| nbody | 1.37 | 1.36 | 148 | 49 | 41 | 10 |
| sha256 | 0.42 | 0.51 | 154 | 67 | 249 | 291 |
| sha512 | 0.18 | 0.10 | 150 | 55 | 256 | 295 |
| formatter_noio | 8.93 | 16.9 | 257 | 152 | 1087 | 497 |

WasmGC takes a third to a half of the memory everywhere and is as fast or
faster on half the cases. It is slower where small objects are allocated
and read in tight loops (mandelbrot: V8's allocation and the casts at
function boundaries; formatter_noio: closures, arrays read through
helpers). Mandelbrot's gap is the allocations: the native and linear
builds inline its small methods and replace the `Complex` that does not
escape by locals (Driver: `Inline`, then `Sroa`, on Mir), which the WasmGC
path, emitted from the IR before them, does not; binaryen's `wasm-opt -all
--closed-world -O3` (inlining, then heap2local) takes its module from
2.02 s to 1.10 s, where signature and type refining alone change nothing
(2026-10-17, node 22). So the first thing to try is inlining and scalar
replacement on the IR for this path. Also left to try: typed arrays in
locals (the fast path inline), br_on_cast instead of ref.test then
ref.cast, precise types for methods (their signatures are shared with the
dispatch table). ObjectMap has one
bucket (WasmGC objects have no address to hash); `sys.io.File` streams and
processes are not supported.

What the runtime duplicates (hxmc/std/hxmc/rt/gc against hxmc/std/hxmc/rt),
and why. The rule: reuse the Haxe source where only the memory layer
differs; write new code where the object model forces it.

| GC module | duplicates | why |
| --- | --- | --- |
| GcStr | Str's string natives (concat, compare, hash, substr, split, parseInt, Std.string...) | Str reads units through Mem over the string's header and chars (77 Mem calls); a WasmGC string is an i16 array. The algorithms (FNV hash, Int64 digits, parseInt) are kept the same, line for line where possible |
| GcArr | Arr's Array methods | Arr works on the slot/data layout with element kinds in the header (30 Mem calls); here the kinds are wasm types |
| GcDyn, GcNative | Dyn's comparison and reflection (as hxmc.Native) | Dyn reads type descriptors and slots through Mem (146 calls); here the tables are Meta's and fields are reached by generated code |
| GcBytes | Bytes' natives | a Bytes is an i8 array, not malloc'd memory |
| GcDate, GcSys | Date and WasiSys | the host's calendar and node's fs instead of libc/WASI over linear memory |
| GcBuf | StringBuf's buffer | the same reason as GcStr |

Not duplicated: everything above the natives (Std, Type, Reflect, the
maps, haxe.Json, haxe.crypto...) is the same Haxe source. Sharing the
natives themselves would need a memory layer under Str, Arr and Dyn
(Mem calls behind an interface the GC build implements with arrays and
structs): possible for Str and Arr, not for Dyn's descriptors.

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

Order:

1. GPU only (done, [hxmc.md](../hxmc.md#ios)): `ios-arm64` and
   `ios-sim-arm64`, macOS arm64's Mach-O and runtime objects with the
   platform in `LC_BUILD_VERSION` (minimum 15.0: `UILaunchScreen` is 14's,
   and 15 is the floor of current Xcodes; SDK 18.0) and `Mem.platform()`
   for packages; the bundle writer (an XML `Info.plist` with an empty
   `UILaunchScreen`, `CodeResources`, an ad hoc signature written by the
   linker with the bundle's special slots, `CodeSign.hx`, which macOS's
   linker signature now is too), the `.ipa`; `hxmc.os.uikit`:
   `UIApplicationMain` run by the generated main (`hxmc_ui_main`), the
   program's body inside UIKit's loop, a `CAMetalLayer`-backed view for the
   Metal back end, touches, the safe area, Suspend and Resume. CI:
   `IosCheck` on Linux, IosTest on an iPhone simulator of a macOS runner
   (`xcrun simctl`, a tap posted on the Simulator's window), not required
   checks yet. `ios-sim-x86_64` is left out: x86-64 needs
   `objc_msgSend_stret` for gfx ([graphics.md](graphics.md)) and Intel
   runners are going away. Left from this step:
   - device signing: the CMS signature blob by the developer's
     certificate (RSA or P-256: `P256.hx` has the curve, DER exists for
     Android), the provisioning profile copied in as
     `embedded.mobileprovision`, its entitlements (also as DER, slot 7,
     needed since iOS 15), the designated requirement naming the
     certificate's chain, the team id: `CodeSign.Identity` is the API,
     filled from a PKCS#12 export of the developer's identity and a profile
     downloaded from their account; installs then through
     libimobiledevice or `xcrun devicectl`;
   - the app icon and an asset catalog (`Assets.car`: undocumented; a
     `CFBundleIcons` of plain PNGs works for the home screen until then),
     `PkgInfo`, a binary `Info.plist`;
   - keys and text input (a `UIKeyInput` view and an input method, as
     macOS's text view), multiple touches, UIScene (required by the SDK
     after iOS 26), `os_log` for what the app prints on a device;
   - the App Store's checks (the declared SDK and Xcode in `Info.plist`'s
     DT* keys, `LC_ENCRYPTION_INFO_64`), the main stack (`RT_STACK_MB`'s
     1 GB reservation; iOS limits an app's address space).
2. Native controls via UIKit: `hxmc.ui.native` on `UIButton`, `UILabel`,
   `UITextField`, ... (the AppKit backend's pattern: classes made at run
   time for targets and delegates).
3. Mixing: a GPU view among UIKit views (`GpuView` over a
   `CAMetalLayer`-backed `UIView`), a native field in a drawn tree for text
   input, as on Android.

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
