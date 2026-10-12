package haxeshim.sys;

/**
  Writes to stdout, synchronously.

  On nodejs `Sys.print` compiles to `process.stdout.write`, which is asynchronous whenever
  stdout happens to be a pipe on macOS. Because the shims print their result and then
  immediately call `Sys.exit` - i.e. `process.exit` - whatever is still sitting in the
  stream's buffer is simply discarded, so that e.g. `haxelib path` would emit a silently
  truncated class path, which in turn makes the compiler fail with rather cryptic errors.

  Writing to the file descriptor is synchronous on every platform, so by the time we return
  the data is out the door.

  See https://github.com/lix-pm/haxeshim/issues/80
**/
class Out {

  static public inline function println(s:String)
    print(s + '\n');

  // port: Sys.stdout() writes synchronously; a reader that went away (EPIPE) ends the output
  static public function print(s:String) {
    try {
      var out = Sys.stdout();
      out.writeString(s);
      out.flush();
    }
    catch (e:Dynamic) {}
  }

}
