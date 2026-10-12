package haxeshim.sys;

import haxe.io.Bytes;

using sys.io.File;
using sys.FileSystem;
using haxe.io.Path;

private abstract Payload(Bytes) from Bytes to Bytes {
  @:from static function ofString(s:String):Payload
    return Bytes.ofString(s);
}

// port: tink Promises become synchronous calls that throw `Error`s
class Fs {

  // port: haxeshim.Attempt.to
  static public function attempt<T>(what:String, how:Void->T):T
    return
      try how()
      catch (e:Error) throw e
      catch (e:Dynamic) throw Error.withData('Failed to $what', e);

  static public function get(path:String):String
    return attempt('get content of $path', path.getContent);

  static public function save(path:String, payload:Payload) {
    ensureDir(path);
    attempt('save to $path', path.saveBytes.bind(payload));
  }

  static public function exists(path:String)
    return attempt('check the existence of $path', path.exists);

  static public function ensureDir(dir:String) {
    var isDir = dir.endsWith('/') || dir.endsWith('\\');

    if (isDir)
      dir = dir.removeTrailingSlashes();

    var parent = dir.directory();

    if (parent.removeTrailingSlashes() == dir) return;

    if (!exists(parent))
      ensureDir(parent.addTrailingSlash());

    if (isDir && !exists(dir))
      attempt('create directory $dir', () -> dir.createDirectory());
  }

  static function isDirectory(path:String)
    return attempt('check if $path is a directory', path.isDirectory);

  static public function ifNewer(files:{ src:String, dest:String })
    return files.src.stat().mtime.getTime() > files.dest.stat().mtime.getTime();

  static public function move(src:String, target:String) {
    ensureDir(target);
    attempt('move $src to $target', src.rename.bind(target));
  }

  static public function copy(src:String, target:String, ?filter:String->Bool, ?overwrite:{ src:String, dest:String }->Bool) {

    function copy(src:String, target:String, ensure:Bool)
      if (filter == null || filter(src))
        if (isDirectory(src)) {
          Fs.ensureDir(target.addTrailingSlash());
          for (entry in src.readDirectory()) copy('$src/$entry', '$target/$entry', false);
        }
        else {
          if (ensure)
            Fs.ensureDir(target);
          var skip =
            if (overwrite == null || overwrite({ src: src, dest: target })) false
            else exists(target);
          if (!skip)
            attempt('copy $src to $target', sys.io.File.copy.bind(src, target));
        }

    copy(src, target, true);
  }

  static public function ls(dir:String, ?filter:String->Bool)
    return [for (entry in dir.readDirectory()) switch '$dir/$entry' {
      case included if (filter == null || filter(included)): included;
      default: continue;
    }];

  static public function delete(path:String)
    attempt('delete $path', () ->
      if (path != null && (path.exists() || uv.Uv.Fs.isSymlink(path)))
        // port: a symbolic link is removed, not what it points to
        if (path.isDirectory() && !uv.Uv.Fs.isSymlink(path)) {
          for (file in path.readDirectory())
            delete('$path/$file');
          path.deleteDirectory();
        }
        else path.deleteFile()
    );

  static public function peel(file:String, depth:Int):Null<String> {
    var start = 0;
    for (i in 0...depth)
      switch file.indexOf('/', start) {
        case -1:
          return null;
        case v:
          start = v + 1;
      }
    return file.substr(start);
  }

  static public function findNearest(name:String, dir:String):Null<String> {

    while (true)
      if ('$dir/$name'.exists())
        return '$dir/$name';
      else
        switch dir.directory() {
          case same if (dir == same): return null;
          case parent: dir = parent;
        }

    return null;
  }
}
