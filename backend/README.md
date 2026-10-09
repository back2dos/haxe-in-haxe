# backend/ (EXPERIMENTAL)

This is a prototype code generator: one typed IR feeding a WasmGC emitter
and a C emitter. It is an explicit scope expansion and not part of the
port's conformance work. The design, measurements and recommendation are in
[bench/WASM-BACKEND.md](../bench/WASM-BACKEND.md).

- `src/backend/Main.hx`: runs the port's compiler (cross platform). Through
  `compiler.Compiler.generateHook`, it receives the filtered program (what an
  HXB archive holds) and writes `<out>.wat` and `<out>.c`.
- `src/backend/Lower.hx`: typed AST → IR (`Ir.hx`), for the subset listed
  in the design note.
- `src/backend/EmitWat.hx`: IR → WasmGC text (prototype; a real emitter
  would write binary wasm, see the design note §2.7).
- `src/backend/EmitC.hx`: IR → C. Its `Roots` analysis decides which
  references need shadow-stack slots.
- `rt/`: the C runtime (generational copying GC, exceptions, arrays) and
  `run.js`, the Node runner for WasmGC modules.
- `bench/`: the benchmark programs. `tools/`: the baseline builders and the
  Wasmtime/WAMR runners.

```sh
sh backend/build.sh                                   # Bench -> bin/backend/Bench/{prog_c,prog_linear.js,prog.wasm}
HXFLAGS="-D retain" VARIANT=-retain sh backend/build.sh
sh backend/build.sh backend/bench/exc Exc
sh backend/tools/baselines.sh                         # HL/C native, HL/C->wasm, JS for comparison
bin/backend/Bench/prog_c
node backend/rt/run.js bin/backend/Bench/prog.wasm
python3 backend/tools/besttime.py 5 bin/backend/Bench/prog_c
```

`build.sh` needs Node, gcc and Binaryen (`BINARYEN`, default
`/root/emsdk/upstream/bin`). `baselines.sh` also needs Emscripten, the
runtime objects from `bench/build-wasm.sh` and a haxe with the hl2c fix
(`HAXE_HLC`).

## Threads: green threads in the C runtime

The hxc runtime runs Haxe threads as M:1 cooperative (green) threads
(`rt/rt_thread.c`): every thread runs on the one OS thread, and only one runs
at a time, so the GC and the runtime tables need no locks. The C build of the
port uses them through the hxc `sys.thread` package (`std-hxc/sys/thread`,
over `hxc.NativeThread`), so the compilation server (`--wait`, its worker
thread and the per-client stdin forwarders), `--connect` stdin forwarding,
`--cmd` output piping and Eval threads (`Thread.create`, `Deque`, `Lock`, ...
in macros and `--interp`) work in it.

- Switching: `ucontext` (`makecontext`/`swapcontext` from the C library, so
  tcc, gcc and cosmocc builds all work). A thread record holds its C stack
  (64 MB reserved with `MAP_NORESERVE` and a guard page, committed as
  touched), its shadow stack (64 MB, likewise; the main thread keeps its
  128 MB one), its exception handler chain and pending exception. A switch
  saves the globals `rt_sp`, `rt_stack_base`, `rt_hcur` and `rt_exn` into
  the record and loads the next thread's, so shadow-stack push/pop,
  allocation and `RT_TRY` are unchanged: with one thread nothing else runs
  (no `poll`, no extra stacks; self-compile time is unchanged).
- GC: the collector scans the running thread's shadow stack as before and,
  through `rt_threads_scan`, every other thread's saved shadow stack, its
  pending exception and the entry closure of a thread not started yet.
  Values passed through `Deque`/`Lock`/`Tls` are ordinary Haxe objects
  reachable from those roots. Natives that wait root their own references.
