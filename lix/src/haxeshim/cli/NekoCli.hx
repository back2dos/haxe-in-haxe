package haxeshim.cli;

import haxeshim.scope.NekoInstallation;
import haxeshim.sys.*;

class NekoCli {

  static public function main() exec(findNeko());

  static public function exec(neko:NekoInstallation, ?args:Array<String>)
    switch Exec.sync(neko.executable, Sys.getCwd(), args ?? Sys.args(), neko.env) {
      case Success(c):
        Sys.exit(c);
      case Failure(e):
        Exec.die(e.code, e.message);
    }

  static public function findNeko() {
    final scope = Exec.gracefully(() -> haxeshim.scope.Scope.seek());
    return scope.haxeInstallation.neko;
  }

}
