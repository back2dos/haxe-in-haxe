package hxmc.rt;

// Every module of hxmc's package of the std that a program may use: what
// the tool types once into the cache of the runtime's typed modules
// (hxmc/src/hxmc/TypesCache.hx). Not part of any program.
import hxmc.I64;
import hxmc.Native;
import hxmc.NativeGc;
import hxmc.NativeNet;
import hxmc.NativeSsl;
import hxmc.NativeSys;
import hxmc.NativeThread;
import hxmc.NativeUv;
import hxmc.NativeZip;
import hxmc.Regex;
import hxmc.RegexUnicode;
import hxmc.rt.Runtime;
import hxmc.unsafe.Arena;
import hxmc.unsafe.Atomic;
import hxmc.unsafe.CString;
import hxmc.unsafe.Callback;
import hxmc.unsafe.Float32;
import hxmc.unsafe.Int16;
import hxmc.unsafe.Int32;
import hxmc.unsafe.Int64;
import hxmc.unsafe.Int8;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Posix;
import hxmc.unsafe.Ptr;
import hxmc.unsafe.Struct;
import hxmc.unsafe.UInt16;
import hxmc.unsafe.UInt32;
import hxmc.unsafe.UInt64;
import hxmc.unsafe.UInt8;
import hxmc.unsafe.Win32;
import hxmc.unsafe.Winsock;

class Modules {}
