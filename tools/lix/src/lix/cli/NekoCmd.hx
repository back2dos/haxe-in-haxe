package lix.cli;

class NekoCmd {
  static public function main(?args:Array<String>) {
    final neko = NekoCli.findNeko();

    Command.attempt(() -> lix.client.haxe.Switcher.ensureNeko(neko, Logger.get()));
    NekoCli.exec(neko, args);
  }
}
