package hxmc.rt;

// The runtime's Haxe modules (hxmc/README.md, "Runtime in Haxe"), loaded
// into every program through Std (hxmc/std/Std.hx). Their classes are
// @:keep (DCE keeps them typed); hxmc compiles only the functions a program
// calls, and the @:hxmc.export ones the runtime's C code calls.
import hxmc.rt.Str;
import hxmc.rt.Dyn;
import hxmc.rt.Arr;
import hxmc.rt.Bytes;
import hxmc.rt.Date;
import hxmc.rt.Zip;
import hxmc.rt.Sys;
import hxmc.rt.Net;

class Runtime {}