- Scheduling points: `NativeThread.park` (all of `Mutex`, `Lock`,
  `Semaphore`, `Condition`, `Deque.pop(true)`, `Thread.readMessage(true)`
  are plain Haxe over park/unpark, with timeouts), `Sys.sleep` (0 yields),
  and waiting for a descriptor. A thread that computes without blocking also
  gives way at each minor collection (`rt_alloc_slow`, before allocating,
  where the caller's live references are rooted), so a spin loop that
  allocates (e.g. on a `haxe.atomic` value in Eval) does not starve the
  others; a loop that never allocates does. Since a switch can happen at
  any allocation, the primitives check their condition again after
  queueing themselves, and an unpark of a thread that is not parked makes
  its next park return at once.
- I/O while other threads exist: a blocking socket (`rt_net.c`) is used
  without blocking (`MSG_DONTWAIT`, a `poll` before `accept`, a
  non-blocking `connect`) and the thread waits for the descriptor in the
  scheduler, honouring `setTimeout` (a timeout fails with EAGAIN, i.e.
  `haxe.io.Error.Blocked`, as the blocking call does). Sockets made
  non-blocking with `setBlocking(false)` still throw `Blocked`.
  `Socket.select` waits in the scheduler, then selects without waiting.
  Reads and writes of `sys.io.File`/`Process` descriptors and `Sys.getChar`
  wait until the descriptor is ready (pipes and terminals; regular files are
  always ready), and `Process.exitCode()` polls the child with growing
  sleeps. `close` marks the descriptor so a thread waiting on it fails
  (EBADF) instead of using a reused number. When no thread can run, the
  scheduler waits in `poll` over the waited descriptors up to the nearest
  timer deadline; if no thread can ever be woken it prints
  `fatal: deadlock, every thread is blocked forever` and exits with 1.
- Still blocking the whole process: `Sys.print`/`println` and writes to
  stdout/stderr, `Sys.command`, file system calls, host name resolution,
  TLS (`rt_ssl.c` BIO send/recv) and libuv (`eval.luv`, `Loop.run`).
  `eval.luv.Thread`/`ThreadPool` stay unsupported (`EvalLuv.hx`).
- Exit: the process exits when the main thread's `main` returns (as on hl
  and cpp), whatever other threads do. An uncaught exception ends only its
  thread (`Thread.onAbort` prints it). `haxe.atomic` needs nothing: the std
  versions for non-threaded targets are correct with one running thread.
  Thread ids are small integers (main: 1); `Thread.events` is not available
  (the custom target does not define `target.threaded`).
- Under `__EMSCRIPTEN__` (the wasm playground) there are no threads:
  `Thread.create` throws "threads are not supported", a wait without a
  timeout that would block forever throws, and a timed wait sleeps and times
  out.

`bench/threads/Threads.hx` checks the package (`sh backend/build.sh
backend/bench/threads Threads && bin/backend/Threads/prog_c`).
`sys.net.Socket`/`Host` are real (`backend/std-hxc/sys/net`, over
`rt_net.c`).

## TLS and libuv: mbedtls and libuv natives

`rt/rt_ssl.c` (mbedtls 2.28 API, behind `hxc.NativeSsl`) backs the Eval
interpreter's `sys.ssl`/`mbedtls.*` (`src/macros/eval/EvalSsl.hx`) and the
hxc target's own `sys.ssl` (`std-hxc/sys/ssl`: `Socket`, `Certificate`,
`Key`, as Eval's `_std` versions over `NativeSsl`; `setCertificate`,
`addSNICertificate` and `Digest` are missing there as in Eval).
`rt/rt_uv.c` (libuv 1.x, behind `hxc.NativeUv`) backs `eval.luv`
(`src/macros/eval/EvalLuv.hx`). `-DHXC_NO_SSL`/`-DHXC_NO_UV` build stubs that
throw when called.

