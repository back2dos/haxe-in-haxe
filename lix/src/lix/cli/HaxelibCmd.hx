package lix.cli;

import lix.client.haxe.Switcher;

class HaxelibCmd {
  static public function main(?args:Array<String>) {
    final scope = Scope.seek();

    Command.attempt(() -> Switcher.ensureNeko(scope.haxeInstallation.neko, Logger.get()));
    HaxelibCli.exec(scope, args);
  }
}
