package haxeshim.sys;

class Os {

  static public var IS_WINDOWS(default, null):Bool = Sys.systemName() == 'Windows';

  static public var DELIMITER(default, null):String = if (IS_WINDOWS) ';' else ':';

  static public var EXECUTABLE_EXTENSION(default, null):String = if (IS_WINDOWS) '.exe' else '';

  static public function slashes(path:String)
    return
      if (IS_WINDOWS) path.replace('/', '\\');
      else path;

  static public var platform(get, null):Platform;
    static function get_platform() {
      return platform ??= {
        var file = sys.io.File.read(Sys.programPath());
        var b = file.read(1024);
        file.close();
        Platform.detect(b);
      }
    }
}