- Native builds link the system's libraries: `RT_NO=
  RT_LIBS="-lmbedtls -lmbedx509 -lmbedcrypto -luv" sh backend/build.sh port`
  (Ubuntu: `libmbedtls-dev libuv1-dev`, mbedtls 2.28, libuv 1.48).
- Cosmopolitan builds link static libraries built with cosmocc by
  `tools/cosmo-deps.sh` (fat x86-64 + aarch64 `.a` files and headers in
  `bin/cosmo-deps`; pinned mbedtls 2.28.10 and libuv 1.48.0, fetched with git
  at their tags and checked against the pinned commits, patched with
  `tools/cosmo-patches/*.patch`; about 2 minutes once). `haxelib/build.sh`
  (`hxc.com`) and `site/build.sh` (`haxe-in-haxe.com`) run it and link the
  result (`NO_DEPS=1` keeps the stubs); `backend/build.sh` links it with
  `RT_DEPS=bin/cosmo-deps`:
  `CC="cosmocc -O2" RT_DEPS=bin/cosmo-deps BIN=hih.com sh backend/build.sh port`.
  User programs built with `-D hxc.static -D hxc.ssl`/`-D hxc.uv` link the
  copy in the haxelib package (`cosmo/`, 1.6 MB zipped), so nothing is built
  or downloaded on first use besides cosmocc itself.
- mbedtls under Cosmopolitan: entropy from `getrandom()` (the patch; every
  host OS, Windows included). System CA certificates
  (`Certificate.loadDefaults`, the default CA of `sys.ssl.Socket`):
  `Sys.systemName()` is "Linux" on every OS in an APE build, so the std's
  Linux file list is read on Linux, and `hxc_NativeSsl_certLoadDefaults`
  picks the others at run time: `/etc/ssl/cert.pem` on macOS (the system
  roots; certificates added to the keychain are not seen), the std's BSD
  list on FreeBSD/OpenBSD/NetBSD, and on Windows upstream's branch (the
  system "Root" store through `crypt32.dll`, loaded with `LoadLibraryA`).
- libuv under Cosmopolitan: one binary runs on Linux, macOS, the BSDs and
  Windows, so libuv is built as its generic unix port: the `poll(2)` backend
  (`posix-poll.c`, as for GNU/Hurd and Cygwin), no file system events
  (`FsEvent` fails with ENOSYS; `FsPoll` works), interfaces through
  `getifaddrs` (no hardware addresses), memory, load and uptime through
  `sysinfo`, and `src/unix/cosmo.c` (the patch) for the executable path,
  CPU count (no model, speed or times), resident set size (the peak) and
  random bytes. Cosmopolitan's errno constants are variables holding the
  host OS's values, so libuv's `UV_E*` codes take the fixed values of its
  Windows table and system errors are translated at run time
  (`uv__cosmo_err`); interface names in IPv6 scope ids are numeric only
  (no `if_nametoindex`), and source-specific multicast is unsupported.
- `Loop.run` blocks the whole process, green threads included, as do TLS
  reads and writes (see the threads section). libuv's thread pool runs
  file system and DNS requests on real threads in C only; their callbacks
  run on the loop's thread. `eval.luv.Thread`/`ThreadPool` stay unsupported.
- Tested on Linux x86-64 only (see bench/COSMO.md): the aarch64 half is built
  but not run (no qemu-aarch64 here), and macOS, Windows and the BSDs are
  untested. Windows is the least likely to work: libuv's unix code there
  depends on Cosmopolitan's emulation of `poll` on pipes, `fork` and Unix
  sockets.

`bench/natives/Luv.hx` (timers, a TCP echo, file system requests, a child
process with a pipe, idle handles, system queries) and `bench/natives/Tls.hx`
(a local `openssl s_server`: handshakes with and without verification, host
name check, system CAs; an HTTPS GET) check a build:

```sh
sh bin/backend/hih/hih.com -cp backend/bench/natives -main Luv --interp
openssl s_server -accept 4433 -cert cert.pem -key key.pem -www &   # cert for localhost, signed by ca.pem
sh bin/backend/hih/hih.com -cp backend/bench/natives --run Tls 4433 ca.pem example.com
```

## The hxc haxelib package

`backend/haxelib/` packages the C target as a library for the user's own Haxe
(`haxe -lib hxc -main Main --custom-target hxc=bin/main`); usage is in
[haxelib/README.md](haxelib/README.md). The user's Haxe types the program;
the init macro (`hxc/Boot.hx`) makes it write the program as HXB and, after
generation, runs the bundled `bin/hxc.com` on the archive (`--hxb-lib`) and
then the C compiler. `hxc.com` is the port with the C backend, compiled by
itself to C and with cosmocc to one portable APE binary.

```sh
sh backend/haxelib/build.sh          # bin/haxelib/hxc.zip (cosmocc on PATH; about 5 min)
haxelib install bin/haxelib/hxc.zip
haxe -lib hxc -cp src -main Main --custom-target hxc=out/main
```

The archive must come from the Haxe build `hxc.com` was made from (the
pinned `haxe/`; recorded in the package's `hxc.json`). The tool runs with the
user's std path as `HAXE_STD_PATH`: DCE reruns on the loaded modules and
treats classes outside the std path as user code (kept whole).

Checked: a Map/sort/exception program and a macro/Reflect/Json program with
cc (gcc), tcc and `-D hxc.static`; `--no-output`, `-D hxc.c-only`, type
errors and `haxelib run hxc`; `bench/natives/Tls.hx` (`sys.ssl`) with
`-D hxc.static -D hxc.ssl` (the package's `cosmo/` libraries) and with tcc
and `-D hxc.ssl` (the system's), and `hxc.NativeUv` with
`-D hxc.static -D hxc.uv`. The backend tool itself built through the
package (`haxe -lib hxc ... -main backend.Main`) gives byte-identical C to
the source build (9 s: typing by the reference compiler, then `hxc.com`).
