package haxeshim;

import shim.Ansi;

class Logger {
  function new() {}
  public function error(s:String) {}
  public function warning(s:String) {}
  public function info(s:String) {}
  public function success(s:String) {}
  public function progress(s:String) {}
  static var SILENT:Logger;
  static var DEFAULT:Logger;
  static public function get(silent:Bool = false):Logger
    return
      if (silent) {
        if (SILENT == null) SILENT = new Logger();
        SILENT;
      }
      else {
        if (DEFAULT == null) DEFAULT = new SysLogger();
        DEFAULT;
      }

}

private class SysLogger extends Logger {
  // port: process.stderr.isTTY, through libuv
  static var isTTY = uv.Uv.Loop.guess(2) == FTty;
  static var out = {
    Ansi.available = isTTY;
    Sys.stderr();
  }
  public function new() super();
  function log(level:Level, msg) {
    progress('');
    out.writeString(Ansi.set(switch level {
      case Error: [Ansi.RED];
      case Warning: [Ansi.YELLOW];
      case Info: [Ansi.DEFAULT_FOREGROUND];
      case Success: [Ansi.GREEN];
    }) + msg + Ansi.set([Ansi.OFF]) + '\n');
    out.flush();
  }

  override public function error(s:String) log(Error, s);
  override public function warning(s:String) log(Warning, s);
  override public function info(s:String) log(Info, s);
  override public function success(s:String) log(Success, s);
  override public function progress(s:String) if (isTTY) {
    if (s.length > 80)
      s = s.substr(0, 77) + '...';
    out.writeString(
      Ansi.eraseLine() + Ansi.setX() + s
    );
    out.flush();
  }

}

private enum Level {
  Error;
  Warning;
  Info;
  Success;
}
