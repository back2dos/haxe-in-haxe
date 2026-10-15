package hxmc.rt;

// The runtime's Haxe modules (README.md, "Runtime in Haxe"), loaded
// into every program through Std (hxmc/std/Std.hx). Their classes are
// @:keep (DCE keeps them typed); hxmc compiles only the functions a program
// calls, and the @:hxmc.export ones the runtime's C code calls.
import hxmc.rt.Str;
import hxmc.rt.Dyn;
import hxmc.rt.Arr;
import hxmc.rt.Bytes;
import hxmc.rt.Date;
import hxmc.rt.Names;
import hxmc.rt.FloatText;
import hxmc.rt.Boxes;
// WebAssembly's runtime (@:hxmc.wasm: what C provides on the native
// targets), typed for a program built for it only
#if (hxmc.target == "wasm32-wasi")
import hxmc.rt.wasm.Heap;
import hxmc.rt.wasm.Gc;
import hxmc.rt.wasm.Exit;
import hxmc.rt.wasm.Wasi;
import hxmc.rt.wasm.Libc;
import hxmc.rt.wasm.LibM;
import hxmc.rt.wasm.Threads;
import hxmc.rt.wasm.NoSslUv;
#else
// the native targets' runtime over C libraries (@:hxmc.native; mbedtls's
// and libuv's, hxmc.rt.Ssl and hxmc.rt.Uv, typed with hxmc.NativeSsl and
// hxmc.NativeUv: for the programs that use them)
import hxmc.rt.GcPaths;
import hxmc.rt.WinRt;
#end

class Runtime {}
